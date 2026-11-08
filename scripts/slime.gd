class_name Slime
extends Node3D
## One jelly slime. Intent -> validated posture -> motor movement -> derived visuals.
##
## This script never writes its own position: SlimeMotor owns the transform, support
## and collision resolution; SlimeShapeModel owns the authoritative dimensions;
## SlimeProps exposes obstacle geometry, passage hints and digestion.

signal poked(local_point: Vector3, impulse: Vector3)

enum Role {
	PLAYER,
	FOLLOWER,
	ROAMER
}

## Fallback when no tuning resource is assigned.
const LIQUID_BLEND_RATE := 2.8

@export var role: Role = Role.PLAYER
@export var tuning: SlimeTuning

@export_group("Nodes")
@export var body: MeshInstance3D
@export var camera: Camera3D
@export var floor_mesh: MeshInstance3D
@export var props: SlimeProps

@export_group("Agent")
## Spawn scale. Clones are created with their target scale already resolved.
@export var start_scale := 1.0
@export var target_leader: Slime = null

var model: SlimeShapeModel
var motor: SlimeMotor

var slime_scale := 1.0
var target_scale := 1.0
var speed01 := 0.0

# Intent (what the agent WANTS), kept separate from the resolved posture.
var liquid_request := false
var engulf_request := false
var liquid_mode: bool:
	get:
		return liquid_request
	set(value):
		liquid_request = value

# Resolved posture (what the world actually allows).
var liquid_amt := 0.0
var height_ratio := 1.0
var squeeze_k := 1.0
var squeeze_v := 0.0
var sq_dir := Vector3(1.0, 0.0, 0.0)
## Squeeze the passage session is asking for this tick (diagnostics / tests).
var sq_target := 1.0
var expansion_blocked := ""

# Motion/contact feedback used by the presentation layer only.
var cur_max := 3.0
var calm := 0.0
var touch_time := -10.0
var splat_x := 0.0
var splat_v := 0.0
var spread_x := 0.0
var spread_v := 0.0
var sharp_amt := 0.0
var contact_r := 2.15
var impact_dir := Vector3(0.0, 0.0, 1.0)
var press_amt := 0.0

# Last passage hint from the ecosystem (hint only; posture is query-validated).
var cur_gap_center := Vector2.ZERO
var cur_gap_w := INF
var cur_gap_dir := Vector2.ZERO
var _passage: Dictionary = {}
## Latched passage session: pair identity + a stable axis. The hint acquires; the
## session owns the lifetime, so the neck uniform cannot blink mid-gate and the
## axis cannot flip between two nearby candidate pairs.
var _passage_session: Dictionary = {}
var _passage_cooldown := 0.0

# Engulf drape state.
var engulf_target = null
var engulf_progress := 0.0

# ---- Fission (budding split) animation state ----
var is_fissioning := false
var fission_timer := 0.0
var fission_fwd := Vector3.FORWARD
var fission_start_scale := 1.0
var fission_target_scale := 1.0
var _fission_snapped := false

# CLONE budding state
var is_budding := false
var bud_timer := 0.0
var bud_parent: Slime = null
var bud_target_scale := 1.0
var bud_fwd := Vector3.FORWARD
## Pre-split scale: both bodies derive their scale from one shared volume budget.
var bud_start_scale := 1.0
## Centre distance chosen by the spawn preflight; the clone starts separated.
var bud_sep := 0.0
var bud_growth_blocked := false
var _bud_snapped := false
## Once snapped, collision stays off until the pair is provably apart.
var _bud_clear := false

# Merge animation state
var is_merging := false
var merge_target: Slime = null
var merge_timer := 0.0
var merge_source_scale := 1.0
var _has_merged := false

# Breadcrumb history for followers (recorded AFTER movement resolution).
var breadcrumbs: Array[Dictionary] = []
var _breadcrumb_timer := 0.0

# Props being digested inside the body.
var inside_props: Array = []

# AI state.
var _ai_roam_timer := 0.0
var _ai_recovery_timer := 0.0
var _ai_target_pos := Vector3.ZERO
var _ai_stuck_timer := 0.0
var _ai_last_pos := Vector3.ZERO
var _following_flatten := false
var _follower_stuck_timer := 0.0

var _mat: ShaderMaterial
var _time := 0.0
var _impulse_time := 10.0
var _impulse2_time := 10.0
var _crawl_dir := Vector3(0.0, 0.0, 1.0)
var _crawl_phase := 0.0
var _facing_yaw := 0.0
var _lean := Vector3.ZERO
var _lean_vel := Vector3.ZERO
var _velocity_cache := Vector3.ZERO
## Last committed posture that cleared the world, restored if a post-move check fails.
var _safe_posture: Array = []

## Baked-hull proxy on SlimeMotor.LAYER_SLIMES. It shares the model's shape resource,
## so every posture change is published to other slimes automatically.
var _proxy: StaticBody3D
var fission_clone: Slime = null

var time: float:
	get:
		return _time

var velocity: Vector3:
	get:
		return motor.velocity if motor != null else _velocity_cache
	set(value):
		if motor != null:
			motor.velocity = value
		else:
			_velocity_cache = value


# ------------------------------------------------------------------------------------------------
# Volume authority
# ------------------------------------------------------------------------------------------------

func get_volume() -> float:
	return tuning.volume_per_scale_cubed() * pow(target_scale, 3.0)


func set_volume(v: float) -> void:
	target_scale = pow(maxf(v, 0.0) / tuning.volume_per_scale_cubed(), 1.0 / 3.0)


func add_volume(delta: float) -> void:
	set_volume(get_volume() + delta)


# ------------------------------------------------------------------------------------------------
# Lifecycle
# ------------------------------------------------------------------------------------------------

func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/slime_tuning.tres") as SlimeTuning
	if props == null:
		props = get_node_or_null("../Ecosystem") as SlimeProps

	if body and body.material_override is ShaderMaterial:
		_mat = body.material_override.duplicate() as ShaderMaterial
		body.material_override = _mat
		_mat.set_shader_parameter("uMelt", tuning.melt)
		_reset_array_uniforms()

	if not is_budding:
		slime_scale = start_scale
		target_scale = start_scale
		_facing_yaw = tuning.start_facing
	elif target_scale <= 0.0:
		target_scale = start_scale

	model = SlimeShapeModel.new()
	model.configure(tuning)
	motor = SlimeMotor.new()
	motor.setup(self, model, tuning)
	motor.velocity = _velocity_cache

	model.resolve(slime_scale, 0.0, 1.0, 1.0, sq_dir)
	sq_dir = model.axis
	motor.support_y = tuning.floor_y
	global_position.y = tuning.floor_y + tuning.skin + model.rest_half_height * slime_scale
	model.set_foot(global_position + Vector3(0.0, -model.rest_half_height * slime_scale, 0.0))
	_apply_transform()
	_setup_proxy()

	if props:
		props.register_slime(self)


func _exit_tree() -> void:
	if props and is_instance_valid(props):
		props.unregister_slime(self)


func _setup_proxy() -> void:
	_proxy = StaticBody3D.new()
	_proxy.name = "SlimeProxy"
	_proxy.top_level = true
	_proxy.collision_layer = SlimeMotor.LAYER_SLIMES
	_proxy.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = model.shape
	_proxy.add_child(cs)
	add_child(_proxy)
	_sync_proxy()


