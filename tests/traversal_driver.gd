extends Node
## Deterministic acceptance fixtures for the traversal refactor.
##
## Each phase teleports the player to a known spot, builds plain obstacle colliders
## on LAYER_OBSTACLES, presses real input actions, then asserts on resolved state
## and on a real overlap query (no penetration is ever accepted).

const LAYER_OBSTACLES := 1

var main: Node
var slime: Slime
var props: SlimeProps
var rig: OrbitCamera
var fixtures: Array = []

var phase := -1
var phase_t := 0.0
var phase_len := 0.0
var failures: Array[String] = []

# Per-phase metrics for the player.
var p_min_z := INF
var p_max_z := -INF
var p_min_sweep := 1.0
var p_min_squeeze := 1.0
var p_max_liquid := 0.0
var p_max_blocked := ""

var follower: Slime = null
var roamer: Slime = null
var _frames := 0
var _checks := 0
var _initial_volume := 0.0
var _volume_before_merge := 0.0
var _merge_count_before := 0
var _pre_split_scale := 1.0
var p_bud_vol_err := 0.0

# Per-tick invariants (F.2/F.4). These run every frame for every live slime.
var _last_positions: Dictionary = {}
var _seen_invariants: Dictionary = {}
var p_max_margin_hits := 0
var p_max_hstep := 0.0
var p_min_squeeze_ratio := 1.0
var p_max_spread_err := 0.0
var _invariant_failures := 0


func _ready() -> void:
	main = get_parent()
	slime = main.get_node_or_null("Slime") as Slime
	props = main.get_node_or_null("Ecosystem") as SlimeProps
	rig = main.get_node_or_null("CameraRig") as OrbitCamera
	if slime == null or props == null or rig == null:
		push_error("traversal_driver: main scene is missing Slime/Ecosystem/CameraRig")
		get_tree().quit(2)
		return

	# Remove the randomized world and the built-in test structures: fixtures are explicit.
	var generated := props.get_node_or_null("Generated")
	if generated != null:
		generated.free()
	props.props.clear()
	props.eaten = 0

	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("run")
	Input.action_release("slime_liquid")

	_initial_volume = slime.get_volume()
	_next_phase()


func _physics_process(delta: float) -> void:
	if slime == null or not is_instance_valid(slime):
		return
	_frames += 1
	if _frames > 4000:
		print("TRAVERSAL RESULT: FAIL (frame guard tripped at phase %d)" % phase)
		get_tree().quit(3)
		return
	phase_t += delta

	# Z is pressed mid-approach, not at the start: the squeeze must engage while moving.
	if phase == 3 and phase_t >= 0.6 and not Input.is_action_pressed("slime_liquid"):
		_press("slime_liquid", true)

	p_min_z = minf(p_min_z, slime.global_position.z)
	p_max_z = maxf(p_max_z, slime.global_position.z)
	p_min_sweep = minf(p_min_sweep, slime.motor.last_sweep_fraction)
	p_min_squeeze = minf(p_min_squeeze, slime.squeeze_k)
	p_max_liquid = maxf(p_max_liquid, slime.liquid_amt)
	if slime.expansion_blocked != "":
		p_max_blocked = slime.expansion_blocked

	_track_invariants()

	if phase_t >= phase_len:
		_finish_phase()


# ------------------------------------------------------------------------------------------------
# Phases
# ------------------------------------------------------------------------------------------------

