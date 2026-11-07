class_name SlimeProps
extends Node3D
## Port of the "3D Anime Slime" prop ecosystem.
##
## Spawns edible/solid props, manages multi-contact simultaneous collision resolution,
## fluid corner flow-around, directional squeeze & liquid mode hole clearance,
## climbing & engulfing on props, eating/digestion, force-driven splats, and multi-slime shadows.

signal eaten_changed(total: int)

const SHAPE_BOX := 0
const SHAPE_PRISM := 1
const SHAPE_CONE := 2

const STATE_IDLE := 0
const STATE_EATING := 1
const STATE_GONE := 2

const EAT_TIME := 0.8
const EAT_LINGER := 2.0

@export var slime: Slime
@export var floor_mesh: MeshInstance3D
@export var prop_shader: Shader
@export var prop_count := 36
@export var spawn_seed := 0
@export var floor_y := -1.2

@export_group("Squeeze & Liquid")
@export_range(0.06, 1.0, 0.01) var min_squeeze := 0.12
@export var squeeze_in_rate := 16.0
@export var squeeze_out_rate := 5.0

var props: Array[PropData] = []
var registered_slimes: Array[Slime] = []
var player_slime: Slime = null
var eaten := 0

var _rng := RandomNumberGenerator.new()
var _prop_root: Node3D
var _floor_mat: ShaderMaterial


class PropData extends RefCounted:
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var radius := 1.0
	var fp := 1.0
	var shape := 0
	var base_r := 1.0
	var sides := 0
	var phase := 0.0
	var half := Vector3.ONE
	var state := 0
	var t := 0.0
	var pd := 0.0
	var pv := 0.0
	var p_ro := 0.0
	var p_thr := 1.0
	var hold := 0.0
	var start := Vector3.ZERO
	var off := Vector3.ZERO
	var vel := Vector3.ZERO
	var touch := -1000.0
	var touch_slime: Slime = null
	var cnx := 0.0
	var cnz := 0.0
	var hit_cd := -1000.0
	var eater: Slime = null
	var last_presser: Slime = null
	var base_scale := Vector3.ONE
	var is_static := false
	var total_mass := 0.0
	var absorbed_mass := 0.0
	var real_volume := 0.0
	var engulf_front := 0.0 # Physical penetration depth allowed during push-eating (0.0 to 1.0)

	func calc_real_volume() -> float:
		var sx := mesh.scale.x if mesh else radius
		var sy := mesh.scale.y if mesh else radius
		var sz := mesh.scale.z if mesh else radius
		match shape:
			SHAPE_BOX:
				real_volume = (2.0 * half.x * sx) * (2.0 * half.y * sy) * (2.0 * half.z * sz)
			SHAPE_PRISM:
				var r := base_r * sx
				var h := 2.0 * half.y * sy
				if sides >= 3 and sides < 12:
					var sector := TAU / float(sides)
					var poly_area := 0.5 * float(sides) * r * r * sin(sector)
					real_volume = poly_area * h
				else:
					real_volume = PI * r * r * h
			SHAPE_CONE:
				var r := base_r * sx
				var h := 2.0 * half.y * sy
				real_volume = (1.0 / 3.0) * PI * r * r * h
			_:
				real_volume = (4.0 / 3.0) * PI * pow(radius, 3.0)
		total_mass = real_volume
		return real_volume



func _ready() -> void:
	# Run after Slimes (priority 0) update their positions, so collisions resolve before render
	process_priority = 1

	if prop_shader == null:
		prop_shader = load("res://shaders/prop.gdshader")
	if spawn_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = spawn_seed

	if floor_mesh == null:
		floor_mesh = get_node_or_null("../Floor") as MeshInstance3D
	if floor_mesh:
		_floor_mat = floor_mesh.material_override as ShaderMaterial

	_prop_root = Node3D.new()
	_prop_root.name = "Generated"
	add_child(_prop_root)

	# Spawn test structures FIRST so random props avoid blocking the test gate and bridge!
	_spawn_test_structures()
	_spawn_props()

	if slime != null:
		register_slime(slime)


func register_slime(s: Slime) -> void:
	if not registered_slimes.has(s):
		registered_slimes.append(s)
		if s.role == Slime.Role.PLAYER:
			player_slime = s


func unregister_slime(s: Slime) -> void:
	registered_slimes.erase(s)
	if player_slime == s:
		player_slime = null
	for p in props:
		if p.last_presser == s:
			p.last_presser = null
			p.pd = 0.0
			p.pv = 0.0
			p.hold = 0.0
		if p.touch_slime == s:
			p.touch_slime = null


# ------------------------------------------------------------------------------------------------
# Spawning
# ------------------------------------------------------------------------------------------------

func _spawn_props() -> void:
	var makers := [
		{"shape": SHAPE_BOX, "size": Vector3(1.4, 1.4, 1.4)},
		{"shape": SHAPE_BOX, "size": Vector3(1.4, 1.4, 1.4)},
		{"shape": SHAPE_BOX, "size": Vector3(2.0, 0.9, 1.2)},
		{"shape": SHAPE_BOX, "size": Vector3(1.0, 2.2, 1.0)},
		{"shape": SHAPE_PRISM, "r": 0.8, "h": 1.6, "sides": 6},
		{"shape": SHAPE_PRISM, "r": 0.8, "h": 1.2, "sides": 20},
		{"shape": SHAPE_PRISM, "r": 0.9, "h": 1.4, "sides": 3},
		{"shape": SHAPE_CONE, "r": 1.0, "h": 1.8, "sides": 4, "yaw": PI / 4.0},
		{"shape": SHAPE_CONE, "r": 1.0, "h": 1.8, "sides": 16},
	]

	for i in prop_count:
		var maker: Dictionary = makers[_rng.randi_range(0, makers.size() - 1)]
		var shape: int = maker["shape"]
		var mesh: Mesh
		var half: Vector3
		var base_r := 1.0
		var sides := 0
		var phase := 0.0
		var yaw_offset: float = maker.get("yaw", 0.0)

		match shape:
			SHAPE_BOX:
				var size: Vector3 = maker["size"]
				var box := BoxMesh.new()
				box.size = size
				mesh = box
				half = size * 0.5
			SHAPE_PRISM:
				base_r = maker["r"]
				var h: float = maker["h"]
				sides = maker["sides"]
				var prism := CylinderMesh.new()
				prism.top_radius = base_r
				prism.bottom_radius = base_r
				prism.height = h
				prism.radial_segments = sides
				prism.rings = 1
				mesh = prism
				half = Vector3(base_r, h * 0.5, base_r)
			SHAPE_CONE:
				base_r = maker["r"]
				var h: float = maker["h"]
				sides = maker["sides"]
				var cone := CylinderMesh.new()
				cone.top_radius = 0.0
				cone.bottom_radius = base_r
				cone.height = h
				cone.radial_segments = sides
				cone.rings = 1
				mesh = cone
				half = Vector3(base_r, h * 0.5, base_r)

		var radius := 0.4 + pow(_rng.randf(), 1.6) * 2.8
		var fp := radius * 1.25
		var position := Vector3.ZERO
		var placed := false

		for _tries in 80:
			var ang := _rng.randf() * TAU
			var dist := (6.0 + _rng.randf() * 12.0) if i < 12 else (16.0 + _rng.randf() * 60.0)
			var x := cos(ang) * dist
			var z := sin(ang) * dist
			if Vector2(x, z).length() < fp + 4.0:
				continue
			var clear := true
			for q in props:
				if Vector2(q.mesh.position.x - x, q.mesh.position.z - z).length() < q.fp + fp + 0.6:
					clear = false
					break
			if not clear:
				continue
			position = Vector3(x, floor_y + half.y * radius, z)
			placed = true
			break

		if not placed:
			continue

		var p := PropData.new()
		p.radius = radius
		p.fp = fp
		p.shape = shape
		p.base_r = base_r
		p.sides = sides
		p.phase = phase
		p.half = half
		p.state = STATE_IDLE

		var mat := ShaderMaterial.new()
		mat.shader = prop_shader
		mat.set_shader_parameter("uColor", _hsl(_rng.randf(), 0.65, 0.62))
		mat.set_shader_parameter("uDissolve", 0.0)
		p.material = mat

		var mi := MeshInstance3D.new()
		mi.name = "Prop%02d" % i
		mi.mesh = mesh
		mi.material_override = mat
		mi.scale = Vector3.ONE * radius
		mi.position = position
		mi.rotation.y = _rng.randf() * TAU + yaw_offset
		_prop_root.add_child(mi)
		p.mesh = mi
		p.base_scale = mi.scale
		p.calc_real_volume()
		props.append(p)


