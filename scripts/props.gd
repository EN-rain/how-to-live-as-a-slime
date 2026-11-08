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
## Props currently being digested by a slime (typically 0-2). Uniform updates and
## the digestion pass only visit these instead of scanning the whole ecosystem.
var active_eating_props: Array[PropData] = []
## 2D spatial hash (10 m cells) so per-slime queries never scan every prop.
const GRID_CELL := 10.0
var _grid := {}
## Idle prop pairs that already form a corridor, rebuilt only when a prop is eaten.
var _candidate_passage_pairs: Array = []
## Denominator for the HUD: never shrinks when a digested prop is removed.
var _spawned_total := 0
## Merged clones waiting to be reused by the next split.
var _slime_pool: Array[Slime] = []

# Preallocated uniform buffers. Packed arrays are value types, so they are still
# copied into the shader; the win is that nothing is resized or allocated per tick.
var _eat_pos_buf := PackedVector3Array()
var _eat_param_buf := PackedVector3Array()
var _box_half_buf := PackedVector3Array()
var _solid_pos_buf := PackedVector3Array()
var _solid_param_buf := PackedVector3Array()
var _solid_half_buf := PackedVector3Array()
var _solid_dir_buf := PackedVector3Array()
var _blob_pos_buf := PackedVector3Array()
var _blob_scale_buf := PackedFloat32Array()
var _floor_param_cache := {}


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
	# Run after every slime (priority 0) has resolved its tick, so constraints and
	# uniform reads always see final positions.
	process_physics_priority = 100
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
	_spawned_total = props.size()

	_eat_pos_buf.resize(6)
	_eat_param_buf.resize(6)
	_box_half_buf.resize(6)
	_solid_pos_buf.resize(8)
	_solid_param_buf.resize(8)
	_solid_half_buf.resize(8)
	_solid_dir_buf.resize(8)
	_blob_pos_buf.resize(8)
	_blob_scale_buf.resize(8)
	rebuild_grid()

	if slime != null:
		register_slime(slime)


func register_slime(s: Slime) -> void:
	if not registered_slimes.has(s):
		registered_slimes.append(s)
		if s.role == Slime.Role.PLAYER:
			player_slime = s
		refresh_follower_slots()


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
	refresh_follower_slots()


## Assign each follower its slot in the train behind a leader. O(slimes), called
## only on registration/removal, never per tick.
func refresh_follower_slots() -> void:
	var counts := {}
	for s in registered_slimes:
		if not is_instance_valid(s) or s.role != Slime.Role.FOLLOWER:
			continue
		var leader: Slime = s.target_leader
		if leader == null or not is_instance_valid(leader):
			s.follower_slot_index = 0
			continue
		var n: int = counts.get(leader, 0)
		s.follower_slot_index = n
		counts[leader] = n + 1


## Keep a merged clone in memory for the next split instead of freeing and
## re-instantiating (scene load + material duplicate + shape setup) mid-frame.
func recycle_slime(s: Slime) -> void:
	s._prepare_for_pool()
	if not _slime_pool.has(s) and _slime_pool.size() < 8:
		_slime_pool.append(s)


func take_pooled_slime() -> Slime:
	while not _slime_pool.is_empty():
		var s: Slime = _slime_pool.pop_back()
		if is_instance_valid(s):
			return s
	return null


## Deterministic seed source for slime-local RNG streams (roamer wandering).
func next_slime_seed() -> int:
	return _rng.randi()


## Compatibility stub. The ecosystem now owns its tick (see _physics_process), so a
## merging, splitting or sleeping slime can never hold back a step.
func slime_ticked(_s: Slime, _dt: float) -> void:
	pass


func _physics_process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	for s in registered_slimes:
		if not is_instance_valid(s):
			continue
		if not s.is_merging:
			_register_motor_contacts(s, dt)
			_process_edible_props(s, dt)
		_update_inside_props(s, dt)
		_update_slime_splat(s, dt)

	_separate_slimes()

	for s in registered_slimes:
		if not is_instance_valid(s):
			continue
		_update_eat_uniforms(s, dt)
		_update_solid_uniforms(s)

	# Press state that no body refreshed this tick (walked away, merged, freed)
	# relaxes here, so a narrow per-slime query can never leave a prop permanently
	# non-solid.
	for p in props:
		if p.state != STATE_IDLE or (p.pd <= 0.0 and p.engulf_front <= 0.0):
			continue
		var presser: Slime = p.last_presser
		if presser != null and is_instance_valid(presser) and presser.pressing_props.has(p):
			continue
		p.pd = maxf(0.0, p.pd * exp(-15.0 * dt))
		p.pv = 0.0
		p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.5)
		if p.pd <= 0.001 and p.engulf_front <= 0.001:
			p.pd = 0.0
			p.engulf_front = 0.0
			p.last_presser = null
			p.hold = 0.0

	_update_digesting_props(dt)
	_update_floor_shadows()


