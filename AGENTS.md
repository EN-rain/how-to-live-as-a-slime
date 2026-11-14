# AGENTS.md — Machine-Readable Developer Guide & Context Index

> **Target Audience**: AI Coding Assistants (Antigravity, Claude Code, Cursor, Copilot, Codex).
> **Primary Purpose**: Immediate orientation, strict architectural invariants, task-to-file routing, and verification commands. **Read this file before exploring raw code.**

---

## 1. Project At A Glance
* **Project Name**: *How to Live as a Slime*
* **Engine**: Godot Engine 4.6 (Mobile renderer, Forward+/Compatibility fallback).
* **Language**: GDScript 2.0 (typed) + Godot Shading Language (`.gdshader`).
* **Root Scenes**:
  * Entry Scene: `res://main_menu/main_menu.tscn` ([`main_menu.gd`](file:///d:/slime/main_menu/main_menu.gd))
  * Gameplay Sandbox: `res://scenes/main.tscn` ([`scenes/main.tscn`](file:///d:/slime/scenes/main.tscn))
* **Core Premise**: Physically-accurate anime jelly slime simulator with continuous collision sweeps, procedural soft-body deformation, volume conservation, organic mitosis/fission, digestion, and a vast continent with a subterranean SDF cavern.

---

## 2. Cardinal System Invariants (DO NOT VIOLATE)

1. **Single Transform Writer**:
   * [`SlimeMotor`](file:///d:/slime/scripts/slime_motor.gd) is the **only** entity permitted to write `global_position` or physical velocities.
   * Never assign `global_position` directly inside [`slime.gd`](file:///d:/slime/scripts/slime.gd) (except for render-interpolation in `_process()` on child node `Body`).
2. **The Core Sphere Clearance Rule**:
   * The slime has an outer visual/soft envelope ($R \approx 2.0\text{ m}$ at scale 1.0) and an invisible inner **Core Sphere** ($R_{\text{core}} = 0.36\text{ m}$, diameter $0.72\text{ m}$ at scale 1.0; ratio `0.18`).
   * An opening $\ge 0.72\text{ m}$ allows the slime to deform and pass through. An opening $< 0.72\text{ m}$ is impassable.
   * Sweeps must check both `core_sphere_center` and `core_sweep_origin` (foot-aligned).
3. **Collision Layer Contract**:
   * `Layer 1` (`1`): **Terrain & Cave Floor** (`LAYER_TERRAIN`)
   * `Layer 2` (`2`): **Slimes** (`LAYER_SLIMES`) — StaticBody3D proxies carrying shape cache.
   * `Layer 4` (`4`): **Obstacles & Solids** (`LAYER_OBSTACLES`) — Props, tree trunks, boulders, cave walls.
4. **Volume Conservation**:
   * Volume is strictly proportional to scale cubed: $V = \frac{4}{3}\pi R_{\text{vol}}^3 s^3$.
   * Mitosis/Fission splits volume $50/50$ along an S-curve. Merge restores volume exactly.
5. **Shape-to-Shader Math Parity**:
   * [`SlimeShapeModel._build_rest_profile()`](file:///d:/slime/scripts/slime_shape_model.gd#L77) and [`slime.gdshader::deformSlime()`](file:///d:/slime/shaders/slime.gdshader#L340) use **identical mathematical profiles**. Never edit one without matching the other.
6. **Shader Performance Rule**:
   * In [`terrain.gdshader`](file:///d:/slime/terrain/terrain.gdshader), all FBM and procedural noise is evaluated in the **vertex function** and passed as varyings. **Never add procedural noise to the fragment shader**.

---

## 3. Fast Task Routing Table ("Where to look for what")

| If you need to modify or debug... | Inspect these files first | Key Functions / Symbols / Uniforms |
| :--- | :--- | :--- |
| **Locomotion, Jumping, Slide, CCD** | [`scripts/slime_motor.gd`](file:///d:/slime/scripts/slime_motor.gd)<br>[`scripts/slime_tuning.gd`](file:///d:/slime/scripts/slime_tuning.gd) | `move_horizontal()`, `move_vertical()`, `_cast()`, `recover_overlap()` |
| **Body Shape, Convex Hulls, Squeeze** | [`scripts/slime_shape_model.gd`](file:///d:/slime/scripts/slime_shape_model.gd) | `resolve()`, `_build_rest_profile()`, `posture_key_for()`, `_cache_entry()` |
| **Mitosis / Fission, Budding, Merge** | [`scripts/slime.gd`](file:///d:/slime/scripts/slime.gd#L1465)<br>[`shaders/slime.gdshader`](file:///d:/slime/shaders/slime.gdshader#L361) | `split_clone()`, `_tick_fission()`, `_tick_budding()`, `merge_clones()`, `uSplitAmt`, `uSplitNeckRadius` |
| **Passage Traversal / Doorways** | [`scripts/slime.gd`](file:///d:/slime/scripts/slime.gd#L983)<br>[`scripts/props.gd`](file:///d:/slime/scripts/props.gd#L567) | `_update_passage()`, `find_passage()`, `measure_passage_pair()`, `PassageState` |
| **Follower & Roamer AI** | [`scripts/slime.gd`](file:///d:/slime/scripts/slime.gd#L1230) | `_process_follower_ai()`, `_process_roamer_ai()`, `breadcrumbs` |
| **Dev Mode (Flight, Noclip, Speed)** | [`scripts/slime.gd`](file:///d:/slime/scripts/slime.gd#L687) | `toggle_dev_mode()`, `toggle_dev_fly()`, `toggle_dev_noclip()`, `_tick_dev_movement()` |
| **Jelly Shader Optics (Refraction/Caustics)** | [`shaders/slime.gdshader`](file:///d:/slime/shaders/slime.gdshader) | `tRefraction`, `uDispersion`, `uRimStrength`, `uDayShallow`, `snoise()`, eye yaw/elev |
| **Prop Generation, Digestion & Eating** | [`scripts/props.gd`](file:///d:/slime/scripts/props.gd)<br>[`shaders/prop.gdshader`](file:///d:/slime/shaders/prop.gdshader) | `_process_edible_props()`, `_update_digesting_props()`, `uDissolve`, spatial hash `_grid` |
| **Slime-vs-Slime Overlap Separation** | [`scripts/props.gd`](file:///d:/slime/scripts/props.gd#L296) | `_separate_slimes()`, `apply_slime_separation()` |
| **Continent Terrain & Biomes** | [`terrain/terrain.gd`](file:///d:/slime/terrain/terrain.gd)<br>[`terrain/terrain.gdshader`](file:///d:/slime/terrain/terrain.gdshader) | `sample_height()`, non-linear grid, MultiMesh grass/trees/rocks |
| **Subterranean Cave & Karst SDF** | [`terrain/cave_system.gd`](file:///d:/slime/terrain/cave_system.gd)<br>[`tools/cave_layout.gd`](file:///d:/slime/tools/cave_layout.gd) | `CaveSystem`, `CaveLayout.to_world()`, `to_local()`, `sample_sdf_floor_below()` |
| **Cave Lighting & Atmosphere** | [`scripts/cave_atmosphere.gd`](file:///d:/slime/scripts/cave_atmosphere.gd) | `_evaluate_and_apply()`, sunlight attenuation, fog/exposure blending |
| **Orbit Camera & Occlusion** | [`scripts/orbit_camera.gd`](file:///d:/slime/scripts/orbit_camera.gd) | `_update_camera()`, `theta`, `phi`, `radius`, occlusion raycast |
| **Settings, Presets, Keybinds, Sound** | [`autoload/settings_manager.gd`](file:///d:/slime/autoload/settings_manager.gd) | `set_quality_preset()`, `set_action_primary_key()`, procedural WAV bank |
| **HUD & Debug Overlay** | [`scripts/hud.gd`](file:///d:/slime/scripts/hud.gd) | `_update_debug_overlay()`, `_draw_debug_3d()`, F3 toggle, wireframe mesh |
| **2D Main Menu & Interactive Mascot** | [`main_menu/main_menu.gd`](file:///d:/slime/main_menu/main_menu.gd)<br>[`main_menu/jelly_mascot_2d.gd`](file:///d:/slime/main_menu/jelly_mascot_2d.gd) | Threaded scene loading, spring-damper mascot physics, `CoreRuleDiagram2D` |

---

## 4. Verification & Testing Commands

Execute headless tests using Godot console binary:

```powershell
# Quick Smoke Test (instantiates main game and runs 60 frames)
& "C:\Users\LENOVO\Desktop\GodotGDScript\Godot_v4.6.1-stable_win64_console.exe" --headless --path d:\slime --script res://tests/test_run_main_scene.gd

# Menu Scene Smoke Test
& "C:\Users\LENOVO\Desktop\GodotGDScript\Godot_v4.6.1-stable_win64_console.exe" --headless --path d:\slime --script res://tests/test_run_main_menu.gd

# Collision Penetration Verification (Tests rock collision across all 8 approach angles)
& "C:\Users\LENOVO\Desktop\GodotGDScript\Godot_v4.6.1-stable_win64_console.exe" --headless --path d:\slime --script res://tests/test_fix_validation.gd

# Dynamic Terrain & Slope Traversal Test
& "C:\Users\LENOVO\Desktop\GodotGDScript\Godot_v4.6.1-stable_win64_console.exe" --headless --path d:\slime --script res://tests/test_dynamic_terrain_traversal.gd

# AncientBigDoor Collar Geometry Verification (rock-sealed rim & side seams, arch clasp, zero grazing normals)
& "C:\Users\LENOVO\Desktop\GodotGDScript\Godot_v4.6.1-stable_win64_console.exe" --headless --path d:\slime --script res://tests/test_door_wall_integration.gd

# Script Compilation Check (Verifies all project scripts compile cleanly)
& "C:\Users\LENOVO\Desktop\GodotGDScript\Godot_v4.6.1-stable_win64_console.exe" --headless --path d:\slime --script res://tests/test_compile_all_scripts.gd
```

### Docker Cloud Sandbox Testing & Baking Pipeline
For offloading heavy operations (such as offline 3D cave baking or long regression tests) to a Linux container, the repository includes a suite of PowerShell bridge scripts connecting to **Docker Cloud Sandboxes** (`ssh.sandboxes-cloud.docker.com`):
* [`sync-to-sbx.ps1`](file:///d:/slime/sync-to-sbx.ps1): Tarballs the project and SCPs it into the cloud sandbox at `~/slime`.
* [`run-sbx-cmd.ps1`](file:///d:/slime/run-sbx-cmd.ps1): Runs commands remotely (e.g. `powershell .\run-sbx-cmd.ps1 "godot --headless --path ~/slime --script res://tests/test_world_cave.gd"`).
* [`fetch-cloud-image.ps1`](file:///d:/slime/fetch-cloud-image.ps1): Fetches screenshots rendered headlessly inside Docker (`/home/agent/slime/cloud_visual_test.png`) back to `d:/slime/tests/`.
* [`pull-from-sbx.ps1`](file:///d:/slime/pull-from-sbx.ps1) / [`push-to-sbx.ps1`](file:///d:/slime/push-to-sbx.ps1): SCP transfer of baked binary assets between host and container.
* [`connect-sbx.ps1`](file:///d:/slime/connect-sbx.ps1): Interactive SSH shell into the Docker container.
* *Note*: Cloud sandbox authentication uses an SSH certificate (`cert.pub`). When expired, refresh the cert or run tests locally with the console binary above.

---

## 5. Architectural Deep-Dives

When you need detailed symbol definitions, sequence diagrams, and mathematical models, refer directly to:

* [**Physics & Locomotion Stack**](file:///d:/slime/docs/architecture/physics_and_motor.md)
* [**Terrain, Biomes & SDF Cave System**](file:///d:/slime/docs/architecture/terrain_and_cave.md)
* [**Prop Ecosystem, Digestion & Slime Separation**](file:///d:/slime/docs/architecture/ecosystem_and_props.md)
* [**Shaders, Optics & Material Pipelines**](file:///d:/slime/docs/architecture/shaders_and_vfx.md)
* [**UI, Settings, Audio Synthesis & HUD**](file:///d:/slime/docs/architecture/ui_and_settings.md)
