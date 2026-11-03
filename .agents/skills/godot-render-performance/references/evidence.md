# Evidence: measured on a reference scene

**Setup.** Godot 4.7.2.stable, Forward+, **1280×720** (the window size was requested at 1920×1080 but the test project rendered at its 1280×720 base size; the json logs confirm 1280×720), vsync off, AMD RX 6950 XT. Full village scene: sun
preset, sky, AgX, SSAO, SSIL, SDFGI, depth fog, leaf shader, blended ground, 20 000 grass tufts (MultiMesh),
fill light, MSAA 4x + TAA, vignette/grain, dust. `scripts/bench_switches.gd` was run as shipped: 90 warm-up
frames and 240 measured frames per configuration, fixed camera. GPU ms = `viewport_get_measured_render_time_gpu`.
Absolute numbers are small because this GPU is fast. Ratios are what matter, and they were stable across 3 runs.

## Leave-one-out with an expensive sun preset (shadow atlas 8192, Soft Ultra filter, PCSS, distance 200)

| Feature removed from the full scene | GPU ms saved (3 runs) |
|---|---|
| SDFGI | 0.376-0.383 |
| AA (MSAA 4x + TAA) | 0.203-0.219 |
| **Sun preset (because of its shadow settings)** | **0.203-0.212** |
| SSIL | 0.173-0.181 |
| Post (vignette/grain) + dust | 0.068 |
| SSAO | 0.049 |
| Fog (depth) | 0.016 |
| Grass (20 000 tufts, no shadows, visibility range) | 0.008 |

Full scene: 1.076-1.082 GPU ms (≈ 782 fps); all features off: 0.174 GPU ms.

## Keep the sun, lower its shadows

Same sun direction, colour and energy; shadows changed to `shadow_budget.gd` "medium" (atlas 4096, Soft Low,
4 splits, no PCSS) with `directional_shadow_max_distance` 40 (gameplay-sized for this scene):

| | Full scene GPU ms | fps | sun preset's extra cost |
|---|---|---|---|
| Sun shadows "ultra", distance 200 | 1.08 | 782 | ≈ 0.21 ms |
| Sun shadows "medium", distance 40 | **0.85** | **950** | ≈ 0 ms (vs Godot defaults) |

Visual difference, ultra → medium / ultra → low (mean absolute pixel difference, 1280×720): wide view 0.19 % /
0.23 %; close-up of barrels and rocks 0.45 % / 0.55 %; long view 0.09 % / 0.14 %. Side by side, only the
PCSS-softened shadow edges of "ultra" can be told apart. That is a lot of cost for a barely visible difference.

## Earlier measurement (vegetation skill), same method

20 000 grass tufts at 1280×720: one MultiMeshInstance3D 1.25 ms per frame vs 20 000 MeshInstance3D nodes
5.50 ms (p95 1.42 vs 7.98 ms).

## Iteration 2: PCSS × shadow distance (found by an eval run, then re-measured)

Same method (1280×720, 240 frames, 3 runs; shadow atlas 8192, Soft Ultra filter) on a lighter scene: sun, sky,
AgX, leaf shader, ground, 20 000 grass tufts (no SSAO/SSIL/SDFGI). GPU ms:

| | distance 200 | distance 40 |
|---|---|---|
| PCSS off (`light_angular_distance` 0) | 0.21-0.27 | 0.22 |
| PCSS on (`light_angular_distance` 1.0) | 0.31 | **0.68-0.70** |

With PCSS on, shortening the shadow distance more than doubled the cost. Without PCSS it changed nothing
measurable in this scene. Conclusion: decide PCSS first. The iteration-1 gain ("ultra" → "medium", 1.08 →
0.85 ms) came from PCSS + filter + atlas, not from the shorter distance.