## Symmetric residual separation for overlapping slimes. Every delta is computed from
## a pre-pass snapshot and applied through each motor's swept move, so the result is
## order independent. The proxies already stop movement intent; this resolves the
## overlap a legal posture change or a spawn may leave behind.
func _separate_slimes() -> void:
	if not tuning.use_analytic_slime_collision:
		_separate_slimes_legacy()
		return

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
			"reach": s.model.rest_max_radius * s.model.scale,
			"mass": s.get_volume() * (2.0 if s.role == Slime.Role.PLAYER else 1.0),
		})
	if bodies.size() < 2:
		return

	# 1D broadphase on x: overlapping pairs must lie within the sum of their
	# horizontal reaches, so sorting lets the scan stop at the first definitively
	# distant neighbour instead of testing every pair.
	var max_reach := 0.0
	for b in bodies:
		max_reach = maxf(max_reach, b["reach"])
	bodies.sort_custom(func(a, b): return (a["xz"] as Vector2).x < (b["xz"] as Vector2).x)

	for _iter in 2:
		var pushes: Array[Vector2] = []
		pushes.resize(bodies.size())
		pushes.fill(Vector2.ZERO)
		var pairs: Array = []
		for i in bodies.size():
			var a: Dictionary = bodies[i]
			for j in range(i + 1, bodies.size()):
				var b: Dictionary = bodies[j]
				if (b["xz"] as Vector2).x - (a["xz"] as Vector2).x > max_reach * 2.0:
					break
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
				pairs.append([i, j])
		if pairs.is_empty():
			return

		var moved := false
		var denied: Array[Vector2] = []
		denied.resize(bodies.size())
		denied.fill(Vector2.ZERO)
		for i in bodies.size():
			var s: Slime = bodies[i]["slime"]
			var push: Vector2 = pushes[i]
			if not is_instance_valid(s) or push.length_squared() < 1e-8:
				continue
			# One tick may only spend part of the motor's step budget: intent motion
			# already used some, and a deep overlap must resolve over several ticks
			# instead of teleporting either body.
			var cap: float = bodies[i]["reach"] * tuning.max_step_fraction * 0.5
			if push.length() > cap:
				push *= cap / push.length()
			var n := push.normalized()
			var frac := s.motor.apply_slime_separation(Vector3(push.x, 0.0, push.y), Vector3(n.x, 0.0, n.y))
			if frac < 0.999:
				denied[i] = push * (1.0 - frac)
			if frac > 1e-4:
				moved = true
				s._sync_proxy()

		# Wall-pinned backstop: a body blocked by level geometry leaves its partner
		# asymmetrically embedded, so the undelivered share transfers to the free side
		# instead of the pair jittering against the wall every tick.
		for pair in pairs:
			var i: int = pair[0]
			var j: int = pair[1]
			var a: Slime = bodies[i]["slime"]
			var b: Slime = bodies[j]["slime"]
			if not is_instance_valid(a) or not is_instance_valid(b):
				continue
			var da: Vector2 = denied[i]
			if da.length_squared() > 1e-8:
				var push_a := Vector3(-da.x, 0.0, -da.y)
				var frac_a := b.motor.apply_slime_separation(push_a, push_a.normalized())
				if frac_a > 1e-4:
					b._sync_proxy()
					moved = true
				denied[i] = Vector2.ZERO
			var db: Vector2 = denied[j]
			if db.length_squared() > 1e-8:
				var push_b := Vector3(-db.x, 0.0, -db.y)
				var frac_b := a.motor.apply_slime_separation(push_b, push_b.normalized())
				if frac_b > 1e-4:
					a._sync_proxy()
					moved = true
				denied[j] = Vector2.ZERO

		if not moved:
			return
		for i in bodies.size():
			var s: Slime = bodies[i]["slime"]
			if is_instance_valid(s):
				bodies[i]["xz"] = Vector2(s.global_position.x, s.global_position.z)


func _separate_slimes_legacy() -> void:
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
		var cap := s.model.rest_max_radius * s.model.scale * tuning.max_step_fraction * 0.5
		if push.length() > cap:
			push *= cap / push.length()
		s.motor.move_horizontal(Vector3(push.x, 0.0, push.y))
		s._sync_proxy()