func _spawn_test_structures() -> void:
	var pillar_mat := ShaderMaterial.new()
	pillar_mat.shader = prop_shader
	pillar_mat.set_shader_parameter("uColor", Color(0.32, 0.72, 0.88))
	pillar_mat.set_shader_parameter("uDissolve", 0.0)

	# 1. Narrow Slit Gate: Two vertical pillars with a 0.5m gap at (8, 0, 8)
	var gate_pos := Vector3(8.0, 0.0, 8.0)
	for side in [-1.0, 1.0]:
		var p_box := BoxMesh.new()
		p_box.size = Vector3(1.2, 3.2, 1.2)
		var p := PropData.new()
		p.radius = 2.4
		p.fp = 2.4
		p.shape = SHAPE_BOX
		p.half = p_box.size * 0.5
		p.material = pillar_mat.duplicate() as ShaderMaterial
		var mi := MeshInstance3D.new()
		mi.name = "GatePillar_%s" % ("L" if side < 0 else "R")
		mi.mesh = p_box
		mi.material_override = p.material
		mi.position = gate_pos + Vector3(side * 0.85, floor_y + 1.6, 0.0)
		_prop_root.add_child(mi)
		p.mesh = mi
		p.is_static = true
		p.base_scale = mi.scale
		p.calc_real_volume()
		props.append(p)

	# 2. Low Tunnel / Overhang Bridge: Clearance of 0.75m at (-10, 0, 8)
	var bridge_pos := Vector3(-10.0, 0.0, 8.0)
	var roof_box := BoxMesh.new()
	roof_box.size = Vector3(3.2, 0.6, 2.4)
	var roof_prop := PropData.new()
	roof_prop.is_static = true
	roof_prop.radius = 2.8
	roof_prop.fp = 2.8
	roof_prop.shape = SHAPE_BOX
	roof_prop.half = roof_box.size * 0.5
	roof_prop.material = pillar_mat.duplicate() as ShaderMaterial
	var roof_mi := MeshInstance3D.new()
	roof_mi.name = "BridgeRoof"
	roof_mi.mesh = roof_box
	roof_mi.material_override = roof_prop.material
	roof_mi.position = bridge_pos + Vector3(0.0, floor_y + 0.75 + 0.3, 0.0)
	_prop_root.add_child(roof_mi)
	roof_prop.mesh = roof_mi
	roof_prop.calc_real_volume()
	props.append(roof_prop)

	for leg_side in [-1.0, 1.0]:
		var leg_box := BoxMesh.new()
		leg_box.size = Vector3(0.5, 0.75, 2.4)
		var leg_p := PropData.new()
		leg_p.is_static = true
		leg_p.radius = 1.8
		leg_p.fp = 1.8
		leg_p.shape = SHAPE_BOX
		leg_p.half = leg_box.size * 0.5
		leg_p.material = pillar_mat.duplicate() as ShaderMaterial
		var leg_mi := MeshInstance3D.new()
		leg_mi.name = "BridgeLeg_%s" % ("L" if leg_side < 0 else "R")
		leg_mi.mesh = leg_box
		leg_mi.material_override = leg_p.material
		leg_mi.position = bridge_pos + Vector3(leg_side * 1.35, floor_y + 0.375, 0.0)
		_prop_root.add_child(leg_mi)
		leg_p.mesh = leg_mi
		leg_p.calc_real_volume()
		props.append(leg_p)


func _hsl(h: float, s: float, l: float) -> Color:
	if s <= 0.0:
		return Color(l, l, l)
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0))


func _hue(p: float, q: float, t: float) -> float:
	if t < 0.0:
		t += 1.0
	if t > 1.0:
		t -= 1.0
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p


# ------------------------------------------------------------------------------------------------
# Per-frame physics & ecosystem update
# ------------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)

	for s in registered_slimes:
		if is_instance_valid(s):
			_step_slime(s, dt)

	# Global press decay for any props no longer actively pressed by a valid slime
	for p in props:
		if p.state == STATE_IDLE and p.pd > 0.0:
			if p.last_presser == null or not is_instance_valid(p.last_presser):
				p.pd = maxf(0.0, p.pd * exp(-15.0 * dt))
				p.pv = 0.0
				if p.pd <= 0.001:
					p.pd = 0.0
					p.last_presser = null
					p.hold = 0.0

	_update_digesting_props(dt)
	_update_floor_shadows()


func _step_slime(s: Slime, dt: float) -> void:
	if s.is_merging:
		return
	# 1. Detect if standing atop a solid prop or climbing
	_update_ground_support(s)

	# 2. Update squeeze & liquid mode gap passage
	_update_slime_squeeze(s, dt)

	# 3. Process edible props pressed/eaten by this slime
	_process_edible_props(s, dt)

	# 4. Multi-contact simultaneous solver for solid obstacles
	_solve_solid_collisions(s, dt)

	# 5. Splat & spread spring dynamics
	_update_slime_splat(s, dt)

	# 6. Inside swallowed prop physics for this slime
	_update_inside_props(s, dt)

	# 7. Feed eating and solid dent uniforms to this slime's shader
	_update_eat_uniforms(s)
	_update_solid_uniforms(s)


func _update_ground_support(s: Slime) -> void:
	var sp := s.position
	var S := s.slime_scale
	var highest_top := floor_y
	var found_prop = null
	var slime_bottom := sp.y - (s.height_per_scale * S)
	var slime_top := slime_bottom + (2.0 * s.height_per_scale * S) * lerpf(1.0, s.liquid_height_ratio, s.liquid_amt)

	for p in props:
		if p.state != STATE_IDLE:
			continue
		var m := p.mesh
		var he := _half_of(p)
		var dx := sp.x - m.position.x
		var dz := sp.z - m.position.z
		var top_y := m.position.y + he.y
		var bottom_y := m.position.y - he.y

		# If prop is elevated above the floor (roof/ceiling/bridge) and slime is under it, ignore
		if bottom_y > floor_y + 0.15 and slime_top <= bottom_y + 0.2:
			continue

		# Check if slime is horizontally within the prop's top footprint
		var in_footprint := false
		if p.shape == SHAPE_BOX:
			var c := cos(m.rotation.y)
			var sn := sin(m.rotation.y)
			var lx := absf(dx * c + dz * sn)
			var lz := absf(-dx * sn + dz * c)
			in_footprint = (lx <= he.x * 1.05 and lz <= he.z * 1.05)
		else:
			var d := Vector2(dx, dz).length()
			var sup := _poly_support(p, dx / maxf(d, 1e-4), dz / maxf(d, 1e-4))
			in_footprint = (d <= sup * 1.05)

		if in_footprint:
			# Slime stepping/climbing: step height scales with slime size (0.55 * S) or liquid climbing (0.75 * S)
			var climb_reach := (0.75 * S) if s.liquid_amt > 0.3 else (0.55 * S)
			if slime_bottom >= top_y - climb_reach:
				if top_y > highest_top:
					highest_top = top_y
					found_prop = p

	s.support_y = highest_top
	s.ground_prop = found_prop


