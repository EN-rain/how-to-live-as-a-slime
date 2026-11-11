extends SceneTree
## P0: rasterises CaveLayout into a top-down floor-height map and a side elevation profile.
## Headless only (uses Image, no rendering). Run in the sandbox:
##   godot --headless --script tools/render_cave_layout.gd

const PX_PER_M := 5.0
const U_MIN := -105.0
const U_MAX := 25.0
const S_MIN := -22.0
const S_MAX := 112.0
const Y_LO := 14.0
const Y_HI := 28.0


func _init() -> void:
	_render_top_down("res://cave_layout_map.png")
	_render_profile("res://cave_layout_profile.png")
	quit(0)


# ------------------------------------------------------------------------------
# Layout sampling (2D)
# ------------------------------------------------------------------------------

## Returns {inside, floor, ceil, kind} for local (u, s).
func _sample(u: float, s: float) -> Dictionary:
	var best := {"inside": false, "floor": 0.0, "ceil": 0.0, "kind": "", "score": 1e9}
	for name: String in CaveLayout.TUNNELS:
		var nodes: Array = CaveLayout.TUNNELS[name]
		for i in range(nodes.size() - 1):
			var a: Dictionary = nodes[i]
			var b: Dictionary = nodes[i + 1]
			var ap: Vector3 = a["p"]
			var bp: Vector3 = b["p"]
			var pa := Vector2(ap.x, ap.z)
			var pb := Vector2(bp.x, bp.z)
			var ab := pb - pa
			var t := clampf((Vector2(u, s) - pa).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
			var d := Vector2(u, s).distance_to(pa + ab * t)
			var half_w := lerpf(float(a["w"]), float(b["w"]), t) * 0.5
			var score := d / half_w
			if score < 1.0 and score < float(best["score"]):
				var fy := lerpf(ap.y, bp.y, t)
				best = {"inside": true, "floor": fy, "ceil": fy + lerpf(float(a["h"]), float(b["h"]), t), "kind": name, "score": score}
	for name: String in CaveLayout.CHAMBERS:
		var c: Dictionary = CaveLayout.CHAMBERS[name]
		var cc: Vector3 = c["c"]
		var nu: float = (u - cc.x) / float(c["rx"])
		var ns: float = (s - cc.z) / float(c["rz"])
		var score := sqrt(nu * nu + ns * ns)
		if score < 1.0 and score < float(best["score"]):
			var dome := sqrt(maxf(1.0 - score * score, 0.0))
			best = {"inside": true, "floor": cc.y, "ceil": cc.y + float(c["h"]) * dome, "kind": name, "score": score}
	if bool(best["inside"]):
		var bf: float = float(best["floor"]) + _bump(u, s, CaveLayout.MOUND) + _bump(u, s, CaveLayout.RUBBLE_CREST)
		var p: Dictionary = CaveLayout.POOL
		var pc: Vector3 = p["c"]
		var pn := Vector2((u - pc.x) / float(p["rx"]), (s - pc.z) / float(p["rz"])).length()
		if pn < 1.0:
			bf = lerpf(pc.y, bf, smoothstep(0.55, 1.0, pn))
			best["water"] = true
		best["floor"] = bf
	return best


func _bump(u: float, s: float, f: Dictionary) -> float:
	var fc: Vector3 = f["c"]
	var d: float = Vector2(u - fc.x, s - fc.z).length() / float(f["r"])
	return float(f["rise"]) * (1.0 - smoothstep(0.0, 1.0, d))


# ------------------------------------------------------------------------------
# Top-down map
# ------------------------------------------------------------------------------

func _to_px(u: float, s: float, h: int) -> Vector2i:
	# North-up style: +s (into the mountain) points up the image.
	return Vector2i(int((u - U_MIN) * PX_PER_M), h - 1 - int((s - S_MIN) * PX_PER_M))


func _render_top_down(path: String) -> void:
	var w := int((U_MAX - U_MIN) * PX_PER_M)
	var h := int((S_MAX - S_MIN) * PX_PER_M)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var inside := PackedByteArray()
	inside.resize(w * h)

	for py in h:
		var s := S_MIN + float(h - 1 - py) / PX_PER_M
		for px in w:
			var u := U_MIN + float(px) / PX_PER_M
			var smp := _sample(u, s)
			var col := Color(0.12, 0.11, 0.10) # solid rock
			if bool(smp["inside"]):
				inside[py * w + px] = 1
				var s_floor: float = float(smp["floor"])
				var t := clampf((s_floor - Y_LO) / (Y_HI - Y_LO), 0.0, 1.0)
				col = Color(0.20, 0.36, 0.40).lerp(Color(0.86, 0.76, 0.52), t)
				if String(smp["kind"]) == "split_crawlway":
					col = Color(0.85, 0.35, 0.70) if (px + py) % 6 < 3 else col
				if bool(smp.get("water", false)):
					col = Color(0.22, 0.62, 0.70)
				# 2 m contour lines
				if fmod(s_floor, 2.0) < 0.12:
					col = col.darkened(0.25)
			elif s < 0.0:
				col = Color(0.30, 0.48, 0.24) # meadow outside the mouth
			img.set_pixel(px, py, col)

	# Wall outline
	for py in range(1, h - 1):
		for px in range(1, w - 1):
			if inside[py * w + px] == 1 and (inside[py * w + px - 1] == 0 or inside[py * w + px + 1] == 0 or inside[(py - 1) * w + px] == 0 or inside[(py + 1) * w + px] == 0):
				img.set_pixel(px, py, Color(0.02, 0.02, 0.02))

	# 10 m grid ticks
	for gu in range(int(U_MIN), int(U_MAX) + 1, 10):
		for py in range(0, h, 4):
			var p := _to_px(float(gu), 0.0, h)
			img.set_pixel(clampi(p.x, 0, w - 1), py, img.get_pixel(clampi(p.x, 0, w - 1), py).lightened(0.12))

	# Ledge route
	for i in range(CaveLayout.LEDGE_ROUTE.size() - 1):
		_line(img, CaveLayout.LEDGE_ROUTE[i] as Vector3, CaveLayout.LEDGE_ROUTE[i + 1] as Vector3, Color(1.0, 0.55, 0.10), 3, h)
	# Markers
	var sky_c: Vector3 = CaveLayout.SKYLIGHT["c"]
	_ring(img, Vector2(sky_c.x, sky_c.z), float(CaveLayout.SKYLIGHT["r"]), Color(1.0, 0.92, 0.35), h)
	_dot(img, Vector2(CaveLayout.WATERFALL.x, CaveLayout.WATERFALL.z), 1.4, Color(1, 1, 1), h)
	_dot(img, Vector2(CaveLayout.SPAWN.x, CaveLayout.SPAWN.z), 1.6, Color(0.95, 0.15, 0.15), h)
	_line(img, CaveLayout.SPAWN, CaveLayout.SPAWN.lerp(CaveLayout.SPAWN_LOOK_AT, 0.35), Color(0.95, 0.15, 0.15), 2, h)
	_dot(img, Vector2(0.0, 0.0), 1.6, Color(0.2, 0.95, 0.3), h)

	img.save_png(path)
	print("Saved ", path, " (", w, "x", h, ")")


func _dot(img: Image, c: Vector2, r_m: float, col: Color, h: int) -> void:
	var cp := _to_px(c.x, c.y, h)
	var r := int(r_m * PX_PER_M)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy <= r * r:
				var x := cp.x + dx
				var y := cp.y + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, col)


