# How to Live as a Slime: Agent Guide

**What this is:** a 3D Godot game, cute but dark. You play a tiny slime; you eat, you grow, until you can eat the world. Open sandbox, no win condition. The world's reactions are the progression.

**Read this first:** [`how-to-live-as-a-slime-plan.md`](how-to-live-as-a-slime-plan.md) covers concept, pillars, size tiers, build order, prototype scope and risks. Do not re-derive the design; follow the plan. Where this file and the plan disagree on implementation details, this file wins (see "Known debt and deliberate shortcuts").

## Engine and project setup

- **Godot 4.6**, **Forward+** renderer, **Jolt Physics**, Windows D3D12 driver (`project.godot`).
- Forward+ has SSIL and SDFGI; Mobile and Compatibility do not. Keep that in mind before suggesting renderer changes.
- `[dotnet] project/assembly_name="How to live as a slime"` is set, but **no C# code exists. Default to GDScript.** Ask before introducing C#.
- Project root is this directory (`D:\how-to-live-as-a-slime`). `.godot/` is editor cache: never edit it by hand and never commit it (keep it in `.gitignore`).
- Git repository: `origin` is https://github.com/EN-rain/how-to-live-as-a-slime (public, `main`). Commit in small, focused commits. Never force-push `main`.
- Godot is **not on PATH.** Open the project in the Godot 4.6 editor and press F5/F6 to run. For headless commands, use the full executable path, e.g.:
  `& "<path-to-godot-4.6>\Godot_v4.6-stable_win64.exe" --headless --path . res://tests/smoke_test.tscn`
  If the path is unknown, ask the user rather than guessing.
- Main scene: `res://scenes/main.tscn`.

## Verify every change

1. The project must open in the Godot 4.6 editor without errors or warnings you introduced.
2. Run the headless smoke test (`res://tests/smoke_test.tscn`: boot, resource wiring, eat/grow/dissolve/damage, input map, overlap growth). It must exit 0.
3. If you changed gameplay, say what you tested by hand (F5/F6) and what you could not test.
4. If a change breaks the smoke test, fix the change, not the test, unless the test itself is wrong. Say so if you edit it.

Last validated with **Godot 4.6.stable**: import, a 480-frame rendered run, and the smoke test at 11/11 (exit 0).

**Adding a new `class_name` needs a rescan first.** A fresh class is not in the global class cache until `--headless --import` (or opening the editor) runs; scripts referencing it fail to compile before that. `--headless` does not compile shaders, so also do one windowed run for look changes.

## Inspector-editable by default (but not everything)

**Rule of thumb:** export what a designer would tune (balance, feel, content, tuning values). Hard-code what is structure or an invariant (things that would break the game if someone changed them in the Inspector).

### Make it inspector-editable

- **Tunable values** use `@export`: speeds, jump, growth curve, thresholds, colors, durations, ranges, sizes. Use `@export_range`, `@export_group` and `@export_subgroup` to keep the Inspector readable.
- **Data sets** (edible kinds, mob kinds, size tiers) use custom `Resource` classes (`.tres`), one per kind, assigned in the Inspector, instead of `const` dictionaries in code.
- **References** to nodes and scenes use `@export` (`@export var edible_scene: PackedScene`, `@export var camera: Camera3D`) instead of long `get_node("../Foo")` paths or `load("res://...")` strings.
- **Shader values** that affect the look go in `uniform`s with hints (`: source_color`, `hint_range`) so they are editable on the material.
- **Input actions** belong in Project Settings > Input Map.
- **Scene structure** (meshes, collision shapes, lights, particles) belongs in `.tscn` files rather than being built in `_ready()`, unless it must be generated at runtime.

### It is fine, and often correct, to hard-code

- **True constants:** math constants, epsilons, enum values, array and buffer sizes.
- **Invariants and wiring:** collision layer indices, group names, signal names, node names that code depends on, input action names. Changing these in the Inspector would break things, so exposing them is a hazard, not a feature.
- **Derived values:** anything computed from exported values (e.g. camera distance from size) should be calculated, not exported separately.
- **Values with dependencies:** things that must stay in sync with each other (ratios that sum to 1, curve endpoints, related thresholds). Export one source of truth and derive the rest.
- **Internal algorithm details:** shader math, easing constants, steering formulas, anything nobody would sensibly tune.
- **One-off prototype values** that are not worth a slot in the Inspector yet. Mark them with a short comment.

### How to hard-code well

- Never leave a magic number inline. Use a named `const` at the top of the script (`const MAX_STEPS: int = 8`) with a one-line comment saying why it is fixed.
- If you are unsure whether to export something, export it with a sensible default, unless exposing it could create an invalid state. Do not clutter the Inspector with values nobody will tweak.
- Give every export a sensible default so scenes still run when nothing is set. Document non-obvious exports with a `##` comment (it shows as a tooltip in the Inspector).
- Before adding a literal number or string, ask: "would a designer want to tweak this, or would changing it break something?" Tweakable means export; breakable means hard-code as a named constant.