func _next_phase() -> void:
	phase += 1
	phase_t = 0.0
	p_min_z = INF
	p_max_z = -INF
	p_min_sweep = 1.0
	p_min_squeeze = 1.0
	p_max_liquid = 0.0
	p_max_blocked = ""
	p_bud_vol_err = 0.0

	match phase:
		0:
			# Settle.
			rig.theta = PI
			_reset_player(Vector3.ZERO)
			phase_len = 0.4
		1:
			# Plain wall: press into it. Must stop with no penetration.
			_clear_fixtures()
			_add_box(Vector3(0.0, _floor() + 1.0, 6.0), Vector3(8.0, 2.0, 0.8))
			_reset_player(Vector3.ZERO)
			_press("move_forward", true)
			phase_len = 2.2
		2:
			# 1.4 m gate with no Z: too wide to fit.
			_clear_fixtures()
			_build_gate(6.0, 1.4)
			_reset_player(Vector3.ZERO)
			_press("move_forward", true)
			phase_len = 3.0
		3:
			# Same gate with Z held: squash + squeeze must carry it through.
			_reset_player(Vector3.ZERO)
			_press("move_forward", true)
			phase_len = 5.6
		4:
			# 0.5 m gate: below the legal minimum width, must stay blocked.
			_clear_fixtures()
			_build_gate(6.0, 0.5)
			_reset_player(Vector3.ZERO)
			_press("move_forward", true)
			_press("slime_liquid", true)
			phase_len = 3.0
		5:
			# Low roof: enter flat, then release Z underneath it.
			_clear_fixtures()
			_add_box(Vector3(0.0, _floor() + 1.05, 6.0), Vector3(4.0, 0.3, 4.0))
			_reset_player(Vector3.ZERO)
			_press("move_forward", true)
			_press("slime_liquid", true)
			phase_len = 2.8
		6:
			_press("move_forward", false)
			_press("slime_liquid", false)
			phase_len = 2.0
		7:
			# Split a follower, then lead it through the 1.4 m gate.
			_clear_fixtures()
			_build_gate(6.0, 1.4)
			_reset_player(Vector3.ZERO)
			_press("slime_liquid", false)
			_press("move_forward", false)
			_pre_split_scale = slime.slime_scale
			slime.split_clone(Slime.Role.FOLLOWER)
			phase_len = 0.7
		8:
			follower = _find_role(Slime.Role.FOLLOWER)
			_press("move_forward", true)
			_press("slime_liquid", true)
			# A liquid squeeze stretches the body lengthwise, so the leader's tail stays
			# in the gate for seconds before the follower can close up behind it.
			phase_len = 12.0
		9:
			# Roamer: leaves Z, wanders on its own.
			_press("move_forward", false)
			_press("slime_liquid", false)
			_reset_player(Vector3.ZERO, false)
			slime.split_clone(Slime.Role.ROAMER)
			phase_len = 3.0
		10:
			# Merge every clone back: volume must be conserved exactly.
			# Merging requires normal posture, so normalize the clones first.
			_volume_before_merge = _total_volume()
			if follower != null and is_instance_valid(follower):
				# Keep each clone's foot on the floor: clones no longer share the
				# player's scale, so copying its center height would bury them.
				follower.global_position = Vector3(
					slime.global_position.x + 2.2,
					_floor() + follower.model.rest_half_height * follower.slime_scale,
					slime.global_position.z)
				_normalize_posture(follower)
			roamer = _find_role(Slime.Role.ROAMER)
			if roamer != null and is_instance_valid(roamer):
				roamer.global_position = Vector3(
					slime.global_position.x - 2.2,
					_floor() + roamer.model.rest_half_height * roamer.slime_scale,
					slime.global_position.z)
				_normalize_posture(roamer)
			slime.merge_nearby_clones()
			_last_positions.clear()
			phase_len = 1.6
		11:
			# Engulf: an edible prop under the puddle is devoured only with Z held.
			_clear_fixtures()
			_reset_player(Vector3.ZERO)
			_add_edible_box(Vector3(0.0, _floor() + 0.25, 2.5), Vector3(0.5, 0.5, 0.5))
			_press("slime_liquid", true)
			phase_len = 5.0
		12:
			# Split with a wall half a metre behind the body: the spawn preflight must
			# pick a free direction, and the volume curve must conserve the pair.
			_clear_fixtures()
			_reset_player(Vector3.ZERO)
			_press("slime_liquid", false)
			_press("move_forward", false)
			_add_box(Vector3(0.0, _floor() + 1.5, 2.9), Vector3(8.0, 3.0, 0.8))
			_pre_split_scale = slime.slime_scale
			slime.split_clone(Slime.Role.ROAMER)
			phase_len = 0.9
		13:
			# Split cleanly in the open so the merge test below starts from a known pair.
			_clear_fixtures()
			_reset_player(Vector3.ZERO)
			_press("slime_liquid", false)
			_press("move_forward", false)
			slime.split_clone(Slime.Role.ROAMER)
			phase_len = 0.9
		14:
			# A wall stands between the pair: the swept merge path must refuse, and no
			# volume may move without contact.
			_clear_fixtures()
			_reset_player(Vector3.ZERO, false)
			roamer = _find_role(Slime.Role.ROAMER)
			# Park any other clones out of merge range so only the walled pair is tested.
			for s in props.registered_slimes:
				if s != slime and s != roamer and is_instance_valid(s):
					s.global_position = Vector3(80.0, _floor() + s.model.rest_half_height * s.slime_scale, 80.0)
					_normalize_posture(s)
			_add_box(Vector3(0.0, _floor() + 1.5, 3.0), Vector3(8.0, 3.0, 0.4))
			if roamer != null and is_instance_valid(roamer):
				roamer.global_position = Vector3(0.0, _floor() + roamer.model.rest_half_height * roamer.slime_scale, 6.0)
				_normalize_posture(roamer)
			_merge_count_before = props.registered_slimes.size()
			_volume_before_merge = _total_volume()
			slime.merge_nearby_clones()
			phase_len = 1.0
		_:
			_report()
			return


