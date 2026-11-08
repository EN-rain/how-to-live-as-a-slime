class_name SlimeShapeModel
extends RefCounted
## Authoritative physical shape for one slime.
##
## Owns the rest profile (identical maths to the shader's rest deformation), the
## resolved posture dimensions, and a conservative convex collision envelope baked
## from that profile. Every size-sensitive system consumes these resolved values;
## nothing re-derives liquid height or spread independently.
##
## The envelope is a convex hull of the resolved profile, so it conservatively
## contains the stylized (non-convex) rendered body. Both squeeze factors live in
## the envelope and are published to the shader, which therefore cannot leave the
## hull. Points are baked
## in world orientation with the foot at the origin because Godot shape queries
## ignore non-uniform scale in the query transform.

const PROFILE_RINGS := 13
## 24 sides keep the chord error under 1 percent, below the collision skin, so the
## smooth rendered surface cannot bulge past the hull by more than `skin`.
const PROFILE_SEGMENTS := 24
const RADIUS_SAMPLES := 48

var tuning: SlimeTuning

var rest_half_height := 1.27744
var rest_full_height := 2.55488
var rest_max_radius := 2.0

var scale := 1.0
var liquid := 0.0
var height_ratio := 1.0
var spread := 1.0
var squeeze := 1.0
## Along-flow stretch that conserves the rendered mass while squeezing. The shader
## applies the identical factor, so neither side can leave the other's envelope.
var flow_stretch := 1.0
var height_boost := 1.0
var axis := Vector3(1, 0, 0)

var foot := Vector3.ZERO
var full_height := 2.55488
var semi_a := 2.0
var semi_b := 2.0

var shape: ConvexPolygonShape3D

var _unit_points := PackedVector3Array()
var _rest_radius_table := PackedFloat32Array()
var _last_key := ""
var _resolved_points := PackedVector3Array()


func configure(t: SlimeTuning) -> void:
	tuning = t
	var k := 0.86 - t.melt * 0.22
	rest_half_height = t.reference_radius * k
	rest_full_height = 2.0 * rest_half_height
	_build_rest_profile()
	_last_key = ""
	if shape == null:
		shape = ConvexPolygonShape3D.new()


func _build_rest_profile() -> void:
	_unit_points = PackedVector3Array()
	var radii := PackedFloat32Array()
	var heights := PackedFloat32Array()
	var R := tuning.reference_radius
	var k := 0.86 - tuning.melt * 0.22
	var ground := -R * k
	rest_max_radius = 0.0
	for i in PROFILE_RINGS:
		var y := -R + 2.0 * R * float(i) / float(PROFILE_RINGS - 1)
		var h01 := clampf((y / R + 1.0) * 0.5, 0.0, 1.0)
		var lower := pow(1.0 - h01, 1.35) * _smoothstep(0.0, 0.22, h01)
		var belly := sin(h01 * PI)
		var spread_r := 1.0 + (lower * 0.34 + belly * 0.08) * (0.8 + tuning.melt * 1.1)
		var r := sqrt(maxf(0.0, R * R - y * y)) * spread_r
		var ys := y * k
		var base_h := ys - ground
		if base_h < 0.9:
			var tb := clampf(base_h / 0.9, 0.0, 1.0)
			ys = ground + 0.9 * (2.0 * tb * tb - tb * tb * tb)
		var fh := ys - ground
		radii.append(r)
		heights.append(fh)
		rest_max_radius = maxf(rest_max_radius, r)
		for s in PROFILE_SEGMENTS:
			var a := TAU * float(s) / float(PROFILE_SEGMENTS)
			_unit_points.append(Vector3(cos(a) * r, fh, sin(a) * r))
	_rest_radius_table = PackedFloat32Array()
	for i in RADIUS_SAMPLES:
		var h := rest_full_height * float(i) / float(RADIUS_SAMPLES - 1)
		_rest_radius_table.append(_interp_radius(heights, radii, h))


func _interp_radius(heights: PackedFloat32Array, radii: PackedFloat32Array, h: float) -> float:
	if h <= heights[0]:
		return radii[0]
	for i in range(1, heights.size()):
		if h <= heights[i]:
			var t := (h - heights[i - 1]) / maxf(1e-6, heights[i] - heights[i - 1])
			return lerpf(radii[i - 1], radii[i], t)
	return radii[radii.size() - 1]


