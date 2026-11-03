# Provenance

- **Ideas and method**: "Why 3D Games Look Bad in Godot", Coding Quests (2026-10-23), https://youtu.be/0792U-wuwjA.
  Switches 1-6 (sun, sky, tone mapping, ambient occlusion, SDFGI, fog), the "sun preset off" final test and the
  value `Color(1.0, 0.86, 0.77)` come from the video. No text, code or images from the video are reproduced.
  The wording, code and measurements are original.
- **API facts**: Godot 4.7.2.stable class reference (`--doctool` dump of the official binary) and
  `godotengine/godot` tag `4.7-stable`, `doc/classes/Environment.xml`, `DirectionalLight3D.xml`, `Light3D.xml`.
  AgX availability checked on tags `4.3-stable` (absent) and `4.4-stable` (present).
- **Validation scene**: Kenney *Fantasy Town Kit* (CC0 1.0, https://kenney.nl). Not redistributed here.
  Also "wooden Barrel" by jrybalov (https://sketchfab.com/3d-models/wooden-barrel-dc8560d9474e4293bc1452487495fd37), CC-BY-4.0, not redistributed here.
- **Script**: `scripts/lighting_preset.gd`, original, MIT.