func _finish_phase() -> void:
	match phase:
		0:
			_expect(_overlap(slime) == 0, "settle: body overlaps no obstacle (got %d)" % _overlap(slime))
		1:
			_expect(slime.global_position.z < 5.4, "wall: stopped before the wall (z=%.2f)" % slime.global_position.z)
			_expect(p_min_sweep < 0.99, "wall: sweep actually blocked (min fraction %.2f)" % p_min_sweep)
			_expect(_overlap(slime) == 0, "wall: no penetration")
		2:
			_expect(slime.global_position.z < 4.6, "gate-1.4/no-Z: blocked (z=%.2f)" % slime.global_position.z)
			_expect(_overlap(slime) == 0, "gate-1.4/no-Z: no penetration")
		3:
			_expect(slime.global_position.z > 7.4, "gate-1.4/Z: passed through (z=%.2f)" % slime.global_position.z)
			_expect(p_min_squeeze < 0.45, "gate-1.4/Z: squeezed (min %.2f)" % p_min_squeeze)
			_expect(_overlap(slime) == 0, "gate-1.4/Z: no penetration")
		4:
			_expect(slime.global_position.z < 4.6, "gate-0.5/Z: impossible gap stays blocked (z=%.2f)" % slime.global_position.z)
			_expect(p_min_squeeze >= 0.115, "gate-0.5/Z: squeeze never forced below the legal minimum (%.3f)" % p_min_squeeze)
			_expect(_overlap(slime) == 0, "gate-0.5/Z: no penetration")
		5:
			_expect(slime.global_position.z > 3.6, "roof: entered the tunnel (z=%.2f)" % slime.global_position.z)
			_expect(p_max_liquid > 0.85, "roof: entered flat (liquid max %.2f)" % p_max_liquid)
			_expect(_overlap(slime) == 0, "roof: no penetration while entering")
		6:
			_expect(slime.liquid_amt > 0.4, "roof/release: stayed flat under the ceiling (liquid %.2f)" % slime.liquid_amt)
			_expect(slime.height_ratio < 0.55, "roof/release: height clamped (ratio %.2f)" % slime.height_ratio)
			_expect(p_max_blocked.contains("overhead"), "roof/release: stand-up reported as ceiling-blocked ('%s')" % p_max_blocked)
			_expect(_overlap(slime) == 0, "roof/release: no penetration on stand-up attempt")
		7:
			follower = _find_role(Slime.Role.FOLLOWER)
			_expect(follower != null, "split: follower exists")
			_expect(p_bud_vol_err < 0.01, "split: volume budget conserved (max err %.4f)" % p_bud_vol_err)
		8:
			if follower != null and is_instance_valid(follower):
				_expect(follower.global_position.z > 7.0, "follower: passed the gate (z=%.2f)" % follower.global_position.z)
				_expect(_overlap(follower) == 0, "follower: no penetration")
			else:
				_expect(false, "follower: exists after following")
		9:
			roamer = _find_role(Slime.Role.ROAMER)
			_expect(absf(_total_volume() - _initial_volume) < 1e-3, "split: volume conserved (%.4f vs %.4f)" % [_total_volume(), _initial_volume])
			if roamer != null and is_instance_valid(roamer):
				var p := roamer.global_position
				_expect(not (is_nan(p.x) or is_nan(p.y) or is_nan(p.z)), "roamer: finite position")
				_expect(p.y > _floor() - 0.5, "roamer: did not sink (y=%.2f)" % p.y)
				_expect(_overlap(roamer) == 0, "roamer: no penetration")
			else:
				_expect(false, "roamer: exists")
		10:
			_expect(absf(_total_volume() - _volume_before_merge) < 1e-3, "merge: volume conserved (%.4f vs %.4f)" % [_total_volume(), _volume_before_merge])
			_expect(props.registered_slimes.size() == 1, "merge: all clones absorbed (%d slimes: %s)" % [props.registered_slimes.size(), _describe_slimes()])
			_expect(_overlap(slime) == 0, "merge: no penetration")
		11:
			var absorbed := slime.get_volume() - _initial_volume
			_expect(props.eaten == 1, "engulf: prop devoured with Z held (eaten %d)" % props.eaten)
			_expect(absorbed > 0.1, "engulf: digested mass reached the slime (+%.3f m³)" % absorbed)
			_expect(_overlap(slime) == 0, "engulf: no penetration")
		12:
			var clone := _find_role(Slime.Role.ROAMER)
			_expect(clone != null, "wall-split: clone spawned in a free direction")
			_expect(not slime.is_fissioning, "wall-split: animation completed")
			_expect(p_bud_vol_err < 0.01, "wall-split: volume budget conserved (max err %.4f)" % p_bud_vol_err)
			if clone != null and is_instance_valid(clone):
				_expect(_overlap(clone) == 0, "wall-split: clone clear of geometry")
		13:
			roamer = _find_role(Slime.Role.ROAMER)
			_expect(roamer != null, "merge-wall: roamer ready")
		14:
			_expect(props.registered_slimes.size() == _merge_count_before, "merge-wall: nothing absorbed (%d, was %d: %s)" % [props.registered_slimes.size(), _merge_count_before, _describe_slimes()])
			_expect(absf(_total_volume() - _volume_before_merge) < 1e-3, "merge-wall: no volume moved without contact")
			if roamer != null and is_instance_valid(roamer):
				_expect(not roamer.is_merging, "merge-wall: blocked path refuses the merge")
				_expect(_overlap(roamer) == 0, "merge-wall: no penetration")
			else:
				_expect(false, "merge-wall: roamer survived")
	_next_phase()


