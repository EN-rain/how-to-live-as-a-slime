class_name SlimeProps
extends Node3D
## Prop ecosystem: geometry, edibility, digestion and visual contact feedback.
##
## Every prop owns a real queryable collider on LAYER_OBSTACLES. This node never
## moves a slime directly: positional constraints are routed through the slime's
## motor (the single movement owner), and passage data is exposed only as a hint
## that the slime validates against real queries before changing posture.

signal eaten_changed(total: int)

const SHAPE_BOX := 0
const SHAPE_PRISM := 1
const SHAPE_CONE := 2

const STATE_IDLE := 0
const STATE_EATING := 1
const STATE_GONE := 2

const LAYER_OBSTACLES := 1

@export var slime: Slime
@export var floor_mesh: MeshInstance3D
@export var prop_shader: Shader
@export var prop_count := 36
@export var spawn_seed := 0
@export var tuning: SlimeTuning

var props: Array[PropData] = []
var registered_slimes: Array[Slime] = []
var player_slime: Slime = null
var eaten := 0

var _rng := RandomNumberGenerator.new()
var _prop_root: Node3D
var _floor_mat: ShaderMaterial
var _floor_body: StaticBody3D
var _tick_frame := -1
var _ticked_this_frame: Array[Slime] = []


class PropData extends RefCounted:
	var mesh: MeshInstance3D
	var material: ShaderMaterial
	var body: StaticBody3D
	var collider: CollisionShape3D
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
	var engulf_front := 0.0

	func _poly_area(r: float) -> float:
		if sides >= 3 and sides < 12:
			return 0.5 * float(sides) * r * r * sin(TAU / float(sides))
		return PI * r * r

	func calc_real_volume() -> float:
		var sx := mesh.scale.x if mesh else radius
		var sy := mesh.scale.y if mesh else radius
		var sz := mesh.scale.z if mesh else radius
		match shape:
			SHAPE_BOX:
				real_volume = (2.0 * half.x * sx) * (2.0 * half.y * sy) * (2.0 * half.z * sz)
			SHAPE_PRISM:
				real_volume = _poly_area(base_r) * sx * sz * (2.0 * half.y * sy)
			SHAPE_CONE:
				real_volume = _poly_area(base_r) * sx * sz * (2.0 * half.y * sy) / 3.0
			_:
				real_volume = (4.0 / 3.0) * PI * pow(radius, 3.0)
		total_mass = real_volume
		return real_volume


func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/slime_tuning.tres") as SlimeTuning
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

	_add_floor_collider()
	# Test structures first so random props never block the gate or bridge.
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
	_ticked_this_frame.erase(s)
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


## Called by every slime at the end of its physics tick. The ecosystem steps
## exactly once per physics frame, after ALL registered slimes have moved, so
## constraints always apply to resolved positions (never before movement).
func slime_ticked(s: Slime, dt: float) -> void:
	var frame := Engine.get_physics_frames()
	if frame != _tick_frame:
		_tick_frame = frame
		_ticked_this_frame.clear()
	if not _ticked_this_frame.has(s):
		_ticked_this_frame.append(s)
	for r in registered_slimes:
		if is_instance_valid(r) and not _ticked_this_frame.has(r):
			return
	step(dt)


func step(dt: float) -> void:
	for s in registered_slimes:
		if not is_instance_valid(s):
			continue
		if not s.is_merging:
			# Read the motor's contacts before push-eating issues its own
			# move_horizontal calls, which would clear that feedback.
			_register_motor_contacts(s, dt)
			_process_edible_props(s, dt)
		_update_inside_props(s, dt)
		_update_slime_splat(s, dt)
		_update_eat_uniforms(s)
		_update_solid_uniforms(s)

	_separate_slimes()

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


