extends RefCounted
## Builds the RG ground mask used by assets/ground_blend.gdshader, from scene data. Godot 4.x.
##   R = worn dirt: along path polylines and around spots (doors, wells, stalls)
##   G = shade under trees
## Usage:
##   const GroundMask := preload("res://path/to/ground_mask.gd")
##   var rect := Rect2(-30, -30, 60, 60)    # world X/Z area covered (x, z, width, depth)
##   var tex := GroundMask.build(rect, 512,
##       [PackedVector2Array([Vector2(1.5, 8), Vector2(1.5, -16)])],  # paths (world XZ polylines)
##       1.6,                                                          # path half-width (dirt)
##       [Vector3(-2.0, 0.5, 0.0)],                                    # spots: (x, z, radius)
##       [Vector3(-0.2, -3.5, 1.8)])                                   # trees: (x, z, shade radius)
##   material.set_shader_parameter("ground_mask", tex)
##   material.set_shader_parameter("mask_world_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
## Bake it once (or save the Image with save_png) rather than rebuilding every run on large maps.


static func build(rect: Rect2, size_px: int, paths: Array, path_half_width: float,
		spots: Array = [], trees: Array = []) -> ImageTexture:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	var px_world := rect.size / float(size_px)
	for y in size_px:
		for x in size_px:
			var p := rect.position + Vector2((x + 0.5) * px_world.x, (y + 0.5) * px_world.y)
			var dirt := 0.0
			for path in paths:
				var d := _dist_to_polyline(p, path)
				dirt = maxf(dirt, 1.0 - smoothstep(path_half_width * 0.6, path_half_width, d))
			for s in spots:
				var d2 := p.distance_to(Vector2(s.x, s.y))
				dirt = maxf(dirt, 1.0 - smoothstep(s.z * 0.4, s.z, d2))
			var shade := 0.0
			for t in trees:
				var d3 := p.distance_to(Vector2(t.x, t.y))
				shade = maxf(shade, 1.0 - smoothstep(t.z * 0.5, t.z, d3))
			img.set_pixel(x, y, Color(dirt, shade, 0.0, 1.0))
	return ImageTexture.create_from_image(img)


static func _dist_to_polyline(p: Vector2, line: PackedVector2Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p, line[i], line[i + 1])
		best = minf(best, p.distance_to(q))
	return best