## Publish the resolved footprint at the moment the motor last committed it.
func _sync_proxy() -> void:
	if _proxy == null or model == null:
		return
	var foot := global_position + Vector3(0.0, -model.rest_half_height * model.scale, 0.0)
	model.set_foot(foot)
	_proxy.global_transform = Transform3D(Basis.IDENTITY, foot)


func get_proxy_rid() -> RID:
	return _proxy.get_rid() if _proxy != null else RID()


## Own proxy + exempt partners + props this slime may pass through. Rebuilt before
## every posture probe and movement so it can never validate against a stale set.
func _refresh_exclusions() -> void:
	var rids: Array[RID] = []
	if _proxy != null:
		rids.append(_proxy.get_rid())
	rids.append_array(_exempt_rids())
	if props:
		rids.append_array(props.rids_edible_by(self))
	motor.set_exclude(rids)


## Partners this body intentionally overlaps while splitting, budding or merging.
func _exempt_rids() -> Array[RID]:
	var rids: Array[RID] = []
	if is_budding and bud_parent != null and is_instance_valid(bud_parent) \
			and not (_bud_snapped and _bud_clear):
		rids.append(bud_parent.get_proxy_rid())
	if is_fissioning and fission_clone != null and is_instance_valid(fission_clone) \
			and not (fission_clone._bud_snapped and fission_clone._bud_clear):
		rids.append(fission_clone.get_proxy_rid())
	if is_merging and merge_target != null and is_instance_valid(merge_target):
		rids.append(merge_target.get_proxy_rid())
	return rids


func _reset_array_uniforms() -> void:
	if _mat == null:
		return
	var zeros6 := PackedVector3Array()
	var small6 := PackedVector3Array()
	for i in 6:
		zeros6.append(Vector3.ZERO)
		small6.append(Vector3(0.01, 0.01, 0.01))
	var zeros2 := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
	var small2 := PackedVector3Array([Vector3(0.01, 0.01, 0.01), Vector3(0.01, 0.01, 0.01)])
	_mat.set_shader_parameter("uEatPos", zeros6)
	_mat.set_shader_parameter("uEatParam", zeros6)
	_mat.set_shader_parameter("uBoxHalf", small6)
	_mat.set_shader_parameter("uSolidPos", zeros2)
	_mat.set_shader_parameter("uSolidParam", zeros2)
	_mat.set_shader_parameter("uSolidHalf", small2)
	_mat.set_shader_parameter("uSolidDir", zeros2)
	_mat.set_shader_parameter("uDrapeAmt", 0.0)
	_mat.set_shader_parameter("uSplitAmt", 0.0)
	_mat.set_shader_parameter("uSqueeze", 0.0)
	_mat.set_shader_parameter("uGapLocal", Vector3.ZERO)


# ------------------------------------------------------------------------------------------------
# Input
# ------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if role != Role.PLAYER:
		return
	if event.is_action_pressed("slime_poke") and camera:
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			_try_poke(event.position)
		elif event is InputEventScreenTouch:
			_try_poke(event.position)
		else:
			var vp := get_viewport()
			if vp:
				_try_poke(vp.get_visible_rect().size * 0.5)
	elif event.is_action_pressed("split_follow"):
		split_clone(Role.FOLLOWER)
	elif event.is_action_pressed("split_roam"):
		split_clone(Role.ROAMER)
	elif event.is_action_pressed("merge_clones"):
		merge_nearby_clones()


func _try_poke(screen_pos: Vector2) -> void:
	if camera == null or model == null:
		return
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var center := model.center()
	var ax := model.axis
	var perp := Vector3(-ax.z, 0.0, ax.x)
	var sa := maxf(model.semi_a, 1e-3)
	var sb := maxf(model.semi_b, 1e-3)
	var sy := maxf(model.full_height * 0.5, 1e-3)
	var oc := origin - center
	var oa := oc.dot(ax) / sa
	var ob := oc.dot(perp) / sb
	var oy := oc.y / sy
	var da := dir.dot(ax) / sa
	var db := dir.dot(perp) / sb
	var dy := dir.y / sy
	var a := da * da + db * db + dy * dy
	var b := oa * da + ob * db + oy * dy
	var c := oa * oa + ob * ob + oy * oy - 1.0
	var disc := b * b - a * c
	if disc < 0.0:
		return
	var sq := sqrt(disc)
	var t := (-b - sq) / maxf(a, 1e-6)
	if t < 0.0:
		t = (-b + sq) / maxf(a, 1e-6)
	if t < 0.0:
		return
	var hit := origin + dir * t
	var local_point := ((hit - global_position) / maxf(slime_scale, 1e-4)).normalized() * tuning.reference_radius
	var push := (hit - camera.global_position).normalized() * tuning.poke_strength
	push.y -= tuning.poke_downward
	trigger_poke(local_point, push)


func trigger_poke(local_point: Vector3, impulse: Vector3) -> void:
	_impulse_time = 0.001
	if _mat:
		_mat.set_shader_parameter("uImpulsePos", local_point)
		_mat.set_shader_parameter("uImpulseVector", impulse)
	poked.emit(local_point, impulse)


func trigger_poke2(local_point: Vector3, impulse: Vector3) -> void:
	_impulse2_time = 0.001
	if _mat:
		_mat.set_shader_parameter("uImpulse2Pos", local_point)
		_mat.set_shader_parameter("uImpulse2Vector", impulse)


func set_shader_param(param: StringName, value: Variant) -> void:
	if _mat:
		_mat.set_shader_parameter(param, value)


# ------------------------------------------------------------------------------------------------
# Physics tick
# ------------------------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var dt := delta
	_time += dt
	_impulse_time += dt
	_impulse2_time += dt
	# Cleared once per tick so posture/growth reasons survive until presentation.
	expansion_blocked = ""

	if is_merging:
		_tick_merge(dt)
		return

	if is_budding:
		_tick_budding(dt)
		_tick_props(dt)
		return

	if is_fissioning:
		# The split tick owns scale, posture, support and presentation for this slime;
		# running the normal pipeline afterwards would give it two writers per tick.
		_tick_fission(dt)
		_tick_props(dt)
		return

	var desired := Vector3.ZERO
	match role:
		Role.PLAYER:
			desired = _process_player_input()
		Role.FOLLOWER:
			desired = _process_follower_ai(dt)
		Role.ROAMER:
			desired = _process_roamer_ai(dt)

	# Refresh before any posture/growth probe so this tick validates against the
	# current yielding set instead of last tick's.
	_refresh_exclusions()
	_update_scale(dt)
	_resolve_posture(dt)
	model.resolve(slime_scale, liquid_amt, height_ratio, squeeze_k, sq_dir)

	var v_resp := tuning.velocity_response * (0.6 if liquid_amt > 0.5 else 1.0)
	motor.velocity = motor.velocity.lerp(desired, 1.0 - exp(-v_resp * dt))
	motor.move_horizontal(Vector3(motor.velocity.x, 0.0, motor.velocity.z) * dt)
	motor.update_support()
	motor.move_vertical(dt, target_scale)
	_clamp_arena()
	_apply_transform()
	_verify_posture_after_move()
	_sync_proxy()

	_update_presentation(dt)
	_update_engulf(dt)
	_tick_props(dt)


func _tick_props(dt: float) -> void:
	if props:
		props.slime_ticked(self, dt)


