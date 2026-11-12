# Shaders, Optics & Material Pipelines

> **Context**: Deep technical architecture reference for [`shaders/slime.gdshader`](file:///d:/slime/shaders/slime.gdshader), [`terrain/terrain.gdshader`](file:///d:/slime/terrain/terrain.gdshader), [`terrain/cave_rock.gdshader`](file:///d:/slime/terrain/cave_rock.gdshader), [`terrain/cave_water.gdshader`](file:///d:/slime/terrain/cave_water.gdshader), [`shaders/floor.gdshader`](file:///d:/slime/shaders/floor.gdshader), and [`shaders/prop.gdshader`](file:///d:/slime/shaders/prop.gdshader).

---

## 1. Overview of Shaders

| Shader File | Render Target | Shading Model | Key Techniques |
| :--- | :--- | :--- | :--- |
| [`shaders/slime.gdshader`](file:///d:/slime/shaders/slime.gdshader) | Slime Body Mesh | `unshaded`, `cull_back`, `depth_draw_always` | Chromatic dispersion, screen-space refraction, procedural eyes, split neck pinching, 3D simplex bubbles, cel outline |
| [`terrain/terrain.gdshader`](file:///d:/slime/terrain/terrain.gdshader) | Continent Ground | `diffuse_lambert_wrap`, `specular_disabled` | Macro/detail vertex-stage FBM, slope biomes, beach sand, alpine snow |
| [`terrain/cave_rock.gdshader`](file:///d:/slime/terrain/cave_rock.gdshader) | Cave Shell Mesh | `diffuse_lambert_wrap`, `specular_schlick_ggx` | Organic domain-warped dual-scale rotated triplanar mapping |
| [`terrain/cave_water.gdshader`](file:///d:/slime/terrain/cave_water.gdshader) | Cave Pools & Lake | `blend_mix`, `depth_draw_always` | Depth extinction, caustic ripple warping, edge contact foam |
| [`shaders/floor.gdshader`](file:///d:/slime/shaders/floor.gdshader) | Flat Studio Floor | `unshaded` | Multi-slime blob shadow projection, anti-aliased grid lines |
| [`shaders/prop.gdshader`](file:///d:/slime/shaders/prop.gdshader) | Food Props | `cull_back`, `specular_disabled` | Flat shading, 3D procedural noise dissolve with emissive glowing edge |

---

## 2. Slime Jelly Shader Deep Dive ([`slime.gdshader`](file:///d:/slime/shaders/slime.gdshader))

### Vertex Stage: `deformSlime()`
Evaluates analytical deformations on a unit sphere mesh ($R = 1.6\text{ m}$):
1. **Rest Flattening (Melt)**:
   * Compresses vertical profile: $y' = y \times (0.86 - 0.22 \times \text{uMelt})$.
   * Flattens base near ground floor with a cubic Hermite ease:
     $$y_{\text{base}} = y_{\text{ground}} + 0.9 \times (2t^2 - t^3)$$
2. **Mitosis Fission Teardrop Bridge (`uSplitAmt`, `uSplitNeckRadius`)**:
   * Stretches forward toward separating clone: `p.xz += sdir * stretch`.
   * Monotonic lateral neck pinch: `p.xz -= sperp * (sperpd * pinch)`.
   * Rear bulge conserving volume: `p.xz -= sdir * backWeight`.
   * Dome cap seam meeting partner at half-distance with smooth minimum.
3. **Locomotion Dynamics**:
   * Breathing oscillation: $\sin(2t) \times 0.022$.
   * Locomotion lean & crawl waves: shifts vertices along movement direction.
   * Splat & spread response on landing: compresses $y$ while expanding $xz$.
   * Poke spring waves: localized exponential wave propagation for primary and secondary pokes.
4. **Solid Contact Dents (`uSolidPos`, `uSolidHalf`, `uSolidDir`)**:
   * Evaluates signed distance to closest 8 obstacles and pushes vertices outward to prevent geometry penetration.
5. **Normal Reconstruction**:
   * Deforms vertex plus tangent and bitangent offsets ($\epsilon = 0.025$) to reconstruct exact deformed surface normals:
     $$\mathbf{n}_{\text{deformed}} = \text{normalize}((\mathbf{p}_1 - \mathbf{p}_0) \times (\mathbf{p}_2 - \mathbf{p}_0))$$

### Fragment Stage: Optics & Stylization
1. **Screen-Space Refraction & Chromatic Dispersion**:
   * Samples `tRefraction` (screen texture) at three shifted UV coordinates:
     * Red: `screenUV - distortion * (1.0 - 0.18 * disp) + dir * disp * 0.4`
     * Green: `screenUV - distortion * 1.0`
     * Blue: `screenUV - distortion * (1.0 + 0.22 * disp) - dir * disp * 0.55`
   * Produces realistic color-fringed glass refraction.
2. **Caustics & Internal Jelly Tinting**:
   * Mixes shallow and deep water tints based on optical path thickness: $\text{thickness} = (\mathbf{n} \cdot \mathbf{v})^{0.65}$.
   * Basal caustic highlights in lime/cyan (`uCausticA` / `uCausticB`).
3. **3D Simplex Bubbles**:
   * Evaluates procedural 3D simplex noise field inside the body volume (`uBubbleNoiseScale`).
   * Scaled down or skipped on distant LODs (`uShaderLOD > 0.5`).
4. **Procedural Cartoon Eyes**:
   * Evaluated directly in spherical coordinates:
     $$\text{eyeYaw} = \text{atan2}(x, z) - \text{uFacing},\quad \text{eyeElev} = \text{asin}(y)$$
   * Renders rounded white sclera with vertical blink squeeze (`uBlink`).
5. **Anime Cel Outline**:
   * Sharp edge darkening based on $1.0 - \mathbf{n} \cdot \mathbf{v}$.

---

## 3. High-Performance Terrain Shader ([`terrain.gdshader`](file:///d:/slime/terrain/terrain.gdshader))

### The Cardinal Optimization
In mobile and integrated GPU environments, procedural 2D/3D noise in fragment shaders creates severe fragment pipeline bottlenecks.
* **Solution**: `terrain.gdshader` evaluates all macro and medium FBM noise **once per vertex** in `vertex()`:
  * `v_macro_pat = fbm2(v_xz * macro_scale)`
  * `v_med_pat = fbm2(v_xz * detail_scale + vec2(5.2, -8.7))`
  * `v_rock_fbm = fbm2(v_xz * 0.022 + vec2(v_world_y * 0.028, -v_world_y * 0.021))`
* The `fragment()` function performs purely analytical color mixing between canopy grass, sand, rock, and snow, guaranteeing consistent 144+ FPS.

---

## 4. Cave Triplanar Rock Shader ([`cave_rock.gdshader`](file:///d:/slime/terrain/cave_rock.gdshader))

Expansive cavern walls suffer from obvious repeating grid artifacts under standard triplanar mapping.
* **Technique**: Non-repeating domain-warped dual-scale rotated triplanar:
  1. Distorts world coordinates with a 3D trigonometric organic domain warp.
  2. Samples **Scale A** (medium rock detail).
  3. Samples **Scale B** (macro scale rotated by $37^\circ$ so feature alignment never matches Scale A).
  4. Blends Scale A and Scale B via procedural mask noise.
  5. Multiplies baked ambient occlusion ($R$), skylight exposure ($G$), and wetness ($B$) from vertex color attributes.