## Symmetric residual separation for overlapping slimes. Every delta is computed from
## a pre-pass snapshot and applied through each motor's swept move, so the result is
## order independent. The proxies already stop movement intent; this resolves the
## overlap a legal posture change or a spawn may leave behind.
func _separate_slimes() -> void:
	var bodies: Array = []
	for s in registered_slimes:
		if not is_instance_valid(s) or s.is_merging or s.model == null:
			continue
		var foot := s.global_position + Vector3(0.0, -s.model.rest_half_height * s.model.scale, 0.0)
		bodies.append({
			"slime": s,
			"xz": Vector2(s.global_position.x, s.global_position.z),
			"bottom": foot.y,
			"top": foot.y + s.model.full_height,
			"mass": s.get_volume() * (2.0 if s.role == Slime.Role.PLAYER else 1.0),
		})
	if bodies.size() < 2:
		return
	var pushes: Array[Vector2] = []
	pushes.resize(bodies.size())
	pushes.fill(Vector2.ZERO)
	for i in bodies.size():
		var a: Dictionary = bodies[i]
		for j in range(i + 1, bodies.size()):
			var b: Dictionary = bodies[j]
			if _pair_exempt(a["slime"], b["slime"]):
				continue
			if a["top"] <= b["bottom"] + tuning.skin or b["top"] <= a["bottom"] + tuning.skin:
				continue
			var d: Vector2 = b["xz"] - a["xz"]
			var dist := d.length()
			var dir := d / dist if dist > 1e-5 else Vector2.RIGHT
			var ra: float = a["slime"].model.horizontal_support(Vector3(dir.x, 0.0, dir.y))
			var rb: float = b["slime"].model.horizontal_support(Vector3(-dir.x, 0.0, -dir.y))
			var pen := ra + rb - tuning.skin - dist
			if pen <= 0.0:
				continue
			var ma: float = a["mass"]
			var mb: float = b["mass"]
			var total := ma + mb
			if total <= 1e-6:
				continue
			pushes[i] -= dir * (pen * mb / total)
			pushes[j] += dir * (pen * ma / total)
	for i in bodies.size():
		var s: Slime = bodies[i]["slime"]
		var push: Vector2 = pushes[i]
		if not is_instance_valid(s) or push.length_squared() < 1e-8:
			continue
		# One tick may only spend part of the motor's step budget: intent motion
		# already used some, and a deep overlap must resolve over several ticks
		# instead of teleporting either body.
		var cap := s.model.rest_max_radius * s.model.scale * tuning.max_step_fraction * 0.5
		if push.length() > cap:
			push *= cap / push.length()
		s.motor.move_horizontal(Vector3(push.x, 0.0, push.y))
		s._sync_proxy()


func _pair_exempt(a: Slime, b: Slime) -> bool:
	if a.is_merging or b.is_merging:
		return true
	if a.is_budding and a.bud_parent == b and not a._bud_snapped:
		return true
	if b.is_budding and b.bud_parent == a and not b._bud_snapped:
		return true
	return false


# ------------------------------------------------------------------------------------------------
# Colliders
# ------------------------------------------------------------------------------------------------

func _add_floor_collider() -> void:
	_floor_body = StaticBody3D.new()
	_floor_body.name = "FloorCollider"
	_floor_body.collision_layer = LAYER_OBSTACLES
	_floor_body.collision_mask = 0
	_floor_body.position = Vector3(0.0, tuning.floor_y - 0.5, 0.0)
	add_child(_floor_body)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	cs.shape = box
	_floor_body.add_child(cs)


func _make_collider_shape(p: PropData) -> Shape3D:
	match p.shape:
		SHAPE_BOX:
			var box := BoxShape3D.new()
			box.size = p.half * 2.0
			return box
		SHAPE_PRISM:
			if p.sides >= 3 and p.sides < 12:
				var pts := PackedVector3Array()
				for i in p.sides:
					var a := TAU * float(i) / float(p.sides)
					pts.append(Vector3(sin(a) * p.base_r, -p.half.y, cos(a) * p.base_r))
					pts.append(Vector3(sin(a) * p.base_r, p.half.y, cos(a) * p.base_r))
				var convex := ConvexPolygonShape3D.new()
				convex.set_points(pts)
				return convex
			var cyl := CylinderShape3D.new()
			cyl.radius = p.base_r
			cyl.height = p.half.y * 2.0
			return cyl
		SHAPE_CONE:
			var n := maxi(p.sides, 12)
			var pts := PackedVector3Array()
			for i in n:
				var a := TAU * float(i) / float(n)
				pts.append(Vector3(sin(a) * p.base_r, -p.half.y, cos(a) * p.base_r))
			pts.append(Vector3(0.0, p.half.y, 0.0))
			var convex := ConvexPolygonShape3D.new()
			convex.set_points(pts)
			return convex
	var sphere := SphereShape3D.new()
	sphere.radius = p.radius
	return sphere


func _attach_collider(p: PropData) -> void:
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = LAYER_OBSTACLES if p.state == STATE_IDLE else 0
	body.collision_mask = 0
	p.mesh.add_child(body)
	var cs := CollisionShape3D.new()
	cs.shape = _make_collider_shape(p)
	body.add_child(cs)
	p.body = body
	p.collider = cs


func _set_prop_solid(p: PropData, solid: bool) -> void:
	if p.body != null:
		p.body.collision_layer = LAYER_OBSTACLES if solid else 0


## Obstacle RIDs this slime may pass through. Policy: an idle prop is solid to every
## query until THIS slime has opened an engulf front on it; a prop already dissolving
## in this slime is past the front. Support and ceilings use the same list, so the
## horizontal and vertical policies can no longer disagree.
func rids_edible_by(s: Slime) -> Array[RID]:
	var rids: Array[RID] = []
	for p in props:
		if p.body == null:
			continue
		if p.state == STATE_EATING and p.eater == s:
			rids.append(p.body.get_rid())
		elif p.state == STATE_IDLE and p.last_presser == s and p.engulf_front > 0.05:
			rids.append(p.body.get_rid())
	return rids


