# Provenance

- **Ideas and method**: "Why 3D Games Look Bad in Godot", Coding Quests (2026-10-23), https://youtu.be/0792U-wuwjA.
  Switches 10-12: character fill light limited by cull mask (energy 0.7, value shown in the video), lanterns
  and window glow as diegetic light sources, narrower FOV + camera pulled back + DOF (and the video's choice
  to leave it off for gameplay comparisons), MSAA 2x + TAA, vignette, grain, floating dust. No text, code or
  images from the video are reproduced. Code and measurements are original.
- **API facts**: Godot 4.7.2.stable class reference (`--doctool` dump of the official binary) and
  `godotengine/godot` tag `4.7-stable` `doc/classes/` (Light3D: cull mask ignored by SDFGI/VoxelGI/LightmapGI/
  volumetric fog; Viewport: TAA limitations; CameraAttributesPractical); godot-docs
  `tutorials/shaders/custom_postprocessing` (CanvasLayer + ColorRect + `hint_screen_texture`).
- **Validation scene**: Kenney *Fantasy Town Kit* (CC0 1.0, https://kenney.nl), not redistributed here.
  Also "wooden Barrel" by jrybalov (https://sketchfab.com/3d-models/wooden-barrel-dc8560d9474e4293bc1452487495fd37), CC-BY-4.0, not redistributed here.
- **Files**: all original, MIT.