## Belt-and-braces after translation: the committed posture must still clear the
## world. If it does not, fall back to the last posture that did rather than leaving
## the hull inside geometry until the next tick's probes notice.
func _verify_posture_after_move() -> void:
	if motor.hull_clear(tuning.skin * 2.0):
		_safe_posture = [slime_scale, liquid_amt, height_ratio, squeeze_k, sq_dir]
		return
	if _safe_posture.is_empty():
		return
	slime_scale = _safe_posture[0]
	liquid_amt = _safe_posture[1]
	height_ratio = _safe_posture[2]
	squeeze_k = _safe_posture[3]
	sq_dir = _safe_posture[4]
	model.resolve(slime_scale, liquid_amt, height_ratio, squeeze_k, sq_dir)
	_apply_transform()


# ------------------------------------------------------------------------------------------------
# Posture resolution (all transitions collision-tested over the whole footprint)
# ------------------------------------------------------------------------------------------------

func _update_scale(dt: float) -> void:
	if absf(target_scale - slime_scale) < 1e-5:
		return
	var new_scale := lerpf(slime_scale, target_scale, 1.0 - exp(-tuning.scale_response * dt))
	if absf(new_scale - target_scale) < 0.001:
		new_scale = target_scale
	if new_scale > slime_scale + 1e-6:
		if not motor.posture_is_legal(new_scale, liquid_amt, height_ratio, squeeze_k, sq_dir):
			expansion_blocked = "growth blocked by geometry"
			return
	_set_scale_anchored(new_scale)


## Change body scale while keeping the foot where it is: the node origin must move
## by the rest-height delta, otherwise growth raises (or shrinking sinks) the body
## through the floor until move_vertical catches up.
func _set_scale_anchored(new_scale: float) -> void:
	var foot_y := model.foot.y
	slime_scale = new_scale
	global_position.y = foot_y + model.rest_half_height * new_scale
	model.set_foot(Vector3(model.foot.x, foot_y, model.foot.z))


## Maintain (or acquire) the passage session. While latched the same two bodies are
## re-measured every tick; new hints are ignored. Release requires the trailing
## extent to be past the corridor along flow AND the unsqueezed posture to validate,
## so the squeeze outlives the pillars instead of snapping open mid-transit.
func _update_passage() -> void:
	if not _passage_session.is_empty():
		var a = _passage_session["a"]
		var b = _passage_session["b"]
		var m: Dictionary = props.measure_passage_pair(self, a, b)
		if m.is_empty():
			_release_passage(0.0)
			return
		# One stable orientation for the whole session (opposite anchors flip signs).
		var session_axis: Vector3 = _passage_session["axis"]
		var session_flow: Vector3 = _passage_session["flow"]
		# One stable orientation for the whole session (opposite anchors flip signs).
		if Vector3(m["flow"]).dot(session_flow) < 0.0:
			m["axis"] = -Vector3(m["axis"])
			m["flow"] = -Vector3(m["flow"])
		# Keep the squeeze direction aligned with the session as well; flipping flow
		# flips the perpendicular axis together with it.
		var m_axis: Vector3 = Vector3(m["axis"]).normalized()
		if m_axis.dot(session_axis) < 0.0:
			m_axis = -m_axis
			m["axis"] = m_axis
		session_axis = m_axis
		_passage_session["axis"] = session_axis
		var flow: Vector3 = m["flow"]
		var center: Vector3 = m["center"]
		var rel := (global_position - Vector3(center.x, 0.0, center.z)).dot(flow)
		var half: float = m["half_length"]
		# Released only once the TRAILING extent has passed the exit plane. Waiting for
		# "either end outside" would release on the approach, before the squeeze starts.
		var cleared := rel - model.semi_b > half
		if cleared:
			var rt := _height_ratio_for(liquid_amt, 1.0)
			if motor.posture_is_legal(slime_scale, liquid_amt, rt, 1.0, session_axis):
				_release_passage(0.35)
				return
		_passage = m
		return

	if _passage_cooldown > 0.0:
		return
	var hint: Dictionary = props.find_passage(self)
	if hint.is_empty():
		return
	var required := _required_squeeze(hint["width"])
	# The floor follows INTENT, not the current blend: with Z held the slime is
	# heading for the liquid posture, whose minimum applies. Using the current
	# (still-normal) floor would refuse to latch until it was already too late.
	var floor_sq := tuning.min_liquid_squeeze if liquid_request else tuning.min_normal_squeeze
	# Fail case: a corridor narrower than the legal floor is never latched. The sweep
	# stops the body at the pillars and describe_block explains the refusal.
	if required >= 1.0 or required < floor_sq - 1e-3:
		return
	var ax: Vector3 = hint["axis"]
	# Canonicalise once: the ellipse axis has no meaningful sign, but the neck and
	# the session must agree on one, and a later pair must not rotate it 90 degrees.
	if ax.x < -1e-5 or (absf(ax.x) <= 1e-5 and ax.z < 0.0):
		ax = -ax
	ax = ax.normalized()
	# Orient flow along the direction the body must travel to enter the corridor (from
	# its current side). Without this, "past the exit" is indistinguishable from
	# "still on the approach".
	var flow: Vector3 = Vector3(hint["flow"]).normalized()
	var to_gap := Vector3(hint["center"].x, 0.0, hint["center"].z) - Vector3(global_position.x, 0.0, global_position.z)
	if to_gap.dot(flow) < 0.0:
		flow = -flow
	hint["flow"] = flow
	_passage_session = {"a": hint["a"], "b": hint["b"], "axis": ax, "flow": flow}
	_passage = hint


func _release_passage(cooldown: float) -> void:
	_passage_session = {}
	_passage = {}
	cur_gap_w = INF
	_passage_cooldown = maxf(_passage_cooldown, cooldown)


## Squeeze ratio needed to fit a gap with the current liquid footprint.
func _required_squeeze(gap_w: float) -> float:
	var spread_now := pow(maxf(lerpf(1.0, tuning.liquid_height_ratio, liquid_amt), 1e-3), -0.5)
	var full_w := 2.0 * model.rest_max_radius * slime_scale * spread_now
	return (gap_w - 2.0 * tuning.skin) / maxf(full_w, 1e-4)


