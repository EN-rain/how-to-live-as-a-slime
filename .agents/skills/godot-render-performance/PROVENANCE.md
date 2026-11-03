# Provenance

- **Ideas and method**: "Why 3D Games Look Bad in Godot", Coding Quests (2026-10-23), https://youtu.be/0792U-wuwjA.
  Performance section: ~50 FPS on an RTX 5080 for the first full setup; testing switches one by one; the sun
  preset being the biggest cost because of its shadow settings; keeping direction/colour while lowering
  shadow resolution and soft-edge quality; questioning AA samples and draw distance; comparing the same
  view, walking the scene, judging visuals and frame rate together. No text, code or images from the video
  are reproduced. Scripts and measurements are original.
- **API facts**: Godot 4.7.2.stable class reference (`--doctool` dump of the official binary) and
  `godotengine/godot` tag `4.7-stable` `doc/classes/` (RenderingServer: `viewport_set_measure_render_time`,
  `viewport_get_measured_render_time_gpu/cpu`, `directional_shadow_atlas_set_size`,
  `directional_soft_shadow_filter_set_quality`, `SHADOW_QUALITY_*`; ProjectSettings
  `rendering/lights_and_shadows/directional_shadow/*`; Light3D `light_angular_distance`; Environment SDFGI
  performance note; Viewport MSAA note).
- **Validation scene**: Kenney *Fantasy Town Kit* (CC0 1.0, https://kenney.nl), not redistributed here.
  Also "wooden Barrel" by jrybalov (https://sketchfab.com/3d-models/wooden-barrel-dc8560d9474e4293bc1452487495fd37), CC-BY-4.0, not redistributed here.
- **Files**: all original, MIT.
