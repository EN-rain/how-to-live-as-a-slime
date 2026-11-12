class_name WaterSplashVFX
extends MultiMeshInstance3D
## Pooled 3D water droplet VFX for slime plunge crowns, swim bow sprays, and aerial drips.

const MAX_PARTICLES := 96

var _active_count := 0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _age := PackedFloat32Array()
var _max_age := PackedFloat32Array()
var _size := PackedFloat32Array()
var _tint := PackedColorArray()
var _rng := RandomNumberGenerator.new()

static var _shared_mesh: ArrayMesh = null
static var _shared_mat: ShaderMaterial = null


func _init() -> void:
	name = "WaterSplashVFX"
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-4200.0, -120.0, -4200.0), Vector3(8400.0, 400.0, 8400.0))
	_rng.seed = 98217

	_pos.resize(MAX_PARTICLES)
	_vel.resize(MAX_PARTICLES)
	_age.resize(MAX_PARTICLES)
	_max_age.resize(MAX_PARTICLES)
	_size.resize(MAX_PARTICLES)
	_tint.resize(MAX_PARTICLES)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _get_droplet_mesh()
	mm.instance_count = MAX_PARTICLES
	mm.visible_instance_count = 0
	multimesh = mm


static func _get_droplet_mesh() -> ArrayMesh:
	if _shared_mesh != null:
		return _shared_mesh

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Smooth rounded water pearl / liquid bead mesh (soft spherical vertex normals — zero jagged spears)
	var lat_segs := 7
	var lon_segs := 10
	var rx_bead := 0.086
	var ry_bead := 0.098
	var rings: Array[Array] = []
	for iy in range(lat_segs + 1):
		var v := float(iy) / float(lat_segs)
		var phi := v * PI
		var sp_y := -cos(phi) * ry_bead
		var ring_r := sin(phi) * rx_bead
		var row: Array[Vector3] = []
		for ix in range(lon_segs + 1):
			var u := (float(ix) / float(lon_segs)) * TAU
			row.append(Vector3(cos(u) * ring_r, sp_y, sin(u) * ring_r))
		rings.append(row)

	var emit_v := func(p: Vector3) -> void:
		var sn := Vector3(p.x / maxf(rx_bead, 1e-4), p.y / maxf(ry_bead, 1e-4), p.z / maxf(rx_bead, 1e-4)).normalized()
		st.set_normal(sn)
		st.add_vertex(p)

	var add_tri := func(p0: Vector3, p1: Vector3, p2: Vector3) -> void:
		var tri_n := (p2 - p0).cross(p1 - p0)
		if tri_n.length_squared() < 1e-10:
			return
		var mid := (p0 + p1 + p2) * 0.3333333
		if tri_n.dot(mid) < 0.0:
			emit_v.call(p0); emit_v.call(p2); emit_v.call(p1)
		else:
			emit_v.call(p0); emit_v.call(p1); emit_v.call(p2)

	for iy in lat_segs:
		for ix in lon_segs:
			var a: Vector3 = rings[iy][ix]
			var b: Vector3 = rings[iy][ix + 1]
			var c: Vector3 = rings[iy + 1][ix + 1]
			var d: Vector3 = rings[iy + 1][ix]
			if iy > 0:
				add_tri.call(a, b, c)
			if iy < lat_segs - 1:
				add_tri.call(a, c, d)

	_shared_mesh = st.commit()

	if _shared_mat == null:
		var sh := Shader.new()
		sh.code = """shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_lambert_wrap, specular_disabled;

varying vec4 v_col;

void vertex() {
	v_col = COLOR;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	float ndv = clamp(dot(n, v), 0.0, 1.0);
	float rim = pow(max(1.0 - ndv, 1e-4), 1.9);
	float edge_soft = smoothstep(0.06, 0.44, ndv);
	vec3 h_vec = normalize(normalize(vec3(0.42, 0.85, 0.36)) + v);
	float glint = pow(max(dot(n, h_vec), 1e-4), 48.0);
	vec3 deep_drop = v_col.rgb * vec3(0.55, 0.86, 1.0);
	vec3 col = mix(deep_drop, vec3(0.96, 0.99, 1.0), clamp(rim * 0.62 + glint * 0.95, 0.0, 1.0));
	ALBEDO = col;
	EMISSION = deep_drop * 0.30 + vec3(0.86, 0.98, 1.0) * (rim * 0.56 + glint * 1.15);
	ROUGHNESS = 0.06;
	SPECULAR = 0.0;
	ALPHA = clamp(v_col.a * edge_soft * (0.72 + rim * 0.40 + glint * 0.35), 0.0, 0.95);
}
"""
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = sh
	_shared_mesh.surface_set_material(0, _shared_mat)
	return _shared_mesh


func _spawn(p: Vector3, v: Vector3, life: float, sz: float, col: Color) -> void:
	var idx := _active_count
	if idx >= MAX_PARTICLES:
		# Replace the oldest active particle when saturated
		var best_ratio := -1.0
		idx = 0
		for i in _active_count:
			var r := _age[i] / maxf(_max_age[i], 0.01)
			if r > best_ratio:
				best_ratio = r
				idx = i
	else:
		_active_count += 1
	_pos[idx] = p
	_vel[idx] = v
	_age[idx] = 0.0
	_max_age[idx] = maxf(life, 0.12)
	_size[idx] = sz
	_tint[idx] = col


