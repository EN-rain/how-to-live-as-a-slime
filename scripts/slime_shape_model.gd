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

## Process-wide instrumentation (F3 overlay). Totals; the HUD derives per-tick rates.
static var debug_rebuild_count := 0
static var debug_baked_points_count := 0

## Quantized posture -> immutable baked hull variants, shared by every slime. A
## continuous posture change usually lands in the same bucket and reuses the same
## shape, so near-steady squeezes stop rebuilding convex hulls every tick.
const HULL_CACHE_MAX := 512
static var _hull_cache := {}
static var _hull_order: Array = []

var _unit_points := PackedVector3Array()
var _rest_radius_table := PackedFloat32Array()
var _last_key_int := -1
var _resolved_points := PackedVector3Array()
var _resolved_dims := Vector3.ZERO


func configure(t: SlimeTuning) -> void:
	tuning = t
	t.validate()
	var k := 0.86 - t.melt * 0.22
	rest_half_height = t.reference_radius * k
	rest_full_height = 2.0 * rest_half_height
	_build_rest_profile()
	_last_key_int = -1
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
func resolve(p_scale: float, _p_liquid: float, _p_height_ratio: float, _p_squeeze: float, p_axis: Vector3) -> bool:
	scale = p_scale
	liquid = 0.0
	height_ratio = 1.0
	squeeze = min_squeeze()
	if p_axis.length_squared() > 1e-6:
		axis = Vector3(p_axis.x, 0.0, p_axis.z).normalized()
	spread = 1.0
	flow_stretch = 1.0
	height_boost = 1.0
	full_height = rest_full_height * scale
	semi_a = rest_max_radius * scale
	semi_b = semi_a
	var key := posture_key_for(scale, liquid, height_ratio, squeeze, axis)
	var e := _cache_entry(scale, liquid, height_ratio, squeeze, axis)
	var dims: Vector3 = e["dims"]
	if key == _last_key_int and dims == _resolved_dims:
		return false
	_last_key_int = key
	_resolved_points = e["points"]
	_resolved_dims = dims
	shape = _variant(e, 0)
	return true


func _rebuild() -> void:
	debug_rebuild_count += 1
	var e := _cache_entry(scale, liquid, height_ratio, squeeze, axis)
	_resolved_points = e["points"]
	_resolved_dims = e["dims"]
	shape = _variant(e, 0)


## The baked envelope for the currently resolved posture, shared by every probe that
## tests the committed hull. Callers must duplicate before eroding it in place.
func resolved_points() -> PackedVector3Array:
	return _resolved_points


## Signature of the currently resolved posture; lets callers cache derived hulls
## (e.g. eroded probes) and rebuild them only when the posture actually changes.
func posture_key() -> int:
	return _last_key_int


## Canonical integer signature of a posture. Coarse enough that a smooth transition
## reuses buckets, fine enough that the hull never strays more than half a step from
## the rendered dimensions (~0.25% of the radius).
static func posture_key_for(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, _p_axis: Vector3) -> int:
	var sx := int(roundf(p_scale * 25.0))
	var lq := int(roundf(p_liquid * 25.0))
	var hr := int(roundf(p_height_ratio * 25.0))
	var sq := int(roundf(p_squeeze * 25.0))
	return (sx << 40) | (lq << 32) | (hr << 24) | (sq << 16)