func _prop_closest_surface_point(p: PropData, target: Vector2) -> Vector2:
	var m := p.mesh
	var he := _half_of(p)
	var dx := target.x - m.position.x
	var dz := target.y - m.position.z
	if p.shape == SHAPE_BOX:
		var c := cos(m.rotation.y)
		var sn := sin(m.rotation.y)
		var lx := dx * c - dz * sn
		var lz := dx * sn + dz * c
		var cx := clampf(lx, -he.x, he.x)
		var cz := clampf(lz, -he.z, he.z)
		if absf(cx) < he.x and absf(cz) < he.z:
			var push_x := he.x - absf(cx)
			var push_z := he.z - absf(cz)
			if push_x < push_z:
				cx = he.x if cx >= 0.0 else -he.x
			else:
				cz = he.z if cz >= 0.0 else -he.z
		var wx := cx * c + cz * sn
		var wz := -cx * sn + cz * c
		return Vector2(m.position.x + wx, m.position.z + wz)
	else:
		var d := maxf(Vector2(dx, dz).length(), 1e-4)
		var ux := dx / d
		var uz := dz / d
		var sup := _poly_support(p, ux, uz) * (0.6 if p.shape == SHAPE_CONE else 1.0)
		return Vector2(m.position.x + ux * sup, m.position.z + uz * sup)


func _update_slime_squeeze(s: Slime, dt: float) -> void:
	var S := s.slime_scale
	var sp := s.position

	# Fix 17: Don't allow liquid to flatten to paper-thin (0.05). Use 0.12 minimum.
	var effective_min_squeeze := min_squeeze
	if s.liquid_amt > 0.01:
		effective_min_squeeze = lerpf(min_squeeze, 0.12, s.liquid_amt)

	var r_max := 0.0
	for k in 6:
		r_max = maxf(r_max, _surf_r(-1.2 + 2.2 * float(k) / 5.0))
	r_max *= S
	var reach := r_max + 0.06 * S

	var slime_bottom := sp.y - s.height_per_scale * S
	var slime_top := slime_bottom + (2.0 * s.height_per_scale * S) * lerpf(1.0, s.liquid_height_ratio, s.liquid_amt)

	var nearby_props: Array[PropData] = []
	for p in props:
		if p.state != STATE_IDLE or p == s.ground_prop or p.mesh == null:
			continue
		# Fix 18: Exclude elevated static overhangs (bridge roof/legs) from gap pairing —
		# they are ceilings, not side walls, and create false near-zero gaps.
		var m := p.mesh
		var he := _half_of(p)
		var prop_bottom := m.position.y - he.y
		if p.is_static and prop_bottom > floor_y + 0.5:
			continue
		if maxf(m.position.y - he.y, floor_y) > minf(m.position.y + he.y, slime_top):
			continue
		var d_sq := Vector2(m.position.x - sp.x, m.position.z - sp.z).length_squared()
		var p_rad := maxf(he.x, he.z)
		if d_sq > (p_rad + reach * 3.0) * (p_rad + reach * 3.0):
			continue
		nearby_props.append(p)

	var spx := Vector2(sp.x, sp.z)
	var best_w := INF
	var best_dir := Vector2.ZERO
	var best_center := Vector2.ZERO
	var best_dist := INF
	var best_flow_dir := Vector2.ZERO

	for i in nearby_props.size():
		var p1 := nearby_props[i]
		var c1 := Vector2(p1.mesh.position.x, p1.mesh.position.z)
		for j in range(i + 1, nearby_props.size()):
			var p2 := nearby_props[j]
			var c2 := Vector2(p2.mesh.position.x, p2.mesh.position.z)
			var pt1 := _prop_closest_surface_point(p1, c2)
			var pt2 := _prop_closest_surface_point(p2, pt1)
			pt1 = _prop_closest_surface_point(p1, pt2)

			var gap_vec := pt2 - pt1
			var gap_w := gap_vec.length()
			if gap_w < 1e-3 or gap_w >= best_w:
				continue
			var gap_dir := gap_vec / gap_w
			var gap_center := (pt1 + pt2) * 0.5
			var flow_dir := Vector2(-gap_dir.y, gap_dir.x)

			var to_gap := spx - gap_center
			var dist_along_flow := absf(to_gap.dot(flow_dir))
			var dist_lateral := absf(to_gap.dot(gap_dir))

			if dist_along_flow < reach * 2.5 and dist_lateral < (gap_w * 0.5 + reach * 1.5):
				best_w = gap_w
				best_dir = gap_dir
				best_center = gap_center
				best_dist = to_gap.length()
				best_flow_dir = flow_dir

	s.cur_gap_w = best_w
	s.cur_gap_center = best_center
	s.cur_gap_dir = best_dir

	var target := 1.0
	if best_w < INF:
		var fit := clampf((best_w * 0.5 - 0.02 * S) / r_max, effective_min_squeeze, 1.0)
		if fit < 1.0:
			var to_gap_vec := best_center - spx
			var dist_flow := to_gap_vec.x * best_flow_dir.x + to_gap_vec.y * best_flow_dir.y
			var dist_lat := absf(to_gap_vec.x * best_dir.x + to_gap_vec.y * best_dir.y)

			var corridor_half_len := 0.6 * S
			var entrance_flow := dist_flow - corridor_half_len # distance from slime center to entrance
			var exit_flow := dist_flow + corridor_half_len     # distance from slime center to exit

			var max_lat := best_w * 0.5 + reach * 0.8
			if dist_lat < max_lat:
				if entrance_flow > 0.0 and entrance_flow < reach * 1.5:
					# Slime front reaches entrance: squeeze smoothly from 1.0 down to fit
					var t_enter := clampf((reach * 1.5 - entrance_flow) / (reach * 1.2), 0.0, 1.0)
					t_enter = t_enter * t_enter * (3.0 - 2.0 * t_enter)
					var lat_factor := clampf(1.0 - dist_lat / max_lat, 0.0, 1.0)
					target = lerpf(1.0, fit, t_enter * lat_factor)
				elif entrance_flow <= 0.0 and exit_flow > -reach * 1.2:
					# Inside corridor: maintain fit squeeze until back exits
					target = fit
				elif exit_flow <= -reach * 1.2:
					# Fully exited corridor: snap back to round
					target = 1.0

	# Fix 16: Once slime has fully passed through, release squeeze quickly using squeeze_in_rate
	var rate: float
	if target < s.squeeze_k:
		rate = squeeze_in_rate  # squeezing in (tightening)
	else:
		# Releasing — use squeeze_in_rate if the body is clearly past the gap to snap back
		var past_gap := best_w == INF or absf((spx - best_center).dot(best_flow_dir)) > reach * 1.5
		rate = squeeze_in_rate if past_gap else squeeze_out_rate
	s.squeeze_k = clampf(s.squeeze_k + (target - s.squeeze_k) * (1.0 - exp(-rate * dt)), effective_min_squeeze, 1.0)

	if target < 0.98 and best_dir.length_squared() > 0.001:
		var d3 := Vector3(best_dir.x, 0.0, best_dir.y).normalized()
		if d3.dot(s.sq_dir) < 0.0:
			d3 = -d3
		s.sq_dir = s.sq_dir.lerp(d3, 1.0 - exp(-16.0 * dt)).normalized()
		if s.sq_dir.length_squared() < 0.01:
			s.sq_dir = Vector3(1, 0, 0)

		# Smooth funneling force: gently guide slime toward the gap centerline as it moves
		var lateral_offset := (spx - best_center).dot(best_dir)
		var to_gap := Vector3(best_center.x - sp.x, 0.0, best_center.y - sp.z)
		var moving_toward := s.velocity.dot(to_gap) > -0.5 or to_gap.length() < reach * 2.0
		if moving_toward and (spx - best_center).length() < reach * 2.5:
			var dist_to_gap := (spx - best_center).length()
			var dist_factor := clampf(1.0 - dist_to_gap / (reach * 2.2), 0.0, 1.0)
			var align_factor := clampf(1.0 - absf(lateral_offset) / (reach * 1.8), 0.0, 1.0) * maxf(0.35, dist_factor)
			# Guide firmly along gap centerline
			var funnel_push := -Vector3(best_dir.x, 0.0, best_dir.y) * lateral_offset * align_factor * 12.0 * dt
			s.position += funnel_push
			s.velocity -= Vector3(best_dir.x, 0.0, best_dir.y) * lateral_offset * align_factor * 4.0 * dt

	var squeeze_val := 1.0 - s.squeeze_k
	s.set_shader_param("uSqueeze", squeeze_val)
	s.set_shader_param("uSqueezeDir", s.sq_dir)


