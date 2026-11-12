# Terrain, Biomes & SDF Cave System

> **Context**: Deep technical architecture reference for [`terrain/terrain.gd`](file:///d:/slime/terrain/terrain.gd), [`terrain/cave_system.gd`](file:///d:/slime/terrain/cave_system.gd), [`tools/cave_layout.gd`](file:///d:/slime/tools/cave_layout.gd), [`tools/cave_sdf.gd`](file:///d:/slime/tools/cave_sdf.gd), and [`scripts/cave_atmosphere.gd`](file:///d:/slime/scripts/cave_atmosphere.gd).

---

## 1. System Overview

The world of *How to Live as a Slime* seamlessly merges a large-scale procedural continent with a subterranean cave network:

```
[World Environment]
   ├── DirectionalLight3D ("Sun") & Ambient Light
   │
   ├── [TerrainScene (terrain/terrain.gd)]
   │     ├── 7200m x 7200m Continent Landmass (Focused non-linear grid)
   │     ├── Annular Contour-Hugging Ocean Mesh (14,000m outer radius)
   │     ├── MultiMesh Vegetation (Meadow grass, trees, rocks, bushes, flowers)
   │     └── ConcavePolygonShape3D Collision Surface (layer 1)
   │
   └── [CaveSystem (terrain/cave_system.gd)]
         ├── Pre-baked SDF Marching-Cubes Shell (cave_mesh.res)
         ├── Baked Floor & Wall Colliders (cave_floor_shape.res / cave_wall_shape.res)
         ├── CaveLayout Coordinate Mapping (Local <-> World)
         ├── Interior Props & Boulder Colliders (layer 4)
         └── CaveAtmosphere (Dynamic lighting, fog, and sunbeam attenuation)
```

---

## 2. Terrain Landmass & Biomes ([`terrain.gd`](file:///d:/slime/terrain/terrain.gd))

* **Dimensions**: $7200\text{ m} \times 7200\text{ m}$ total size, continent radius $2600\text{ m}$, sea level $0.0\text{ m}$.
* **Focused Non-Linear Grid**:
  * $192 \times 192$ subdivisions.
  * Vertex spacing contracts non-linearly near the central player valley (~$9.7\text{ m}$ spacing) while smoothly expanding toward the horizon, achieving high visual fidelity near the player with 24% fewer total triangles than a uniform grid.
* **Biomes & Elevation Model**:
  * **Central Valley / Amphitheater**: Base elevation $22.0\text{ m}$, flat center radius $45\text{ m}$.
  * **Northern Alpine Mountains**: Sharp ridged peaks reaching $115\text{ m} - 150\text{ m}$, blending from alpine rock into snow.
  * **Western Mesas**: Stepped horizontal terrace plateaus modulated by sine-quantized noise.
  * **Eastern Rolling Downs**: Gentle grassy hills.
  * **Annular Ocean**: Concentric rings ($28$ rings, $96$ segments) hugging the continental shelf down to seabed depth $-22.0\text{ m}$.
* **MultiMesh Vegetation & Props**:
  * **Grass**: $15,200$ instances (scaled by quality preset), fade range $140\text{ m} - 170\text{ m}$. Placed via direct barycentric interpolation over the cached terrain grid (0 noise calls).
  * **Trees**: $140$ deterministic instances (CommonTree1/2, Pine1/2) with static trunk colliders on `LAYER_OBSTACLES` (layer 4).
  * **Rocks & Boulders**: $120$ deterministic instances with individual convex colliders on `LAYER_OBSTACLES`.
  * **Flora**: Bushes, plants, flowers scattered on gentle meadow slopes.
* **Key Queries**:
  * `sample_height(x: float, z: float) -> float`: Evaluates continental height. Features early-out bounding boxes to skip mountainous octaves in the flat valley.
  * `sample_normal(x: float, z: float) -> Vector3`: Computes normal via central finite differences.
  * `sample_spawn_floor_y(x: float, z: float, est_foot_y: float) -> float`: Determines whether an actor is on the overworld mountain surface or inside the cave, returning the appropriate floor height.

---

## 3. Subterranean Cave Network ([`cave_system.gd`](file:///d:/slime/terrain/cave_system.gd) & [`cave_layout.gd`](file:///d:/slime/tools/cave_layout.gd))

### Coordinate Systems & Layout Transformation
The cave uses a localized frame defined by [`CaveLayout`](file:///d:/slime/tools/cave_layout.gd):
* **Origin**: $\text{ORIGIN} = (-72.9, 26.0, -126.9)$ in world coordinates.
* **Forward (into mountain)**: $\text{FWD\_XZ} = (-0.425105, -0.905144)$ (NNW).
* **Right**: $\text{RIGHT\_XZ} = (0.905144, -0.425105)$ (ENE).
* **Conversion Methods**:
  * `CaveLayout.to_world(local: Vector3) -> Vector3`
  * `CaveLayout.to_local(world: Vector3) -> Vector3`

### Cavern Chambers & Features
1. **Entrance Outcrop / Twilight Passage**:
   * Cutout into the karst hillside with kitbashed talus, crags, and fallen logs.
2. **Breakdown Fork**:
   * Splits into the main high hall throat and the secret narrow **Split Crawlway** ($3.65\text{ m}$ clear width; full slime scale 1.0 is blocked, split slime scale $\le 0.794$ slips through).
3. **Collapse Hall**:
   * Enormous cathedral chamber ($70\text{ m} \times 46\text{ m}$, ceiling height $32\text{ m}$).
   * Dome apex at $50.5\text{ m}$, limestone karst cap at $56.5\text{ m}$.
   * **Skylight Key Spot**: Natural collapsed roof opening with volumetric sunbeams and dust motes.
   * **Breakdown Mound**: Central talus pile beneath the skylight.
   * **Spiraling Ledge Route**: 9-node path along the western/northern wall allowing slimes to scale the hall up to the mountain rim.
4. **Pool Basin & Waterfall**:
   * Deep natural limestone pool with custom reflective water shader ([`cave_water.gdshader`](file:///d:/slime/terrain/cave_water.gdshader)) fed by a vertical cavern cascade.
5. **Secret Geode Pocket**:
   * Crystalline hollow illuminated by glowing teal/magenta crystals ([`cave_crystal.gdshader`](file:///d:/slime/terrain/cave_crystal.gdshader)) with an interactive spinning geode reward.
6. **Abyssal Atrium & Underground Lake**:
   * Vast subterranean lake ($56\text{ m} \times 46\text{ m}$, water height $7.60\text{ m}$).
   * Terminates at **Vault Sanctum**, flanked by stone braziers and the monumental **Ancient Big Door** ($7.4\text{ m} \times 9.2\text{ m}$).

---

## 4. Cave Atmosphere Controller ([`cave_atmosphere.gd`](file:///d:/slime/scripts/cave_atmosphere.gd))

Attached dynamically to the scene, this controller samples the camera's location relative to `CaveSDF.eval_cave_void_smooth()` and blends:
1. **Sunlight Attenuation**: Rapidly throttles outdoor `Sun.light_energy` to prevent light leaking through the mountain ceiling underground.
2. **WorldEnvironment Exposure**: Transitions tonemap exposure from outdoor $1.05$ to cave $1.18$.
3. **Ambient Light Contribution**: Decreases sky contribution to $0.0$ and blends ambient tint from daylight cool sky to warm hall slate or cool grotto teal.
4. **Cavern Fog**: Enables exponential fog ($0.0082 - 0.0118$ density) inside the hall to produce realistic subterranean depth haze.
5. **Glow & Bloom**: Increases HDR bloom threshold to accent glowing crystals and skylight shafts.

---

## 5. Offline Baking Pipeline (`tools/bake_cave.gd`)

Cavern geometry is procedurally generated from [`CaveSDF.gd`](file:///d:/slime/tools/cave_sdf.gd) using Surface Nets / Marching Cubes:
1. Evaluates smooth min/max unions between tunnel capsules and chamber ellipsoids.
2. Generates vertex normals, baked ambient occlusion (AO in vertex color R), skylight visibility (G), and wetness (B).
3. Bakes binary resources:
   * `res://terrain/cave/cave_mesh.res` (Visual ArrayMesh with triplanar rock shader)
   * `res://terrain/cave/cave_floor_shape.res` (Walkable floor ConcavePolygonShape3D on layer 1)
   * `res://terrain/cave/cave_wall_shape.res` (Steep wall ConcavePolygonShape3D on layer 4)