func _pair_exempt(a: Slime, b: Slime) -> bool:
	# Must mirror Slime._exempt_rids(): a partner the motors are told to ignore has
	# to be ignored here too, or a split would be torn apart by its own resolver.
	if a.is_merging or b.is_merging:
		return true
	if a.is_budding and a.bud_parent == b and not (a._bud_snapped and a._bud_clear):
		return true
	if b.is_budding and b.bud_parent == a and not (b._bud_snapped and b._bud_clear):
		return true
	if a.is_fissioning and a.fission_clone == b and not (b._bud_snapped and b._bud_clear):
		return true
	if b.is_fissioning and b.fission_clone == a and not (a._bud_snapped and a._bud_clear):
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


## Rebuild the spatial hash and the corridor-pair cache. Cheap, but O(props^2) for
## the pairs, so it only runs at spawn and when a prop is eaten, never per tick.
func rebuild_grid() -> void:
	_grid.clear()
	for p in props:
		if p.state == STATE_IDLE and p.mesh != null and is_instance_valid(p.mesh):
			_grid_insert(p)
	rebuild_passage_pairs()


func rebuild_passage_pairs() -> void:
	var idle: Array[PropData] = []
	for p in props:
		if p.state == STATE_IDLE and p.mesh != null and is_instance_valid(p.mesh):
			idle.append(p)
	_candidate_passage_pairs.clear()
	for i in idle.size():
		var a := idle[i]
		var ax := a.mesh.global_position
		for j in range(i + 1, idle.size()):
			var b := idle[j]
			var bx := b.mesh.global_position
			if Vector2(ax.x - bx.x, ax.z - bx.z).length_squared() > 144.0:
				continue
			var m := _measure_pair_geometry(a, b)
			if m.is_empty():
				continue
			if m["width"] >= GRID_CELL or m["half_length"] < 0.025:
				continue
			_candidate_passage_pairs.append({"a": a, "b": b})


func _grid_key(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / GRID_CELL), floori(pos.z / GRID_CELL))


func _grid_insert(p: PropData) -> void:
	var k := _grid_key(p.mesh.global_position)
	var bucket = _grid.get(k)
	if bucket == null:
		bucket = []
		_grid[k] = bucket
	bucket.append(p)


func _grid_remove(p: PropData) -> void:
	if p.mesh == null:
		return
	var bucket = _grid.get(_grid_key(p.mesh.global_position))
	if bucket != null:
		bucket.erase(p)


## Idle props whose centre lies within `radius` of the given ground-plane point.
func query_nearby_props(xz: Vector2, radius: float) -> Array[PropData]:
	var out: Array[PropData] = []
	var r2 := radius * radius
	var x0 := floori((xz.x - radius) / GRID_CELL)
	var x1 := floori((xz.x + radius) / GRID_CELL)
	var z0 := floori((xz.y - radius) / GRID_CELL)
	var z1 := floori((xz.y + radius) / GRID_CELL)
	for cx in range(x0, x1 + 1):
		for cz in range(z0, z1 + 1):
			var bucket = _grid.get(Vector2i(cx, cz))
			if bucket == null:
				continue
			for p in bucket:
				var m: MeshInstance3D = p.mesh
				if m == null or not is_instance_valid(m):
					continue
				var dx := m.global_position.x - xz.x
				var dz := m.global_position.z - xz.y
				if dx * dx + dz * dz <= r2:
					out.append(p)
	return out


## Obstacle RIDs this slime may pass through. Policy: an idle prop is solid to every
## query until THIS slime has opened an engulf front on it; a prop already dissolving
## in this slime is past the front. Support and ceilings use the same list, so the
## horizontal and vertical policies can no longer disagree.
func rids_edible_by(s: Slime) -> Array[RID]:
	var rids: Array[RID] = []
	for p in active_eating_props:
		if p.eater == s and p.body != null:
			rids.append(p.body.get_rid())
	for p in s.pressing_props:
		if p.body != null and p.state == STATE_IDLE and p.last_presser == s and p.engulf_front >= 0.85:
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

func _spawn_cube_box(cname: String, pos: Vector3, size: Vector3, color: Color, p_static: bool) -> PropData:
	var box := BoxMesh.new()
	box.size = size
	var p := PropData.new()
	p.is_static = p_static
	p.shape = SHAPE_BOX
	p.half = size * 0.5
	p.radius = maxf(size.x, maxf(size.y, size.z)) * 0.5
	p.fp = Vector2(size.x, size.z).length() * 0.5

	var mat := ShaderMaterial.new()
	mat.shader = prop_shader
	mat.set_shader_parameter("uColor", color)
	mat.set_shader_parameter("uDissolve", 0.0)
	p.material = mat

	var mi := MeshInstance3D.new()
	mi.name = cname
	mi.mesh = box
	mi.material_override = mat
	mi.position = pos
	_prop_root.add_child(mi)
	p.mesh = mi
	p.base_scale = Vector3.ONE
	p.calc_real_volume()
	_attach_collider(p)
	props.append(p)
	return p