func _resolve_posture(dt: float) -> void:
	_passage = {}
	cur_gap_w = INF
	var axis := sq_dir
	sq_target = 1.0

	_passage_cooldown = maxf(0.0, _passage_cooldown - dt)
	if props != null:
		_update_passage()
	if not _passage.is_empty():
		var gap_dir: Vector3 = _passage.get("axis", Vector3.ZERO)
		if gap_dir.length_squared() > 1e-6:
			axis = Vector3(gap_dir.x, 0.0, gap_dir.z).normalized()
		var gap_w: float = _passage.get("width", INF)
		var min_sq := lerpf(tuning.min_normal_squeeze, tuning.min_liquid_squeeze, liquid_amt)
		sq_target = clampf(_required_squeeze(gap_w), min_sq, 1.0)
		var gc: Vector3 = _passage.get("center", Vector3.ZERO)
		cur_gap_center = Vector2(gc.x, gc.z)
		cur_gap_w = gap_w
		cur_gap_dir = Vector2(axis.x, axis.z)

	# --- Lateral squeeze spring (tighten into a passage, release when clear) ---
	var stiffness := tuning.squeeze_in_rate if sq_target < squeeze_k else tuning.squeeze_out_rate
	squeeze_v += (stiffness * (sq_target - squeeze_k) - 2.0 * sqrt(stiffness) * squeeze_v) * dt
	var sq_cand := squeeze_k + squeeze_v * dt
	var min_sq_now := lerpf(tuning.min_normal_squeeze, tuning.min_liquid_squeeze, liquid_amt)
	if sq_cand < min_sq_now:
		sq_cand = min_sq_now
		squeeze_v = 0.0
	elif sq_cand > 1.0:
		sq_cand = 1.0
		squeeze_v = 0.0

	# Resting in the open: the posture cannot change enough to matter, so skip
	# rebuilding convex hulls every physics tick.
	if absf(sq_cand - squeeze_k) < 1e-4 and squeeze_k >= 0.999 and sq_target >= 0.999:
		squeeze_k = 1.0
		squeeze_v = 0.0
		sq_dir = axis
	else:
		var r := _height_ratio_for(liquid_amt, sq_cand)
		if motor.posture_is_legal(slime_scale, liquid_amt, r, sq_cand, axis):
			squeeze_k = sq_cand
			# Commit the (canonicalised) axis only once the posture passes, so a
			# rejected hint never rotates the envelope or feeds a stale direction.
			sq_dir = axis
		else:
			# Hold the last legal posture instead of re-probing the same value.
			squeeze_v = 0.0
			# A gradual squeeze can be blocked by a corner that the *final* posture
			# clears (the wide shoulder clips the passage lip before the body is
			# narrow enough). Intermediate hulls of a narrowing transition are larger
			# than both endpoints along flow, so test the committed target alone.
			var snapped := false
			if sq_target < squeeze_k - 1e-4:
				var rt := _height_ratio_for(liquid_amt, sq_target)
				if motor.posture_target_is_legal(slime_scale, liquid_amt, rt, sq_target, axis):
					squeeze_k = sq_target
					sq_dir = axis
					snapped = true
			if not snapped and expansion_blocked == "":
				expansion_blocked = motor.describe_block(r, sq_cand)
	squeeze_k = clampf(squeeze_k, min_sq_now, 1.0)

	# --- Liquid posture blend ---
	var target_liq := 1.0 if liquid_request else 0.0
	var blend_rate := tuning.liquid_blend_rate if tuning != null else LIQUID_BLEND_RATE
	var cand := clampf(liquid_amt + clampf(target_liq - liquid_amt, -blend_rate * dt, blend_rate * dt), 0.0, 1.0)
	if absf(cand - liquid_amt) > 1e-6:
		var ratio := _height_ratio_for(cand, squeeze_k)
		# The per-tick liquid step is tiny (blend_rate*dt) and the body commits a single
		# posture, so test the candidate hull alone rather than sweeping up to a dozen
		# intermediate hulls that never physically exist. This keeps blocked frames
		# (the bisection below) from bursting into dozens of convex-hull rebuilds.
		if motor.posture_target_is_legal(slime_scale, cand, ratio, squeeze_k, axis):
			liquid_amt = cand
			height_ratio = ratio
		else:
			var good := liquid_amt
			var bad := cand
			for _i in 4:
				var mid := (good + bad) * 0.5
				var mr := _height_ratio_for(mid, squeeze_k)
				if motor.posture_target_is_legal(slime_scale, mid, mr, squeeze_k, axis):
					good = mid
				else:
					bad = mid
			if absf(good - liquid_amt) > 1e-5:
				liquid_amt = good
				height_ratio = _height_ratio_for(good, squeeze_k)
			if expansion_blocked == "":
				expansion_blocked = motor.describe_block(ratio, squeeze_k)
	else:
		height_ratio = _height_ratio_for(liquid_amt, squeeze_k)


## Height ratio for a candidate posture, reduced only as far as the liquid posture
## allows and only when an overhead obstacle actually requires it.
func _height_ratio_for(liq: float, sq: float) -> float:
	var base := lerpf(1.0, tuning.liquid_height_ratio, liq)
	# Normal posture never compresses vertically, so skip the ceiling cast entirely.
	if liq <= 0.001:
		return base
	var boost := 1.0 + (1.0 - sq) * tuning.squeeze_height_gain * (1.0 - liq)
	var rest_h := model.rest_full_height * slime_scale
	# Measure headroom with the footprint the candidate liquid posture will have,
	# not the current (narrower) hull: a puddle may widen under a ceiling edge.
	var probe := motor.adhoc_probe(model.baked_points(slime_scale, liq, base, sq, sq_dir))
	var rise := motor.ceiling_clearance_up(rest_h * 1.2 + 0.05, probe)
	if rise == INF:
		return base
	var avail := model.full_height + rise
	var wanted := rest_h * base * boost
	if wanted <= avail + 1e-4:
		return base
	var allowed := clampf(avail / maxf(rest_h * boost, 1e-4), 0.0, 1.0)
	var min_ratio := lerpf(1.0, tuning.min_liquid_height_ratio, liq)
	return clampf(minf(base, allowed), min_ratio, 1.0)


## Validated intent setter shared by player input and AI. A blocked stand-up keeps
## the request pending instead of dropping it.
func _set_liquid_request(value: bool) -> void:
	if value:
		liquid_request = true
		expansion_blocked = ""
		return
	if liquid_request:
		if motor.posture_is_legal(slime_scale, 0.0, 1.0, squeeze_k, sq_dir):
			liquid_request = false
		elif expansion_blocked == "":
			expansion_blocked = motor.describe_block(1.0, squeeze_k)
	else:
		liquid_request = false


# ------------------------------------------------------------------------------------------------
# Role input / AI
# ------------------------------------------------------------------------------------------------

func _process_player_input() -> Vector3:
	var wants_liquid := Input.is_action_pressed("slime_liquid")
	if is_fissioning or is_merging:
		wants_liquid = false
	# Same validated path as the AI: a blocked stand-up keeps the Z intent pending.
	_set_liquid_request(wants_liquid)
	engulf_request = wants_liquid

	var in_z := Input.get_axis("move_back", "move_forward")
	var in_x := Input.get_axis("move_left", "move_right")

	var fwd := Vector3(0.0, 0.0, -1.0)
	if camera:
		fwd = -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var desired := fwd * in_z + right * in_x

	if liquid_amt > 0.5:
		cur_max = tuning.liquid_speed
	elif Input.is_action_pressed("run"):
		cur_max = tuning.run_speed
	else:
		cur_max = tuning.walk_speed

	if desired.length_squared() > 0.0:
		desired = desired.normalized() * cur_max
	return desired