func is_edible_by_push(s: Slime, p: PropData) -> bool:
	if p.state != STATE_IDLE or p.is_static or p.mesh == null:
		return false
	# Authoritative volume check: Slime can push-eat anything whose real volume is <= Slime's real volume
	return s.get_volume() >= p.real_volume * 0.98


func _process_edible_props(s: Slime, dt: float) -> void:
	var S := s.slime_scale
	var sp := s.position
	var s_vol := s.get_volume()

	for p in props:
		if not is_edible_by_push(s, p):
			# If this prop was being pressed by this slime but is no longer push-edible, decay its engulf_front
			if p.last_presser == s:
				p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.0)
			continue
		var m := p.mesh
		var dx := m.position.x - sp.x
		var dz := m.position.z - sp.z
		var d := maxf(Vector2(dx, dz).length(), 1e-4)

		var he0 := _half_of(p)
		var ca := cos(m.rotation.y)
		var sa := sin(m.rotation.y)
		var ro: float
		if p.shape == SHAPE_BOX:
			ro = absf((dx * ca - dz * sa) / d) * he0.x + absf((dx * sa + dz * ca) / d) * he0.z
		else:
			ro = _poly_support(p, -dx / d, -dz / d) * (0.6 if p.shape == SHAPE_CONE else 1.0)

		var sr_p := _surf_r((m.position.y - sp.y) / S) * S

		var target := maxf(0.0, sr_p + ro - d)
		if target <= 0.001:
			# If this slime was pressing this prop, smoothly decay its press spring & engulf front back out
			if p.last_presser == s:
				p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.5)
				var acc := 140.0 * (0.0 - p.pd) - 8.0 * p.pv
				p.pv += acc * dt
				p.pd += p.pv * dt
				if p.pd <= 0.001 and p.engulf_front <= 0.001:
					p.pd = 0.0
					p.pv = 0.0
					p.engulf_front = 0.0
					p.last_presser = null
					p.hold = 0.0
			continue

		# If another valid slime is already pressing this prop and is closer, don't steal it
		if p.last_presser != null and p.last_presser != s and is_instance_valid(p.last_presser):
			var dist_other := p.mesh.position.distance_to(p.last_presser.position)
			var dist_me := p.mesh.position.distance_to(sp)
			if dist_other < dist_me:
				continue

		p.last_presser = s
		# Compute exact relative volume ratio (prop volume / slime volume)
		var vol_ratio := clampf(p.real_volume / maxf(1e-4, s_vol), 0.0, 1.0)

		var thr := ro * (0.85 + 0.45 * vol_ratio) + 0.1 * S
		var press01 := minf(target / thr, 1.0)
		var acc := 140.0 * (target - p.pd) - 8.0 * p.pv
		p.pv += acc * dt
		p.pd += p.pv * dt
		if p.pd < 0.0:
			p.pd = 0.0
			if p.pv < 0.0:
				p.pv = 0.0
		p.p_ro = ro
		p.p_thr = thr

		# Section 1: Physical Engulf-Front Resistance
		# Instead of a velocity cap that running bypasses, constrain slime's physical position
		# to a moving engulf front that advances only with sustained pushing!
		var nx0 := dx / d
		var nz0 := dz / d
		var inward_speed := s.velocity.x * nx0 + s.velocity.z * nz0

		# Resistance factor: 0.0 for tiny items, ramping up steeply for objects near slime size
		var size_resistance := clampf((vol_ratio - 0.20) / 0.80, 0.0, 1.0)

		# 1. Viscous Speed Drag:
		# Pushing into objects near slime size heavily resists forward movement down to a crawl
		if inward_speed > 0.0:
			var allowed_speed := lerpf(s.cur_max, s.cur_max * 0.15, pow(size_resistance, 1.4))
			if inward_speed > allowed_speed:
				var excess := inward_speed - allowed_speed
				s.velocity.x -= nx0 * excess
				s.velocity.z -= nz0 * excess
				inward_speed = allowed_speed

		# 2. Advance Engulf Front:
		# Tiny props (< 20%): fast gulp (rate ~ 3.5 - 4.5)
		# Medium props (50%): steady strain (rate ~ 1.0)
		# Props near slime size (> 80%): heavy resistance, steep slowdown (rate ~ 0.06 - 0.2)
		if inward_speed > 0.1:
			var size_factor := pow(maxf(0.0, 1.0 - vol_ratio), 1.8)
			var advance_rate := 3.8 * size_factor + 0.06 * (1.0 - size_resistance * 0.85)
			p.engulf_front = minf(1.0, p.engulf_front + advance_rate * dt)
		else:
			# Elastic push back: if player lets go or stops pushing,
			# an object near slime size pushes back forcefully!
			var pushback_rate := 1.2 + 3.0 * size_resistance
			p.engulf_front = maxf(0.0, p.engulf_front - dt * pushback_rate)
			var recoil := 2.5 * size_resistance * (1.0 - p.engulf_front)
			s.velocity.x -= nx0 * recoil * dt
			s.velocity.z -= nz0 * recoil * dt

		# 3. Physical Positional Constraint:
		# Slime body cannot penetrate deeper than allowed by current engulf_front!
		var max_allowed_pen := (sr_p + ro) * p.engulf_front
		var current_pen := target
		if current_pen > max_allowed_pen:
			var over_pen := current_pen - max_allowed_pen
			# Constrain position so slime cannot push through before engulf front opens
			s.position.x -= nx0 * over_pen * 0.95
			s.position.z -= nz0 * over_pen * 0.95
			# Zero out inward penetration velocity against the engulf front wall
			var vin := s.velocity.x * nx0 + s.velocity.z * nz0
			if vin > 0.0:
				s.velocity.x -= nx0 * vin
				s.velocity.z -= nz0 * vin

		# Absorption completes when engulf front has fully enclosed the prop (>= 0.95)
		if p.engulf_front >= 0.95:
			p.state = STATE_EATING
			p.eater = s
			p.last_presser = null
			p.base_scale = m.scale
			eaten += 1
			p.t = 0.0
			p.start = m.position
			p.off = Vector3(_rng.randf() - 0.5, -0.1 + _rng.randf() * 0.3, _rng.randf() - 0.5)
			p.total_mass = p.real_volume
			p.absorbed_mass = 0.0
			eaten_changed.emit(eaten)


# ------------------------------------------------------------------------------------------------
# Multi-contact simultaneous solver & fluid corner flow-around
# ------------------------------------------------------------------------------------------------

class ContactInfo extends RefCounted:
	var prop: PropData
	var normal: Vector3
	var pen: float
	var c_r: float
	var sharp: float