New code follows this rule. Existing code that breaks it is listed under "Known debt" and should be migrated when touched, not silently copied.

## Agent skills (`.agents/skills/`)

Each skill is a directory with a `SKILL.md`. Load a skill **only when the task matches its description**; do not load them all at once.

- **Godot engine** (`awesome-gamedev-agent-skills`, Apache-2.0, @ `19d93f9`): `godot-3d-essentials`, `godot-shaders`, `godot-physics`, `godot-animation`, `godot-gdscript`, `godot-nodes-scenes`, `godot-signals-groups`, `godot-resources`, `godot-audio`
- **Discipline** (same source): `shader-programming`, `game-feel`, `camera-systems`, `performance-optimization`, `game-ai`, `physics-tuning`
- **Rendering / visual quality** (`godot-skill-quality`, MIT, @ `1771e83`): `godot-lighting-environment`, `godot-vegetation-shaders`, `godot-lights-camera-post`, `godot-render-performance`

Good fits for this project: `godot-resources` for the data-driven refactor, `godot-signals-groups` for eating and size-tier events, `game-feel` for juice, `camera-systems` for the growth pull-back.

**Version note:** the rendering pack was measured on Godot 4.7.2. This project is on 4.6. Verify any snippet against 4.6 before using it, and avoid 4.7-only features.

Not installed on purpose: the `awesome-gamedev-agent-skills` router (it expects the full set), 2D/Unity/other-engine skills, and C# skills.

## Conventions from the plan (follow these)

- **Build order:** slime movement, eating, growth, toon look, content, mobs, juice, tone. Finish all 8 at low quality before polishing any one.
- **The slime:** `CharacterBody3D` + vertex-wobble `spatial` shader + squash and stretch. Get the feel right first.
- **Reusable scenes:** build `Edible` (Area3D trigger; size, nutrition, color) and `Mob` (state machine) **once** and reuse them everywhere.
- **Placeholders:** primitives and free CC0 models. No custom world art until the loop works. The slime itself is built in code and shader, not from a model.
- **Map:** small and hand-placed. **No procedural generation.**
- **Scope:** 3 size tiers (bugs, critters, people), about 10-12 edibles, 2-3 enemy types for the prototype. Cut the rest for now.
- **Growth:** scale player, camera distance, speed, jump and physics together. Keep a size gate (you can only eat things smaller than you).
- **Darkness:** comes from the world's reactions and visual tone, not from story.

## GDScript style

- Static typing everywhere (`var speed: float`, `func eat(target: Edible) -> void`).
- `snake_case` for variables, functions and files; `PascalCase` for classes and nodes.
- Use signals for cross-node communication ("eaten", "size_tier_changed"); do not reach across the tree.
- Prefer composition and instancing over deep inheritance.
- Keep scripts small and single-purpose.

## Collision layers

Eating relies on `Area3D` layers and masks. Verified against `project.godot` and the scene files: the layer **indices** are 1-4, and the stored bitmasks are 1, 2, 4, 8.

| Layer | Name | Bit | Who is on it | Who scans it |
|---|---|---|---|---|
| 1 | World | 1 | ground, rocks, trees | slime, mobs |
| 2 | Slime | 2 | the player | mobs (for bite and chase) |
| 3 | Mob | 4 | villagers, birds | slime (eat `Area3D`) |
| 4 | Edible | 8 | edible triggers | slime (eat `Area3D`) |

Where this shows up in files: slime `collision_layer = 2`, `collision_mask = 5` (world + mob); mob `collision_layer = 4`, `collision_mask = 3` (world + slime); edible `collision_layer = 8`; slime `EatArea` `collision_mask = 12` (mob + edible).

The layer **names** above are not set in Project Settings yet — the bits are what matter. If you add the names, keep this table in sync.

## Adding content

- **Edibles and mobs are resources.** Duplicate a `.tres` in `resources/edibles/` or `resources/mobs/`, edit it in the Inspector, then reference it from `EDIBLE_GROUPS` (edibles) or a spawn call. No script edits.
- Keep `id` unique: it is the mesh-cache key, so two kinds sharing an id share a mesh.
- Balance lives in the resource, not the script. `EdibleData`/`MobData` are the source of truth; the scripts only read them.
- Build the `Edible`/`Mob` scenes once and instance them; do not build one-off scenes for a single object.

## Known debt and deliberate shortcuts

These were prototype shortcuts. **Do not "fix" them as a drive-by.** Ask first, then migrate them as a planned refactor toward the inspector-editable rule above (only the tunable and content values, not true constants or wiring).