func _process_follower_ai(dt: float) -> Vector3:
	if target_leader == null or not is_instance_valid(target_leader):
		target_leader = null
		if props and props.player_slime and is_instance_valid(props.player_slime) and props.player_slime != self:
			target_leader = props.player_slime
		else:
			_following_flatten = false
			return Vector3.ZERO

	var follower_index := 0
	if props:
		for s in props.registered_slimes:
			if s == self:
				break
			if is_instance_valid(s) and s.role == Role.FOLLOWER and s.target_leader == target_leader:
				follower_index += 1

	var slot_spacing := model.rest_max_radius * slime_scale * 2.0 + 0.8
	var desired_dist := tuning.follow_distance * (target_leader.slime_scale + slime_scale) * 0.5 + float(follower_index) * slot_spacing

	var target_pt := target_leader.global_position
	var env_ceiling_h := INF
	var env_gap_w := INF

	var trail := target_leader.breadcrumbs
	var found_breadcrumb := false
	if trail.size() > 0:
		var accum := 0.0
		var prev := target_leader.global_position
		for i in range(trail.size() - 1, -1, -1):
			var b: Dictionary = trail[i]
			accum += prev.distance_to(b["pos"])
			prev = b["pos"]
			if accum >= desired_dist:
				target_pt = b["pos"]
				env_ceiling_h = b.get("ceiling_h", INF)
				env_gap_w = b.get("gap_w", INF)
				found_breadcrumb = true
				break

	if not found_breadcrumb:
		var leader_back := -target_leader._crawl_dir
		if leader_back.length_squared() < 0.01:
			leader_back = Vector3(0.0, 0.0, 1.0)
		target_pt = target_leader.global_position + leader_back.normalized() * desired_dist

	var to_target := target_pt - global_position
	to_target.y = 0.0
	var dist := to_target.length()

	_follower_stuck_timer += dt
	if _ai_last_pos.distance_squared_to(global_position) > 0.3:
		_follower_stuck_timer = 0.0
		_ai_last_pos = global_position
	if _follower_stuck_timer > tuning.follower_stuck_time and dist > 1.0:
		var perp := to_target.cross(Vector3.UP).normalized()
		target_pt = global_position + perp * 3.0 + to_target.normalized() * 2.0
		_follower_stuck_timer = 0.0
		to_target = target_pt - global_position
		to_target.y = 0.0
		dist = to_target.length()

	# Own dimensions against the recorded environment; safety comes from queries.
	var my_full_height := model.rest_full_height * slime_scale
	var my_width := 2.0 * model.rest_max_radius * slime_scale
	var needs_flat := env_ceiling_h < my_full_height * 1.1 or env_gap_w < my_width * 1.5
	var has_room := env_ceiling_h > my_full_height * 1.35 and env_gap_w > my_width * 2.0
	if needs_flat and not liquid_request:
		_following_flatten = true
	elif _following_flatten and has_room:
		_following_flatten = false
	if _following_flatten:
		_set_liquid_request(true)
	elif liquid_request and has_room and squeeze_k > 0.9:
		_set_liquid_request(false)
	if squeeze_k < 0.7 and not liquid_request:
		_following_flatten = true
		_set_liquid_request(true)

	var posture_max := tuning.liquid_speed if liquid_amt > 0.5 else tuning.walk_speed
	cur_max = posture_max
	if dist > tuning.follower_catch_up_distance and liquid_amt < 0.5:
		cur_max = tuning.run_speed * 0.9

	var stop_dist := slime_scale * 0.35 + 0.2
	var slow_dist := stop_dist + 2.0
	if dist <= stop_dist:
		return Vector3.ZERO

	var speed_factor := clampf((dist - stop_dist) / (slow_dist - stop_dist), 0.0, 1.0)
	speed_factor = speed_factor * speed_factor * (3.0 - 2.0 * speed_factor)
	return to_target.normalized() * (cur_max * speed_factor)


func _process_roamer_ai(dt: float) -> Vector3:
	_ai_roam_timer += dt
	_ai_stuck_timer += dt
	if _ai_recovery_timer > 0.0:
		_ai_recovery_timer = maxf(0.0, _ai_recovery_timer - dt)

	if _ai_last_pos.distance_squared_to(global_position) > 0.2:
		_ai_stuck_timer = 0.0
		_ai_last_pos = global_position

	if _ai_stuck_timer > tuning.roamer_stuck_time:
		if _ai_stuck_timer > tuning.roamer_stuck_time * 1.8:
			var ang := randf() * TAU
			var escape_dest := global_position + Vector3(cos(ang) * 12.0, 0.0, sin(ang) * 12.0)
			var flat := Vector2(escape_dest.x, escape_dest.z)
			if flat.length() > tuning.arena_radius * 0.85:
				flat = flat.normalized() * (tuning.arena_radius * 0.75)
				escape_dest.x = flat.x
				escape_dest.z = flat.y
			_ai_target_pos = escape_dest
			_ai_stuck_timer = 0.0
			_ai_recovery_timer = tuning.roamer_recover_time
		_set_liquid_request(true)

	if squeeze_k < 0.6 and not liquid_request:
		_set_liquid_request(true)
	elif liquid_request and squeeze_k > 0.92 and _ai_recovery_timer <= 0.0 and _ai_stuck_timer < 1.0:
		_set_liquid_request(false)

	if _ai_roam_timer > 0.0 and (global_position.distance_squared_to(_ai_target_pos) < 9.0 or _ai_target_pos == Vector3.ZERO):
		_ai_roam_timer = 0.0
		var base_ang := atan2(_crawl_dir.x, _crawl_dir.z) if _crawl_dir.length_squared() > 0.01 else randf() * TAU
		var drift := randf_range(-PI * 0.4, PI * 0.4)
		var new_ang := base_ang + drift
		var wander_dist := randf_range(6.0, 14.0)
		var wander_dest := global_position + Vector3(sin(new_ang) * wander_dist, 0.0, cos(new_ang) * wander_dist)
		var flat := Vector2(wander_dest.x, wander_dest.z)
		if flat.length() > tuning.arena_radius * 0.85:
			flat = flat.normalized() * (tuning.arena_radius * 0.75)
			wander_dest.x = flat.x
			wander_dest.z = flat.y
		_ai_target_pos = wander_dest
		_ai_roam_timer = -randf_range(2.0, 4.0)

	var wander_dir := _ai_target_pos - global_position
	wander_dir.y = 0.0
	var desired_heading := wander_dir.normalized() if wander_dir.length_squared() > 0.01 else _crawl_dir

	cur_max = tuning.liquid_speed if liquid_amt > 0.5 else tuning.walk_speed
	return desired_heading * cur_max


# ------------------------------------------------------------------------------------------------
# Presentation
# ------------------------------------------------------------------------------------------------