func _spawn_props() -> void:
	# Deterministic Edible Cube Lineup (South Station: z = -9.0 and z = -14.0)
	# Row 1: Small-to-medium cubes (edible at starting scale by push or Z engulf)
	var row1_sizes := [0.55, 0.65, 0.75, 0.85, 0.95, 1.05, 1.15]
	for i in row1_sizes.size():
		var s: float = row1_sizes[i]
		var x := -7.8 + float(i) * 2.6
		var z := -9.0
		var col := _hsl(0.32 - float(i) * 0.04, 0.70, 0.58)
		_spawn_cube_box("EdibleCube_S%d" % i, Vector3(x, tuning.floor_y + s * 0.5, z), Vector3(s, s, s), col, false)

	# Row 2: Larger cubes (test growth progression, heavy resistance, and Z engulfing)
	var row2_sizes := [1.25, 1.40, 1.60, 1.80, 2.05, 2.35]
	for i in row2_sizes.size():
		var s: float = row2_sizes[i]
		var x := -8.75 + float(i) * 3.5
		var z := -14.0
		var col := _hsl(0.08 - float(i) * 0.012, 0.75, 0.56)
		_spawn_cube_box("EdibleCube_L%d" % i, Vector3(x, tuning.floor_y + s * 0.5, z), Vector3(s, s, s), col, false)


