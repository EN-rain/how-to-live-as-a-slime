---
name: godot-lighting-environment
description: Fix flat, washed-out or "default-looking" outdoor 3D lighting in Godot 4 by setting up the sun, sky ambient, AgX tone mapping, SSAO/SSIL, SDFGI and fog in the right order. Use this whenever a Godot 3D scene looks flat, bland, "like a Godot game", too dark in the shadows, blown out in the highlights, lacks depth, or objects look like they float — and whenever someone asks how to configure DirectionalLight3D, WorldEnvironment/Environment, tonemap, ambient occlusion, global illumination or fog in Godot, even if they only say "make my Godot scene look better" or "my game looks bad".
license: MIT (see LICENSE)
---

# Godot outdoor lighting & environment (Godot 4.x, Forward+)

A "bad-looking" Godot 3D scene is almost always a lighting decision, not an engine limit and not an asset
problem. The editor's preview sun and environment are a starting point; they do not choose good lighting for you.
Check these settings **before** replacing models or textures.

The six steps below are applied **in order**. Each one solves one specific, visible problem, and none replaces
another. Add an effect only when you can name the problem it solves.

| # | Step | Problem it solves | Main settings |
|---|---|---|---|
| 1 | Sun | All walls equally bright → buildings look flat, no sense of where light comes from | `DirectionalLight3D` direction + warm colour |
| 2 | Sky | Shadowed faces go black | `ProceduralSkyMaterial`, `ambient_light_source = SKY` |
| 3 | Tone mapping | Bright surfaces clip to one flat white | `tonemap_mode = TONE_MAPPER_AGX` + small exposure/colour adjustment |
| 4 | Ambient occlusion | Objects float: no darkening where they touch the ground | `ssao_enabled` (+ `ssil_enabled`) |
| 5 | SDFGI | No bounce light: green grass doesn't tint nearby walls | `sdfgi_enabled` |
| 6 | Fog | Background as strong as foreground → no depth | `fog_enabled`, depth mode |

`scripts/lighting_preset.gd` implements each step as one static function with tunable defaults. Read it and
use it (or copy the relevant lines) rather than retyping property names.

## Before you change anything

1. Pick 2-3 fixed camera views that matter (a building corner showing two walls, a close-up where props touch
   the ground, a long view down a path) and capture them. Compare every change from **the same views**.
2. Note the renderer: SSIL and SDFGI are Forward+ only; SSAO works in Forward+ and Compatibility, not Mobile.
   On Mobile/Compatibility, do steps 1-3 and 6, and consider baked `LightmapGI` for bounce light.
3. Note the scene scale. SSAO radius, fog distances/density and SDFGI cell size are in world units: values
   that look right in a 1 unit = 1 m scene must be scaled for a stylised kit where a wall is 1 unit high.

## 1. Sun — direction and colour (the most important change)

Problem: the sun comes from roughly the camera direction or straight down, so the front and side walls of a
building receive the same light. Nothing tells the eye where light comes from.

- Lower the sun (≈ 20-35° above the horizon) and rotate it **to the side** relative to the main view, so one
  face of each building catches the sun and the adjacent face falls into shadow. Long shadows across roads
  and the ground are a good sign.
- Warm the colour: `Color(1.0, 0.86, 0.77)` is a good afternoon value.
- `shadow_enabled = true`. Leave shadow **quality** settings at their defaults here. Shadow resolution and
  filtering are a separate performance decision (see the `godot-render-performance` skill). Do not confuse
  "the sun is expensive" with "the sun's shadow settings are expensive".

Check: on a building corner, the lit wall is clearly brighter than the shaded one (≈ 1.5× or more in luminance).

## 2. Sky — the second light source

Problem: once the sun is directional, shadowed faces can go nearly black. In reality they are lit by the sky.

- Use a real sky: `Sky` + `ProceduralSkyMaterial`, blue top, **slightly warmer horizon**; `background_mode = BG_SKY`.
- `ambient_light_source = AMBIENT_SOURCE_SKY`, `ambient_light_sky_contribution = 1.0`, then dose
  `ambient_light_energy`. A flat `AMBIENT_SOURCE_COLOR` grey hides the problem but loses the colour contrast.