func _update_presentation(dt: float) -> void:
	var speed := motor.velocity.length()
	speed01 = minf(speed / maxf(tuning.speed_for_full_crawl, 0.01), 1.0)
	if speed > 0.05:
		_crawl_dir = Vector3(motor.velocity.x, 0.0, motor.velocity.z).normalized()

	var crawl_strain := 1.0 - clampf(press_amt * 0.55, 0.0, 0.6)
	_crawl_phase += speed * dt * tuning.crawl_rate * crawl_strain

	var lean_target := Vector3(motor.velocity.x * tuning.lean_gain * (1.0 - calm), 0.0, motor.velocity.z * tuning.lean_gain * (1.0 - calm)) - _lean
	_lean_vel += lean_target * tuning.lean_stiffness * dt
	_lean_vel += _lean_vel * (-tuning.lean_damping * dt)
	_lean += _lean_vel * dt
	if _time - touch_time < 0.2:
		_lean_vel = Vector3.ZERO
		_lean *= exp(-14.0 * dt)

	if speed > tuning.moving_threshold:
		var diff := atan2(_crawl_dir.x, _crawl_dir.z) - _facing_yaw
		diff = atan2(sin(diff), cos(diff))
		_facing_yaw += diff * (1.0 - exp(-tuning.facing_response * dt))
	var blink := tuning.blink_closed_amount if fmod(_time, tuning.blink_period) > tuning.blink_start else 1.0

	if _mat:
		_mat.set_shader_parameter("uImpulseTime", _impulse_time)
		_mat.set_shader_parameter("uImpulse2Time", _impulse2_time)
		_mat.set_shader_parameter("uMoveDir", _crawl_dir)
		_mat.set_shader_parameter("uMoveAmt", speed01 * (1.0 - 0.95 * calm))
		_mat.set_shader_parameter("uCrawl", _crawl_phase)
		_mat.set_shader_parameter("uLean", _lean)
		_mat.set_shader_parameter("uRippleIntensity", tuning.ripple_base + tuning.ripple_per_speed * speed01 + liquid_amt * 0.15 + press_amt * 0.28)
		_mat.set_shader_parameter("uFacing", _facing_yaw)
		_mat.set_shader_parameter("uBlink", blink)
		_mat.set_shader_parameter("uLiquid", liquid_amt)
		_mat.set_shader_parameter("uLiquidHeight", height_ratio)
		_mat.set_shader_parameter("uLiquidSpread", model.spread)
		_mat.set_shader_parameter("uSqueeze", clampf(1.0 - model.squeeze, 0.0, 0.94))
		_mat.set_shader_parameter("uSqueezeDir", sq_dir)
		# Publish the posture factors the hull baked, so the mesh scales identically.
		_mat.set_shader_parameter("uSqueezeLat", model.squeeze)
		_mat.set_shader_parameter("uSqueezeLong", model.flow_stretch)
		_mat.set_shader_parameter("uSqueezeHeight", model.height_boost)
		_mat.set_shader_parameter("uSkinLocal", tuning.skin / maxf(slime_scale, 1e-3))
		# Keep the neck pinned to the corridor while any squeeze remains, including the
		# release spring after unlatch: zeroing it early teleports the waist to origin.
		if cur_gap_w < INF or squeeze_k < 0.999:
			var off := Vector3(cur_gap_center.x, 0.0, cur_gap_center.y) - global_position
			var ml := model.mesh_local(off)
			_mat.set_shader_parameter("uGapLocal", Vector3(ml.x, 0.0, ml.z))
		else:
			_mat.set_shader_parameter("uGapLocal", Vector3.ZERO)

	if role == Role.PLAYER:
		_breadcrumb_timer += dt
		if _breadcrumb_timer >= tuning.breadcrumb_interval:
			_breadcrumb_timer = 0.0
			breadcrumbs.append({"pos": global_position, "ceiling_h": _measure_ceiling_clearance(), "gap_w": cur_gap_w, "time": _time})
			while breadcrumbs.size() > tuning.breadcrumb_limit:
				breadcrumbs.pop_front()


func _measure_ceiling_clearance() -> float:
	var rise := motor.ceiling_clearance_up(model.rest_full_height * slime_scale)
	if rise == INF:
		return INF
	return model.full_height + rise


# ------------------------------------------------------------------------------------------------
# Engulf (drape) — request-driven, always decays
# ------------------------------------------------------------------------------------------------

func _update_engulf(dt: float) -> void:
	if props == null:
		return

	var target_p = null
	if engulf_request and liquid_amt > 0.35:
		var puddle_radius := minf(model.semi_a, model.semi_b)
		var my_volume := get_volume()
		var best_score := -INF
		for p in props.props:
			if p.state != SlimeProps.STATE_IDLE or p.is_static:
				continue
			var m: MeshInstance3D = p.mesh
			if m == null or not is_instance_valid(m):
				continue
			var he: Vector3 = props._half_of(p)
			var prop_top: float = m.global_position.y + he.y
			var prop_bottom: float = m.global_position.y - he.y

			var top_area := 4.0 * he.x * he.z if p.shape == SlimeProps.SHAPE_BOX else (PI * he.x * he.z)
			var side_area := (4.0 * he.x + 4.0 * he.z) * (2.0 * he.y)
			var needed_shell_volume := (top_area + side_area) * 0.08 * slime_scale
			if my_volume < needed_shell_volume * 0.8:
				continue

			var flat_d: float = Vector2(global_position.x - m.global_position.x, global_position.z - m.global_position.z).length()
			var prop_max_r: float = Vector2(he.x, he.z).length()
			var covers_horiz := flat_d + prop_max_r <= puddle_radius * 1.05
			var touches_vert := model.foot.y <= prop_top + 0.3 * slime_scale and global_position.y + 0.5 * slime_scale >= prop_bottom
			if covers_horiz and touches_vert:
				var score := 1000.0 - flat_d
				if score > best_score:
					best_score = score
					target_p = p

	if target_p != null:
		if engulf_target != target_p:
			engulf_target = target_p
			engulf_progress = 0.0
		engulf_progress = minf(1.0, engulf_progress + dt / maxf(tuning.devour_duration, 0.1))
		var m: MeshInstance3D = target_p.mesh
		if _mat and m and is_instance_valid(m):
			_mat.set_shader_parameter("uDrapePos", (m.global_position - global_position) / maxf(slime_scale, 1e-4))
			_mat.set_shader_parameter("uDrapeHalf", props._half_of(target_p) / maxf(slime_scale, 1e-4))
			_mat.set_shader_parameter("uDrapeShape", float(target_p.shape) + target_p.sides * 0.01)
			_mat.set_shader_parameter("uDrapeYaw", m.rotation.y)
			_mat.set_shader_parameter("uDrapeAmt", engulf_progress)
		if engulf_progress >= 1.0:
			props.devour(target_p, self)
			engulf_progress = 0.0
			engulf_target = null
			set_shader_param("uDrapeAmt", 0.0)
		return

	if engulf_progress > 0.0:
		engulf_progress = maxf(0.0, engulf_progress - dt * 2.0)
		set_shader_param("uDrapeAmt", engulf_progress)
		if engulf_progress <= 0.001:
			engulf_progress = 0.0
			engulf_target = null
			set_shader_param("uDrapeAmt", 0.0)
	else:
		engulf_target = null


# ------------------------------------------------------------------------------------------------
# Fission / budding / merge
# ------------------------------------------------------------------------------------------------

func _tick_fission(dt: float) -> void:
	_refresh_exclusions()
	const SNAP_POINT := 0.70
	var duration := maxf(tuning.fission_duration, 0.01)
	var prev_k := clampf(fission_timer / duration, 0.0, 1.0)
	var k_next := clampf((fission_timer + dt) / duration, 0.0, 1.0)
	var k := prev_k
	# This tick is the single writer of BOTH scales, always from the same k, so the
	# pair's volume is conserved exactly. When the droplet's next growth is blocked,
	# hold the shared progress instead of handing over volume it cannot hold.
	var clone := fission_clone if fission_clone != null and is_instance_valid(fission_clone) else null
	if clone == null or clone.set_bud_scale(k_next):
		fission_timer += dt
		k = k_next
	elif prev_k != k_next:
		# Let the droplet catch up to the last shared progress if its block cleared.
		clone.set_bud_scale(prev_k)

	# Volume budget: the parent keeps (1 - 0.5k) of the pre-split volume.
	_set_scale_anchored(fission_start_scale * pow(maxf(1.0 - 0.5 * k, 0.0), 1.0 / 3.0))
	if k < SNAP_POINT:
		# Phase 1: tension stretch and neck formation against the separating half.
		var stretch_k := k / SNAP_POINT
		var e := sin(stretch_k * PI * 0.5)
		set_shader_param("uSplitAmt", e * 0.95)
	else:
		# Phase 2: the bridge snaps, and the body recoils with an elastic jiggle.
		if not _fission_snapped:
			_fission_snapped = true
			trigger_poke(Vector3(fission_fwd.x, 0.25, fission_fwd.z).normalized() * 1.5, -fission_fwd * 1.6)
			trigger_poke2(Vector3(-fission_fwd.x, -0.1, -fission_fwd.z).normalized() * 1.5, fission_fwd * 0.8)

		var snap_k := (k - SNAP_POINT) / (1.0 - SNAP_POINT)
		var snap_decay := exp(-snap_k * 5.5) * cos(snap_k * PI * 2.5)
		set_shader_param("uSplitAmt", maxf(0.0, snap_decay * 0.85))

	model.resolve(slime_scale, 0.0, 1.0, squeeze_k, sq_dir)
	motor.update_support()
	motor.move_vertical(dt, target_scale)
	_apply_transform()
	set_shader_param("uSplitDir", fission_fwd)

	if k >= 1.0:
		is_fissioning = false
		fission_clone = null
		_set_scale_anchored(fission_target_scale)
		_apply_transform()
		set_shader_param("uSplitAmt", 0.0)
	_sync_proxy()


