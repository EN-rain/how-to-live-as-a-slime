---
name: godot-render-performance
description: >-
  Find and fix what makes a good-looking Godot 4 3D scene slow, without throwing away the look: measure each
  visual feature's GPU cost at a fixed view (alone and "everything except this one"), then lower the cost of
  the expensive feature's sub-settings (shadow map size, soft-shadow filter, shadow distance, MSAA samples,
  SDFGI, grass draw distance) instead of deleting the feature. Ships a reusable GDScript bench and sun-shadow
  quality presets. Use this whenever a Godot scene's FPS dropped after adding lighting, shadows, SDFGI, SSAO,
  SSIL, fog, anti-aliasing, grass or post effects, when someone asks which Godot graphics settings are
  expensive, how to profile GPU time, or how to make a beautiful scene run on weaker hardware.
license: MIT (see LICENSE)
---

# Godot render performance: keep the look, pay less (Godot 4.x)

A setup can look great and still be too expensive. A slow scene usually means one specific setup is too
expensive, not that the engine is slow. The common mistake is to fix it by deleting the light, the shadows
or the effect, and so throw away the improvement. The working method is: **measure per feature, find the
expensive one, split it into its sub-settings, and lower only the sub-setting that costs a lot for little
visible difference.**

## 1. Measure correctly

- Disable vsync and FPS caps (`display/window/vsync/vsync_mode = Disabled`, `--max-fps 0`). Otherwise every
  measurement is the monitor's refresh interval, and you can only show that a change reaches the cap.
- Measure **GPU time** (`RenderingServer.viewport_set_measure_render_time` +
  `viewport_get_measured_render_time_gpu`), not only FPS. On a light scene the frame time is CPU- or
  present-bound and hides GPU costs.
- Use a **fixed view** (same camera position, same resolution, ideally the target resolution), let it settle
  (SDFGI, TAA and shader compilation need dozens of frames), average a few hundred frames, and repeat the run.
  Differences smaller than run-to-run noise are not findings.
- Then walk through the scene: some costs depend on the view (grass, shadows, SSR, transparency).

## 2. Find the expensive switch: `scripts/bench_switches.gd`

Give it one reversible `Callable(on: bool)` per feature. It measures `all_off`, `all_on`, each feature
**alone**, and **everything minus one**. The "minus" column is the useful one: it is what you save by removing
that feature from the full scene, and it is how the most expensive switch is found. The result is often a
surprise. It may be the feature that improved the image the most (often the sun preset, because of the
shadow settings bundled with it).

```gdscript
var bench := preload("res://tools/bench_switches.gd").new()
add_child(bench)
var r := await bench.run({
    "sun_shadows": func(on): $Sun.shadow_enabled = on,
    "sdfgi": func(on): env.sdfgi_enabled = on,
    "ssil": func(on): env.ssil_enabled = on,
    "aa": func(on): get_viewport().msaa_3d = Viewport.MSAA_4X if on else Viewport.MSAA_DISABLED,
    "grass": func(on): $Grass.visible = on,
})   # prints a markdown table; r = per-config GPU ms, frame ms, p95, fps
```

## 3. Split the expensive feature; lower the right sub-setting

The sun's **direction/colour** and the **quality of its shadows** are two different things: keep the warm,
directional light and reduce the shadow cost (`scripts/shadow_budget.gd`).

**Decide PCSS first, then tune the rest.** PCSS (`light_angular_distance` > 0) blurs over a world-space
size. A shorter shadow distance packs more texels into the same area, so PCSS samples more of them.
Measured: with PCSS on, shadow distance 200 → 40 **doubled** the sun's GPU cost (0.31 → 0.68 ms). With PCSS
off, the same change made no measurable difference. Turn PCSS off for gameplay (keep it for screenshots and
cinematics) before shortening the distance.

| Lever | Where | Note |
|---|---|---|
| PCSS | `Light3D.light_angular_distance` > 0 | Most expensive soft-shadow option; interacts with distance (see above) |
| Soft-shadow filter | `.../directional_shadow/soft_shadow_filter_quality` (default 2 = Soft Low) | Ultra = many more samples per pixel |
| Shadow map size | `rendering/lights_and_shadows/directional_shadow/size` (default 4096) or `RenderingServer.directional_shadow_atlas_set_size()` | 8192 rarely visible vs 4096 at gameplay distances |
| Shadow max distance | `DirectionalLight3D.directional_shadow_max_distance` (default 100) | Splits spread over this distance: set it to what gameplay needs for **sharper** near shadows and fewer casters in large scenes. Not a free win with PCSS on |
| Splits | `directional_shadow_mode` | 2 splits for small/top-down scenes |
| Grass / small props shadows | `GeometryInstance3D.cast_shadow = OFF` | Thousands of thin casters for barely visible shadows |

Other usual suspects, with the same "lower, don't delete" logic:
- **SDFGI**: `rendering/global_illumination/gi/use_half_resolution`, fewer `sdfgi_cascades`, larger
  `sdfgi_min_cell_size`. On low-end GPUs prefer baked `LightmapGI`.
- **SSIL / SSAO**: lower quality presets in the project settings (`rendering/environment/ssil/*`,
  `ssao/*`), half resolution; SSAO alone is much cheaper than SSIL.
- **Anti-aliasing**: do you need MSAA 4x/8x? MSAA 2x + TAA was the video's final choice. MSAA 8x is flagged
  as very expensive in the Godot docs.
- **Draw distance**: does the whole grass field need to be visible that far? `visibility_range_end` per chunk.
- **Fog / post / dust**: usually cheap. Measure before touching them.

## 4. Decide with both numbers

Compare the **same view** before/after the change, look at the images side by side, and look at the GPU
time. The highest setting is not the most visible improvement: often you pay a lot of frame time for a
difference you can barely see. The goal is the best image for the frame budget you accept (e.g. a 60 Hz
target leaves 16.6 ms; leave headroom for gameplay, physics and weaker GPUs), not maximum settings.

## Final check: do not optimise the look away

After optimising, re-run the `godot-lighting-environment` "sun off" test. If turning the sun preset off
changes the scene as much as before, the light that makes the scene work is still there. Only its cost went
down.

Measured numbers (bench tables, shadow-level image diffs): `references/evidence.md`.

## Related skills

- `godot-lighting-environment`: the setup whose cost this skill manages.
- `godot-vegetation-shaders`: MultiMesh, grass shadows, visibility ranges.
- `godot-lights-camera-post`: local light shadows, MSAA/TAA, post effects.