## Cache entry for one quantized posture bucket.
func _cache_entry(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> Dictionary:
	var key := posture_key_for(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis)
	var e = _hull_cache.get(key)
	if e != null:
		return e
	var q_scale := roundf(p_scale * 25.0) / 25.0
	var dims := _envelope_dims(q_scale, p_liquid, p_height_ratio, p_squeeze)
	var ax := _canonical_axis(p_axis)
	e = {"dims": dims, "axis": ax, "points": _bake_dims(dims, ax), "raw": null, "e2": null, "e05": null}
	_hull_cache[key] = e
	_hull_order.append(key)
	while _hull_order.size() > HULL_CACHE_MAX:
		_hull_cache.erase(_hull_order.pop_front())
	return e


## Support extents of a posture: circular horizontal radius (x == y) and proportional core height (z).
func _envelope_dims(p_scale: float, p_liquid: float, _p_height_ratio: float, p_squeeze: float) -> Vector3:
	var sq := clampf(p_squeeze, lerpf(tuning.min_normal_squeeze, tuning.min_liquid_squeeze, p_liquid), 1.0)
	var r := p_scale * sq
	return Vector3(r, r, p_scale * sq)


func _canonical_axis(p_axis: Vector3) -> Vector3:
	var ax := Vector3(p_axis.x, 0.0, p_axis.z)
	if ax.length_squared() < 1e-8:
		return Vector3.RIGHT
	return ax.normalized()


## Bake the unit profile at explicit support extents (circular in XZ, never oval).
func _bake_dims(dims: Vector3, _axis: Vector3) -> PackedVector3Array:
	var n := _unit_points.size()
	var pts := PackedVector3Array()
	pts.resize(n)
	var rx := dims.x
	var ry := dims.z
	for i in n:
		var p := _unit_points[i]
		pts[i] = Vector3(p.x * rx, p.y * ry, p.z * rx)
	return pts


func cached_points(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3) -> PackedVector3Array:
	return _cache_entry(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis)["points"]


## variant: 0 = raw hull, 1 = eroded by 2*skin (posture legality), 2 = eroded by
## 0.5*skin (clearance). Variants build lazily so a miss only pays for what is queried.
func cached_shape(p_scale: float, p_liquid: float, p_height_ratio: float, p_squeeze: float, p_axis: Vector3, variant := 0) -> ConvexPolygonShape3D:
	return _variant(_cache_entry(p_scale, p_liquid, p_height_ratio, p_squeeze, p_axis), variant)


func _variant(e: Dictionary, variant: int) -> ConvexPolygonShape3D:
	var field := "raw"
	var margin := 0.0
	if variant == 1:
		field = "e2"
		margin = tuning.skin * 2.0
	elif variant == 2:
		field = "e05"
		margin = tuning.skin * 0.5
	if e[field] == null:
		var pts: PackedVector3Array = e["points"]
		if margin > 0.0:
			pts = erode_points(pts.duplicate(), margin)
		e[field] = _shape_from(pts)
	return e[field]


static func _shape_from(pts: PackedVector3Array) -> ConvexPolygonShape3D:
	var s := ConvexPolygonShape3D.new()
	s.set_points(pts)
	return s


## Radial + top erosion, shared by the hull cache and the motor's ad-hoc probes.
static func erode_points(pts: PackedVector3Array, margin: float) -> PackedVector3Array:
	var n := pts.size()
	var top := 0.0
	for i in n:
		top = maxf(top, pts[i].y)
	top = maxf(0.0, top - margin)
	var bot := minf(margin, top)
	for i in n:
		var p := pts[i]
		var r := sqrt(p.x * p.x + p.z * p.z)
		var f := maxf(0.0, r - margin) / maxf(r, 1e-5)
		pts[i] = Vector3(p.x * f, clampf(p.y, bot, top), p.z * f)
	return pts


## Bake envelope points (foot at origin, world orientation) for arbitrary dimensions
## without mutating the resolved state. Used for transition/expansion probes.
func baked_points(p_scale: float, p_liquid: float, _p_height_ratio: float, p_squeeze: float, _p_axis: Vector3) -> PackedVector3Array:
	debug_baked_points_count += 1
	var sq := clampf(p_squeeze, lerpf(tuning.min_normal_squeeze, tuning.min_liquid_squeeze, p_liquid), 1.0)
	var sa := p_scale * sq
	var sv := p_scale * sq
	var n := _unit_points.size()
	var pts := PackedVector3Array()
	pts.resize(n)
	for i in n:
		var p := _unit_points[i]
		pts[i] = Vector3(p.x * sa, p.y * sv, p.z * sa)
	return pts


func set_foot(world_foot: Vector3) -> void:
	foot = world_foot


func query_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, foot)


## Max horizontal extent of the resolved body along any horizontal direction (circular).
func horizontal_support(_dir: Vector3) -> float:
	return semi_a


## Current body radius at a world height (circular in XZ).
func world_radius_at(world_y: float, _dir: Vector3) -> float:
	if world_y >= foot.y + full_height:
		return semi_a
	var rest_h := (world_y - foot.y) / maxf(1e-6, scale * height_ratio)
	return rest_radius_at(rest_h) * scale * spread


## Convert a world offset from the actor root into mesh-local shader units.
func mesh_local(world_offset: Vector3) -> Vector3:
	var s := maxf(1e-6, scale)
	var r := maxf(1e-6, spread)
	return Vector3(world_offset.x / (s * r), world_offset.y / s, world_offset.z / (s * r))


func center() -> Vector3:
	return foot + Vector3(0, full_height * 0.5, 0)


## Inner clearance sphere radius: if an opening fits this radius, the slime goes through.
func core_sphere_radius() -> float:
	var r := rest_max_radius * scale * spread * min_squeeze()
	return maxf(r, 0.05)


func core_sphere_center() -> Vector3:
	return center()


## Cached circular inner core hull at the posture's minimum legal radius.
func core_shape(variant := 1) -> ConvexPolygonShape3D:
	return cached_shape(scale, liquid, height_ratio, min_squeeze(), Vector3.RIGHT, variant)