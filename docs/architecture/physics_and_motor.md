# Physics, Shape Model & Locomotion Stack

> **Context**: Deep technical architecture reference for [`scripts/slime.gd`](file:///d:/slime/scripts/slime.gd), [`scripts/slime_motor.gd`](file:///d:/slime/scripts/slime_motor.gd), [`scripts/slime_shape_model.gd`](file:///d:/slime/scripts/slime_shape_model.gd), and [`scripts/slime_tuning.gd`](file:///d:/slime/scripts/slime_tuning.gd).

---

## 1. Subsystem Architecture Overview

The slime locomotion and collision pipeline is strictly decoupled:

```
[Slime.gd (Actor & High-level State)]
   │
   ├── Input processing & AI desired velocity
   ├── Scale animation & volume tracking (V ∝ s³)
   ├── Passage FSM (OPEN -> APPROACHING -> ENTERING -> INSIDE -> EXITING)
   ├── Mitosis/Fission & Merge animation clocks
   └── Visual smoothing in _process() (slope normal alignment)
   │
   ▼
[SlimeShapeModel.gd (Authoritative Dimensions & Convex Hull Caching)]
   │
   ├── Mathematical rest profile (matches deformSlime() in vertex shader)
   ├── Quantized posture integer keys: (scale, liquid, height_ratio, squeeze, axis)
   ├── Conservative cached ConvexPolygonShape3D shapes
   └── Shape erosion variants (Tight = 0.5 * skin for growth, Loose = 2.0 * skin for hold)
   │
   ▼
[SlimeMotor.gd (Physical Solver & CCD)]
   │
   ├── Single writer of global_position & motor.velocity
   ├── Sweep-and-slide horizontal motion (cast_motion over equal budgeted substeps)
   ├── Dual-origin sweeps (core_sphere_center & core_sweep_origin)
   ├── recover_overlap() (averaging up to 8 contact normals to prevent corner traps)
   └── update_support() & move_vertical() (downward support query with climb reach)
```

---

## 2. Key Classes & Symbol Maps

### [`SlimeTuning.gd`](file:///d:/slime/scripts/slime_tuning.gd)
Authored immutable resource (`res://resources/slime_tuning.tres`) shared across slimes.
* **Movement**: `walk_speed = 3.0`, `run_speed = 10.0`, `liquid_speed = 2.2`, `velocity_response = 8.0`, `gravity = 22.0`, `climb_reach = 0.40`.
* **Solver Quality**: `max_probe_steps = 12`, `min_probe_steps = 2`, `max_move_substeps = 6`, `slide_iterations = 4`, `recovery_iterations = 6`.
* **Dimensions**: `reference_radius = 1.6`, `melt = 0.28`, `volume_radius = 1.6`, `skin = 0.02`.
* **Core Sphere & Clearance**: `min_normal_squeeze = 0.18`, `min_liquid_squeeze = 0.12`, `core_sphere_radius_ratio = 0.95`.
* **Methods**:
  * `volume_per_scale_cubed() -> float`: Returns $\frac{4}{3}\pi R_{\text{vol}}^3$.
  * `validate() -> void`: Clamps all values to safe bounds to prevent divide-by-zeros.

---

### [`SlimeShapeModel.gd`](file:///d:/slime/scripts/slime_shape_model.gd)
Owns the mathematical rest profile and builds conservative baked convex collision envelopes.
* **Constants**: `PROFILE_RINGS = 13`, `PROFILE_SEGMENTS = 24`, `RADIUS_SAMPLES = 48`, `HULL_CACHE_MAX = 512`.
* **Key Fields**: `scale`, `liquid`, `height_ratio`, `spread`, `squeeze`, `axis`, `foot`, `full_height`, `semi_a`, `semi_b`, `shape: ConvexPolygonShape3D`.
* **Core Methods**:
  * `configure(t: SlimeTuning) -> void`: Initializes rest half height and calls `_build_rest_profile()`.
  * `_build_rest_profile() -> void`: Generates 3D profile vertices using polynomial melt math matching the shader.
  * `resolve(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis) -> bool`: Re-derives dimensions and updates the cached convex hull if the quantized posture key changed.
  * `posture_key_for(scale, liquid, height, squeeze, axis) -> int`: Generates canonical 64-bit integer bitmask signature:
    $$\text{key} = (s_x \ll 40) \mid (l_q \ll 32) \mid (h_r \ll 24) \mid (s_q \ll 16)$$
  * `core_sphere_radius() -> float`: Returns `rest_max_radius * scale * min_squeeze() * tuning.core_sphere_radius_ratio` ($0.36\text{ m}$ at scale 1.0).
  * `core_sphere_center() -> Vector3`: Returns `foot + Vector3(0, rest_half_height * scale, 0)`.

---

### [`SlimeMotor.gd`](file:///d:/slime/scripts/slime_motor.gd)
The physical locomotion and collision solver.
* **Collision Layers**:
  * `LAYER_TERRAIN = 1`
  * `LAYER_SLIMES = 2`
  * `LAYER_OBSTACLES = 4`
  * `LAYER_SOLID = LAYER_TERRAIN | LAYER_OBSTACLES | LAYER_SLIMES`
* **Key Fields**: `velocity`, `vertical_vel`, `support_y`, `on_ground`, `ground_normal`, `contact_normals`, `contact_bodies`, `impact_speed`.
* **Core Methods**:
  * `move_horizontal(motion: Vector3) -> void`:
    * Subdivides motion into `MAX_MOVE_SUBSTEPS = 6` chunks.
    * Uses `cast_motion` on `core_sphere_shape()` from both `center_pos` and `base_pos` (`core_sweep_origin()`).
    * Slides along contact normals up to `slide_iterations = 4`.
  * `recover_overlap() -> void`:
    * Queries `get_rest_info` up to 8 times from `core_sweep_origin()`.
    * Averages all contact normals to compute an escape trajectory rather than ping-ponging in corners.
  * `update_support() -> void`:
    * Downward swept cast checking terrain (`LAYER_TERRAIN`) and obstacles (`LAYER_OBSTACLES`).
    * Incorporates `climb_reach` to step up onto ledges without sinking underground.
    * Checks `ceiling_clearance_up()` to reject stepping onto ledges where the headroom is insufficient.
  * `move_vertical(dt: float, target_scale: float) -> void`:
    * Integrates gravity ($22.0\text{ m/s}^2$) when airborne.
    * Anchors foot to `support_y + tuning.skin` using upward/downward sweeps.
  * `apply_slime_separation(push: Vector3, normal: Vector3) -> float`:
    * Applies caller-computed separation from [`props.gd`](file:///d:/slime/scripts/props.gd) while sweeping only against obstacles to prevent mutual veto.

---

### [`Slime.gd`](file:///d:/slime/scripts/slime.gd)
The high-level character actor.
* **Roles**: `PLAYER`, `FOLLOWER`, `ROAMER`.
* **Lifecycle**:
  * `_prepare_for_pool()` / `_activate_from_pool()`: Object pooling for fission/merge recycling.
* **Passage FSM**:
  * `_update_passage()`: Tracks latched passages between two obstacles across 5 states (`OPEN`, `APPROACHING`, `ENTERING`, `INSIDE`, `EXITING`).
* **Mitosis / Fission Pipeline**:
  * `split_clone(role)`: Validates preflight space in 10 radial directions (`split_angles`), determines snap separation `d_snap` and parent recoil share `parent_share`.
  * `_tick_fission(dt)`: Advances timer, updates parent scale along S-curve, transfers volume to clone, drives hourglass bridge uniforms (`uSplitAmt`, `uSplitNeckRadius`, `uSplitPartnerLocal`).
  * `_tick_budding(dt)`: Advances clone along separation vector, triggers snap impulse at `split_snap = 0.68`, enables collision once clear.
* **Visual Smoothing**:
  * `_process(_delta)`: Interpolates position between `_prev_global_pos` and `global_position`. Slerps `_visual_up` toward `motor.ground_normal` with foot-anchored slope offset so the base lies flush against slopes.

---

## 3. Posture Quantization & Caching Flow

```
Continuous Posture (scale, liquid, height_ratio, squeeze, axis)
                       │
                       ▼
       SlimeShapeModel.posture_key_for()
                       │
             [Check _hull_cache]
             ├── HIT  ──> Reuse immutable cached Shape3D
             └── MISS ──> Bake unit profile -> Cache entry -> Evict LRU (>512 entries)
```
This guarantees that steady-state locomotion and near-steady squeezes consume **0 CPU cycles** generating convex polygon shapes.
