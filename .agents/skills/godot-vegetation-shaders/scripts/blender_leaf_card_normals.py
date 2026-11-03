"""Bake "outward from the canopy centre" custom normals into leaf-card meshes (offline alternative to the
leaf_canopy shader). Use it when you cannot or do not want to use a custom shader (Mobile/Compatibility
renderer, StandardMaterial3D workflow, many trees sharing one simple material).

A canopy made of flat leaf cards lights every card by its own flat normal -> patchy blobs of light. Pointing
every leaf vertex normal away from the canopy centre makes the whole canopy shade as one volume.

Run (Blender 4.2+ / checked on 5.2 LTS, headless):
  blender --background --factory-startup --python blender_leaf_card_normals.py -- \
      --in tree.glb --out tree_normals.glb --objects Leaves [--center auto|x,y,z] [--blend 0.85] [--squash 1,1,1]

  --objects  comma list of LEAF mesh objects (trunk/branches must keep their own normals)
  --center   canopy centre in the object's local space (Blender Z-up); auto = bounding-box centre
  --blend    1.0 = fully spherical normals; 0.7-0.9 keeps some per-card variation
  --squash   ellipsoid half-size per axis relative to the bounding box (e.g. 1,1,0.7 for flat canopies)
Limitation (measured): leaf cards are usually rendered double-sided (cull disabled), and Godot flips the
normal of BACK faces, so the cards seen from behind get inward normals. The bake still improves the canopy,
but less than assets/leaf_canopy.gdshader, which sidesteps the flip. Prefer the shader when you can.
(Duplicating cards into two single-sided back-to-back faces was tried: coplanar faces cause shadow acne.)
Written with Mesh.normals_split_custom_set (corner normals), exported with export_normals=True.
"""
import argparse
import os
import sys

import bpy
from mathutils import Vector


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--objects", required=True)
    ap.add_argument("--center", default="auto")
    ap.add_argument("--blend", type=float, default=0.85)
    ap.add_argument("--squash", default="1,1,1")
    return ap.parse_args(argv)


def load(path):
    ext = os.path.splitext(path)[1].lower()
    if ext == ".blend":
        bpy.ops.wm.open_mainfile(filepath=path)
        return
    bpy.ops.wm.read_factory_settings(use_empty=True)
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=path)
    else:
        sys.exit(f"Unsupported input: {path}")


def bake(obj, center_arg, blend, squash):
    me = obj.data
    lo = Vector((min(v.co[i] for v in me.vertices) for i in range(3)))
    hi = Vector((max(v.co[i] for v in me.vertices) for i in range(3)))
    center = (lo + hi) / 2 if center_arg == "auto" else Vector(map(float, center_arg.split(",")))
    radius = Vector(((hi - lo)[i] / 2 * squash[i] or 1.0 for i in range(3)))
    normals = []
    for loop in me.loops:
        co = me.vertices[loop.vertex_index].co
        outward = Vector(((co - center)[i] / radius[i] for i in range(3))).normalized()
        original = Vector(me.corner_normals[loop.index].vector)
        normals.append(original.lerp(outward, blend).normalized())
    me.normals_split_custom_set(normals)
    return center


def main():
    a = parse_args()
    load(a.inp)
    squash = [float(x) for x in a.squash.split(",")]
    for name in a.objects.split(","):
        obj = bpy.data.objects.get(name)
        if obj is None or obj.type != "MESH":
            sys.exit(f"Leaf mesh object not found: {name}")
        c = bake(obj, a.center, a.blend, squash)
        print(f"baked {name}: {len(obj.data.loops)} corners, centre {tuple(round(x, 3) for x in c)}")
    bpy.ops.export_scene.gltf(filepath=a.out, export_format="GLB", export_yup=True, export_apply=True,
                              export_normals=True)
    print(f"wrote {a.out}")


main()