## The clone's share of the pre-split volume at shared progress `k`, as a scale.
func _bud_scale_for(k: float) -> float:
	return bud_start_scale * pow(maxf(0.5 * clampf(k, 0.0, 1.0), 0.0), 1.0 / 3.0)


## Apply the clone's volume-budget scale for shared progress `k`. Returns false when
## the requested growth is blocked by level geometry; the scale is held so the parent
## can hold its own progress instead of handing over volume this hull cannot hold.
func set_bud_scale(k: float) -> bool:
	var s := _bud_scale_for(k)
	var ok := true
	bud_growth_blocked = false
	if s > slime_scale + 1e-5 and not motor.posture_is_legal(s, 0.0, 1.0, 1.0, sq_dir):
		ok = false
		bud_growth_blocked = true
		s = slime_scale
	if absf(s - slime_scale) > 1e-6:
		_set_scale_anchored(s)
		model.resolve(slime_scale, 0.0, 1.0, 1.0, sq_dir)
	return ok


func _tick_budding(dt: float) -> void:
	_refresh_exclusions()
	const SNAP_POINT := 0.70
	var k := 0.0
	var parent_driven := bud_parent != null and is_instance_valid(bud_parent) and bud_parent.is_fissioning
	if parent_driven:
		# The parent is this pair's single scale writer; it advanced both already.
		# Read its own fission clock: the two durations are independent tunables.
		k = clampf(bud_parent.fission_timer / maxf(bud_parent.tuning.fission_duration, 0.01), 0.0, 1.0)
		bud_timer = k * tuning.bud_duration
	else:
		bud_timer += dt
		k = clampf(bud_timer / maxf(tuning.bud_duration, 0.01), 0.0, 1.0)
		# Growth is a posture change and must pass the same geometry probe as any other;
		# when blocked, hold the scale so the neck keeps stretching in place.
		set_bud_scale(k)

	if k < SNAP_POINT:
		# Phase 1: the droplet clings to the parent and is drawn out under tension.
		var stretch_k := k / SNAP_POINT
		var e := sin(stretch_k * PI * 0.5)
		set_shader_param("uSplitAmt", e * 0.95)
		if bud_parent and is_instance_valid(bud_parent):
			var pull := pow(stretch_k, 1.6)
			_bud_separation_step(dt, bud_sep + bud_separation_extra(slime_scale) * 0.25 * pull)
	else:
		# Phase 2: the neck snaps and the free droplet overshoots then settles.
		if not _bud_snapped:
			_bud_snapped = true
			trigger_poke(Vector3(-bud_fwd.x, 0.25, -bud_fwd.z).normalized() * 1.5, bud_fwd * 1.6)
			trigger_poke2(Vector3(bud_fwd.x, -0.1, bud_fwd.z).normalized() * 1.4, -bud_fwd * 0.8)

		var snap_k := (k - SNAP_POINT) / (1.0 - SNAP_POINT)
		var snap_e := sin(snap_k * PI * 0.5)
		var snap_decay := exp(-snap_k * 5.5) * cos(snap_k * PI * 2.5)
		set_shader_param("uSplitAmt", maxf(0.0, snap_decay * 0.85))
		if bud_parent and is_instance_valid(bud_parent):
			_bud_separation_step(dt, bud_sep + bud_separation_extra(slime_scale) * (0.25 + 0.18 * snap_e))
		# Collision stays off until the swept separation has actually cleared both
		# hulls; the pairwise pass finishes any residual overlap first.
		if not _bud_clear and _is_clear_of_parent():
			_bud_clear = true

	model.resolve(slime_scale, 0.0, 1.0, 1.0, sq_dir)
	motor.update_support()
	motor.move_vertical(dt, target_scale)
	_apply_transform()
	set_shader_param("uSplitDir", -bud_fwd)

	if k >= 1.0:
		is_budding = false
		bud_parent = null
		_set_scale_anchored(bud_target_scale)
		_apply_transform()
		set_shader_param("uSplitAmt", 0.0)
	_sync_proxy()


## Growth room this pair's separation still needs, in metres scaled to both bodies.
func bud_separation_extra(clone_scale: float) -> float:
	var r := model.rest_max_radius
	if bud_parent == null or not is_instance_valid(bud_parent):
		return r * 2.0 * clone_scale
	return r * (bud_parent.slime_scale + clone_scale)


## Drive the separation like any other locomotion: a capped velocity swept by the
## motor, so the distance covered never depends on the frame rate.
func _bud_separation_step(dt: float, sep: float) -> void:
	var target_pos := bud_parent.global_position + bud_fwd * sep
	var delta := target_pos - global_position
	delta.y = 0.0
	var v := delta / maxf(dt, 1e-4)
	if v.length() > tuning.walk_speed:
		v = v.normalized() * tuning.walk_speed
	motor.move_horizontal(v * dt)


func _is_clear_of_parent() -> bool:
	if bud_parent == null or not is_instance_valid(bud_parent):
		return true
	var d := Vector2(global_position.x - bud_parent.global_position.x, global_position.z - bud_parent.global_position.z)
	if d.length_squared() < 1e-8:
		return false
	var dir := Vector3(d.x, 0.0, d.y) / d.length()
	var radius := model.horizontal_support(dir) + bud_parent.model.horizontal_support(-dir)
	return d.length() >= radius + tuning.skin


