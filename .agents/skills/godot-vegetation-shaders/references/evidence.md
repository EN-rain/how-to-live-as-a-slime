# Evidence: measured on a reference scene

**Setup.** Godot 4.7.2.stable, Forward+, 1280×720, AMD RX 6950 XT. Kenney *Fantasy Town Kit* village (CC0;
walls 1 unit high). A Blender-generated tree has 150 random leaf cards; a Blender-generated grass tuft has 12
blades. Lighting = `godot-lighting-environment` preset (sun, sky, AgX, SSAO). Every file of this skill was run
as shipped. Animated shaders were rendered at fixed times (TIME replaced by a global uniform).

| Technique | Measurement | Result |
|---|---|---|
| Leaf canopy shader (`normal_blend` 0.85) | canopy luminance split into card-to-card "patchiness" (residual after 12 px blur) and smooth gradient | patchiness −15 %, gradient +17 %, mean brightness +29 %: one lit side and one shaded side. `normal_blend` 1.0: same within noise |
| Leaf normals baked in Blender, double-sided StandardMaterial3D | same metric | patchiness −8 %: helps, less than the shader (back-face normal flip) |
| Wind, vertex-colour weighted (`bend_curve` 2) | mean abs pixel change between t = 0 s and t = 1.3 s, root band vs tip band | root **0.0003**, tip **0.040** |
| Wind, naive (every vertex same offset) | same | root **0.032** ≈ tip 0.044: the tuft slides |
| Vertex colours painted by `blender_grass_vertex_colors.py` (input had none) → Godot | same wind test; colour values in Godot | root 0.0015, tip 0.047; mid-height weight 0.50 arrives as 0.50 |
| Same script, before the weld fix | islands found on an imported 12-blade tuft | 48 (one per segment, wrong); after the fix: 12 |
| Ground blend + mask | visual (same views) | varied greens, dirt along the road/doors/stall, darker grass under trees. Mask 384 px / 60 units: stair-stepped dirt edge; 768 px: clean |
| 20 000 grass tufts, 1 MultiMeshInstance3D, shadows off, visibility range 40 | frame time, 300 frames, fixed camera | **1.25 ms** mean, 1.42 ms p95 |
| Same 20 000 tufts as MeshInstance3D nodes | same | **5.50 ms** mean, 7.98 ms p95 |
| No grass | same | 0.58 ms mean |

## Iteration 2 (improvements found by the eval runs)

| Change | Measurement | Result |
|---|---|---|
| Wind weight on a **tinted** tuft (dark green 0.10/0.25/0.08 → light green 0.55/0.85/0.35) | root / tip mean abs pixel change, t = 0 → 1.3 s | red channel only (iteration 1): root 0.0007, tip **0.027** (under-bends); brightness, no remap: root **0.0039** (creeps), tip 0.046; brightness + `weight_range` (0.25, 0.85): root **0.0001**, tip **0.040** |
| Same shader on the grey-gradient tuft | same | root 0.0003, tip 0.040 (unchanged from iteration 1: no regression) |
| Leaf `specular` 0.5 → 0 | canopy mean blue channel; visual | 0.093 → **0.044**; the grey-blue sky sheen over the shaded half of the canopy disappears |
| Leaf `alpha_to_coverage` (MSAA 2x, no TAA) | mean abs change after a 0.2 px camera move (shimmer), canopy region | no AA 0.00106; MSAA 0.00101; MSAA + alpha-to-coverage **0.00099** (small gain on this hard-edged leaf texture) |