func _ring(img: Image, c: Vector2, r_m: float, col: Color, h: int) -> void:
	for i in 180:
		var a := float(i) / 180.0 * TAU
		_dot(img, c + Vector2(cos(a), sin(a)) * r_m, 0.25, col, h)


func _line(img: Image, a: Vector3, b: Vector3, col: Color, thick: int, h: int) -> void:
	var steps := int(a.distance_to(b) * PX_PER_M * 1.5) + 1
	for i in steps + 1:
		var p := a.lerp(b, float(i) / float(steps))
		_dot(img, Vector2(p.x, p.z), float(thick) * 0.5 / PX_PER_M, col, h)


# ------------------------------------------------------------------------------
# Side elevation profile along the main route
# ------------------------------------------------------------------------------

func _route_points() -> Array:
	var pts: Array = []
	for item: String in CaveLayout.MAIN_ROUTE:
		if item.begins_with("@"):
			var c: Dictionary = CaveLayout.CHAMBERS[item.substr(1)]
			var cc: Vector3 = c["c"]
			pts.append(Vector3(cc.x, 0.0, cc.z))
		else:
			for n: Dictionary in CaveLayout.TUNNELS[item]:
				pts.append(n["p"] as Vector3)
	return pts


func _render_profile(path: String) -> void:
	var w := 1100
	var h := 420
	var y_min := 10.0
	var y_max := 64.0
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.12, 0.11, 0.10))

	var pts := _route_points()
	var samples: Array = []
	var total := 0.0
	var sky_c_prof: Vector3 = CaveLayout.SKYLIGHT["c"]
	var sky_r_prof: float = float(CaveLayout.SKYLIGHT["r"])
	for i in range(pts.size() - 1):
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		var n := maxi(int(seg * 2.0), 1)
		for k in n:
			var t := float(k) / float(n)
			var u := lerpf(a.x, b.x, t)
			var s := lerpf(a.z, b.z, t)
			var smp := _sample(u, s)
			if Vector2(u - sky_c_prof.x, s - sky_c_prof.z).length() < sky_r_prof + 2.5:
				smp["skylight"] = true
			samples.append({"d": total + seg * t, "smp": smp})
		total += seg

	for e: Dictionary in samples:
		var x: int = int(float(e["d"]) / total * float(w - 1))
		var smp: Dictionary = e["smp"]
		if not bool(smp["inside"]):
			continue
		var s_floor: float = float(smp["floor"])
		var s_ceil: float = float(smp["ceil"])
		if bool(smp.get("skylight", false)):
			s_ceil = y_max
		var fy: int = int((1.0 - (s_floor - y_min) / (y_max - y_min)) * float(h - 1))
		var cy: int = int((1.0 - (s_ceil - y_min) / (y_max - y_min)) * float(h - 1))
		var air_col := Color(0.55, 0.62, 0.58) if bool(smp.get("skylight", false)) else Color(0.30, 0.34, 0.38)
		for y in range(clampi(cy, 0, h - 1), clampi(fy, 0, h - 1)):
			img.set_pixel(x, y, air_col)
		for y in range(clampi(fy, 0, h - 1), mini(fy + 3, h)):
			img.set_pixel(x, y, Color(0.86, 0.76, 0.52))
		if bool(smp.get("water", false)):
			var wy: int = int((1.0 - (float(CaveLayout.POOL["water_y"]) - y_min) / (y_max - y_min)) * float(h - 1))
			for y in range(clampi(wy, 0, h - 1), clampi(fy, 0, h - 1)):
				img.set_pixel(x, y, Color(0.22, 0.62, 0.70))

	# Mountain surface target and 10 m grid lines
	var my := int((1.0 - (CaveLayout.MOUNTAIN_SURFACE_OVER_HALL - y_min) / (y_max - y_min)) * float(h - 1))
	for x in range(0, w, 3):
		img.set_pixel(x, my, Color(0.35, 0.70, 0.30))
	for gy in range(10, 65, 10):
		var py := int((1.0 - (float(gy) - y_min) / (y_max - y_min)) * float(h - 1))
		for x in range(0, w, 8):
			img.set_pixel(x, clampi(py, 0, h - 1), Color(0.25, 0.24, 0.22))
	img.save_png(path)
	print("Saved ", path, " route length = %.1f m" % total)