func _spawn_test_structures() -> void:
	var gate_col := Color(0.32, 0.72, 0.88)
	var tunnel_col := Color(0.42, 0.62, 0.92)
	var corridor_col := Color(0.36, 0.82, 0.76)
	var wall_col := Color(0.52, 0.56, 0.68)

	# --- STATION 1 (North, z = 9.0): Gate Width Progression ---
	# 1A. Wide Gate (2.8m gap) at x = -9.0: passable in normal mode without Z
	var gate_28 := Vector3(-9.0, 0.0, 9.0)
	for side in [-1.0, 1.0]:
		_spawn_cube_box(
			"Gate28_%s" % ("L" if side < 0 else "R"),
			gate_28 + Vector3(side * (1.4 + 0.7), tuning.floor_y + 1.5, 0.0),
			Vector3(1.4, 3.0, 1.4), gate_col, true)

	# 1B. Standard Narrow Gate (1.4m gap) at x = 0.0: blocked in normal mode, passes with Z
	var gate_14 := Vector3(0.0, 0.0, 9.0)
	for side in [-1.0, 1.0]:
		_spawn_cube_box(
			"Gate14_%s" % ("L" if side < 0 else "R"),
			gate_14 + Vector3(side * (0.7 + 0.7), tuning.floor_y + 1.5, 0.0),
			Vector3(1.4, 3.0, 1.4), gate_col, true)

	# 1C. Tight Liquid Gate (1.12m gap) at x = 8.0: tight Z-mode core sphere pass
	var gate_11 := Vector3(8.0, 0.0, 9.0)
	for side in [-1.0, 1.0]:
		_spawn_cube_box(
			"Gate11_%s" % ("L" if side < 0 else "R"),
			gate_11 + Vector3(side * (0.56 + 0.7), tuning.floor_y + 1.5, 0.0),
			Vector3(1.4, 3.0, 1.4), gate_col, true)

	# 1D. Impossible Gate (0.55m gap) at x = 15.5: narrower than core sphere, blocks even in Z
	var gate_05 := Vector3(15.5, 0.0, 9.0)
	for side in [-1.0, 1.0]:
		_spawn_cube_box(
			"Gate05_%s" % ("L" if side < 0 else "R"),
			gate_05 + Vector3(side * (0.275 + 0.7), tuning.floor_y + 1.5, 0.0),
			Vector3(1.4, 3.0, 1.4), wall_col, true)

	# --- STATION 2 (West, x = -11.0): Low Ceiling / Overhang Bridges ---
	# 2A. Low Tunnel (0.75m vertical clearance) at (-11, 0, 1)
	var bridge_low := Vector3(-11.0, 0.0, 1.0)
	_spawn_cube_box(
		"LowTunnel_Roof",
		bridge_low + Vector3(0.0, tuning.floor_y + 0.75 + 0.35, 0.0),
		Vector3(3.6, 0.7, 3.0), tunnel_col, true)
	for leg_side in [-1.0, 1.0]:
		_spawn_cube_box(
			"LowTunnel_Leg_%s" % ("L" if leg_side < 0 else "R"),
			bridge_low + Vector3(leg_side * 1.5, tuning.floor_y + 0.375, 0.0),
			Vector3(0.6, 0.75, 3.0), tunnel_col, true)

	# 2B. Medium Tunnel (1.25m vertical clearance) at (-11, 0, -5.5)
	var bridge_med := Vector3(-11.0, 0.0, -5.5)
	_spawn_cube_box(
		"MedTunnel_Roof",
		bridge_med + Vector3(0.0, tuning.floor_y + 1.25 + 0.35, 0.0),
		Vector3(3.6, 0.7, 2.6), tunnel_col, true)
	for leg_side in [-1.0, 1.0]:
		_spawn_cube_box(
			"MedTunnel_Leg_%s" % ("L" if leg_side < 0 else "R"),
			bridge_med + Vector3(leg_side * 1.5, tuning.floor_y + 0.625, 0.0),
			Vector3(0.6, 1.25, 2.6), tunnel_col, true)

	# --- STATION 3 (East, x = 11.0): Long Narrow Cube Corridor & Chicane ---
	# 3A. Long 1.5m-wide Corridor at (11, 0, 1.5)
	var corr_pos := Vector3(11.0, 0.0, 1.5)
	for side in [-1.0, 1.0]:
		_spawn_cube_box(
			"CorridorWall_%s" % ("L" if side < 0 else "R"),
			corr_pos + Vector3(side * (0.75 + 0.6), tuning.floor_y + 1.4, 0.0),
			Vector3(1.2, 2.8, 4.4), corridor_col, true)

	# 3B. Staggered Cube Slalom at (11, 0, -5.5)
	_spawn_cube_box("SlalomCube_A", Vector3(9.4, tuning.floor_y + 1.1, -4.2), Vector3(1.6, 2.2, 1.6), corridor_col, true)
	_spawn_cube_box("SlalomCube_B", Vector3(12.6, tuning.floor_y + 1.1, -5.8), Vector3(1.6, 2.2, 1.6), corridor_col, true)
	_spawn_cube_box("SlalomCube_C", Vector3(9.4, tuning.floor_y + 1.1, -7.4), Vector3(1.6, 2.2, 1.6), corridor_col, true)

	# --- STATION 4 (South-West, x = -12.0, z = -12.0): Solid Cube Wall ---
	_spawn_cube_box("SolidWall_Test", Vector3(-12.5, tuning.floor_y + 1.5, -11.5), Vector3(1.2, 3.0, 5.0), wall_col, true)


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

## Effective size ratio of a prop relative to a slime (combines linear dimension ratio and volume ratio).
func _prop_size_ratio(s: Slime, p: PropData) -> float:
	var S := maxf(s.model.scale, 1e-4)
	var he := _half_of(p)
	var prop_max_dim := 2.0 * maxf(he.x, maxf(he.y, he.z))
	var slime_h := s.model.rest_full_height * S
	var dim_ratio := prop_max_dim / maxf(slime_h, 1e-4)
	var vol_ratio := p.real_volume / maxf(1e-4, s.get_volume())
	return maxf(vol_ratio, pow(dim_ratio, 1.45))


func is_edible_by_push(s: Slime, p: PropData) -> bool:
	if p.state != STATE_IDLE or p.is_static or p.mesh == null:
		return false
	return _prop_size_ratio(s, p) <= 0.78


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
	active_eating_props.append(p)
	_grid_remove(p)
	for idx in range(_candidate_passage_pairs.size() - 1, -1, -1):
		var pair: Dictionary = _candidate_passage_pairs[idx]
		if pair["a"] == p or pair["b"] == p:
			_candidate_passage_pairs.remove_at(idx)
	eaten += 1
	eaten_changed.emit(eaten)


