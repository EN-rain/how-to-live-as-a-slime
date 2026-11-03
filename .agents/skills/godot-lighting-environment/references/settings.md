# Settings reference — godot-lighting-environment

Checked against **Godot 4.7.2.stable** (class reference dumped from the 4.7.2 binary with `--doctool`, and
`doc/classes/*.xml` at tag `4.7-stable` of godotengine/godot for descriptions and renderer notes).
Defaults shown are Godot defaults; "preset" is the value used by `scripts/lighting_preset.gd`.

## DirectionalLight3D / Light3D

| Property | Default | Preset | Note |
|---|---|---|---|
| `light_color` | white | `Color(1.0, 0.86, 0.77)` | warm afternoon |
| `light_energy` | 1.0 | 1.5 | raise only with AgX on |
| `shadow_enabled` | false | true | |
| `shadow_blur` | 1.0 | — | quality/perf: see godot-render-performance |
| `directional_shadow_mode` | `SHADOW_PARALLEL_4_SPLITS` (2) | — | perf |
| `directional_shadow_max_distance` | 100.0 | — | perf: set to what the scene needs |
| orientation | — | elevation 28°, azimuth −35° | light shines along local −Z |

## Environment — sky & ambient

| Property | Default | Preset |
|---|---|---|
| `background_mode` | `BG_CLEAR_COLOR` | `BG_SKY` |
| `sky` → `Sky.sky_material` | — | `ProceduralSkyMaterial` |
| `ProceduralSkyMaterial.sky_top_color` / `sky_horizon_color` | — | blue / warmer horizon |
| `ambient_light_source` | `AMBIENT_SOURCE_BG` (0) | `AMBIENT_SOURCE_SKY` |
| `ambient_light_sky_contribution` | 1.0 | 1.0 |
| `ambient_light_energy` | 1.0 | 1.0 |
| `reflected_light_source` | `REFLECTION_SOURCE_BG` | `REFLECTION_SOURCE_SKY` |

## Environment — tone mapping & adjustments

| Property | Default | Preset | Note |
|---|---|---|---|
| `tonemap_mode` | `TONE_MAPPER_LINEAR` (0) | `TONE_MAPPER_AGX` (4) | AgX exists since Godot 4.4 (absent in 4.3-stable, present in 4.4-stable) |
| `tonemap_exposure` | 1.0 | 1.1 | |
| `tonemap_agx_contrast` / `tonemap_agx_white` | 1.25 / 16.29 | — | AgX-specific |
| `adjustment_enabled` | false | true | |
| `adjustment_contrast` / `adjustment_saturation` | 1.0 / 1.0 | 1.05 / 1.15 | |

## Environment — SSAO / SSIL / SDFGI

| Property | Default | Preset | Renderer |
|---|---|---|---|
| `ssao_enabled` | false | true | Forward+ and Compatibility, not Mobile |
| `ssao_radius` / `ssao_intensity` | 1.0 / 2.0 | scene-scaled / 2.0 | |
| `ssil_enabled` | false | true | Forward+ only |
| `ssil_radius` / `ssil_intensity` | 5.0 / 1.0 | — | |
| `sdfgi_enabled` | false | true | Forward+ only; only `GI_MODE_STATIC` meshes; GPU-demanding |
| `sdfgi_use_occlusion` | false | true | |
| `sdfgi_min_cell_size` | 0.2 | scene-scaled | |
| `sdfgi_energy` / `sdfgi_bounce_feedback` / `sdfgi_cascades` | 1.0 / 0.5 / 4 | — | |

Perf tip from the docs: `ProjectSettings.rendering/global_illumination/gi/use_half_resolution` for SDFGI.

## Environment — fog

| Property | Default | Preset |
|---|---|---|
| `fog_enabled` | false | true |
| `fog_mode` | `FOG_MODE_EXPONENTIAL` (0) | `FOG_MODE_DEPTH` (1) recommended |
| `fog_depth_begin` / `fog_depth_end` / `fog_depth_curve` | 10 / 100 / 1.0 | just past gameplay space / near horizon |
| `fog_density` | 0.01 | low (exponential); 1.0 lets depth mode reach full fog |
| `fog_light_color` | `Color(0.518, 0.553, 0.608)` | sky horizon colour |
| `fog_sky_affect` | 1.0 | 0.0 |
| `fog_aerial_perspective` | 0.0 | 0.5 (requires `BG_SKY`; small cost) |
| `fog_sun_scatter` | 0.0 | 0.1 |
| `fog_height` / `fog_height_density` | 0 / 0 | ground fog: use sparingly, keep paths readable |

Note: Godot 4.7 has no `fog_depth_enabled` / `fog_height_enabled` properties; use `fog_mode` and
`fog_height_density`.
