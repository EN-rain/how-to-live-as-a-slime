# Inspector Editability Migration — Task 1 Baseline Report

**Captured:** 2026-11-18  
**Environment:** Windows local Godot `v4.6.1.stable` (`Intel(R) Iris(R) Xe Graphics` for Vulkan, `--headless` for logic/compile tests)

---

## 1. Baseline Test Results (Before Any Migration Edits)

| Script | Outcome | Details / Recorded Failures |
|---|---|---|
| `res://tests/test_compile_all_scripts.gd` | **PASS** (exit `0`) | `SCANNED 33 SCRIPTS: 0 FAILURES` |
| `res://tests/test_run_main_scene.gd` | **PASS** (exit `0`) | `Main game ran for 60 frames successfully.` |
| `res://tests/test_cave_dungeon_territories.gd` | **PASS** (exit `0`) | `SPIDER_FOREST_TREES=413`, `STICKY_WEB_ZONES=15`, `WEBWOOD_DENSITY inner=106 (0.00959) fringe=87 (0.00328) ratio=2.924`, `ACTORS: wolves=7 spiders=61 rats=20 crypt_skeletons=10 overlord=true rat_king=true total=141`, `ALL_CAVE_DUNGEON_TERRITORY_CHECKS_PASSED` |
| `res://tests/test_quality_presets_and_startup.gd` | **FAIL** (assert) | Line 25: `Assertion failed: Low render scale should be 1.00`. Observed `SlimeSettings` presets: `0 Low (Scale: 0.58, Grass: 0.20)`, `1 Medium (Scale: 0.78, Grass: 0.55)`, `2 High (Scale: 1.00, Grass: 1.00)`, `3 Ultra (Scale: 1.00, Grass: 1.30)`. |
| `res://tests/capture_webwood_previews.gd` | **FAIL (Linux path)** | `PREVIEW_FAIL: could not create /home/agent/slime/webwood_previews` (hardcoded Docker path). Windows Vulkan equivalent `capture_spider_webwood_visuals.gd` **PASS** (6/6 PNGs saved). |

---

## 2. Startup, Build & Vulkan GPU Timings

- **Main scene init (`MAIN_INIT_MS`)**: `1137.68 – 1633.11 ms`
- **Webwood build (`_build_spider_webwood()`)**: `318.03 ms` (post-optimization baseline)
- **Vulkan GPU frame time (`trail → hollow → canopy`)**:
  - `trail`: `11.716 ms`
  - `hollow`: `14.968 ms`
  - `canopy`: `15.240 ms`

---

## 3. Existing `.tscn` Overrides & Resource Inventory

- `scenes/main.tscn`:
  - `Slime`: position `(-101.71, 22.85, -84.55)`, bound `camera`, `floor_mesh`, `props`.
  - `CameraRig`: `orbit_camera.gd`, bound `camera`, `follow`.
  - `Props` (`visible = false`): 12 authored test cubes (`Cube01..Cube12`).
  - `Ecosystem` (`props.gd`): `enable_test_structures = false`, `enable_food_cubes = false`.
  - `TerrainScene`: instanced `res://terrain/terrain.tscn` (no property overrides).
- `terrain/terrain.tscn`:
  - Uses default script `@export` values for `terrain.gd`, with `ShaderMaterial` defaults on `Terrain`, `Water`, `Grass`, `GrassWispy`, `GrassDistant`.
  - `Cave` (`res://terrain/cave/cave.tscn`): pre-wired `default_bake_config.tres`, `default_scatter_config.tres`, `default_water_config.tres`, `cave_layout.tres`.
- `resources/slime_tuning.tres`:
  - Empty override file (`script = ExtResource("1_tuning")`); all effective values come from `SlimeTuning` script defaults.
- `scenes/slime.tscn`:
  - Overrides `body = NodePath("Body")`, `SphereMesh` (`radius=1.6, height=3.2`), and `ShaderMaterial_instance` uniforms.

---

## 4. Disconnected / Suspected No-Op `@export` Audit

1. `SlimeTuning.core_sphere_radius_ratio` (`scripts/slime_tuning.gd`): exported, unused by `SlimeShapeModel` (uses `min_squeeze()`).
2. `TerrainScene.sea_level` (`terrain/terrain.gd`): drives visible water mesh only; `CaveSystem.sample_water_at()` (`terrain/cave_system.gd:363`) uses hardcoded `0.0` sea level.
3. `CaveWaterConfig.stream_flow_speed` (`terrain/cave/resources/cave_water_config.gd:17`): defaults to `1.35`, while `CaveSystem` gameplay flow query uses `1.45`.
4. `WorldLandmarks` static/const coords (`SPIDER_FOREST_CENTER`, `SPIDER_TRAIL_START`, `SPIDER_TRAIL_BEND`, `sticky_web_zones`): duplicated in `terrain.gdshader`, `grass.gdshader`, `grass_far.gdshader`, `tree_foliage.gdshader`, `territory_builder.gd`, and `world_ecosystem.gd`.