func _prop_of_body(body: Object) -> PropData:
	for p in props:
		if p.body == body:
			return p
	return null


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
			position = Vector3(x, tuning.floor_y + half.y * radius, z)
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
		_attach_collider(p)
		props.append(p)


func _spawn_test_structures() -> void:
	var pillar_mat := ShaderMaterial.new()
	pillar_mat.shader = prop_shader
	pillar_mat.set_shader_parameter("uColor", Color(0.32, 0.72, 0.88))
	pillar_mat.set_shader_parameter("uDissolve", 0.0)

	# 1. Narrow Slit Gate: Two vertical pillars with a 1.4m gap at (8, 0, 8)
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
		mi.position = gate_pos + Vector3(side * 1.3, tuning.floor_y + 1.6, 0.0)
		_prop_root.add_child(mi)
		p.mesh = mi
		p.is_static = true
		p.base_scale = mi.scale
		p.calc_real_volume()
		_attach_collider(p)
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
	roof_mi.position = bridge_pos + Vector3(0.0, tuning.floor_y + 0.75 + 0.3, 0.0)
	_prop_root.add_child(roof_mi)
	roof_prop.mesh = roof_mi
	roof_prop.base_scale = roof_mi.scale
	roof_prop.calc_real_volume()
	_attach_collider(roof_prop)
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
		leg_mi.position = bridge_pos + Vector3(leg_side * 1.35, tuning.floor_y + 0.375, 0.0)
		_prop_root.add_child(leg_mi)
		leg_p.mesh = leg_mi
		leg_p.base_scale = leg_mi.scale
		leg_p.calc_real_volume()
		_attach_collider(leg_p)
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
		return p + (q - p) * (2.0 - t) * 6.0
	return p


# ------------------------------------------------------------------------------------------------
# Edibility & push-eating
# ------------------------------------------------------------------------------------------------

func is_edible_by_push(s: Slime, p: PropData) -> bool:
	if p.state != STATE_IDLE or p.is_static or p.mesh == null:
		return false
	return s.get_volume() >= p.real_volume * tuning.edible_volume_ratio


func devour(p: PropData, s: Slime) -> void:
	if p.state == STATE_IDLE:
		_begin_eating(p, s)


func _begin_eating(p: PropData, s: Slime) -> void:
	p.state = STATE_EATING
	p.eater = s
	p.last_presser = null
	p.base_scale = p.mesh.scale
	p.t = 0.0
	p.start = p.mesh.position
	p.off = Vector3(_rng.randf() - 0.5, -0.1 + _rng.randf() * 0.3, _rng.randf() - 0.5)
	p.total_mass = p.real_volume
	p.absorbed_mass = 0.0
	_set_prop_solid(p, false)
	eaten += 1
	eaten_changed.emit(eaten)


