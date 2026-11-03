# Provenance

- **Ideas and method**: "Why 3D Games Look Bad in Godot", Coding Quests (2026-10-23), https://youtu.be/0792U-wuwjA.
  Switches 7-9 (leaf shader, wind, ground) and the MultiMesh grass fill: leaf normals pointing out of the
  canopy centre, vertex colours as wind weight (dark root, light tip), scrolling noise, a mask for worn dirt
  and shade, MultiMesh with no grass shadows and a limited visibility distance. No text, code or images from
  the video are reproduced. Shaders, scripts and measurements are original.
- **API facts**: Godot 4.7.2.stable class reference (`--doctool` dump of the official binary) and the 4.7
  spatial shader reference (docs.godotengine.org/en/stable, "Godot Engine 4.7"); Blender 5.2 LTS Python API
  (docs.blender.org/api/5.2) and the glTF exporter options as reported by Blender 5.2.3 itself
  (`bpy.ops.export_scene.gltf.get_rna_type()`).
- **Validation scene**: Kenney *Fantasy Town Kit* (CC0 1.0, https://kenney.nl), not redistributed here.
  Also "wooden Barrel" by jrybalov (https://sketchfab.com/3d-models/wooden-barrel-dc8560d9474e4293bc1452487495fd37), CC-BY-4.0, not redistributed here.
- **Files**: all original, MIT.