func _solve_solid_collisions(s: Slime, dt: float) -> void:
	var S := s.slime_scale
	# Gather contacts from all solid props:
	# A prop is SOLID if it is NOT edible by push and is not our current ground support!
	var contacts: Array[ContactInfo] = []
	for p in props:
		if p.state != STATE_IDLE or p == s.ground_prop:
			continue
		# If it's edible by push, it's handled by engulf-front resistance, NOT solid collision solver!
		if is_edible_by_push(s, p):
			continue
		var c := _detect_prop_contact(s, p)
		if c != null and c.pen > 0.0:
			contacts.append(c)

	if contacts.is_empty():
		return

	# Sort deepest penetration first
	contacts.sort_custom(func(a: ContactInfo, b: ContactInfo) -> bool: return a.pen > b.pen)

	# Simultaneous iterative resolution (4 passes)
	for _pass in 4:
		if contacts.size() >= 2 and (contacts[0].normal.dot(contacts[1].normal) < -0.2 or contacts[0].prop != contacts[1].prop):
			var c0 := contacts[0]
			var c1 := contacts[1]
			var pen0 := _calc_prop_penetration(s, c0.prop, c0.c_r)
			var pen1 := _calc_prop_penetration(s, c1.prop, c1.c_r)
			# Symmetrically center the slime directly between opposing walls
			var net_push := (c0.normal * pen0 + c1.normal * pen1) * 0.5
			# When between two different props (corridor passage), only push laterally — don't push backward along flow!
			if c0.prop != c1.prop:
				var lat_axis := s.sq_dir if s.sq_dir.length_squared() > 0.01 else (c0.normal - c1.normal).normalized()
				net_push = lat_axis * net_push.dot(lat_axis)
				# Also adapt squeeze immediately upon physical double-wall contact
				if s.cur_gap_w < INF:
					var fit_k := clampf((s.cur_gap_w * 0.5) / maxf(0.1, c0.c_r), 0.08, 1.0)
					s.squeeze_k = minf(s.squeeze_k, lerpf(s.squeeze_k, fit_k, 0.4))
			if net_push.length_squared() > 1e-6:
				s.position.x += net_push.x
				s.position.z += net_push.z
			# Resolve any remaining non-opposing contacts (e.g. end wall)
			for idx in range(2, contacts.size()):
				var c := contacts[idx]
				var pen := _calc_prop_penetration(s, c.prop, c.c_r)
				if pen > 0.001:
					s.position.x += c.normal.x * pen * 0.8
					s.position.z += c.normal.z * pen * 0.8
		else:
			for c in contacts:
				var pen := _calc_prop_penetration(s, c.prop, c.c_r)
				if pen > 0.001:
					var push := c.normal * pen * 0.75
					if s.cur_gap_w < INF and s.sq_dir.length_squared() > 0.01:
						# Never let single-wall lateral push overshoot past the gap centerline
						var lat_axis := Vector3(s.sq_dir.x, 0.0, s.sq_dir.y)
						var lat_push := push.dot(lat_axis)
						var cur_offset := (Vector2(s.position.x, s.position.z) - s.cur_gap_center).dot(Vector2(lat_axis.x, lat_axis.z))
						if (cur_offset > 0.0 and lat_push < 0.0) or (cur_offset < 0.0 and lat_push > 0.0):
							var max_push := absf(cur_offset)
							if absf(lat_push) > max_push:
								push -= lat_axis * (lat_push - signf(lat_push) * max_push)
					s.position += push

	# Primary contact for splat & stick
	var c0 := contacts[0]
	s.impact_dir = Vector3(-c0.normal.x, 0, -c0.normal.z)
	c0.prop.touch = s.time
	c0.prop.touch_slime = s
	c0.prop.cnx = c0.normal.x
	c0.prop.cnz = c0.normal.z
	s.sharp_amt += (c0.sharp - s.sharp_amt) * (1.0 - exp(-15.0 * dt))
	s.contact_r = c0.c_r / S
	s.touch_time = s.time

	# Multi-contact channel / narrow passage flow
	if contacts.size() >= 2:
		var c1 := contacts[1]
		if c0.prop != c1.prop:
			# Between two separate obstacles: treat as a corridor passage regardless of normal angle!
			var corridor_dir: Vector3
			if s.sq_dir.length_squared() > 0.01:
				corridor_dir = Vector3(-s.sq_dir.z, 0.0, s.sq_dir.x).normalized()
			else:
				var n_across := (c0.normal - c1.normal).normalized()
				corridor_dir = Vector3(-n_across.z, 0.0, n_across.x).normalized()

			var input_dir := s.velocity
			if input_dir.length_squared() < 0.01:
				input_dir = s._crawl_dir  # Slime has no .mesh; use _crawl_dir which is always valid
			if corridor_dir.dot(input_dir) < 0.0:
				corridor_dir = -corridor_dir

			var v_corridor := maxf(0.0, s.velocity.dot(corridor_dir))
			# Ensure forward velocity is maintained when pushing through
			if v_corridor < 1.0:
				v_corridor = maxf(v_corridor, s.velocity.length())
			s.velocity = corridor_dir * v_corridor
			return
		else:
			# Two contacts on the same prop: concave corner / crease on a single obstacle
			var dot_n := c0.normal.dot(c1.normal)
			if dot_n < 0.85:
				var sum_n := c0.normal + c1.normal
				if sum_n.length_squared() > 0.01:
					var crease := sum_n.cross(Vector3.UP).normalized()
					if crease.dot(s.velocity) < 0.0:
						crease = -crease
					var v_along_crease := maxf(0.0, s.velocity.dot(crease))
					s.velocity = crease * v_along_crease
					return

	# Single contact handling: fluid sliding with low friction
	var nx := c0.normal.x
	var nz := c0.normal.z
	var v := s.velocity
	var vdot := v.x * nx + v.z * nz

	if vdot < 0.0:
		var vin := -vdot
		# Project velocity onto surface tangent: cancel normal penetration velocity
		v.x -= nx * vdot
		v.z -= nz * vdot

		var vt_len := Vector2(v.x, v.z).length()
		if vt_len > 1e-4:
			var tangent := Vector3(v.x / vt_len, 0.0, v.z / vt_len)
			if s.squeeze_k < 0.95 or c0.sharp > 0.15:
				# Near openings or around corners: zero friction, slight fluid flow deflection around corner
				# Cap flow_boost to 0.15x to prevent runaway speed at triangle/cone vertices
				var flow_boost := vin * minf(0.15, (0.35 if s.squeeze_k < 0.95 else (0.25 * c0.sharp)))
				s.velocity = tangent * (vt_len + flow_boost)
			else:
				# Flat wall impact with viscous drag clinging
				var fr := (1.0 - exp(-6.0 * dt))
				s.velocity = tangent * maxf(0.0, vt_len * (1.0 - fr))
		else:
			# Head-on impact (vt_len <= 1e-4)
			# Deflect along tangent towards the gap opening so slime slides smoothly into the opening
			var tangent := Vector3(-nz, 0.0, nx)
			if s.cur_gap_w < INF:
				var to_gap := Vector3(s.cur_gap_center.x - s.position.x, 0.0, s.cur_gap_center.y - s.position.z)
				if tangent.dot(to_gap) < 0.0:
					tangent = -tangent
				s.velocity = tangent * maxf(vin * 0.8, 2.0)
			else:
				# Use crawl_dir as stable tiebreak — to_prop is always perpendicular and flips each frame
				if tangent.dot(s._crawl_dir) < 0.0:
					tangent = -tangent
				s.velocity = tangent * maxf(vin * 0.2, 0.5)

		# Only trigger impact poke/splat if hitting a flat wall in open space, NOT around corners or when squeezing
		if vin > 0.6 and s.squeeze_k > 0.85 and c0.sharp < 0.2 and s.time - c0.prop.hit_cd > 0.3:
			c0.prop.hit_cd = s.time
			var sev := minf(1.0, pow(vin / 8.5, 0.9))
			s.splat_v += sev * 28.0 * (1.0 + 0.5 * c0.sharp)
			s.trigger_poke(
				Vector3(-nx, -0.15, -nz).normalized() * 1.6,
				Vector3(nx * 1.6 * sev, 0.18 * sev, nz * 1.6 * sev)
			)


