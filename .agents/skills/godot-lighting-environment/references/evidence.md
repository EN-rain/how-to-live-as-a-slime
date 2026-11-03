# Evidence — measured on a reference scene

Every step of this skill was reproduced in a test village before being written down, with the exact code in
`scripts/lighting_preset.gd`. These numbers show what "working" looks like. Your own values will differ with
scene, assets and camera.

**Setup.** Godot 4.7.2.stable, Forward+, 1280×720, AMD RX 6950 XT. Village built from Kenney *Fantasy Town Kit*
(CC0), where walls are 1 unit high (~0.4× real scale). Baseline = white sun from the camera side, flat grey
ambient colour, Linear tonemap (the "preview defaults" look). Each step is cumulative. Luminance = Rec.709
weights on sRGB pixel values (0-1), mean over a fixed rectangle of the same view.

| Step | Measurement | Before → after |
|---|---|---|
| 1 Sun (elev. 28°, side azimuth, `Color(1.0,0.86,0.77)`) | front / side wall luminance ratio | 1.03 → **1.72** |
| 1 Sun with no ambient at all | shaded wall luminance | **0.00** (pure black: the problem step 2 solves) |
| 2 Sky ambient (`AMBIENT_SOURCE_SKY`) | shaded wall luminance; B/R ratio shaded vs sunlit wall | 0.00 → 0.27; **1.65 vs 1.07** (cool shadow, warm sun) |
| 3 AgX vs Linear, over-bright sun (energy 4) | clipped pixels (all channels ≥ 0.97) on the sunlit wall | Linear **50 %** → AgX **0 %** |
| 4 SSAO + SSIL (radius scaled to 0.4) | contact zones (barrel base, rock base) luminance, two different cameras | −4 %, −3 % (close view); −11 % (second view); open wall −0.8 %, sky 0 % |
| 5 SDFGI (`min_cell_size` 0.1) | green share of the lower shaded wall, next to grass | 30.3 % → 32.3 % (subtle; stronger with larger lawns / brighter sun) |
| 6 Fog, exponential 0.015 | contrast (std-dev) far trees / mid-ground house | −33 % / −22 % (mid-ground also veiled) |
| 6 Fog, depth mode (begin past gameplay space) | contrast far trees / mid-ground house; road vs grass luminance | −25 % / **0 %**; unchanged |
| 6 Fog, too thick (exponential 0.25) | mid-ground contrast; road readability | −91 %; road blends into grass (the "more fog isn't better" failure) |
| Final: everything on, sun step OFF | front / side wall ratio | 1.04: flat again. Nothing else replaces the sun |

Practical takeaways:
- The sun step alone produced the largest visible change. Its effect is not recovered by any combination of
  the other steps.
- A flat ambient colour hides black shadows but gives grey, colourless shade. Sky ambient gives cool shade.
- AgX matters only once something is bright enough to clip, which happens quickly when sun energy is raised.
- SSAO/SDFGI are deliberately subtle in a wide view. Judge them close up and while moving.
- Depth-mode fog fades the background without touching the playable area. Exponential fog does both.
