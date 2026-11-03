---
name: godot-lights-camera-post
description: >-
  Final polish for Godot 4 3D scenes: keep the player character readable in shadow with a cull-masked fill
  light, add warm local lights from lanterns/windows, frame shots with FOV and depth of field, and finish the
  image with MSAA + TAA, a subtle vignette, film grain and floating dust. Use this whenever a Godot character
  disappears in the dark or looks flat against the background, the scene needs lanterns/torches/window glow,
  someone asks about camera FOV, depth of field, CameraAttributesPractical, anti-aliasing (jagged edges,
  shimmering), vignette, grain, post-processing or particles for atmosphere in Godot, even if they just say
  "the final image still looks raw".
license: MIT (see LICENSE)
---

# Godot local lights, camera & finishing touches (Godot 4.x)

These come **after** the sun/sky/tonemap/AO/fog setup (`godot-lighting-environment`) and vegetation work.
Each step fixes a specific problem. `scripts/lights_camera_post.gd` implements them as static functions and
`assets/vignette_grain.gdshader` is the post effect. Numbers in `references/evidence.md`.

## 1. Character fill light: readable in shadow, without lighting the world

Problem: once the scene has real shadows and fog, the player character disappears when it walks into shade.

- Attach a small `OmniLight3D` to the character (energy ≈ 0.7, short range, no shadows, low specular).
- Restrict it with `light_cull_mask` to a dedicated render layer, and add that layer to the character's
  meshes (`VisualInstance3D.layers`). Keep layer 1 on them so cameras and other lights still see them.
  `add_fill_light()` does both.
- Measured: character +56 % brighter, the ground and road next to it unchanged. The same light without the
  mask brightened the surroundings by 23 %, which reads as a lamp following the player.
- The cull mask is ignored by SDFGI, VoxelGI, LightmapGI and volumetric fog (Godot docs): with SDFGI on, the
  fill light's bounce still reaches the surroundings. Keep its energy low.

## 2. Local lights: pockets of warmth from things that exist

- Put warm `OmniLight3D`s (or `SpotLight3D`s) on **objects that are visibly light sources**: lanterns,
  torches, fires, lit windows. Light the player can explain feels authentic; decorative floating lamps do not.
- For windows and lantern glass, make the glowing part emissive (`make_emissive()` → `emission_enabled`,
  orange colour, energy 1-2). With glow enabled in the Environment it blooms slightly.
- No shadows by default: each shadowed omni light costs shadow-atlas space and draw calls. Enable them only
  where a shadow is clearly visible.
- Judge local lights at dusk or in shade. At noon under a strong sun they are nearly invisible. That is
  normal, not a bug.

## 3. Camera: FOV, distance, depth of field (a composition choice, not a free upgrade)

- A narrower FOV with the camera pulled back (target keeps its on-screen size: `reframe_tighter()`) makes the
  background look larger relative to the character: more cinematic, more "presence" for distant landmarks.
- A little far depth of field (`CameraAttributesPractical`: `dof_blur_far_enabled`, `dof_blur_far_distance`
  just past the subject, `dof_blur_amount` ≈ 0.05-0.1) separates the subject from the background. Measured:
  background detail −99 %, the character pixel-identical.
- Trade-off: both reduce what the player sees of the world. Use them for cutscenes, photo mode,
  third-person exploration with few threats. Avoid them for gameplay that needs awareness. When comparing
  lighting changes, keep the camera fixed so composition does not bias the judgement.

## 4. Finishing touches: anti-aliasing, vignette, grain, dust

- Anti-aliasing: `Viewport.msaa_3d = MSAA_2X` + `use_taa = true` (`apply_antialiasing()`), or the project
  settings `rendering/anti_aliasing/quality/msaa_3d` and `use_taa`. MSAA fixes geometry edges, TAA fixes
  shading and alpha-scissor shimmer (foliage, grass) and soft-shadow noise. Measured against a 2× supersampled
  reference: edge error −17 to −23 %. TAA also softens the whole image slightly and can ghost on particles and
  skinned meshes (Godot docs). If the image looks soft, try MSAA + FXAA/SMAA (`screen_space_aa`) instead.
- **Check flat ground for banding when MSAA is combined with SDFGI/SSAO/SSIL.** In the reference scene (Godot
  4.7.2 Forward+, AMD RX 6950 XT), MSAA together with SDFGI and SSAO drew fine horizontal stripes across roads
  and dirt (row-to-row variation 1.79 vs 0.03 with TAA alone; removing SDFGI cut it to 0.49). It may depend on
  the GPU/driver, so look at a flat surface at a grazing angle. If it shows, drop MSAA and keep TAA (optionally
  plus FXAA/SMAA). TAA alone was cleaner than MSAA + TAA on roof edges and less clean on a foliage-heavy region.
- Foliage cut-outs (alpha scissor) are not smoothed by plain MSAA. Turn on **alpha-to-coverage** on the leaf
  and grass materials: `enable_foliage_alpha_to_coverage()` sets `alpha_antialiasing_mode` on a
  StandardMaterial3D; custom shaders use `render_mode alpha_to_coverage`. It needs MSAA and helps most with soft
  alpha edges and mipmapped leaf textures. Measured on hard-edged leaves: −2 % shimmer vs MSAA alone, so TAA
  stays the main fix when foliage shimmers in motion.
- Vignette + grain: Godot's Environment has **no** built-in vignette or grain (Godot 4.7 class reference).
  Use `vignette_grain.gdshader` on a full-screen `ColorRect` in a `CanvasLayer` (`add_vignette_grain()`). Put
  the UI on a higher CanvasLayer. Keep it small: vignette strength ≈ 0.15 darkens the corners without greying
  the sky; 0.25 was already visible as grey corners. The centre of the image is untouched (measured).
- Floating dust: a few hundred tiny, slow, unshaded particles in a box around the play area (`add_dust()`).
  It should be noticed only when looking for it.

The goal of this step is to glue the image together. If a viewer notices the effect first, it is too strong.

## Verify

Same fixed views before/after, plus the character walking from sun into shade. Check: the character is
readable everywhere; local lights come from visible sources; no jagged roof lines or shimmering foliage when
the camera moves; vignette/grain/dust barely noticeable. Then measure frame time (`godot-render-performance`):
MSAA sample count and TAA are real costs.

## Related skills

- `godot-lighting-environment`: sun, sky, AgX, AO, GI, fog (before this).
- `godot-vegetation-shaders`: canopy, wind, ground, grass fields.
- `godot-render-performance`: what each of these costs and how to choose.