func _detect_prop_contact(s: Slime, p: PropData) -> ContactInfo:
	var S := s.slime_scale
	var sp := s.position
	var m := p.mesh
	var dx := m.position.x - sp.x
	var dz := m.position.z - sp.z
	var d := maxf(Vector2(dx, dz).length(), 1e-4)
	var he := _half_of(p)

	if d - Vector2(he.x, he.z).length() > 2.8 * S:
		return null

	var base_y := m.position.y - he.y
	var top_y := m.position.y + he.y
	var y_lo := maxf(base_y, floor_y)
	var slime_bottom := sp.y - s.height_per_scale * S
	var slime_effective_top := slime_bottom + (2.0 * s.height_per_scale * S) * lerpf(1.0, s.liquid_height_ratio, s.liquid_amt)
	var y_hi := minf(top_y, slime_effective_top)
	if y_hi < y_lo:
		return null

	var pen := 0.0
	var nx := 0.0
	var nz := 0.0
	var c_r := 0.0
	var sharp := 0.0
	var n := 5

	# Directional ellipse axes
	var sq_axis := s.sq_dir
	var flow_axis := Vector3(-sq_axis.z, 0, sq_axis.x)

	if p.shape == SHAPE_BOX:
		var r := 0.0
		for k in n:
			var y := y_lo + (y_hi - y_lo) * float(k) / float(n - 1)
			r = maxf(r, _surf_r((y - sp.y) / S) * S + 0.06 * S)

		var c := cos(m.rotation.y)
		var sn := sin(m.rotation.y)
		var wx := -dx
		var wz := -dz
		var lx := wx * c - wz * sn
		var lz := wx * sn + wz * c
		var cx := clampf(lx, -he.x, he.x)
		var cz := clampf(lz, -he.z, he.z)
		var ex := lx - cx
		var ez := lz - cz
		var dd := Vector2(ex, ez).length()

		# Corner sharpness
		var ox := absf(lx) - he.x
		var oz := absf(lz) - he.z
		var t := clampf(minf(ox, oz) / (0.22 * r), 0.0, 1.0)
		sharp = t * t * (3.0 - 2.0 * t)

		# Elliptical radius along contact direction
		var world_ex := ex * c + ez * sn
		var world_ez := -ex * sn + ez * c
		var dir_len := maxf(Vector2(world_ex, world_ez).length(), 1e-4)
		var unx := world_ex / dir_len
		var unz := world_ez / dir_len

		var r_gap := maxf(r * s.squeeze_k, 0.05 * S)
		# Only stretch along flow when aligned and within the gap corridor,
		# never when approaching or hitting outside front faces!
		var gap_corridor_factor := 1.0
		if s.cur_gap_w < INF and sq_axis.length_squared() > 0.01:
			var to_gap := Vector2(sp.x - s.cur_gap_center.x, sp.z - s.cur_gap_center.y)
			var dist_flow := absf(to_gap.x * flow_axis.x + to_gap.y * flow_axis.z)
			gap_corridor_factor = clampf(1.0 - maxf(0.0, dist_flow - he.z) / (0.8 * S), 0.0, 1.0)
		var r_flow := maxf(r * (1.0 + 0.5 * (1.0 - s.squeeze_k) * gap_corridor_factor), 0.05 * S)
		var effective_r := r
		if sq_axis.length_squared() > 0.01:
			var p_gap := absf(unx * sq_axis.x + unz * sq_axis.z)
			var p_flow := absf(unx * flow_axis.x + unz * flow_axis.z)
			var denom := sqrt((p_gap * r_flow) * (p_gap * r_flow) + (p_flow * r_gap) * (p_flow * r_gap))
			if denom > 1e-4:
				effective_r = (r_gap * r_flow) / denom
		effective_r = clampf(effective_r, minf(r_gap, r_flow), maxf(r_gap, r_flow))
		c_r = effective_r

		if dd < effective_r:
			if dd > 1e-4:
				ex /= dd
				ez /= dd
				pen = effective_r - dd
			else:
				# Deep inside box: safely push opposing velocity
				var px := he.x - absf(lx)
				var pz := he.z - absf(lz)
				if px < pz:
					ex = 1.0 if lx >= 0.0 else -1.0
					ez = 0.0
					pen = px + r_gap
				else:
					ex = 0.0
					ez = 1.0 if lz >= 0.0 else -1.0
					pen = pz + r_flow
			nx = ex * c + ez * sn
			nz = -ex * sn + ez * c

			# When squeezing, side walls and corners must not push backward along the corridor flow
			if s.squeeze_k < 0.90:
				var flow_proj := Vector3(nx, 0.0, nz).dot(flow_axis)
				if flow_proj < 0.0:
					var lateral_comp := Vector3(nx, 0.0, nz) - flow_axis * flow_proj
					if lateral_comp.length_squared() > 1e-4:
						var lat_norm := lateral_comp.normalized()
						nx = lat_norm.x
						nz = lat_norm.z
	else:
		var ux := -dx / d
		var uz := -dz / d
		var sup := _poly_support(p, ux, uz)

		if p.sides >= 3 and p.sides < 12:
			var rc := p.base_r * m.scale.x
			var ap := rc * cos(PI / p.sides)
			var t := clampf((sup - ap) / (rc - ap), 0.0, 1.0)
			sharp = t * t * (3.0 - 2.0 * t)

		var h := 2.0 * he.y
		for k in n:
			var y := y_lo + (y_hi - y_lo) * float(k) / float(n - 1)
			var rs := _surf_r((y - sp.y) / S) * S + 0.06 * S
			var r_gap := maxf(rs * s.squeeze_k, 0.05 * S)
			var r_flow := maxf(rs * (1.0 + 0.5 * (1.0 - s.squeeze_k)), 0.05 * S)
			var eff_rs := rs
			if sq_axis.length_squared() > 0.01:
				var p_gap := absf(ux * sq_axis.x + uz * sq_axis.z)
				var p_flow := absf(ux * flow_axis.x + uz * flow_axis.z)
				var denom := sqrt((p_gap * r_flow) * (p_gap * r_flow) + (p_flow * r_gap) * (p_flow * r_gap))
				if denom > 1e-4:
					eff_rs = (r_gap * r_flow) / denom
			eff_rs = clampf(eff_rs, minf(r_gap, r_flow), maxf(r_gap, r_flow))
			var reach := sup * (maxf(0.06, 1.0 - (y - base_y) / h) if p.shape == SHAPE_CONE else 1.0)
			if eff_rs + reach - d > pen:
				pen = eff_rs + reach - d
				c_r = eff_rs
		if p.sides >= 3 and p.sides < 12:
			var ca := cos(m.rotation.y)
			var sa := sin(m.rotation.y)
			var lx := ux * ca - uz * sa
			var lz := ux * sa + uz * ca
			var sector := TAU / p.sides
			var phi := atan2(lx, lz) - p.phase
			var d_sec := fmod(phi, sector)
			if d_sec < 0.0:
				d_sec += sector
			var face_local_ang := atan2(lx, lz) - d_sec + sector * 0.5
			var fn_lx := sin(face_local_ang)
			var fn_lz := cos(face_local_ang)
			var fn_wx := fn_lx * ca + fn_lz * sa
			var fn_wz := -fn_lx * sa + fn_lz * ca
			# Blend between flat face normal and vertex radial normal based on sharpness
			var blend_to_radial := smoothstep(0.4, 0.9, sharp)
			nx = lerpf(fn_wx, ux, blend_to_radial)
			nz = lerpf(fn_wz, uz, blend_to_radial)
			var nlen := maxf(Vector2(nx, nz).length(), 1e-4)
			nx /= nlen
			nz /= nlen
		else:
			nx = ux
			nz = uz

		if s.squeeze_k < 0.90:
			var flow_proj := Vector3(nx, 0.0, nz).dot(flow_axis)
			if flow_proj < 0.0:
				var lateral_comp := Vector3(nx, 0.0, nz) - flow_axis * flow_proj
				if lateral_comp.length_squared() > 1e-4:
					var lat_norm := lateral_comp.normalized()
					nx = lat_norm.x
					nz = lat_norm.z

	if pen <= 0.0:
		return null

	var ci := ContactInfo.new()
	ci.prop = p
	ci.normal = Vector3(nx, 0, nz).normalized()
	ci.pen = pen
	ci.c_r = c_r
	ci.sharp = sharp
	return ci


