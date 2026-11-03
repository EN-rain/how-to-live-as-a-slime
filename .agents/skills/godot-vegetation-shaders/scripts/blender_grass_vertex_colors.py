"""Paint a root-dark -> tip-bright vertex colour on grass/foliage meshes, for wind shaders.

The wind shader (assets/grass_wind.gdshader) uses the vertex colour as a per-vertex "how much may I move"
weight: 0 at the root (planted), 1 at the tip (bends). Many asset packs already ship this; this script adds
it to meshes that do not, then exports a glTF that Godot imports with the colour as the COLOR built-in.

Run (Blender 4.2+ / checked on 5.2 LTS, headless):
  blender --background --factory-startup --python blender_grass_vertex_colors.py -- \
      --in grass.glb --out grass_colored.glb [--objects Grass,Flower] [--mode island|object] [--gamma 1.0]

  --in      .glb/.gltf/.fbx/.obj/.blend to process (a .blend is opened as is)
  --objects comma list of mesh object names (default: every mesh)
  --mode    island: normalise height per connected piece (each blade gets its own 0..1; best for tufts whose
                    blades have different heights)
            object: normalise over the whole object's height
  --gamma   >1 keeps more of the lower blade still (weight = h^gamma)
The colour is written as a byte colour attribute named "Color" on the POINT domain (r = g = b = weight)
and exported as glTF COLOR_0.
"""
import argparse
import os
import sys

import bpy
import bmesh


def parse_args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--objects", default="")
    ap.add_argument("--mode", choices=["island", "object"], default="island")
    ap.add_argument("--gamma", type=float, default=1.0)
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


def islands(bm, eps=1e-5):
    """Connected vertex groups (one per blade / leaf card).
    Vertices at the same position count as connected: imported glTF/FBX meshes are split at UV/normal seams,
    so edge connectivity alone would cut a blade into one island per segment."""
    parent = list(range(len(bm.verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    for e in bm.edges:
        union(e.verts[0].index, e.verts[1].index)
    by_pos = {}
    for v in bm.verts:
        key = tuple(round(c / eps) for c in v.co)
        if key in by_pos:
            union(v.index, by_pos[key])
        else:
            by_pos[key] = v.index
    groups = {}
    for v in bm.verts:
        groups.setdefault(find(v.index), []).append(v)
    return list(groups.values())


def paint(obj, mode, gamma):
    me = obj.data
    # Height = Blender Z (exported as glTF/Godot Y). Work in object space, so object rotation is ignored.
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.verts.ensure_lookup_table()
    groups = islands(bm) if mode == "island" else [list(bm.verts)]
    weight = [0.0] * len(bm.verts)
    for g in groups:
        zs = [v.co.z for v in g]
        lo, hi = min(zs), max(zs)
        span = (hi - lo) or 1.0
        for v in g:
            weight[v.index] = ((v.co.z - lo) / span) ** gamma
    bm.free()

    for name in [a.name for a in me.color_attributes]:
        me.color_attributes.remove(me.color_attributes[name])
    attr = me.color_attributes.new(name="Color", type="BYTE_COLOR", domain="POINT")
    for i, w in enumerate(weight):
        attr.data[i].color = (w, w, w, 1.0)
    me.color_attributes.active_color = attr
    return len(groups)


def main():
    a = parse_args()
    load(a.inp)
    wanted = {n for n in a.objects.split(",") if n}
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and (not wanted or o.name in wanted)]
    if not meshes:
        sys.exit("No mesh object matched.")
    for o in meshes:
        n = paint(o, a.mode, a.gamma)
        print(f"painted {o.name}: {len(o.data.vertices)} verts, {n} piece(s), mode={a.mode}")
    bpy.ops.export_scene.gltf(
        filepath=a.out, export_format="GLB", export_yup=True, export_apply=True,
        # Export exactly the attribute we wrote: other colour layers would become COLOR_0 instead.
        export_vertex_color="NAME", export_vertex_color_name="Color", export_all_vertex_colors=False)
    print(f"wrote {a.out}")


main()
