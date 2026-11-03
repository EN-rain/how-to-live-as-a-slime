---
name: godot-vegetation-shaders
description: >-
  Make trees, grass and ground look alive and believable in Godot 4: leaf-card canopy normals, wind sway that bends grass instead of sliding it (vertex colours), a blended ground with worn dirt paths and shade under trees, and dense grass fields with MultiMesh. Ships ready-to-use .gdshader files, a MultiMesh scatter script, a ground-mask builder and Blender scripts to prepare assets. Use this whenever foliage, trees, bushes, grass, meadows or terrain look flat, fake, patchy, static, "pasted on" or too expensive in a Godot 3D scene, when someone wants wind/swaying vegetation, leaf shaders, grass shaders or to scatter thousands of plants, even if they don't say "shader".
license: MIT (see LICENSE)
---

# Godot vegetation: canopy, wind, ground, mass placement (Godot 4.x)

Vegetation usually looks fake for four reasons, and each has a specific fix. Fix the lighting first
(`godot-lighting-environment` skill): these techniques are judged under a directional sun and a sky.

| Problem | Fix | Ships |
|---|---|---|
| Tree canopies look like a pile of flat cards with patchy brightness | Light leaves as if they pointed **out of the canopy centre** | `assets/leaf_canopy.gdshader` · `scripts/blender_leaf_card_normals.py` |
| Static vegetation = dead world; naive wind makes tufts **slide** | Per-vertex weight: root planted, tip bends; scrolling noise for gusts | `assets/grass_wind.gdshader` · `scripts/blender_grass_vertex_colors.py` |
| One flat green under everything → plants look pasted on | Several greens + worn dirt + darker shade, placed by a **mask** | `assets/ground_blend.gdshader` · `scripts/ground_mask.gd` |
| Dense grass is slow or impossible | One `MultiMeshInstance3D`, no shadows, visibility range | `scripts/scatter_multimesh.gd` |

All files were run and measured in a reference scene; numbers are in `references/evidence.md`.
Copy the files you need into the project (e.g. `res://shaders/`, `res://tools/`) and adapt the uniforms.

## 1. Leaf canopy — one volume, not a pile of cards

Leaves are usually flat quads ("cards") with a leaf texture. Each card has its own normal, so the lighting
treats every card separately → random bright and dark patches.

- Put `leaf_canopy.gdshader` on the leaf surface. Pass the old albedo texture as `leaf_texture`.
- Set `canopy_center` / `canopy_radius` in the **mesh's local space**. The leaves' AABB works well:
  `mesh.get_aabb().get_center()` and `aabb.size * 0.5`. For trees with several canopy lobes, use one leaf mesh
  per lobe.
- `normal_blend` 0.85 (default) keeps a little per-card variation. 1.0 gave no measurable extra gain.
- The shader writes `NORMAL` in `fragment()` from a varying on purpose. With `cull_disabled` Godot flips
  back-face normals, which would point half the leaves into the canopy.
- No custom shader possible (Mobile/Compatibility pipeline, StandardMaterial3D-only workflow)? Bake the same
  normals in Blender with `blender_leaf_card_normals.py`. Measured: it helps, but less than the shader,
  because of that back-face flip on double-sided leaf materials.