func _calc_prop_penetration(s: Slime, p: PropData, c_r: float) -> float:
	var sp := s.position
	var S := s.slime_scale
	var m := p.mesh
	var dx := m.position.x - sp.x
	var dz := m.position.z - sp.z
	var he := _half_of(p)

	if p.shape == SHAPE_BOX:
		var c := cos(m.rotation.y)
		var sn := sin(m.rotation.y)
		var lx := -dx * c + dz * sn
		var lz := -dx * sn - dz * c
		var cx := clampf(lx, -he.x, he.x)
		var cz := clampf(lz, -he.z, he.z)
		var dd := Vector2(lx - cx, lz - cz).length()
		return maxf(0.0, c_r - dd)
	else:
		var d := maxf(Vector2(dx, dz).length(), 1e-4)
		var ux := -dx / d
		var uz := -dz / d
		var base_y := m.position.y - he.y
		var top_y := m.position.y + he.y
		var h := 2.0 * he.y
		var slime_bottom := sp.y - s.height_per_scale * S
		var slime_effective_top := slime_bottom + (2.0 * s.height_per_scale * S) * lerpf(1.0, s.liquid_height_ratio, s.liquid_amt)
		var y_lo := maxf(base_y, floor_y)
		var y_hi := minf(top_y, slime_effective_top)
		# For cones: use the same per-height tapered reach as detection, to avoid stutter
		if p.shape == SHAPE_CONE and h > 1e-4:
			var best_pen := 0.0
			var n := 5
			for k in n:
				var y := y_lo + (y_hi - y_lo) * float(k) / float(n - 1)
				var sup_full := _poly_support(p, ux, uz)
				var reach := sup_full * maxf(0.06, 1.0 - (y - base_y) / h)
				var rs := _surf_r((y - sp.y) / S) * S + 0.06 * S
				var pen_at_y := rs + reach - d
				if pen_at_y > best_pen:
					best_pen = pen_at_y
			return maxf(0.0, best_pen)
		else:
			var sup := _poly_support(p, ux, uz)
			return maxf(0.0, c_r + sup - d)

func _update_slime_splat(s: Slime, dt: float) -> void:
	var since := s.time - s.touch_time
	# Sustained push into a wall keeps the slime flattened
	var is_pushing := s.velocity.length_squared() > 0.1
	var tgt := 0.20 if since < 0.15 else (0.12 if (since < 0.4 and is_pushing) else 0.0)

	var ks := 120.0 if s.splat_v > 0.0 else 40.0
	s.splat_v += (ks * (tgt - s.splat_x) - 2.0 * sqrt(ks) * s.splat_v) * dt
	s.splat_x = clampf(s.splat_x + s.splat_v * dt, 0.0, 1.1)
	if s.splat_x == 0.0 and s.splat_v < 0.0:
		s.splat_v = 0.0

	var kp := 70.0 if s.splat_x > s.spread_x else 22.0
	s.spread_v += (kp * (s.splat_x - s.spread_x) - 2.0 * sqrt(kp) * s.spread_v) * dt
	s.spread_x = maxf(0.0, s.spread_x + s.spread_v * dt)
	if s.spread_x == 0.0 and s.spread_v < 0.0:
		s.spread_v = 0.0

	s.set_shader_param("uSplat", s.splat_x * (1.0 - 0.7 * s.sharp_amt))
	s.set_shader_param("uSpread", s.spread_x * (1.0 - 0.5 * s.sharp_amt))
	s.set_shader_param("uWall", s.contact_r)
	s.set_shader_param("uSplatDir", s.impact_dir)