func _process_edible_props(s: Slime, dt: float) -> void:
	var S := s.model.scale
	var sp := s.global_position
	var foot := s.model.foot
	var s_vol := s.get_volume()

	for p in props:
		if not is_edible_by_push(s, p):
			if p.last_presser == s:
				p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.0)
			continue
		var m := p.mesh
		var he := _half_of(p)
		var prop_top := m.global_position.y + he.y
		var prop_bottom := m.global_position.y - he.y
		# Geometry below the foot is support, not a press target; geometry above
		# the body cannot be pressed either.
		if prop_top <= foot.y + 0.05 * S or prop_bottom >= foot.y + s.model.full_height:
			if p.last_presser == s:
				p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.5)
			continue
		var dx := m.global_position.x - sp.x
		var dz := m.global_position.z - sp.z
		var d := maxf(Vector2(dx, dz).length(), 1e-4)
		var dir := Vector3(dx / d, 0.0, dz / d)
		var ro := _horizontal_reach(p, -dir, foot.y)
		var sr_p := s.model.world_radius_at(m.global_position.y, dir)
		var gap := d - (sr_p + ro)
		var target := maxf(0.0, -gap)
		var inward_speed := s.motor.velocity.x * dir.x + s.motor.velocity.z * dir.z

		# The prop is solid to the sweep until the front opens, so a live press sits at
		# the face with roughly a skin of clearance rather than overlapping. Contact plus
		# inward intent is the press signal; the front is the gate that makes it passable.
		var in_contact := gap <= 0.08
		var pressing := in_contact and (inward_speed > 0.05 or target > 0.001)
		if not pressing:
			if p.last_presser == s:
				p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.5)
				var acc_r := 140.0 * (0.0 - p.pd) - 8.0 * p.pv
				p.pv += acc_r * dt
				p.pd += p.pv * dt
				if p.pd <= 0.001 and p.engulf_front <= 0.001:
					p.pd = 0.0
					p.pv = 0.0
					p.engulf_front = 0.0
					p.last_presser = null
					p.hold = 0.0
			continue

		if p.last_presser != null and p.last_presser != s and is_instance_valid(p.last_presser):
			var dist_other := p.mesh.global_position.distance_to(p.last_presser.global_position)
			var dist_me := p.mesh.global_position.distance_to(sp)
			if dist_other < dist_me:
				continue

		p.last_presser = s
		var vol_ratio := clampf(p.real_volume / maxf(1e-4, s_vol), 0.0, 1.0)
		var thr := ro * (0.85 + 0.45 * vol_ratio) + 0.1 * S
		# Visual press depth ramps across the contact window instead of requiring
		# penetration the solid sweep will never allow.
		var press_depth := maxf(target, 0.08 - gap)
		var acc := 140.0 * (press_depth - p.pd) - 8.0 * p.pv
		p.pv += acc * dt
		p.pd += p.pv * dt
		if p.pd < 0.0:
			p.pd = 0.0
			if p.pv < 0.0:
				p.pv = 0.0
		p.p_ro = ro
		p.p_thr = thr

		var size_resistance := clampf((vol_ratio - 0.20) / 0.80, 0.0, 1.0)

		# Viscous drag: pushing near-size objects resists forward speed.
		if inward_speed > 0.0:
			var allowed_speed := lerpf(s.cur_max, s.cur_max * 0.15, pow(size_resistance, 1.4))
			if inward_speed > allowed_speed:
				var excess := inward_speed - allowed_speed
				s.motor.velocity -= dir * excess
				inward_speed = allowed_speed

		# Engulf front advances only under sustained push; elastic recoil otherwise.
		if inward_speed > 0.1:
			var size_factor := pow(maxf(0.0, 1.0 - vol_ratio), 1.8)
			var advance_rate := 3.8 * size_factor + 0.06 * (1.0 - size_resistance * 0.85)
			p.engulf_front = minf(1.0, p.engulf_front + advance_rate * dt)
		else:
			var pushback_rate := 1.2 + 3.0 * size_resistance
			p.engulf_front = maxf(0.0, p.engulf_front - dt * pushback_rate)
			var recoil := 2.5 * size_resistance * (1.0 - p.engulf_front)
			s.motor.velocity -= dir * recoil * dt

		# No positional pushback: the prop is solid until the front opens and excluded
		# afterwards, so the front itself is the only gate on how far the body advances.
		if p.engulf_front >= 0.95:
			_begin_eating(p, s)


# ------------------------------------------------------------------------------------------------
# Passage hints (geometry only; the slime validates posture with real queries)
# ------------------------------------------------------------------------------------------------

## Measure one specific pair as a passage. Returns {} when either prop is gone,
## eaten, out of the body's vertical band, or no longer forms two opposing faces
## with overlapping extent along the flow. A latched session re-measures through
## here so its width/center/axis track the same two bodies and never get re-scored.
func measure_passage_pair(s: Slime, a: PropData, b: PropData) -> Dictionary:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return {}
	if a.state != STATE_IDLE or b.state != STATE_IDLE or a.mesh == null or b.mesh == null:
		return {}
	if not props.has(a) or not props.has(b):
		return {}
	var foot := s.model.foot
	var top := foot.y + s.model.full_height
	for p: PropData in [a, b]:
		var he := _half_of(p)
		var m: Node3D = p.mesh
		var bottom: float = m.global_position.y - he.y
		var top_y: float = m.global_position.y + he.y
		if bottom > tuning.floor_y + 0.5 or top_y < foot.y or bottom > top:
			return {}

	var ya := a.mesh.global_position.y
	var yb := b.mesh.global_position.y
	var ca := _closest_and_normal(a, Vector3(b.mesh.global_position.x, ya, b.mesh.global_position.z))
	var cb := _closest_and_normal(b, Vector3(a.mesh.global_position.x, yb, a.mesh.global_position.z))
	ca = _closest_and_normal(a, Vector3(cb.point.x, ya, cb.point.z))
	cb = _closest_and_normal(b, Vector3(ca.point.x, yb, ca.point.z))

	var gap_vec := Vector3(cb.point.x - ca.point.x, 0.0, cb.point.z - ca.point.z)
	var w := gap_vec.length()
	if w < 1e-3:
		return {}
	var gap_dir := gap_vec / w
	var na := Vector3(ca.normal.x, 0.0, ca.normal.z)
	var nb := Vector3(cb.normal.x, 0.0, cb.normal.z)
	if na.length() < 0.3 or nb.length() < 0.3:
		return {}
	na = na.normalized()
	nb = nb.normalized()
	if na.dot(gap_dir) < 0.9 or nb.dot(gap_dir) > -0.9:
		return {}
	var flow := Vector3(-gap_dir.z, 0.0, gap_dir.x)
	var center := Vector3((ca.point.x + cb.point.x) * 0.5, 0.0, (ca.point.z + cb.point.z) * 0.5)

	var ea := _flow_extent(a, flow)
	var eb := _flow_extent(b, flow)
	var fa := Vector3(a.mesh.global_position.x, 0.0, a.mesh.global_position.z).dot(flow)
	var fb := Vector3(b.mesh.global_position.x, 0.0, b.mesh.global_position.z).dot(flow)
	var lo := maxf(fa - ea, fb - eb)
	var hi := minf(fa + ea, fb + eb)
	if hi - lo < 0.05:
		return {}
	var half_length := (hi - lo) * 0.5
	center += flow * ((lo + hi) * 0.5 - center.dot(flow))
	return {"width": w, "center": center, "axis": gap_dir, "flow": flow, "half_length": half_length}