# ------------------------------------------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------------------------------------------

func _floor() -> float:
	return props.tuning.floor_y


func _add_box(center: Vector3, size: Vector3) -> void:
	# Fixtures are full PropData so the slime's passage detector sees them exactly
	# like authored world geometry (a raw StaticBody3D would be collision-only).
	var p := SlimeProps.PropData.new()
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = center
	props.add_child(mi)
	p.mesh = mi
	p.shape = SlimeProps.SHAPE_BOX
	p.half = size * 0.5
	p.radius = maxf(size.x, size.z) * 0.5
	p.fp = p.radius
	p.is_static = true
	p.base_scale = mi.scale
	p.calc_real_volume()
	props._attach_collider(p)
	props.props.append(p)
	fixtures.append(p)


func _add_edible_box(center: Vector3, size: Vector3) -> void:
	var p := SlimeProps.PropData.new()
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.position = center
	props.add_child(mi)
	p.mesh = mi
	p.shape = SlimeProps.SHAPE_BOX
	p.half = size * 0.5
	p.radius = maxf(size.x, size.z) * 0.5
	p.fp = p.radius
	p.is_static = false
	p.base_scale = mi.scale
	p.calc_real_volume()
	props._attach_collider(p)
	props.props.append(p)
	fixtures.append(p)


func _normalize_posture(s: Slime) -> void:
	s.liquid_request = false
	s.engulf_request = false
	s.liquid_amt = 0.0
	s.height_ratio = 1.0
	s.squeeze_k = 1.0
	s.squeeze_v = 0.0
	s.model.resolve(s.slime_scale, 0.0, 1.0, 1.0, s.sq_dir)
	s._apply_transform()
	s.motor.velocity = Vector3.ZERO
	s.motor.vertical_vel = 0.0
	s.motor.recover_overlap()
	s.motor.update_support()
	s.motor.move_vertical(1.0 / 60.0, s.slime_scale)