func _update_digesting_props(dt: float) -> void:
	for p in props:
		if p.state == STATE_EATING:
			p.t += dt
			# Smoothly decay press spring so the contact dent fades during absorption
			p.pd = maxf(0.0, p.pd * exp(-10.0 * dt))
			p.pv = maxf(0.0, p.pv * exp(-10.0 * dt))
			var k := minf(p.t / EAT_TIME, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var dis := maxf(0.0, 1.0 - maxf(0.0, p.t - EAT_TIME) / EAT_LINGER)
			var shrink := maxf(0.001, (1.0 - 0.35 * e) * (0.65 + 0.35 * dis))
			p.mesh.scale = p.base_scale * shrink
			if p.material != null:
				p.material.set_shader_parameter("uDissolve", 1.0 - dis)
			p.mesh.rotation.y += dt * 0.4

			# Smoothly transfer digested mass into slime size progression
			var s: Slime = p.eater if p.eater != null and is_instance_valid(p.eater) else player_slime
			if s != null and is_instance_valid(s):
				var total_digest_time: float = EAT_TIME + EAT_LINGER
				var progress := clampf(p.t / total_digest_time, 0.0, 1.0)
				var e_mass := progress * progress * (3.0 - 2.0 * progress)
				var target_absorbed: float = p.total_mass * e_mass
				var delta_m: float = target_absorbed - p.absorbed_mass
				if delta_m > 0.0:
					p.absorbed_mass = target_absorbed
					# Authoritative volume transfer: add prop volume directly into slime target scale
					# Volume = (4/3)*PI*(body_radius*target_scale)^3
					# target_scale_new = (target_scale^3 + delta_m / ((4/3)*PI*body_radius^3))^(1/3)
					var vol_factor := (4.0 / 3.0) * PI * pow(s.body_radius, 3.0)
					s.target_scale = pow(pow(s.target_scale, 3.0) + (delta_m / vol_factor), 1.0 / 3.0)

				var S: float = s.slime_scale
				if p.t < EAT_TIME:
					var target_in_belly: Vector3 = s.position + p.off * (S * 0.70)
					p.mesh.position = p.start.lerp(target_in_belly, e)
					p.vel = Vector3.ZERO
				else:
					if not s.inside_props.has(p):
						s.inside_props.append(p)

			if dis <= 0.0:
				if p.eater != null and is_instance_valid(p.eater):
					p.eater.inside_props.erase(p)
				elif player_slime != null:
					player_slime.inside_props.erase(p)
				p.mesh.queue_free()
				p.state = STATE_GONE


func _update_inside_props(s: Slime, dt: float) -> void:
	# Inside props physics for this slime
	var S := s.slime_scale
	var sp := s.position
	for item in s.inside_props:
		var p: PropData = item as PropData
		if p == null or p.mesh == null:
			continue
		p.vel.y -= 7.0 * dt
		p.vel *= exp(-2.0 * dt)
		p.mesh.position += p.vel * dt

		var m: MeshInstance3D = p.mesh
		var he: Vector3 = _half_of(p)
		var rr: float = maxf(maxf(he.x, he.y), he.z) * 0.8
		var rh: float = maxf(0.15, 1.6 * S - rr)
		var rv: float = maxf(0.15, 1.15 * S - rr)
		var l: Vector3 = m.position - sp
		var qx: float = l.x / rh
		var qy: float = l.y / rv
		var qz: float = l.z / rh
		var ql: float = sqrt(qx * qx + qy * qy + qz * qz)
		if ql > 1.0:
			m.position = sp + l / ql
			var n: Vector3 = Vector3(qx / rh, qy / rv, qz / rh).normalized()
			var vn: float = p.vel.dot(n)
			if vn > 0.0:
				p.vel -= n * vn * 1.4

		if m.position.y < floor_y + he.y:
			m.position.y = floor_y + he.y
			if p.vel.y < 0.0:
				p.vel.y *= -0.2


func _update_eat_uniforms(s: Slime) -> void:
	var S := s.slime_scale
	var sp := s.position
	var eat_pos := PackedVector3Array()
	var eat_param := PackedVector3Array()
	var box_half := PackedVector3Array()
	for i in 6:
		eat_pos.append(Vector3.ZERO)
		eat_param.append(Vector3.ZERO)
		box_half.append(Vector3(0.01, 0.01, 0.01))

	var pressing: Array[PropData] = []
	for p in props:
		# Fix: Only IDLE props occupy pressing slots (0-2). Once EATING, props occupy eating slots (3-5) exclusively,
		# preventing double-dent deformation in the shader during the first 0.8s.
		if p.state == STATE_IDLE and p.pd > 0.004 and p.p_ro > 0.0 and p.last_presser == s:
			var dist := Vector2(p.mesh.position.x - sp.x, p.mesh.position.z - sp.z).length()
			if dist <= 2.2 * S + p.p_ro:
				pressing.append(p)
	pressing.sort_custom(func(a: PropData, b: PropData) -> bool: return a.pd > b.pd)
	if pressing.size() > 3:
		pressing.resize(3)

	var pa := 0.0
	var press_dir := Vector3(0, 0, 1)
	for i in pressing.size():
		var p := pressing[i]
		var m := p.mesh.position
		var dx := m.x - sp.x
		var dz := m.z - sp.z
		var d := maxf(Vector2(dx, dz).length(), 1e-4)
		var yl := (m.y - sp.y) / S
		var dv := (_surf_r(yl) * S + p.p_ro - p.pd) / S
		eat_pos[i] = Vector3(dx / d * dv, yl, dz / d * dv)
		eat_param[i] = Vector3(float(p.shape) + p.sides * 0.01, 1.0, p.mesh.rotation.y + p.phase)
		box_half[i] = _box_half(p, S)
		var a := minf(1.0, p.pd / p.p_thr)
		var vr := clampf(p.real_volume / maxf(1e-4, s.get_volume()), 0.0, 1.0)
		var strain_boost := 1.0 + 0.45 * clampf((vr - 0.25) / 0.75, 0.0, 1.0)
		a = minf(1.0, a * strain_boost)
		if a > pa:
			pa = a
			press_dir = Vector3(dx / d, 0, dz / d)

	s.press_amt += (pa - s.press_amt) * 0.25
	s.set_shader_param("uPressAmt", s.press_amt)
	s.set_shader_param("uPressDir", press_dir)

	var near := 0.0
	for p in props:
		# Only count props that are actively being pressed by this slime (p_ro is stale otherwise)
		if p.state != STATE_IDLE or p.p_ro <= 0.0 or p.last_presser != s:
			continue
		var gap := Vector2(p.mesh.position.x - sp.x, p.mesh.position.z - sp.z).length() - (1.9 * S + p.p_ro)
		near = maxf(near, minf(1.0, maxf(0.0, 1.0 - gap / (1.5 * S + p.p_ro))))
	s.calm += (maxf(near, s.press_amt) - s.calm) * 0.2

	var slot := 3
	for p in props:
		if p.state != STATE_EATING or p.eater != s or slot > 5:
			continue
		var m := p.mesh.position
		eat_pos[slot] = Vector3((m.x - sp.x) / S, (m.y - sp.y) / S, (m.z - sp.z) / S)
		var eat_fade := clampf(p.t / 0.4, 0.0, 1.0)
		eat_param[slot] = Vector3(float(p.shape) + p.sides * 0.01, eat_fade, p.mesh.rotation.y + p.phase)
		box_half[slot] = _box_half(p, S)
		slot += 1

	s.set_shader_param("uEatPos", eat_pos)
	s.set_shader_param("uEatParam", eat_param)
	s.set_shader_param("uBoxHalf", box_half)


func _update_solid_uniforms(s: Slime) -> void:
	var S := s.slime_scale
	var sp := s.position
	var solid_pos := PackedVector3Array()
	var solid_param := PackedVector3Array()
	var solid_half := PackedVector3Array()
	var solid_dir := PackedVector3Array()
	for i in 2:
		solid_pos.append(Vector3.ZERO)
		solid_param.append(Vector3.ZERO)
		solid_half.append(Vector3(0.01, 0.01, 0.01))
		solid_dir.append(Vector3.ZERO)

	var active: Array[PropData] = []
	for p in props:
		if p.state == STATE_IDLE and p.touch_slime == s and s.time - p.touch < 1.2:
			var he := _half_of(p)
			var dist := Vector2(p.mesh.position.x - sp.x, p.mesh.position.z - sp.z).length()
			if dist <= 2.4 * S + Vector2(he.x, he.z).length():
				active.append(p)
	active.sort_custom(func(a: PropData, b: PropData) -> bool: return a.touch > b.touch)
	if active.size() > 2:
		active.resize(2)

	var depth := minf(1.2, maxf(s.splat_x, s.spread_x * 0.5) * (0.5 + 0.7 * s.sharp_amt))
	for i in active.size():
		var p := active[i]
		var m := p.mesh.position
		solid_pos[i] = Vector3((m.x - sp.x) / S + p.cnx * depth, (m.y - sp.y) / S, (m.z - sp.z) / S + p.cnz * depth)
		solid_dir[i] = Vector3(-p.cnx, 0, -p.cnz)
		var fade := 1.0 - minf(1.0, maxf(0.0, (s.time - p.touch - 0.8) / 0.4))
		solid_param[i] = Vector3(float(p.shape) + p.sides * 0.01, fade, p.mesh.rotation.y + p.phase)
		solid_half[i] = _box_half(p, S)

	s.set_shader_param("uSolidPos", solid_pos)
	s.set_shader_param("uSolidParam", solid_param)
	s.set_shader_param("uSolidHalf", solid_half)
	s.set_shader_param("uSolidDir", solid_dir)


func _update_floor_shadows() -> void:
	if _floor_mat == null:
		return
	var b_pos := PackedVector3Array()
	var b_scale := PackedFloat32Array()

	for s in registered_slimes:
		if b_pos.size() >= 8:
			break
		if not is_instance_valid(s):
			continue
		var s_scale := s.slime_scale * lerpf(1.0, 1.85, s.liquid_amt)
		b_pos.append(s.global_position)
		b_scale.append(s_scale)



	var count := b_pos.size()
	while b_pos.size() < 8:
		b_pos.append(Vector3.ZERO)
		b_scale.append(0.0)

	_floor_mat.set_shader_parameter("uBlobCount", count)
	_floor_mat.set_shader_parameter("uBlobPos", b_pos)
	_floor_mat.set_shader_parameter("uBlobScale", b_scale)


# ------------------------------------------------------------------------------------------------
# Shape helpers
# ------------------------------------------------------------------------------------------------

func _surf_r(yl: float) -> float:
	var melt := 0.28
	var k := 0.86 - melt * 0.22
	var g_floor := -1.6 * k
	var lo := g_floor
	var hi := 1.6 * k
	for _i in 18:
		var mid := (lo + hi) * 0.5
		var b := mid - g_floor
		var f := mid
		if b < 0.9:
			var t := clampf(b / 0.9, 0.0, 1.0)
			f = g_floor + 0.9 * (2.0 * t * t - t * t * t)
		if f < yl:
			lo = mid
		else:
			hi = mid

	var py := clampf(lo / k, -1.6, 1.6)
	var h := (py / 1.6 + 1.0) * 0.5
	var sm := smoothstep(0.0, 0.22, h)
	var spread := 1.0 + (pow(1.0 - h, 1.35) * sm * 0.34 + sin(h * PI) * 0.08) * (0.8 + melt * 1.1)
	return maxf(0.3, sqrt(maxf(0.0, 2.56 - py * py)) * spread)


func _half_of(p: PropData) -> Vector3:
	return p.half * p.mesh.scale.x


func _poly_support(p: PropData, ux: float, uz: float) -> float:
	var r := p.base_r * p.mesh.scale.x
	if p.sides < 3 or p.sides >= 12:
		return r
	var ca := cos(p.mesh.rotation.y)
	var sa := sin(p.mesh.rotation.y)
	var lx := ux * ca - uz * sa
	var lz := ux * sa + uz * ca
	var sector := TAU / p.sides
	var d := fmod(atan2(lx, lz) - p.phase, sector)
	if d < 0.0:
		d += sector
	var from_face := absf(d - sector * 0.5)
	return r * cos(sector * 0.5) / cos(from_face)


func _box_half(p: PropData, S: float) -> Vector3:
	var he := _half_of(p)
	if p.shape == SHAPE_BOX:
		return he / S
	var r := p.base_r * p.mesh.scale.x
	return Vector3(r, he.y, r) / S


func total() -> int:
	return props.size()