func _tick_merge(dt: float) -> void:
	_refresh_exclusions()
	merge_timer += dt
	if merge_target == null or not is_instance_valid(merge_target) or merge_target.is_merging:
		_cancel_merge()
		_tick_props(dt)
		return

	var delta := merge_target.global_position - global_position
	delta.y = 0.0
	var dist := delta.length()
	if dist > 1e-4:
		motor.move_horizontal(delta)
	_set_scale_anchored(maxf(0.02, lerpf(slime_scale, 0.02, 1.0 - exp(-12.0 * dt))))
	model.resolve(slime_scale, 0.0, 1.0, 1.0, sq_dir)
	motor.update_support()
	motor.move_vertical(dt, 0.02)
	_apply_transform()
	_sync_proxy()

	var close := dist < 0.6 * maxf(merge_target.model.rest_max_radius * merge_target.slime_scale, 0.2)
	if close and not _has_merged:
		_has_merged = true
		merge_target.add_volume(get_volume())
		merge_target.trigger_poke(Vector3(0.0, 0.3, 0.0), Vector3(0.0, -0.65, 0.0))
		merge_target.trigger_poke2(Vector3(0.0, -0.3, 0.0), Vector3(0.0, 0.5, 0.0))
		if props:
			for p in props.props:
				if p.state == SlimeProps.STATE_EATING and p.eater == self:
					p.eater = merge_target
					if not merge_target.inside_props.has(p):
						merge_target.inside_props.append(p)
			props.unregister_slime(self)
		inside_props.clear()
		queue_free()
		return
	if merge_timer >= tuning.merge_duration:
		# Volume only moves on contact. A merge that never arrived is cancelled and
		# the body regrows through the ordinary scale pipeline, not by teleport.
		_cancel_merge()
		_update_scale(dt)
		model.resolve(slime_scale, 0.0, 1.0, 1.0, sq_dir)
		_apply_transform()
		_sync_proxy()
	_tick_props(dt)


func _cancel_merge() -> void:
	is_merging = false
	merge_target = null
	merge_timer = 0.0
	_has_merged = false


func split_clone(clone_role: Role) -> void:
	if target_scale < tuning.min_split_scale or is_fissioning or is_budding or is_merging:
		return
	if liquid_amt > 0.1 or engulf_target != null or liquid_request:
		return

	var fwd: Vector3
	if motor.velocity.length() > 0.3:
		fwd = _crawl_dir.normalized()
	elif camera:
		fwd = -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	else:
		fwd = _crawl_dir.normalized()
	if fwd.length_squared() < 0.01:
		fwd = Vector3(0.0, 0.0, -1.0)

	var split_fwd := -fwd
	var half_volume := get_volume() * 0.5
	var new_target_scale := pow(half_volume / tuning.volume_per_scale_cubed(), 1.0 / 3.0)

	# Preflight: the clone's final hull must fit at the tangent offset, so try the
	# forward direction first and turn until one is free. No free direction means the
	# split is refused instead of spawning inside geometry.
	_refresh_exclusions()
	var clone_radius := model.rest_max_radius * new_target_scale
	var spawn_offset := Vector3.ZERO
	for deg in [0.0, 45.0, -45.0, 90.0, -90.0, 180.0]:
		var d := split_fwd.rotated(Vector3.UP, deg_to_rad(deg))
		var offset := model.horizontal_support(d) + clone_radius + tuning.skin
		if motor.spawn_is_clear(model.foot + d * offset, new_target_scale):
			split_fwd = d
			spawn_offset = d * offset
			break
	if spawn_offset == Vector3.ZERO:
		return

	var clone := _spawn_fission_clone(clone_role, split_fwd, new_target_scale, spawn_offset)
	if clone == null:
		return
	fission_clone = clone

	fission_fwd = split_fwd
	fission_start_scale = slime_scale
	fission_target_scale = new_target_scale
	set_volume(half_volume)
	is_fissioning = true
	fission_timer = 0.0
	_fission_snapped = false
	# Apply the parent's matching share on the spawn frame itself, so the pair's
	# volume is conserved from the instant the clone exists.
	var k0 := clampf(get_physics_process_delta_time() / maxf(tuning.fission_duration, 0.01), 0.0, 1.0)
	_set_scale_anchored(fission_start_scale * pow(1.0 - 0.5 * k0, 1.0 / 3.0))


func _spawn_fission_clone(clone_role: Role, fwd_dir: Vector3, clone_target_scale: float, spawn_offset: Vector3) -> Slime:
	var prefab := load("res://scenes/slime.tscn") as PackedScene
	if prefab == null:
		return null
	var clone := prefab.instantiate() as Slime
	if clone == null:
		return null

	# First frame of the clone's volume-budget curve: the spawn scale the curve
	# itself would produce, so growth starts without a step.
	var k_first := get_physics_process_delta_time() / maxf(tuning.fission_duration, 0.01)
	var clone_start_scale := clampf(slime_scale * pow(maxf(0.5 * k_first, 0.0), 1.0 / 3.0), 0.02, clone_target_scale)

	clone.role = clone_role
	clone.tuning = tuning
	clone.props = props
	clone.floor_mesh = floor_mesh
	clone.camera = null
	clone.start_scale = clone_start_scale
	clone.target_scale = clone_target_scale
	clone.slime_scale = clone_start_scale
	clone._velocity_cache = Vector3.ZERO
	clone.position = global_position + spawn_offset
	# Same floor as the parent, not the same centre height: the halves have
	# different scales, so copying the centre would bury the smaller one.
	clone.position.y = model.foot.y + model.rest_half_height * clone_start_scale
	clone._facing_yaw = _facing_yaw
	if clone_role == Role.FOLLOWER:
		clone.target_leader = self

	clone.is_budding = true
	clone.bud_parent = self
	clone.bud_timer = 0.0
	clone.bud_start_scale = slime_scale
	clone.bud_sep = spawn_offset.length()
	clone.bud_target_scale = clone_target_scale
	clone.bud_fwd = fwd_dir

	var parent_node := get_parent()
	if parent_node == null:
		return null
	parent_node.add_child(clone)
	# The clone's proxy exists now; exclude it (and the parent) before any probe.
	clone._refresh_exclusions()
	clone.motor.recover_overlap()
	clone._sync_proxy()
	return clone


func merge_nearby_clones() -> void:
	if props == null or is_merging or is_fissioning or is_budding:
		return
	if liquid_amt > 0.1 or liquid_request:
		return

	var merge_rad := model.rest_max_radius * slime_scale * tuning.merge_range_factor + 1.0
	var to_merge: Array[Slime] = []

	for s in props.registered_slimes:
		if s == self or not is_instance_valid(s) or s.is_merging or s.is_fissioning or s.is_budding:
			continue
		if s.liquid_amt > 0.1 or s.liquid_request:
			continue
		var dist := global_position.distance_to(s.global_position)
		if dist > merge_rad + s.model.rest_max_radius * s.slime_scale:
			continue
		if not _merge_path_clear(s):
			continue
		to_merge.append(s)

	if to_merge.is_empty():
		return

	for s in to_merge:
		s.is_merging = true
		s.merge_target = self
		s.merge_timer = 0.0
		s.merge_source_scale = s.target_scale
		s.velocity = Vector3.ZERO
		s.liquid_request = false
		s.engulf_request = false
		s.set_shader_param("uDrapeAmt", 0.0)

	trigger_poke(Vector3(0.0, 0.3, 0.0), Vector3(0.0, -0.6, 0.0))


func _merge_path_clear(other: Slime) -> bool:
	# The whole hull has to make the trip, not just its endpoints: a merge across a
	# wall or a pillar would otherwise teleport the source through it. Swept by the
	# traveller's own motor so its exclusion set and foot are the ones that move.
	var from := other.model.foot
	var to := Vector3(model.foot.x, from.y, model.foot.z)
	return other.motor.sweep_is_clear(from, to, other.slime_scale)


# ------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------

## The motor owns the transform; clamping is just another swept move.
func _clamp_arena() -> void:
	motor.clamp_to_arena(Vector3.ZERO, tuning.arena_radius)


func _apply_transform() -> void:
	scale = Vector3.ONE * slime_scale