func _total_volume() -> float:
	var v := 0.0
	for s in props.registered_slimes:
		if is_instance_valid(s):
			v += s.get_volume()
	return v


func _describe_slimes() -> String:
	var parts: Array[String] = []
	for s in props.registered_slimes:
		if is_instance_valid(s):
			parts.append("%s scale=%.3f z=%.2f" % [Slime.Role.keys()[s.role], s.target_scale, s.global_position.z])
	return ", ".join(parts)


func _build_gate(z: float, gap: float) -> void:
	var pillar := 1.2
	var cx := gap * 0.5 + pillar * 0.5
	_add_box(Vector3(-cx, _floor() + 1.5, z), Vector3(pillar, 3.0, 0.8))
	_add_box(Vector3(cx, _floor() + 1.5, z), Vector3(pillar, 3.0, 0.8))


func _clear_fixtures() -> void:
	for f in fixtures:
		var p: SlimeProps.PropData = f
		props.props.erase(p)
		if p.mesh != null and is_instance_valid(p.mesh):
			p.mesh.free()
	fixtures.clear()


func _reset_player(flat_pos: Vector3, reset_scale := true) -> void:
	_last_positions.clear()
	Input.action_release("move_forward")
	Input.action_release("move_back")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("slime_liquid")

	slime.liquid_request = false
	slime.engulf_request = false
	slime.liquid_amt = 0.0
	slime.height_ratio = 1.0
	slime.squeeze_k = 1.0
	slime.squeeze_v = 0.0
	if reset_scale:
		slime.target_scale = 1.0
		slime.slime_scale = 1.0
	slime.model.resolve(slime.slime_scale, 0.0, 1.0, 1.0, slime.sq_dir)
	slime._apply_transform()
	slime.motor.velocity = Vector3.ZERO
	slime.motor.vertical_vel = 0.0
	var y := _floor() + props.tuning.skin + slime.model.rest_half_height * slime.slime_scale
	slime.global_position = Vector3(flat_pos.x, y, flat_pos.z)
	slime.motor.recover_overlap()
	slime.motor.update_support()
	slime.motor.move_vertical(1.0 / 60.0, slime.slime_scale)


func _press(action: StringName, pressed: bool) -> void:
	if pressed:
		Input.action_press(action, 1.0)
	else:
		Input.action_release(action)


# ------------------------------------------------------------------------------------------------
# Assertions / reporting
# ------------------------------------------------------------------------------------------------

func _track_invariants() -> void:
	var next_positions: Dictionary = {}
	for s in _all_slimes():
		var id := s.get_instance_id()
		var pos := s.global_position
		next_positions[id] = pos

		if _last_positions.has(id):
			var prev: Vector3 = _last_positions[id]
			var moved := Vector2(pos.x - prev.x, pos.z - prev.z).length()
			p_max_hstep = maxf(p_max_hstep, moved)
			if not (s.is_merging or s.is_budding or s.is_fissioning):
				var cap := s.model.rest_max_radius * s.model.scale * props.tuning.max_step_fraction
				if moved > cap + 0.06:
					_invariant("step", "horizontal step %.3f m exceeds motor cap %.3f m (phase %d)" % [moved, cap, phase])

		var min_sq := lerpf(props.tuning.min_normal_squeeze, props.tuning.min_liquid_squeeze, s.liquid_amt)
		p_min_squeeze_ratio = minf(p_min_squeeze_ratio, s.squeeze_k / maxf(min_sq, 1e-4))
		if s.squeeze_k < min_sq - 1e-3 or s.squeeze_k > 1.0 + 1e-3:
			_invariant("squeeze", "squeeze %.3f outside [%.3f, 1] (phase %d)" % [s.squeeze_k, min_sq, phase])

		if s.liquid_amt > 0.05:
			var fill := s.model.spread * s.model.spread * s.model.height_ratio
			p_max_spread_err = maxf(p_max_spread_err, absf(fill - 1.0))
			if absf(fill - 1.0) > 0.005:
				_invariant("spread", "spread^2*height %.4f != 1 at liquid %.2f (phase %d)" % [fill, s.liquid_amt, phase])

		if s == slime and s.is_fissioning and s.fission_clone != null and is_instance_valid(s.fission_clone):
			var pair_vol := pow(s.slime_scale, 3.0) + pow(s.fission_clone.slime_scale, 3.0)
			var ref_vol := pow(_pre_split_scale, 3.0)
			var err := absf(pair_vol - ref_vol) / maxf(ref_vol, 1e-6)
			p_bud_vol_err = maxf(p_bud_vol_err, err)

		var hits := _overlap_margin(s, 0.04)
		p_max_margin_hits = maxi(p_max_margin_hits, hits)
		if hits > 0:
			_invariant("penetration", "obstacle penetration deeper than 4 cm at (%.2f, %.2f, %.2f) scale %.2f foot %.2f liquid %.2f, phase %d" % [pos.x, pos.y, pos.z, s.model.scale, s.model.foot.y, s.model.liquid, phase])

	_last_positions = next_positions


