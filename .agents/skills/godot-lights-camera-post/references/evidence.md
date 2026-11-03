# Evidence: measured on a reference scene

**Setup.** Godot 4.7.2.stable, Forward+, 1280×720, AMD RX 6950 XT. Kenney *Fantasy Town Kit* village (CC0;
walls 1 unit high, so ranges were scaled by about 0.4). Base lighting = `godot-lighting-environment` preset
plus the vegetation skill. A capsule stands in for the player character. The files of this skill were used
as shipped.

| Step | Measurement | Result |
|---|---|---|
| Fill light, energy 0.7, cull mask = character layer | mean luminance: character / road beside it / ground beside it | character 0.27 → **0.42 (+56 %)**; road +0.06 %; ground +0.07 % |
| Same light without cull mask | same | character +57 %; road **+23 %**; ground **+24 %** (the whole area brightens) |
| Lantern light at dusk (sun 6°, energy 0.6) | visual | warm pool of light under the lantern; invisible at noon |
| FOV 50° → 28°, camera moved back to keep the character's size | visual | character same size; background trees/houses visibly larger |
| Far DOF (focus just past the character, amount 0.08) | Laplacian variance (detail) background trees / house / character interior pixels | trees −99.8 %, house −91 %; character interior **identical** (mean abs diff 0.0) |
| MSAA 2x + TAA vs no AA, compared with a 2× supersampled render | mean abs error to the reference on roof/wall edge regions; whole image | edges −23 % and −17 %; whole image **+25 %** (TAA softens everything slightly) |
| Vignette 0.25 + grain 0.03 | luminance centre / corners | centre unchanged (0.454 → 0.455); corners −25 % (too visible on the sky → default lowered to 0.15) |
| Dust, 400 particles | visual | sparse specks, readable as dust, not distracting |

## Iteration 2

| Finding | Measurement | Result |
|---|---|---|
| Dust motes were untextured quads | visual at 1280×720+ | read as hard white squares → now a soft radial `GradientTexture2D`; squares gone |
| MSAA × SDFGI/SSAO banding on flat ground (full scene, long view down the road) | mean row-to-row luminance change on the road (higher = stripes) | MSAA 2x only **1.79**; MSAA 2x + TAA 1.81; TAA only **0.03**; full scene without AA 0.03; MSAA + TAA without SDFGI 0.49 |
| TAA only vs MSAA 2x + TAA, compared with a 2× supersampled render | mean abs error, roof-edge region / foliage-heavy region | 0.0035 vs 0.0044 (TAA only better) / 0.022 vs 0.006 (TAA only worse) |