- `specular` defaults to **0**. Leaves are matte: at Godot's default 0.5, sky reflections lay a grey-blue
  sheen over the canopy (measured: the canopy's blue channel halves once it is removed). `SPECULAR = 0` removes
  reflections too; the `specular_disabled` render mode only removes the direct-light highlight.
- The shader uses `alpha_to_coverage`. With MSAA on, cut-out leaf edges are smoothed. The measured gain was
  small (−2 % frame-to-frame shimmer vs MSAA alone, on a texture with hard alpha edges). It grows with softer
  alpha edges and mipmapped leaf textures. TAA remains the main fix for foliage shimmer.

Expected: a lit side and a shaded side across the whole canopy, instead of a speckled one.

## 2. Wind — bend, don't slide

A gentle sway with small motions travelling through the foliage is what makes a scene feel alive.

- `grass_wind.gdshader` moves each vertex by `weight^bend_curve`. The weight comes from the **vertex colour**:
  dark root = 0 (planted), bright tip = 1. If every vertex moves the same, the whole tuft slides over the
  ground. That is the classic mistake, and it was measured: the naive version moves the root pixels as much
  as the tips.
- Check whether the asset already has vertex colours (many packs do: dark roots, light tips). If not:
  `blender --background --factory-startup --python blender_grass_vertex_colors.py -- --in grass.glb --out grass_vc.glb`
  (`--mode island` gives each blade its own 0..1; it welds split vertices so imported meshes work).
  Or set `weight_source = 2` to use height in the tuft (needs a sensible `blade_height`).
- The weight is the vertex colour's **brightness** (max of R, G, B; `weight_source = 0`). That works for grey
  masks and for tinted gradients (dark green root → light green tip). Then set `weight_range` to the root
  and tip values so they map to exactly 0 and 1. Read them from the mesh once:
  ```gdscript
  var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
  var lo := 1.0; var hi := 0.0
  for c in cols: var b := maxf(c.r, maxf(c.g, c.b)); lo = minf(lo, b); hi = maxf(hi, b)
  material.set_shader_parameter("weight_range", Vector2(lo, hi))
  ```
  Measured on a tinted tuft: the red channel alone under-bends the tips by 31 %; brightness without the remap
  lets the root creep (×11). With the remap, the root stays still and the tips move fully.
- Assign a seamless noise texture to `wind_noise` (`NoiseTexture2D` with `seamless = true`, or
  `FastNoiseLite.get_seamless_image()`). The scrolling noise makes gusts travel across the field.
- Works on MultiMesh instances (`MODEL_MATRIX` is per instance) and uses `world_vertex_coords`, so there is no
  per-vertex matrix inverse.
- Apply the same idea to tree leaves with a small `wind_strength` (the weight can be distance from the trunk).

Pitfalls:
- Vertex colours from Blender must be written in **linear** (`attr.data[i].color = ...`). The shipped
  script does this. A mid-height weight of 0.5 must arrive as 0.5 in Godot's `COLOR`. An sRGB-encoded
  weight arrives as about 0.2, and the blade then barely moves until near the tip.
- Blender's glTF exporter can export a fake white `COLOR_0` from another colour layer. Export with
  `export_vertex_color='NAME'`, `export_vertex_color_name='Color'` and `export_all_vertex_colors=False`.

## 3. Ground — connect vegetation to the world

- `ground_blend.gdshader` mixes two greens with large-scale noise, darker shade grass and worn dirt with a
  noisy edge. A world-space **RG mask** decides where: R = dirt (paths, doorways, around stalls/wells),
  G = shade under trees.
- Build the mask from scene data with `ground_mask.gd` (path polylines + spots + tree positions), or paint it
  in an image editor over a top-down screenshot. Set `mask_world_rect` to the covered X/Z area.
- Mask resolution: aim for about 10+ pixels per world unit around paths. Coarser masks give stair-stepped dirt
  edges (seen at ~6 px/unit, fine at ~13 px/unit).
- Optional `grass_texture` / `dirt_texture` uniforms multiply the colours for close-up detail.

## 4. Mass placement — MultiMesh, no grass shadows

- `scatter_multimesh.gd` builds **one** `MultiMeshInstance3D` for thousands of tufts (random yaw/scale,
  optional exclusion callback to keep paths clear). Measured: 20 000 tufts = 1.25 ms per frame as one
  MultiMesh vs 5.50 ms as 20 000 `MeshInstance3D` nodes (p95 1.4 vs 8.0 ms).
- `cast_shadow = OFF` on grass: thousands of thin blades in the shadow maps cost a lot and are barely visible.
  The ground and the lighting carry the shading.
- Set a `visibility_range_end` (with fade). A whole MultiMesh fades as one object, so split big fields into
  chunks (one MultiMeshInstance3D each) for per-chunk culling and fading.
- Scale matters: compare the grass height with a door or a character. Grass at half a storey reads as a wheat
  field.

## Verify

Capture the same views before/after, plus two captures of a close-up tuft at different times (or a short
video). Roots should not move while tips do. Then walk through the field and check the frame time with the
grass on and off (see `godot-render-performance`).

## Related skills

- `godot-lighting-environment`: sun, sky, AgX, AO, GI, fog (do this first).
- `godot-render-performance`: frame-time budget for grass density, visibility ranges, shadows.
- `godot-lights-camera-post`: dust particles, DOF and finishing touches.