func _all_slimes() -> Array[Slime]:
	var out: Array[Slime] = []
	for s in props.registered_slimes:
		if is_instance_valid(s):
			out.append(s)
	return out


## One failure line per invariant kind; the count still reflects every occurrence.
func _invariant(kind: String, label: String) -> void:
	_invariant_failures += 1
	if _seen_invariants.has(kind):
		return
	_seen_invariants[kind] = true
	failures.append(label)


## Names of bodies the candidate squeeze posture would hit (diagnostics only).
func _overlap_margin(s: Slime, margin: float) -> int:
	# Probe an envelope eroded by `margin`: a hit means penetration deeper than that.
	if s == null or not is_instance_valid(s) or s.model == null:
		return 0
	var src := s.model.baked_points(s.model.scale, s.model.liquid, s.model.height_ratio, s.model.squeeze, s.model.axis)
	var pts := PackedVector3Array()
	var top := maxf(0.0, s.model.full_height - margin)
	for p in src:
		var r := Vector2(p.x, p.z).length()
		var f := maxf(0.0, r - margin) / maxf(r, 1e-5)
		pts.append(Vector3(p.x * f, minf(p.y, top), p.z * f))
	var probe := ConvexPolygonShape3D.new()
	probe.set_points(pts)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, s.model.foot)
	q.collision_mask = LAYER_OBSTACLES
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var res := s.get_world_3d().direct_space_state.intersect_shape(q, 8)
	return res.size()


func _overlap(s: Slime) -> int:
	# Probe at 99.5% of the resolved envelope: sweep-then-slide deliberately parks the
	# body flush against contacts, and a flush touch is not penetration.
	if s == null or not is_instance_valid(s) or s.model == null:
		return 0
	var probe := ConvexPolygonShape3D.new()
	probe.set_points(s.model.baked_points(s.model.scale * 0.995, s.model.liquid, s.model.height_ratio, s.model.squeeze, s.model.axis))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = probe
	q.transform = Transform3D(Basis.IDENTITY, s.model.foot)
	q.collision_mask = LAYER_OBSTACLES
	q.collide_with_bodies = true
	q.collide_with_areas = false
	return s.get_world_3d().direct_space_state.intersect_shape(q, 8).size()


func _find_role(r: Slime.Role) -> Slime:
	for s in props.registered_slimes:
		if is_instance_valid(s) and s != slime and s.role == r:
			return s
	return null


func _expect(ok: bool, label: String) -> void:
	_checks += 1
	if ok:
		print("  PASS  ", label)
	else:
		print("  FAIL  ", label)
		failures.append(label)


func _report() -> void:
	_expect(p_max_margin_hits == 0, "invariant: no obstacle penetration deeper than 4 cm (%d hits)" % p_max_margin_hits)
	_expect(p_min_squeeze_ratio >= 0.999, "invariant: squeeze never below the posture minimum (min ratio %.3f)" % p_min_squeeze_ratio)
	_expect(p_max_spread_err <= 0.005, "invariant: liquid spread^2*height = 1 (max deviation %.4f)" % p_max_spread_err)
	print("")
	print("  metrics: max horizontal step %.3f m, margin hits %d, invariant failures %d" % [p_max_hstep, p_max_margin_hits, _invariant_failures])
	if failures.is_empty():
		print("TRAVERSAL RESULT: PASS (%d checks)" % _checks)
		get_tree().quit(0)
	else:
		print("TRAVERSAL RESULT: FAIL (%d failures / %d checks)" % [failures.size(), _checks])
		for f in failures:
			print("  - ", f)
		get_tree().quit(1)