## Returns {} or {width, center, axis, flow, half_length, a, b}. A passage requires
## two genuinely opposing, near-parallel faces AND overlapping extent along the flow
## direction — two nearby props alone are never a corridor. Acquisition only: a
## latched session re-measures its own pair instead.
func find_passage(s: Slime) -> Dictionary:
	var result: Dictionary = {}
	var S := s.model.scale
	var foot := s.model.foot
	var top := foot.y + s.model.full_height
	# Anticipate the fully squeezed footprint: the along-flow stretch is part of the
	# hull now, so the hint must reach as far as the stretched tip actually does.
	var stretch_max := 1.0 + (1.0 - tuning.min_liquid_squeeze) * tuning.squeeze_elongation
	var reach := s.model.rest_max_radius * S * maxf(s.model.spread, tuning.liquid_spread_ratio) * stretch_max
	var candidates: Array[PropData] = []
	for p in props:
		if p.state != STATE_IDLE or p.mesh == null or is_edible_by_push(s, p):
			continue
		var he := _half_of(p)
		var m := p.mesh
		var bottom := m.global_position.y - he.y
		var top_y := m.global_position.y + he.y
		if bottom > tuning.floor_y + 0.5:
			continue
		if top_y < foot.y or bottom > top:
			continue
		var d := Vector2(m.global_position.x - s.global_position.x, m.global_position.z - s.global_position.z).length()
		if d > reach * 3.0 + maxf(he.x, he.z):
			continue
		candidates.append(p)

	var sp := Vector3(s.global_position.x, 0.0, s.global_position.z)
	var move_dir := Vector3(s.motor.velocity.x, 0.0, s.motor.velocity.z)
	var moving := move_dir.length() > 0.1
	if moving:
		move_dir = move_dir.normalized()
	var best_score := -INF

	for i in candidates.size():
		for j in range(i + 1, candidates.size()):
			var a := candidates[i]
			var b := candidates[j]
			var m := measure_passage_pair(s, a, b)
			if m.is_empty():
				continue
			var w: float = m["width"]
			if w >= reach * 2.0:
				continue
			var flow: Vector3 = m["flow"]
			var half_length: float = m["half_length"]
			var center: Vector3 = m["center"]
			var to_gap := center - sp
			# Only nearby passages the body is actually entering may reshape it: a gate
			# far away (or already behind the direction of travel) must not squeeze it.
			if to_gap.length() > reach * 1.15 + half_length + 0.5:
				continue
			if moving and to_gap.dot(move_dir) < 0.1:
				continue
			var score := 1.0 / (1.0 + to_gap.length())
			score += (absf(move_dir.dot(flow)) * 2.0) if moving else 0.5
			if score > best_score:
				best_score = score
				result = m.duplicate()
				result["a"] = a
				result["b"] = b
	return result


func _closest_and_normal(p: PropData, target: Vector3) -> Dictionary:
	var m := p.mesh
	var local := m.to_local(target)
	var he := p.half
	var lp := Vector3.ZERO
	var ln := Vector3.ZERO
	if p.shape == SHAPE_BOX:
		if absf(local.x) < he.x and absf(local.y) < he.y and absf(local.z) < he.z:
			var px := he.x - absf(local.x)
			var pz := he.z - absf(local.z)
			if px < pz:
				lp = Vector3(he.x if local.x >= 0.0 else -he.x, local.y, local.z)
				ln = Vector3(1.0 if local.x >= 0.0 else -1.0, 0.0, 0.0)
			else:
				lp = Vector3(local.x, local.y, he.z if local.z >= 0.0 else -he.z)
				ln = Vector3(0.0, 0.0, 1.0 if local.z >= 0.0 else -1.0)
		else:
			lp = Vector3(clampf(local.x, -he.x, he.x), clampf(local.y, -he.y, he.y), clampf(local.z, -he.z, he.z))
			var dvec := local - lp
			ln = dvec.normalized() if dvec.length_squared() > 1e-8 else Vector3(0, 1, 0)
	else:
		var y := clampf(local.y, -he.y, he.y)
		var dxz := Vector2(local.x, local.z)
		var d := maxf(dxz.length(), 1e-4)
		var ux := dxz.x / d
		var uz := dxz.y / d
		var sup := _poly_support_local(p, ux, uz)
		if p.shape == SHAPE_CONE:
			sup *= maxf(0.06, 1.0 - (y + he.y) / maxf(2.0 * he.y, 1e-4))
		lp = Vector3(ux * sup, y, uz * sup)
		if p.sides >= 3 and p.sides < 12:
			var sector := TAU / float(p.sides)
			var ang := atan2(ux, uz) - p.phase
			var dsec := fmod(ang, sector)
			if dsec < 0.0:
				dsec += sector
			var face_ang := ang - dsec + sector * 0.5
			ln = Vector3(sin(face_ang), 0.0, cos(face_ang))
		else:
			ln = Vector3(ux, 0.0, uz)
	return {"point": m.to_global(lp), "normal": (m.basis * ln).normalized()}


