# Prop Ecosystem, Digestion & Slime Separation

> **Context**: Deep technical architecture reference for [`scripts/props.gd`](file:///d:/slime/scripts/props.gd) and [`shaders/prop.gdshader`](file:///d:/slime/shaders/prop.gdshader).

---

## 1. Subsystem Architecture Overview

[`SlimeProps.gd`](file:///d:/slime/scripts/props.gd) runs at physics priority 100 (after slimes have resolved their movement). It manages:

```
[SlimeProps (Ecosystem Manager)]
   │
   ├── 2D Spatial Hash Grid (_grid: 10m cells)
   │     └── Accelerates nearby queries from O(N) to O(1)
   │
   ├── Prop Geometries & Colliders
   │     ├── Boxes, Prisms, Cylinders, Pyramids, Cones
   │     └── StaticBody3D colliders on LAYER_OBSTACLES (Layer 4)
   │
   ├── Digestion Pipeline
   │     ├── Edibility evaluation (prop volume <= 0.98 * slime volume)
   │     ├── State machine: STATE_IDLE -> STATE_EATING -> STATE_GONE
   │     ├── Shader dissolve drive (uDissolve in prop.gdshader)
   │     └── Mass & volume transfer into Slime.add_volume()
   │
   ├── Symmetric Analytic Slime-vs-Slime Separation
   │     ├── 1D X-axis broadphase sweep
   │     ├── Analytical horizontal support overlap check
   │     ├── Mass-weighted push distribution (Player has 2x virtual mass)
   │     └── Wall-pinned backstop redirection
   │
   └── Floor Blob Shadow Projection
         └── Pushes up to 8 slime blob positions and radii into floor.gdshader
```

---

## 2. Prop Representation & Digestion State Machine

### `PropData` (Inner RefCounted Class)
* **Shapes**: `SHAPE_BOX` (0), `SHAPE_PRISM` (1), `SHAPE_CONE` (2).
* **States**:
  * `STATE_IDLE` (0): Intact solid obstacle on `LAYER_OBSTACLES`.
  * `STATE_EATING` (1): Actively engulfed and dissolving; collider disabled, uniform uploaded to slime shader.
  * `STATE_GONE` (2): Fully digested; mesh hidden and freed from active list.
* **Key Fields**: `mesh`, `material`, `body`, `collider`, `half`, `total_mass`, `absorbed_mass`, `real_volume`, `engulf_front`, `last_presser`, `eater`.

### Edibility & Consumption Cycle
1. **Edibility Criterion**: A prop can be pushed and eaten if:
   $$\text{prop.real\_volume} \le \text{slime.get\_volume()} \times \text{tuning.edible\_volume\_ratio}\quad (\approx 0.98)$$
2. **Contact & Push**:
   * When a slime pushes against an edible prop, `engulf_front` advances.
   * If `engulf_front` exceeds threshold, the prop transitions to `STATE_EATING`.
3. **Dissolution**:
   * In `STATE_EATING`, `t` increases toward `tuning.eat_time` ($0.8\text{ s}$).
   * The prop's material updates `uDissolve = t / eat_time`.
   * [`prop.gdshader`](file:///d:/slime/shaders/prop.gdshader) discards fragments based on 3D procedural noise with an animated glowing emission edge (`uGlow`).
4. **Volume Transfer**:
   * As the prop dissolves, mass transfers proportionally into `eater.add_volume()`.
   * Upon reaching `STATE_GONE`, `eater.inside_props` removes the prop and emits `eaten_changed`.

---

## 3. Shader Uniform Bridge

To allow the slime's visual jelly shader to "wrap" around nearby obstacles and render objects floating inside its body during digestion, `props.gd` maintains fixed-size uniform buffers:

* **Digestion (`uEatPos`, `uEatParam`, `uBoxHalf`)**:
  * Up to 6 simultaneous items being digested.
  * Tracks local position inside the slime, shape type, and bounding extents for interior rendering.
* **Solid Contact Dents (`uSolidPos`, `uSolidParam`, `uSolidHalf`, `uSolidDir`)**:
  * Up to 8 closest solid obstacles.
  * Allows [`slime.gdshader`](file:///d:/slime/shaders/slime.gdshader) to dent inward realistically when pressing against walls, gates, and boulders without penetrating the geometry.

---

## 4. Analytic Slime-vs-Slime Separation Solver

When multiple slimes (Player, Followers, Roamers) overlap due to posture transitions, spawning, or corner clustering, `_separate_slimes()` resolves overlap symmetrically:

```
Step 1: Collect active bodies & project to horizontal 2D disc bounding bounds
Step 2: 1D Sweep-and-Prune sort along X axis (stops check when dx > 2 * max_reach)
Step 3: Pairwise overlap penetration test:
        pen = ra + rb - skin - distance
Step 4: Compute mass-weighted push:
        push_a = -dir * (pen * mass_b / total_mass)
        push_b = +dir * (pen * mass_a / total_mass)
Step 5: Apply via SlimeMotor.apply_slime_separation(push, normal):
        Only tests against LAYER_OBSTACLES so slimes do not veto each other
Step 6: Wall-Pinned Backstop Redirection:
        If body A is pinned against a solid wall (denied push > 0),
        the denied portion transfers to free body B so the cluster does not jitter!
```

---

## 5. Passage Measurement & Caching

* `rebuild_passage_pairs()`: Evaluates all pairs of idle props within $12\text{ m}$. Caches geometry measurements (`width`, `half_length`, `flow`, `axis`, `center`).
* `find_passage(slime: Slime) -> Dictionary`: Finds the most relevant passage ahead of the slime's velocity vector.
* `measure_passage_pair(slime, a, b) -> Dictionary`: Live re-measurement of the latched pair during transit to ensure continuous squeeze deformation until the trailing edge has exited.