func emit_plunge(center: Vector3, radius: float, water_y: float, impact_speed: float = 4.5, is_cave: bool = true) -> void:
	var count := clampi(int(round(22.0 + impact_speed * 1.8)), 22, 34)
	var energy := clampf(impact_speed / 5.0, 0.78, 1.90)
	var base_col := Color(0.48, 0.92, 1.0, 0.94) if is_cave else Color(0.68, 0.95, 1.0, 0.96)
	for i in count:
		var ang := (float(i) / float(count)) * TAU + _rng.randf_range(-0.14, 0.14)
		var ring_r := radius * _rng.randf_range(0.55, 1.02)
		var dir_xz := Vector3(cos(ang), 0.0, sin(ang))
		var sp := center + dir_xz * ring_r
		sp.y = water_y + _rng.randf_range(0.04, 0.18)
		var is_mist := (i % 3 == 2)
		var v_out := (_rng.randf_range(0.95, 2.2) if is_mist else _rng.randf_range(1.6, 3.8)) * energy
		var v_up := (_rng.randf_range(4.4, 7.0) if is_mist else _rng.randf_range(3.6, 6.0)) * energy
		var vel := dir_xz * v_out + Vector3(0.0, v_up, 0.0)
		var life := _rng.randf_range(0.55, 0.96)
		var sz := _rng.randf_range(0.48, 0.78) if is_mist else _rng.randf_range(0.64, 1.06)
		var col := base_col.lerp(Color(0.95, 0.99, 1.0, 0.96), _rng.randf_range(0.25, 0.78))
		_spawn(sp, vel, life, sz, col)


func emit_swim_spray(pos: Vector3, vel_xz: Vector3, radius: float, water_y: float, is_cave: bool = true) -> void:
	var spd := Vector2(vel_xz.x, vel_xz.z).length()
	if spd < 1.0:
		return
	var fwd := Vector3(vel_xz.x, 0.0, vel_xz.z).normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var count := 5 if spd > 3.5 else 3
	var base_col := Color(0.56, 0.95, 1.0, 0.94) if is_cave else Color(0.76, 0.98, 1.0, 0.96)
	for _k in count:
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var bow_off := fwd * (radius * _rng.randf_range(0.45, 0.96)) + right * (side * radius * _rng.randf_range(0.32, 0.88))
		var sp := Vector3(pos.x + bow_off.x, water_y + 0.06, pos.z + bow_off.z)
		var pvel := right * (side * _rng.randf_range(1.1, 2.4)) - fwd * _rng.randf_range(0.2, 1.0) + Vector3(0.0, _rng.randf_range(1.8, 3.2) * clampf(spd * 0.25, 0.72, 1.35), 0.0)
		_spawn(sp, pvel, _rng.randf_range(0.38, 0.65), _rng.randf_range(0.44, 0.80), base_col)


func emit_wet_drip(pos: Vector3, radius: float, wetness: float) -> void:
	if wetness < 0.2:
		return
	var ang := _rng.randf() * TAU
	var rr := radius * _rng.randf_range(0.35, 0.82)
	var sp := pos + Vector3(cos(ang) * rr, _rng.randf_range(-0.15, 0.45) * radius, sin(ang) * rr)
	var pvel := Vector3(cos(ang) * 0.35, _rng.randf_range(-0.6, 0.35), sin(ang) * 0.35)
	_spawn(sp, pvel, _rng.randf_range(0.25, 0.45), _rng.randf_range(0.45, 0.75), Color(0.68, 0.94, 1.0, wetness * 0.82))


func step(dt: float, active_water_y: float) -> void:
	if multimesh == null:
		return
	if _active_count <= 0:
		if multimesh.visible_instance_count != 0:
			multimesh.visible_instance_count = 0
		return

	var i := 0
	var grav := Vector3(0.0, -14.5, 0.0)
	while i < _active_count:
		var a := _age[i] + dt
		var ma := _max_age[i]
		var v := _vel[i] + grav * dt
		v *= clampf(1.0 - dt * 0.85, 0.0, 1.0)
		var p := _pos[i] + v * dt

		if a >= ma or (active_water_y > -9000.0 and v.y < 0.0 and p.y < active_water_y - 0.14):
			var last := _active_count - 1
			if i != last:
				_pos[i] = _pos[last]
				_vel[i] = _vel[last]
				_age[i] = _age[last]
				_max_age[i] = _max_age[last]
				_size[i] = _size[last]
				_tint[i] = _tint[last]
			_active_count = last
			continue

		_age[i] = a
		_vel[i] = v
		_pos[i] = p

		var t := clampf(a / ma, 0.0, 1.0)
		var spd := v.length()
		var up_d := v / spd if spd > 0.08 else Vector3.UP
		var ref := Vector3.FORWARD if absf(up_d.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
		var rx := up_d.cross(ref).normalized()
		var rz := rx.cross(up_d).normalized()
		var sz := _size[i] * lerpf(1.0, 0.48, t * t)
		var stretch := sz * clampf(0.95 + spd * 0.055, 0.95, 1.38)
		var b := Basis(rx * sz, up_d * stretch, rz * sz)
		multimesh.set_instance_transform(i, Transform3D(b, p))

		var col := _tint[i]
		var fade := clampf(t / 0.10, 0.0, 1.0) * (1.0 - smoothstep(0.45, 1.0, t))
		col.a *= fade
		multimesh.set_instance_color(i, col)
		i += 1

	multimesh.visible_instance_count = _active_count