func _flow_extent(p: PropData, flow: Vector3) -> float:
	var he := _half_of(p)
	if p.shape == SHAPE_BOX:
		var ld := p.mesh.basis.inverse() * flow
		var l := Vector2(ld.x, ld.z)
		if l.length_squared() < 1e-8:
			return maxf(he.x, he.z)
		l = l.normalized()
		return absf(l.x) * he.x + absf(l.y) * he.z
	return _poly_support(p, flow.x, flow.z)


func _horizontal_reach(p: PropData, dir_world: Vector3, foot_y: float) -> float:
	var he := _half_of(p)
	if p.shape == SHAPE_BOX:
		var ld := p.mesh.basis.inverse() * dir_world
		var l := Vector2(ld.x, ld.z)
		if l.length_squared() < 1e-8:
			return maxf(he.x, he.z)
		l = l.normalized()
		return absf(l.x) * he.x + absf(l.y) * he.z
	var sup := _poly_support(p, dir_world.x, dir_world.z)
	if p.shape == SHAPE_CONE:
		var bottom := p.mesh.global_position.y - he.y
		var y_lo := maxf(bottom, foot_y)
		var taper := maxf(0.06, 1.0 - (y_lo - bottom) / maxf(2.0 * he.y, 1e-4))
		return sup * taper
	return sup


# ------------------------------------------------------------------------------------------------
# Motor contact feedback (visual only; the motor already resolved the motion)
# ------------------------------------------------------------------------------------------------

func _register_motor_contacts(s: Slime, dt: float) -> void:
	var bodies := s.motor.contact_bodies
	var normals := s.motor.contact_normals
	if bodies.is_empty():
		return
	var S := s.model.scale
	for i in bodies.size():
		var p := _prop_of_body(bodies[i])
		if p == null:
			continue
		var n: Vector3 = normals[i] if i < normals.size() else Vector3.ZERO
		p.touch = s.time
		p.touch_slime = s
		p.cnx = n.x
		p.cnz = n.z
		if i == 0:
			s.impact_dir = Vector3(-n.x, 0.0, -n.z)
			s.touch_time = s.time
			var to_prop := Vector3(p.mesh.global_position.x - s.global_position.x, 0.0, p.mesh.global_position.z - s.global_position.z)
			s.contact_r = s.model.horizontal_support(to_prop) / maxf(S, 1e-4)
			var sharp := _contact_sharpness(p, s)
			s.sharp_amt += (sharp - s.sharp_amt) * (1.0 - exp(-15.0 * dt))

	var p0 := _prop_of_body(bodies[0])
	var vin := s.motor.impact_speed
	if p0 != null and vin > 0.6 and s.model.squeeze > 0.85 and s.time - p0.hit_cd > 0.3:
		p0.hit_cd = s.time
		var n0: Vector3 = normals[0]
		var sev := minf(1.0, pow(vin / 8.5, 0.9))
		s.splat_v += sev * 28.0 * (1.0 + 0.5 * s.sharp_amt)
		s.trigger_poke(
			Vector3(-n0.x, -0.15, -n0.z).normalized() * 1.6,
			Vector3(n0.x * 1.6 * sev, 0.18 * sev, n0.z * 1.6 * sev))


func _contact_sharpness(p: PropData, s: Slime) -> float:
	var local := p.mesh.to_local(s.global_position)
	var he := p.half
	if p.shape == SHAPE_BOX:
		var ox := absf(local.x) - he.x
		var oz := absf(local.z) - he.z
		var r := maxf(s.model.rest_max_radius * s.model.scale, 0.1)
		var t := clampf(minf(ox, oz) / (0.22 * r), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)
	if p.sides >= 3 and p.sides < 12:
		var d := Vector2(local.x, local.z)
		if d.length_squared() < 1e-6:
			return 0.0
		d = d.normalized()
		var sup := _poly_support_local(p, d.x, d.y)
		var ap := p.base_r * cos(PI / float(p.sides))
		var t := clampf((sup - ap) / maxf(p.base_r - ap, 1e-4), 0.0, 1.0)
		return t * t * (3.0 - 2.0 * t)
	return 0.0