static func _smoothstep(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func rest_radius_at(rest_height: float) -> float:
	var f := clampf(rest_height / maxf(1e-6, rest_full_height), 0.0, 1.0) * float(RADIUS_SAMPLES - 1)
	var i := int(f)
	var j := mini(i + 1, RADIUS_SAMPLES - 1)
	return lerpf(_rest_radius_table[i], _rest_radius_table[j], f - float(i))


func min_squeeze() -> float:
	return lerpf(tuning.min_normal_squeeze, tuning.min_liquid_squeeze, liquid)


## Resolve posture dimensions. Returns true when the baked envelope must be rebuilt.
func resolve(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> bool:
	scale = p_scale
	liquid = p_liquid
	height_ratio = p_height_ratio
	squeeze = clampf(p_squeeze, min_squeeze(), 1.0)
	if p_axis.length_squared() > 1e-6:
		axis = Vector3(p_axis.x, 0.0, p_axis.z).normalized()
	spread = pow(maxf(height_ratio, 1e-3), -0.5)
	flow_stretch = 1.0 + (1.0 - squeeze) * tuning.squeeze_elongation
	height_boost = 1.0 + (1.0 - squeeze) * tuning.squeeze_height_gain * (1.0 - liquid)
	full_height = rest_full_height * scale * height_ratio * height_boost
	semi_a = rest_max_radius * scale * spread * squeeze
	semi_b = rest_max_radius * scale * spread * flow_stretch
	var key := "%.4f|%.4f|%.4f|%.4f|%.4f|%.4f" % [scale, liquid, height_ratio, squeeze, axis.x, axis.z]
	if key == _last_key:
		return false
	_last_key = key
	_rebuild()
	return true


func _rebuild() -> void:
	_resolved_points = baked_points(scale, liquid, height_ratio, squeeze, axis)
	shape.set_points(_resolved_points)


## The baked envelope for the currently resolved posture, shared by every probe that
## tests the committed hull. Callers must duplicate before eroding it in place.
func resolved_points() -> PackedVector3Array:
	return _resolved_points


## Bake envelope points (foot at origin, world orientation) for arbitrary dimensions
## without mutating the resolved state. Used for transition/expansion probes.
func baked_points(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> PackedVector3Array:
	var ax := Vector3(p_axis.x, 0.0, p_axis.z)
	if ax.length_squared() < 1e-8:
		ax = Vector3(1, 0, 0)
	ax = ax.normalized()
	var perp := Vector3(-ax.z, 0.0, ax.x)
	var sq := clampf(p_squeeze, lerpf(tuning.min_normal_squeeze, tuning.min_liquid_squeeze, p_liquid), 1.0)
	var spr := pow(maxf(p_height_ratio, 1e-3), -0.5)
	var stretch := 1.0 + (1.0 - sq) * tuning.squeeze_elongation
	var boost := 1.0 + (1.0 - sq) * tuning.squeeze_height_gain * (1.0 - p_liquid)
	var sa := p_scale * spr * sq
	var sb := p_scale * spr * stretch
	var sv := p_scale * p_height_ratio * boost
	var axx := ax.x
	var axz := ax.z
	var px := perp.x
	var pz := perp.z
	var n := _unit_points.size()
	var pts := PackedVector3Array()
	pts.resize(n)
	for i in n:
		var p := _unit_points[i]
		var along := p.x * axx + p.z * axz
		var across := p.x * px + p.z * pz
		pts[i] = Vector3(
			axx * along * sa + px * across * sb,
			p.y * sv,
			axz * along * sa + pz * across * sb)
	return pts


func set_foot(world_foot: Vector3) -> void:
	foot = world_foot


func query_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, foot)


## Max horizontal extent of the resolved body along a horizontal direction.
func horizontal_support(dir: Vector3) -> float:
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-8:
		return semi_a
	d = d.normalized()
	var perp := Vector3(-axis.z, 0.0, axis.x)
	var ca := d.dot(axis)
	var cb := d.dot(perp)
	return sqrt(semi_a * semi_a * ca * ca + semi_b * semi_b * cb * cb)


## Current body radius at a world height, along a horizontal direction.
func world_radius_at(world_y: float, dir: Vector3) -> float:
	# Above the body there is no cross-section; use the widest horizontal extent so
	# the engulf backstop still works for a puddle (its apex ring has zero radius).
	if world_y >= foot.y + full_height:
		return horizontal_support(dir)
	var rest_h := (world_y - foot.y) / maxf(1e-6, scale * height_ratio * height_boost)
	var r := rest_radius_at(rest_h) * scale * spread
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 1e-8:
		return r
	d = d.normalized()
	var perp := Vector3(-axis.z, 0.0, axis.x)
	var ca := d.dot(axis)
	var cb := d.dot(perp)
	var fa := ca * squeeze
	var fb := cb * flow_stretch
	var m := sqrt(fa * fa + fb * fb)
	return r * maxf(m, 1e-4)


## Convert a world offset from the actor root into mesh-local shader units.
## The shader subtracts `uGapLocal` AFTER the liquid spread multiply, so the
## horizontal components must be divided by scale * spread as well.
func mesh_local(world_offset: Vector3) -> Vector3:
	var s := maxf(1e-6, scale)
	var r := maxf(1e-6, spread)
	return Vector3(world_offset.x / (s * r), world_offset.y / s, world_offset.z / (s * r))


func center() -> Vector3:
	return foot + Vector3(0, full_height * 0.5, 0)