- Result: shadowed walls get a cool blue fill while sunlit walls stay warm. That warm/cool contrast is most
  of what makes outdoor light read as natural. The sun says *where* direct light comes from; the sky controls
  everything else.

## 3. Tone mapping — AgX

Problem: depending on light and exposure, bright surfaces (light roofs, sunlit plaster) exceed what the
screen can show. With `TONE_MAPPER_LINEAR` they all clip to the same flat white.

- `tonemap_mode = TONE_MAPPER_AGX` (new in Godot 4.4+; enum value 4). AgX rolls highlights off smoothly.
- Combine it with a small `tonemap_exposure` tweak and a light colour adjustment (`adjustment_enabled`,
  contrast ≈ 1.05, saturation ≈ 1.1-1.2). AgX alone looks a bit grey; the adjustment restores punch.
- "Adding light" and "adding light correctly" are different things: raise sun energy only after AgX is on.

## 4. Ambient occlusion — ground the objects

Problem: barrels, rocks and fences meet the ground with no darker contact zone, so they look pasted on.

- `ssao_enabled = true`; set `ssao_radius` to roughly the size of the gaps you want darkened (scene units).
- `ssil_enabled = true` adds screen-space bounce near contacts (Forward+). Toggle SSAO and SSIL separately
  if you need to know which one does what.
- SSAO is screen-space, so it depends on what is on screen and changes as the camera moves. **Judge it while
  walking through the scene**, not on a single screenshot. The effect should be subtle: darker creases and
  contacts, no grey halos on open walls.

## 5. SDFGI — light bounces

Problem: light stops at the first surface. Sunlit grass should bounce green onto nearby shaded walls.

- `sdfgi_enabled = true`, `sdfgi_use_occlusion = true`. Lower `sdfgi_min_cell_size` for small-scale scenes.
- SDFGI only affects meshes with `gi_mode = GI_MODE_STATIC` (the default). Thin one-sided walls leak light.
- Judge bounce colour with the scene's **real albedo**: neon grass makes neon walls. Fix over-saturated
  materials first, then judge GI.
- SDFGI is GPU-demanding (not for integrated GPUs). Measure it (see `godot-render-performance`).

## 6. Fog — depth

Problem: distant trees have the same contrast as the fence next to you, so distances can't be judged.

- `fog_enabled = true`, `fog_light_color` ≈ the sky horizon colour, `fog_sky_affect = 0` to keep the sky,
  `fog_aerial_perspective` ≈ 0.5 (needs `BG_SKY`) so far objects melt into the sky colour.
- Prefer `fog_mode = FOG_MODE_DEPTH` with `fog_depth_begin` just beyond the gameplay space and `fog_depth_end`
  near the horizon: the playable area stays crisp and only the background fades. Exponential fog (the default
  mode) also veils mid-ground objects. Use it only at low density.
- **More fog is not better.** Thick ground fog can look atmospheric but hide the road. If the player can't see
  where to go, the "improvement" made the game harder. Readability beats atmosphere.

## Verify

Re-capture the same views after each step and compare side by side. Expected, in order: two-tone building
faces with long shadows; cool readable shadows; no flat-white highlights; darker contacts; subtle colour
bleeding; a background that fades while the foreground stays crisp. Then turn the **sun step off** in the
finished scene: if everything else still "works", the sun was not set up well. No other effect replaces the
direction and contrast it establishes.

For measured before/after values and screenshots from a reference scene, see `references/evidence.md`.
For the full property list with defaults and doc citations, see `references/settings.md`.

## Related skills

- `godot-render-performance`: the scene got slow after this setup (shadow quality, SDFGI, AA costs).
- `godot-vegetation-shaders`: trees, grass and ground still look fake after lighting is fixed.
- `godot-lights-camera-post`: a character disappears in the shadows, local lights, DOF, AA, vignette.