func _update_slime_splat(s: Slime, dt: float) -> void:
	var since := s.time - s.touch_time
	var is_pushing := s.motor.velocity.length_squared() > 0.1
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


# ------------------------------------------------------------------------------------------------
# Digestion & inside props
# ------------------------------------------------------------------------------------------------

func _update_digesting_props(dt: float) -> void:
	for p in props:
		if p.state != STATE_EATING:
			continue
		p.t += dt
		p.pd = maxf(0.0, p.pd * exp(-10.0 * dt))
		p.pv = maxf(0.0, p.pv * exp(-10.0 * dt))
		var k := minf(p.t / tuning.eat_time, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var dis := maxf(0.0, 1.0 - maxf(0.0, p.t - tuning.eat_time) / tuning.eat_linger)
		var shrink := maxf(0.001, (1.0 - 0.35 * e) * (0.65 + 0.35 * dis))
		p.mesh.scale = p.base_scale * shrink
		if p.material != null:
			p.material.set_shader_parameter("uDissolve", 1.0 - dis)
		p.mesh.rotation.y += dt * 0.4

		var s: Slime = p.eater if p.eater != null and is_instance_valid(p.eater) else player_slime
		if s != null and is_instance_valid(s):
			var total_digest_time := tuning.eat_time + tuning.eat_linger
			var progress := clampf(p.t / total_digest_time, 0.0, 1.0)
			var e_mass := progress * progress * (3.0 - 2.0 * progress)
			var target_absorbed := p.total_mass * e_mass
			var delta_m := target_absorbed - p.absorbed_mass
			if delta_m > 0.0:
				p.absorbed_mass = target_absorbed
				s.add_volume(delta_m)

			if p.t < tuning.eat_time:
				var target_in_belly: Vector3 = s.model.center() + p.off * (s.model.scale * 0.70)
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
	var center := s.model.center()
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
		var rh: float = maxf(0.15, maxf(s.model.semi_a, s.model.semi_b) * 0.8 - rr)
		var rv: float = maxf(0.15, s.model.full_height * 0.45 - rr)
		var l: Vector3 = m.position - center
		var qx: float = l.x / rh
		var qy: float = l.y / rv
		var qz: float = l.z / rh
		var ql: float = sqrt(qx * qx + qy * qy + qz * qz)
		if ql > 1.0:
			m.position = center + l / ql
			var n: Vector3 = Vector3(qx / rh, qy / rv, qz / rh).normalized()
			var vn: float = p.vel.dot(n)
			if vn > 0.0:
				p.vel -= n * vn * 1.4

		if m.position.y < tuning.floor_y + he.y:
			m.position.y = tuning.floor_y + he.y
			if p.vel.y < 0.0:
				p.vel.y *= -0.2


# ------------------------------------------------------------------------------------------------
# Shader uniforms (all positions in mesh-local units via the resolved model)
# ------------------------------------------------------------------------------------------------

func _update_eat_uniforms(s: Slime) -> void:
	var S := s.model.scale
	var sp := s.global_position
	var eat_pos := PackedVector3Array()
	var eat_param := PackedVector3Array()
	var box_half := PackedVector3Array()
	for i in 6:
		eat_pos.append(Vector3.ZERO)
		eat_param.append(Vector3.ZERO)
		box_half.append(Vector3(0.01, 0.01, 0.01))

	var pressing: Array[PropData] = []
	for p in props:
		if p.state == STATE_IDLE and p.pd > 0.004 and p.p_ro > 0.0 and p.last_presser == s:
			var dist := Vector2(p.mesh.global_position.x - sp.x, p.mesh.global_position.z - sp.z).length()
			if dist <= s.model.rest_max_radius * S * 1.1 + p.p_ro:
				pressing.append(p)
	pressing.sort_custom(func(a: PropData, b: PropData) -> bool: return a.pd > b.pd)
	if pressing.size() > 3:
		pressing.resize(3)

	var pa := 0.0
	var press_dir := Vector3(0, 0, 1)
	for i in pressing.size():
		var p := pressing[i]
		var m := p.mesh.global_position
		var dx := m.x - sp.x
		var dz := m.z - sp.z
		var d := maxf(Vector2(dx, dz).length(), 1e-4)
		var dir := Vector3(dx / d, 0.0, dz / d)
		var dv := (s.model.world_radius_at(m.y, dir) + p.p_ro - p.pd) / maxf(S, 1e-4)
		eat_pos[i] = Vector3(dir.x * dv, (m.y - sp.y) / maxf(S, 1e-4), dir.z * dv)
		eat_param[i] = Vector3(float(p.shape) + p.sides * 0.01, 1.0, p.mesh.rotation.y + p.phase)
		box_half[i] = _box_half(p, S)
		var a := minf(1.0, p.pd / p.p_thr)
		var vr := clampf(p.real_volume / maxf(1e-4, s.get_volume()), 0.0, 1.0)
		var strain_boost := 1.0 + 0.45 * clampf((vr - 0.25) / 0.75, 0.0, 1.0)
		a = minf(1.0, a * strain_boost)
		if a > pa:
			pa = a
			press_dir = dir

	s.press_amt += (pa - s.press_amt) * 0.25
	s.set_shader_param("uPressAmt", s.press_amt)
	s.set_shader_param("uPressDir", press_dir)

	var near := 0.0
	for p in props:
		if p.state != STATE_IDLE or p.p_ro <= 0.0 or p.last_presser != s:
			continue
		var to_prop := Vector3(p.mesh.global_position.x - sp.x, 0.0, p.mesh.global_position.z - sp.z)
		var gap := to_prop.length() - (s.model.horizontal_support(to_prop) + p.p_ro)
		near = maxf(near, minf(1.0, maxf(0.0, 1.0 - gap / (1.5 * S + p.p_ro))))
	s.calm += (maxf(near, s.press_amt) - s.calm) * 0.2

	var slot := 3
	for p in props:
		if p.state != STATE_EATING or p.eater != s or slot > 5:
			continue
		var m := p.mesh.global_position
		eat_pos[slot] = s.model.mesh_local(m - sp)
		var eat_fade := clampf(p.t / 0.4, 0.0, 1.0)
		eat_param[slot] = Vector3(float(p.shape) + p.sides * 0.01, eat_fade, p.mesh.rotation.y + p.phase)
		box_half[slot] = _box_half(p, S)
		slot += 1

	s.set_shader_param("uEatPos", eat_pos)
	s.set_shader_param("uEatParam", eat_param)
	s.set_shader_param("uBoxHalf", box_half)


func _update_solid_uniforms(s: Slime) -> void:
	var S := s.model.scale
	var sp := s.global_position
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
			var dist := Vector2(p.mesh.global_position.x - sp.x, p.mesh.global_position.z - sp.z).length()
			if dist <= s.model.rest_max_radius * S * 1.2 + Vector2(he.x, he.z).length():
				active.append(p)
	active.sort_custom(func(a: PropData, b: PropData) -> bool: return a.touch > b.touch)
	if active.size() > 2:
		active.resize(2)

	var depth := minf(1.2, maxf(s.splat_x, s.spread_x * 0.5) * (0.5 + 0.7 * s.sharp_amt))
	for i in active.size():
		var p := active[i]
		var m := p.mesh.global_position
		var local := s.model.mesh_local(m - sp)
		solid_pos[i] = Vector3(local.x + p.cnx * depth, local.y, local.z + p.cnz * depth)
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
		b_pos.append(s.global_position)
		b_scale.append(s.model.scale * s.model.spread)

	var count := b_pos.size()
	while b_pos.size() < 8:
		b_pos.append(Vector3.ZERO)
		b_scale.append(0.0)

	_floor_mat.set_shader_parameter("uBlobCount", count)
	_floor_mat.set_shader_parameter("uBlobPos", b_pos)
	_floor_mat.set_shader_parameter("uBlobScale", b_scale)


# ------------------------------------------------------------------------------------------------
# Shape helpers (world-space, rotation-correct)
# ------------------------------------------------------------------------------------------------

func _half_of(p: PropData) -> Vector3:
	return p.half * p.mesh.scale.x


func _poly_support_local(p: PropData, ux: float, uz: float) -> float:
	if p.sides < 3 or p.sides >= 12:
		return p.base_r
	var sector := TAU / float(p.sides)
	var d := fmod(atan2(ux, uz) - p.phase, sector)
	if d < 0.0:
		d += sector
	var from_face := absf(d - sector * 0.5)
	return p.base_r * cos(sector * 0.5) / cos(from_face)


func _poly_support(p: PropData, ux: float, uz: float) -> float:
	var ld := p.mesh.basis.inverse() * Vector3(ux, 0.0, uz)
	var l := Vector2(ld.x, ld.z)
	if l.length_squared() < 1e-8:
		return p.base_r * p.mesh.scale.x
	l = l.normalized()
	return _poly_support_local(p, l.x, l.y) * p.mesh.scale.x


func _box_half(p: PropData, S: float) -> Vector3:
	var he := _half_of(p)
	if p.shape == SHAPE_BOX:
		return he / maxf(S, 1e-4)
	var r := p.base_r * p.mesh.scale.x
	return Vector3(r, he.y, r) / maxf(S, 1e-4)


func total() -> int:
	return props.size()