func _process_edible_props(s: Slime, dt: float) -> void:
	var S := s.model.scale
	var sp := s.global_position
	var foot := s.model.foot
	var sdt := minf(dt, 1.0 / 30.0)
	var vis_r := s.model.rest_max_radius * S * s.model.spread
	var nearby := query_nearby_props(Vector2(sp.x, sp.z), vis_r + 2.5)

	for p in nearby:
		if not is_edible_by_push(s, p):
			if p.last_presser == s:
				p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.5)
			continue
		var m := p.mesh
		var he := _half_of(p)
		var prop_top := m.global_position.y + he.y
		var prop_bottom := m.global_position.y - he.y
		if prop_top <= foot.y + 0.05 * S or prop_bottom >= foot.y + s.model.full_height:
			if p.last_presser == s:
				p.engulf_front = maxf(0.0, p.engulf_front - dt * 2.5)
			continue
		var dx := m.global_position.x - sp.x
		var dz := m.global_position.z - sp.z
		var d := maxf(Vector2(dx, dz).length(), 1e-4)
		var dir := Vector3(dx / d, 0.0, dz / d)
		var ro := _horizontal_reach(p, -dir, foot.y)
		var gap := d - (vis_r + ro)
		var target := maxf(0.0, -gap)
		var v_check := s.pre_move_velocity if s.pre_move_velocity.length_squared() > s.motor.velocity.length_squared() else s.motor.velocity
		var inward_speed := v_check.x * dir.x + v_check.z * dir.z

		var size_ratio := clampf(_prop_size_ratio(s, p) / 0.78, 0.0, 1.0)
		var size_resistance := clampf((size_ratio - 0.16) / 0.84, 0.0, 1.0)

		var in_contact := gap <= 0.15
		var actively_pushing := in_contact and inward_speed > 0.08
		if not actively_pushing:
			if p.last_presser == s:
				var pushback_rate := lerpf(1.6, 3.8, size_resistance)
				if p.engulf_front > 0.01 and size_resistance > 0.12 and in_contact:
					var recoil := (1.2 + 3.2 * size_resistance) * p.engulf_front
					s.motor.velocity -= dir * (recoil * dt)
				p.engulf_front = maxf(0.0, p.engulf_front - dt * pushback_rate)
				var acc_r := 140.0 * (0.0 - p.pd) - 8.0 * p.pv
				p.pv += acc_r * sdt
				p.pd += p.pv * sdt
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
		var thr := ro * (0.85 + 0.45 * size_ratio) + 0.1 * S
		var press_depth := maxf(target, 0.12 - gap)
		var acc := 140.0 * (press_depth - p.pd) - 8.0 * p.pv
		p.pv += acc * sdt
		p.pd += p.pv * sdt
		if p.pd < 0.0:
			p.pd = 0.0
			if p.pv < 0.0:
				p.pv = 0.0
		p.p_ro = ro
		p.p_thr = thr

		# Heavy resistance: near-slime-size objects resist inward push speed and require sustained effort
		var resist_curve := pow(size_resistance, 1.35)
		if size_resistance > 0.05:
			var allowed_inward := lerpf(s.cur_max, s.cur_max * 0.10, resist_curve)
			var cur_in := s.motor.velocity.dot(dir)
			if cur_in > allowed_inward:
				s.motor.velocity -= dir * (cur_in - allowed_inward)
			# Physical wall resistance before the engulf front opens
			var resist_standoff := vis_r * lerpf(0.25, 0.85, resist_curve) * (1.0 - p.engulf_front * 0.80) + ro
			if d < resist_standoff:
				var push_out := minf(resist_standoff - d, 0.06)
				s.motor.apply_slime_separation(-dir * push_out, -dir)

		var advance_rate := lerpf(3.2, 0.25, pow(size_resistance, 1.15))
		p.engulf_front = minf(1.0, p.engulf_front + advance_rate * dt)

		if p.engulf_front >= 0.95:
			_begin_eating(p, s)

	var pressing_list: Array[PropData] = []
	for p in nearby:
		if p.last_presser == s and p.engulf_front > 0.01:
			pressing_list.append(p)
	s.pressing_props = pressing_list


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
	return _measure_pair_geometry(a, b)