- **Mobs use steering, not `NavigationAgent3D`.** The map is flat and hand-placed, with no runtime navmesh bake. Swap when the map gains obstacles. (The plan mentions `NavigationAgent3D`; steering is the current truth.)
- **Edible and mob visuals are built at runtime from primitives** inside their scenes. Target: build them in `.tscn` files.
- **`main.gd` still builds the world in code** (lighting, ground, trees, rocks). Target: a world scene with exported settings.
- **Internal child references are still `$Body` / `$Mesh` / `$HUD/Label`**, and the slime's eyes are built in `_ready()`. Node names are wiring, so this is lower priority than the world refactor; move the eyes into `slime.tscn` when touching the look.
- No menus, save system, win screen or threat meter. All explicitly cut in the plan.

## Current state (prototype pass 2: optimized)

`scenes/main.tscn` is playable: eat, grow, camera pull-back, toon look, 11 edibles in 3 tiers, villagers and birds that flee or fight, juice (sound, particles, shake, HUD), and restart on R.

**Performance budget: 60 fps on integrated graphics.** Measured on Intel Iris Xe (D3D12, Forward+, 1152×648) with `--print-fps --disable-vsync`: **12-17 fps** in pass 1, **~85-100 fps** now.

Frame-rate check (read the tail of the `Project FPS` lines; the first few include load hitches):

```
godot --path . --print-fps --disable-vsync --quit-after 480
```

| Change | Effect |
|---|---|
| `SSAO_ENABLED = false` in `main.gd` | +~55 fps (the single biggest win) |
| `SDFGI_ENABLED = false` in `main.gd` | +~10 fps |
| `ToonMaterial.shared()` + per-kind mesh cache | fewer materials, fewer rebuilds |
| `instance uniform float dissolve` in `toon.gdshader` | dissolve per instance on a shared material |
| 2 shadow cascades over 55 m, shadows only on props >= 1.5 m | cheaper shadow map |
| `visibility_range_end` on props/mobs, camera far 160 m | less overdraw |

Rules for new content: reuse `ToonMaterial.shared()` (never `make()` in a spawn loop), cache meshes per kind, set `visibility_range_end`, and use `instance uniform` + `set_instance_shader_parameter` for per-object effects instead of per-instance materials. Do not flip SSAO/SDFGI back on without measuring.

## Project map (content and data)

| Path | What lives there |
|---|---|
| `scripts/data/edible_data.gd`, `mob_data.gd` | Resource classes: the shape of the content data |
| `resources/edibles/*.tres` | 11 edible kinds, one file each (id, shape, size, nutrition, colour) |
| `resources/mobs/*.tres` | villager and bird (size, speeds, flies, colour, bite stats) |
| `resources/` | Add new kinds here; then reference them from `EDIBLE_GROUPS` or a spawn call |
| `tests/smoke_test.tscn` | Headless regression test (11 checks) |
| `project.godot` → `[input]` | Movement, jump and restart bindings |

Non-obvious notes:
- `scripts/lighting_preset.gd` is vendored **verbatim** from the `godot-lighting-environment` skill (MIT). Do not edit it.
- `assets/sounds/pop.wav` was generated procedurally; there is no external audio asset.
- `scripts/toon_material.gd` is the cel material factory; the outline is an inverted-hull `next_pass`.
- `scripts/icosphere.gd` builds the slime body mesh (plan §8: an icosphere wobbles evenly, a UV sphere pinches at the poles).
- Shared eat contract: `Edible` and `Mob` use the same eat/absorb interface (`try_eat`, `absorb`); keep it consistent.
- `area_entered` fires once, so `Slime._sweep_eat_overlaps()` re-checks the eat area after every size change. Without it you cannot eat something you grew past while standing still. Keep the sweep if you replace the eat area.
- Physics-state changes (`monitorable`, `collision_layer`, `CollisionShape3D.disabled`) must be deferred when made from inside `area_entered`/`body_entered` callbacks, or Godot errors with "Function blocked during in/out signal".
- `Edible`/`Mob` export `data: EdibleData`/`MobData`. Spawn code must set `data` before `add_child()`, because `_ready()` reads it. Both scripts fall back to a default resource if it is unset, so a freshly placed node still runs.

**Tuning knobs:** `Slime`'s exported `Movement`, `Growth`, `Feel` and `Look` groups (Inspector); `resources/edibles/*.tres`; `resources/mobs/*.tres`; the `EDIBLE_GROUPS` spawn table in `main.gd`; `SDFGI_ENABLED`/`SSAO_ENABLED`.

## Working agreement

- Work in this directory only.
- **Ask before:** changing `project.godot` renderer or physics settings, adding plugins or asset packs, or switching GDScript to C#.
- Keep scenes small and composable; prefer instancing `Edible` and `Mob` over hand-built duplicates.
- Every change must leave the project openable in the Godot 4.6 editor without errors.
- Licenses: installed skills are Apache-2.0 (`awesome-gamedev-agent-skills`) and MIT (`godot-skill-quality`). Keep their attribution intact.