## Slime-independent corridor geometry for one pair: `{}` unless the two faces are
## genuinely opposing and overlap along the flow direction. Used both by the live
## measurement (which adds the body's vertical band) and by the spawn-time pair cache.
func _measure_pair_geometry(a: PropData, b: PropData) -> Dictionary:
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
	var move_dir := Vector3(s.motor.velocity.x, 0.0, s.motor.velocity.z)
	var moving := move_dir.length() > 0.05
	if not moving:
		return {}
	move_dir = move_dir.normalized()

	# A nearly stationary clone does not need a fresh hint every tick; four ticks
	# still latch long before intent can build up speed.
	if s.role != Slime.Role.PLAYER and Engine.get_physics_frames() % 4 != 0:
		return {}
	var result: Dictionary = {}
	var S := s.model.scale
	var rest_radius := s.model.rest_max_radius * S
	var stretch_max := 1.0 + (1.0 - tuning.min_liquid_squeeze) * tuning.squeeze_elongation
	var reach := rest_radius * maxf(s.model.spread, tuning.liquid_spread_ratio) * stretch_max

	var near := query_nearby_props(Vector2(s.global_position.x, s.global_position.z), reach * 3.0 + 3.0)
	var near_set := {}
	for p in near:
		near_set[p] = true

	var sp := Vector3(s.global_position.x, 0.0, s.global_position.z)
	var best_score := -INF

	for pair in _candidate_passage_pairs:
		var a: PropData = pair["a"]
		var b: PropData = pair["b"]
		if not near_set.has(a) or not near_set.has(b):
			continue
		if is_edible_by_push(s, a) or is_edible_by_push(s, b):
			continue
		var m := measure_passage_pair(s, a, b)
		if not m.is_empty():
			var w: float = m["width"]
			# Squeeze passages are only for gaps genuinely narrower than the rest body.
			# Wide openings (wider than the rest body) do not squeeze the slime into an oval.
			if w >= 2.0 * rest_radius - 2.0 * tuning.skin:
				continue
			var flow: Vector3 = m["flow"]
			var half_length: float = m["half_length"]
			var center: Vector3 = m["center"]
			var to_gap := center - sp
			if to_gap.length() > reach * 1.15 + half_length + 0.5:
				continue
			if moving and to_gap.dot(move_dir) < 0.1:
				continue
			var score := 1.0 / (1.0 + to_gap.length()) + ((absf(move_dir.dot(flow)) * 2.0) if moving else 0.5)
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
	# Springs are integrated with a clamped step so one long frame cannot explode
	# them; their visual response is far faster than 30 Hz anyway.
	var sdt := minf(dt, 1.0 / 30.0)
	var since := s.time - s.touch_time
	var is_pushing := s.motor.velocity.length_squared() > 0.1
	var tgt := 0.20 if since < 0.15 else (0.12 if (since < 0.4 and is_pushing) else 0.0)

	var ks := 120.0 if s.splat_v > 0.0 else 40.0
	s.splat_v += (ks * (tgt - s.splat_x) - 2.0 * sqrt(ks) * s.splat_v) * sdt
	s.splat_x = clampf(s.splat_x + s.splat_v * sdt, 0.0, 1.1)
	if s.splat_x == 0.0 and s.splat_v < 0.0:
		s.splat_v = 0.0

	var kp := 70.0 if s.splat_x > s.spread_x else 22.0
	s.spread_v += (kp * (s.splat_x - s.spread_x) - 2.0 * sqrt(kp) * s.spread_v) * sdt
	s.spread_x = maxf(0.0, s.spread_x + s.spread_v * sdt)
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
	# Backward so a finished prop can leave both lists in place.
	for i in range(active_eating_props.size() - 1, -1, -1):
		var p: PropData = active_eating_props[i]
		# The entry outlives the node if the prop was freed externally (world rebuild,
		# test fixture teardown); digestion itself keeps ticking on the data object.
		var mesh_ok := p.mesh != null and is_instance_valid(p.mesh)
		p.t += dt
		p.pd = maxf(0.0, p.pd * exp(-10.0 * dt))
		p.pv = maxf(0.0, p.pv * exp(-10.0 * dt))
		var k := minf(p.t / tuning.eat_time, 1.0)
		var e := k * k * (3.0 - 2.0 * k)
		var dis := maxf(0.0, 1.0 - maxf(0.0, p.t - tuning.eat_time) / tuning.eat_linger)
		var shrink := maxf(0.001, (1.0 - 0.35 * e) * (0.65 + 0.35 * dis))
		if mesh_ok:
			p.mesh.scale = p.base_scale * shrink
			if p.material != null and is_instance_valid(p.material):
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
				if mesh_ok:
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
			if p.mesh != null and is_instance_valid(p.mesh):
				p.mesh.queue_free()
			# Drop every reference now: the node is only freed at the end of the frame,
			# and a state entry pointing at a freed mesh is worse than no entry at all.
			p.mesh = null
			p.body = null
			p.collider = null
			p.material = null
			p.state = STATE_GONE
			active_eating_props.remove_at(i)
			props.erase(p)


func _update_inside_props(s: Slime, dt: float) -> void:
	var center := s.model.center()
	for item in s.inside_props:
		var p: PropData = item as PropData
		if p == null or p.mesh == null or not is_instance_valid(p.mesh):
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

func _update_eat_uniforms(s: Slime, dt: float) -> void:
	s.press_amt = lerpf(s.press_amt, 0.0, 1.0 - exp(-15.0 * dt))
	s.set_shader_param("uPressAmt", s.press_amt)
	s.calm = lerpf(s.calm, 0.0, 1.0 - exp(-12.0 * dt))


func _update_solid_uniforms(s: Slime, use_visual_body := false) -> void:
	if s.model == null:
		return
	var S := maxf(s.model.scale, 1e-4)
	if use_visual_body and s.body != null:
		S = maxf(s.slime_scale * s.body.scale.x, 1e-4)
	var sp := s.body.global_position if (use_visual_body and s.body != null) else s.global_position
	var foot_y := sp.y - s.model.rest_half_height * S
	var top_y := foot_y + s.model.rest_full_height * S
	for i in 8:
		_solid_pos_buf[i] = Vector3.ZERO
		_solid_param_buf[i] = Vector3.ZERO
		_solid_half_buf[i] = Vector3(0.01, 0.01, 0.01)
		_solid_dir_buf[i] = Vector3.ZERO

	var vis_r := s.model.rest_max_radius * S * s.model.spread
	var candidates: Array = []
	for p in query_nearby_props(Vector2(sp.x, sp.z), vis_r + 5.0):
		if p.state != STATE_IDLE or p.mesh == null or not is_instance_valid(p.mesh):
			continue
		var he := _half_of(p)
		var m := p.mesh.global_position
		if m.y - he.y > top_y + 0.3 or m.y + he.y < foot_y - 0.1:
			continue
		var cn := _closest_and_normal(p, Vector3(sp.x, m.y, sp.z))
		var pt: Vector3 = cn["point"]
		var surf_dist := Vector2(pt.x - sp.x, pt.z - sp.z).length()
		if surf_dist <= vis_r + 0.80:
			candidates.append({"prop": p, "dist": surf_dist, "cn": cn})

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["dist"]) < float(b["dist"]))
	var count := mini(candidates.size(), 8)
	for i in count:
		var entry: Dictionary = candidates[i]
		var p: PropData = entry["prop"]
		var cn: Dictionary = entry["cn"]
		var n_out: Vector3 = cn["normal"]
		var m := p.mesh.global_position
		_solid_pos_buf[i] = (m - sp) / S
		_solid_dir_buf[i] = Vector3(-n_out.x, 0.0, -n_out.z)
		var weight := 1.0
		if is_edible_by_push(s, p) and p.last_presser == s and p.engulf_front > 0.01:
			weight = clampf(1.0 - pow(p.engulf_front, 1.5) * 0.85, 0.15, 1.0)
		_solid_param_buf[i] = Vector3(float(p.shape) + p.sides * 0.01, weight, p.mesh.rotation.y + p.phase)
		_solid_half_buf[i] = _box_half(p, S)

	if s._mat != null:
		s._mat.set_shader_parameter("uSolidPos", _solid_pos_buf)
		s._mat.set_shader_parameter("uSolidParam", _solid_param_buf)
		s._mat.set_shader_parameter("uSolidHalf", _solid_half_buf)
		s._mat.set_shader_parameter("uSolidDir", _solid_dir_buf)


func _update_floor_shadows() -> void:
	if _floor_mat == null:
		return
	var candidates: Array[Slime] = []
	for s in registered_slimes:
		if is_instance_valid(s) and s.model != null:
			candidates.append(s)
	# Only 8 blobs fit the shader. Pick the ones nearest the camera so clones in
	# view keep their shadow instead of the first eight registered.
	if candidates.size() > 8:
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var cam_pos := cam.global_position
			candidates.sort_custom(func(a: Slime, b: Slime) -> bool:
				return a.global_position.distance_squared_to(cam_pos) < b.global_position.distance_squared_to(cam_pos))
		candidates.resize(8)

	for i in 8:
		if i < candidates.size():
			var s := candidates[i]
			_blob_pos_buf[i] = s.global_position
			_blob_scale_buf[i] = s.model.scale * s.model.spread
		else:
			_blob_pos_buf[i] = Vector3.ZERO
			_blob_scale_buf[i] = 0.0

	_set_floor_param("uBlobCount", candidates.size())
	_set_floor_param("uBlobPos", _blob_pos_buf)
	_set_floor_param("uBlobScale", _blob_scale_buf)


func _set_floor_param(param: StringName, value: Variant) -> void:
	var prev = _floor_param_cache.get(param)
	if prev != null and prev == value:
		return
	_floor_param_cache[param] = value
	_floor_mat.set_shader_parameter(param, value)


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
	return _spawned_total