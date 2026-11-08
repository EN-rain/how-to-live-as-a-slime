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

## Passage latch phases. The physical squeeze is driven by the same session in every
## state; the phase only controls how long the latch and its visual neck persist.
enum PassageState {
	OPEN,
	APPROACHING,
	ENTERING,
	INSIDE,
	EXITING
}

## Fallback when no tuning resource is assigned.
const LIQUID_BLEND_RATE := 2.8
## Shared clone prefab and mesh LOD variants (one resource per level, not per slime).
static var _slime_scene: PackedScene = null
static var _lod_meshes: Array[SphereMesh] = []
const LOD_FAR_DISTANCE := 18.0
const LOD_SMALL_SCALE := 0.55
## Normalized split progress where the neck pinches to zero. Shared by the volume
## curve, the separation curve and the shader neck so all three snap together.
const SPLIT_SNAP := 0.68
## Neck radius at the seam as a fraction of the smaller half's radius.
const SPLIT_NECK_RATIO := 0.32
## Angles the spawn preflight tries for the bud direction, in degrees.
const SPLIT_ANGLES := [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 135.0, -135.0, 180.0]

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
var passage_state: PassageState = PassageState.OPEN
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
## Snap separation chosen by the preflight and the share of it the parent must yield
## backwards (non-zero when forward space alone is too tight).
var fission_d_snap := 0.0
var fission_parent_share := 0.0
var fission_back_done := 0.0

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
## Coupled-split curve endpoints: interior start and collision-free snap distance.
var bud_d0 := 0.0
var bud_d_snap := 0.0
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
## Idle props this body is actively pushing with an open engulf front. Maintained by
## the ecosystem each tick so exclusion queries never need to scan every prop.
var pressing_props: Array = []

# AI state.
var _ai_roam_timer := 0.0
var _ai_recovery_timer := 0.0
var _ai_target_pos := Vector3.ZERO
var _ai_stuck_timer := 0.0
var _ai_last_pos := Vector3.ZERO
## Per-slime seeded stream: roamer wandering is reproducible from spawn_seed.
var _rng := RandomNumberGenerator.new()
var _following_flatten := false
var _follower_stuck_timer := 0.0
## Slot in the follower train for the current leader, assigned by SlimeProps.
var follower_slot_index := 0
## Stationary clones skip the physics/posture pipeline until something moves.
var _is_sleeping := false
var _lod_level := -1
var _lod_timer := 0.0

var _mat: ShaderMaterial
var _shader_param_cache := {}
var _time := 0.0
var _impulse_time := 10.0
var _impulse2_time := 10.0
var _crawl_dir := Vector3(0.0, 0.0, 1.0)
var _crawl_phase := 0.0
var _facing_yaw := 0.0
var _lean := Vector3.ZERO
var _lean_vel := Vector3.ZERO
var _velocity_cache := Vector3.ZERO
var pre_move_velocity := Vector3.ZERO
## Last committed posture that cleared the world, restored if a post-move check fails.
var _safe_posture: Array = []
## Physics-tick snapshots used to smooth the mesh between ticks. Gameplay, picking
## and collision always read the node's physics transform, never the mesh.
var _prev_global_pos := Vector3.ZERO
var _prev_scale := 1.0

## Baked-hull proxy on SlimeMotor.LAYER_SLIMES. It shares the model's shape resource,
## so every posture change is published to other slimes automatically.
var _proxy: StaticBody3D
var _proxy_cs: CollisionShape3D
var _core_mesh: MeshInstance3D
static var _core_sphere_mesh: SphereMesh
static var _core_material: StandardMaterial3D
## Posture key whose hull was last proven clear; steady ticks skip the re-check.
var _verified_key := -1
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

## Park a merged clone: hidden, inert and non-colliding, but still allocated so the
## next split can reuse its model, motor, material and proxy.
func _prepare_for_pool() -> void:
	_is_sleeping = true
	is_merging = false
	merge_target = null
	visible = false
	if _proxy != null:
		_proxy.collision_layer = 0
	process_mode = Node.PROCESS_MODE_DISABLED


## Reverse of _prepare_for_pool. The spawner applies the split-specific state
## (role, scales, bud fields, position) right after this.
func _activate_from_pool() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	if body != null:
		# Drop any interpolation offset left from the merge frame; the spawner sets
		# the physics transform and the render lerp starts from there.
		body.position = Vector3.ZERO
		body.scale = Vector3.ONE
	if _proxy != null:
		_proxy.collision_layer = SlimeMotor.LAYER_SLIMES

	is_fissioning = false
	fission_timer = 0.0
	fission_clone = null
	_fission_snapped = false
	fission_d_snap = 0.0
	fission_parent_share = 0.0
	fission_back_done = 0.0
	is_budding = false
	bud_timer = 0.0
	bud_parent = null
	bud_growth_blocked = false
	bud_d0 = 0.0
	bud_d_snap = 0.0
	_bud_snapped = false
	_bud_clear = false
	is_merging = false
	merge_target = null
	merge_timer = 0.0
	_has_merged = false

	liquid_request = false
	engulf_request = false
	liquid_amt = 0.0
	height_ratio = 1.0
	squeeze_k = 1.0
	squeeze_v = 0.0
	sq_target = 1.0
	sq_dir = model.axis
	expansion_blocked = ""

	breadcrumbs.clear()
	_breadcrumb_timer = 0.0
	inside_props.clear()
	pressing_props.clear()
	_passage.clear()
	_passage_session.clear()
	_passage_cooldown = 0.0
	cur_gap_w = INF
	cur_gap_center = Vector2.ZERO
	cur_gap_dir = Vector2.ZERO
	engulf_target = null
	engulf_progress = 0.0

	_ai_roam_timer = 0.0
	_ai_recovery_timer = 0.0
	_ai_target_pos = Vector3.ZERO
	_ai_stuck_timer = 0.0
	_ai_last_pos = global_position
	_following_flatten = false
	_follower_stuck_timer = 0.0
	follower_slot_index = 0

	_time = 0.0
	_impulse_time = 10.0
	_impulse2_time = 10.0
	_crawl_dir = Vector3(0.0, 0.0, 1.0)
	_crawl_phase = 0.0
	_lean = Vector3.ZERO
	_lean_vel = Vector3.ZERO
	speed01 = 0.0
	press_amt = 0.0
	calm = 0.0
	cur_max = tuning.walk_speed
	touch_time = -10.0
	splat_x = 0.0
	splat_v = 0.0
	spread_x = 0.0
	spread_v = 0.0
	sharp_amt = 0.0
	contact_r = 2.15
	impact_dir = Vector3(0.0, 0.0, 1.0)
	_velocity_cache = Vector3.ZERO
	_is_sleeping = false
	_lod_level = -1
	_lod_timer = 0.0
	_safe_posture.clear()
	_verified_key = -1

	motor.velocity = Vector3.ZERO
	motor.vertical_vel = 0.0
	motor.impact_speed = 0.0
	motor.last_sweep_fraction = 1.0
	motor.contact_normals.clear()
	motor.contact_bodies.clear()
	motor.on_ground = true
	motor.ground_body = null
	motor.support_y = tuning.floor_y

	_shader_param_cache.clear()
	_reset_array_uniforms()
	set_shader_param("uRefRadius", tuning.reference_radius)
	set_shader_param("uSplitAmt", 0.0)
	set_shader_param("uSplitNeckRadius", 0.0)
	set_shader_param("uSplitPartnerLocal", Vector3.ZERO)


func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/slime_tuning.tres") as SlimeTuning
	if props == null:
		props = get_node_or_null("../Ecosystem") as SlimeProps

	if body and body.material_override is ShaderMaterial:
		_mat = body.material_override.duplicate() as ShaderMaterial
		body.material_override = _mat
		set_shader_param("uMelt", tuning.melt)
		set_shader_param("uRefRadius", tuning.reference_radius)
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

	_resolve_model(0.0, 1.0, 1.0)
	sq_dir = model.axis
	motor.support_y = tuning.floor_y
	global_position.y = tuning.floor_y + tuning.skin + model.rest_half_height * slime_scale
	model.set_foot(global_position + Vector3(0.0, -model.rest_half_height * slime_scale, 0.0))
	_apply_transform()
	_setup_proxy()
	_setup_core_visual()
	_prev_global_pos = global_position
	_prev_scale = slime_scale

	if props:
		_rng.seed = props.next_slime_seed()
		props.register_slime(self)


func _exit_tree() -> void:
	if props and is_instance_valid(props):
		props.unregister_slime(self)


func _setup_core_visual() -> void:
	if body == null:
		return
	if _core_sphere_mesh == null:
		_core_sphere_mesh = SphereMesh.new()
		_core_sphere_mesh.radius = 1.0
		_core_sphere_mesh.height = 2.0
		_core_sphere_mesh.radial_segments = 32
		_core_sphere_mesh.rings = 16
	if _core_material == null:
		_core_material = StandardMaterial3D.new()
		_core_material.albedo_color = Color(0.10, 0.50, 0.90, 1.0)
		_core_material.emission_enabled = true
		_core_material.emission = Color(0.22, 0.85, 1.0, 1.0)
		_core_material.emission_energy_multiplier = 0.70
		_core_material.roughness = 0.20
		_core_material.metallic = 0.12
	_core_mesh = MeshInstance3D.new()
	_core_mesh.name = "CoreSphere"
	_core_mesh.mesh = _core_sphere_mesh
	_core_mesh.material_override = _core_material
	_core_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(_core_mesh)
	_sync_core_visual()


func _sync_core_visual() -> void:
	if _core_mesh == null or model == null:
		return
	var s := maxf(slime_scale, 1e-4)
	var rxz := model.core_sphere_radius() / s
	_core_mesh.position = Vector3.ZERO
	_core_mesh.scale = Vector3(rxz, rxz, rxz)


func _setup_proxy() -> void:
	_proxy = StaticBody3D.new()
	_proxy.name = "SlimeProxy"
	_proxy.top_level = true
	_proxy.collision_layer = SlimeMotor.LAYER_SLIMES
	_proxy.collision_mask = 0
	_proxy_cs = CollisionShape3D.new()
	_proxy_cs.shape = model.shape
	_proxy.add_child(_proxy_cs)
	add_child(_proxy)
	_sync_proxy()


## Resolve the authoritative shape, republishing it to the proxy only when the
## quantized posture key changed (the hull resource is shared and immutable).
## Omitted arguments keep the live posture.
func _resolve_model(p_liquid := -1.0, p_height_ratio := -1.0, p_squeeze := -1.0) -> void:
	var liq := liquid_amt if p_liquid < 0.0 else p_liquid
	var hr := height_ratio if p_height_ratio < 0.0 else p_height_ratio
	var sq := squeeze_k if p_squeeze < 0.0 else p_squeeze
	if model.resolve(slime_scale, liq, hr, sq, sq_dir):
		_verified_key = -1
		if _proxy_cs != null:
			_proxy_cs.shape = model.shape
	_sync_core_visual()


## Publish the resolved footprint at the moment the motor last committed it.
func _sync_proxy() -> void:
	if _proxy == null or model == null:
		return
	var foot := global_position + Vector3(0.0, -model.rest_half_height * model.scale, 0.0)
	model.set_foot(foot)
	_proxy.global_transform = Transform3D(Basis.IDENTITY, foot)


func get_proxy_rid() -> RID:
	return _proxy.get_rid() if _proxy != null else RID()


## One shared sphere per LOD level. The material is a per-instance override, so
## swapping the mesh never changes the look, only the vertex count.
static func _lod_mesh(level: int) -> SphereMesh:
	if _lod_meshes.is_empty():
		var hi := SphereMesh.new()
		hi.radius = 1.6
		hi.height = 3.2
		hi.radial_segments = 64
		hi.rings = 48
		var lo := SphereMesh.new()
		lo.radius = 1.6
		lo.height = 3.2
		lo.radial_segments = 24
		lo.rings = 16
		_lod_meshes = [hi, lo]
	return _lod_meshes[clampi(level, 0, _lod_meshes.size() - 1)]


## Clones far from the camera (or too small to matter) drop to the low-poly mesh
## and the cheap fragment path. Re-evaluated twice a second, not per tick.
func _update_lod(dt: float) -> void:
	if body == null:
		return
	_lod_timer -= dt
	if _lod_timer > 0.0:
		return
	_lod_timer = 0.5
	var level := 0
	if role != Role.PLAYER:
		var cam := get_viewport().get_camera_3d()
		var far := cam == null or cam.global_position.distance_to(global_position) > LOD_FAR_DISTANCE
		if far or slime_scale < LOD_SMALL_SCALE:
			level = 1
	if level == _lod_level:
		return
	_lod_level = level
	body.mesh = _lod_mesh(level)
	set_shader_param("uShaderLOD", 1.0 if level == 1 else 0.0)


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
	var zeros8 := PackedVector3Array()
	var small8 := PackedVector3Array()
	for i in 8:
		zeros8.append(Vector3.ZERO)
		small8.append(Vector3(0.01, 0.01, 0.01))
	set_shader_param("uEatPos", zeros6)
	set_shader_param("uEatParam", zeros6)
	set_shader_param("uBoxHalf", small6)
	set_shader_param("uSolidPos", zeros8)
	set_shader_param("uSolidParam", zeros8)
	set_shader_param("uSolidHalf", small8)
	set_shader_param("uSolidDir", zeros8)
	set_shader_param("uDrapeAmt", 0.0)
	set_shader_param("uSplitAmt", 0.0)
	set_shader_param("uSplitNeckRadius", 0.0)
	set_shader_param("uSplitPartnerLocal", Vector3.ZERO)
	set_shader_param("uSqueeze", 0.0)
	set_shader_param("uGapLocal", Vector3.ZERO)


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
		set_shader_param("uImpulsePos", local_point)
		set_shader_param("uImpulseVector", impulse)
	poked.emit(local_point, impulse)


func trigger_poke2(local_point: Vector3, impulse: Vector3) -> void:
	_impulse2_time = 0.001
	if _mat:
		set_shader_param("uImpulse2Pos", local_point)
		set_shader_param("uImpulse2Vector", impulse)


## Dirty-checked uniform write. Idle and walking frames re-send almost the same
## values every tick; skipping unchanged ones keeps the material free of redundant
## copies and shader parameter updates.
func set_shader_param(param: StringName, value: Variant) -> void:
	if _mat == null:
		return
	var prev = _shader_param_cache.get(param)
	if prev != null and _same_param(prev, value):
		return
	_shader_param_cache[param] = value
	_mat.set_shader_parameter(param, value)


static func _same_param(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b):
		return false
	match typeof(a):
		TYPE_FLOAT:
			return is_equal_approx(a, b)
		TYPE_VECTOR3:
			return (a as Vector3).is_equal_approx(b)
		TYPE_VECTOR2:
			return (a as Vector2).is_equal_approx(b)
		TYPE_COLOR:
			return (a as Color).is_equal_approx(b)
		_:
			return a == b


# ------------------------------------------------------------------------------------------------
# Physics tick
# ------------------------------------------------------------------------------------------------

## Visual-only smoothing between physics ticks. `Body` carries the mesh and shadow;
## the node itself keeps the physics transform that gameplay and picking use. The
## engine's built-in interpolation is off, so this is the single interpolator.
func _process(_delta: float) -> void:
	if body == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	body.global_position = _prev_global_pos.lerp(global_position, f)
	var s := lerpf(_prev_scale, slime_scale, f)
	# The node already applies slime_scale; undo it on the child so the total visual
	# scale is exactly the interpolated one and never compounds between ticks.
	body.scale = Vector3.ONE * (s / maxf(slime_scale, 1e-4))
	if props != null and not _is_sleeping:
		props._update_solid_uniforms(self, true)


func _physics_process(delta: float) -> void:
	# Snapshot the physics state before this tick moves it: _process lerps the mesh
	# from here to the committed transform, so 120/144 Hz clients see smooth motion
	# while gameplay stays on the fixed tick.
	_prev_global_pos = global_position
	_prev_scale = slime_scale

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

	_update_lod(dt)

	if _can_sleep(desired):
		if not _is_sleeping:
			_is_sleeping = true
			motor.velocity = Vector3.ZERO
			_update_presentation(dt)
		_tick_props(dt)
		return
	_is_sleeping = false

	# Refresh before any posture/growth probe so this tick validates against the
	# current yielding set instead of last tick's.
	_refresh_exclusions()
	var v_resp := tuning.velocity_response
	motor.velocity = motor.velocity.lerp(desired, 1.0 - exp(-v_resp * dt))
	pre_move_velocity = motor.velocity
	_update_scale(dt)
	_resolve_posture(dt)
	_resolve_model()

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


## A clone that wants nothing, holds a settled posture and has no moving neighbour
## cannot change this tick: skip exclusions, posture probes, sweeps and presentation.
func _can_sleep(desired: Vector3) -> bool:
	if role == Role.PLAYER or props == null:
		return false
	if motor.velocity.length_squared() > 1e-4 or desired.length_squared() > 1e-4:
		return false
	if absf(slime_scale - target_scale) > 1e-4:
		return false
	if absf(height_ratio - 1.0) > 1e-4 or squeeze_k < 0.999:
		return false
	var pos := global_position
	for other in props.registered_slimes:
		if other == self or not is_instance_valid(other):
			continue
		if other.motor.velocity.length_squared() > 0.01 \
				and other.global_position.distance_squared_to(pos) < 12.25:
			return false
	return true


## Belt-and-braces after translation: if `move_horizontal` advanced on the inner core
## sphere, shrink `squeeze_k` to match the legal clearance at the new position.
func _verify_posture_after_move() -> void:
	_verified_key = model.posture_key()
	_safe_posture = [slime_scale, liquid_amt, height_ratio, squeeze_k, sq_dir]


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
		var new_core_r := model.rest_max_radius * new_scale * model.min_squeeze()
		if not motor.core_sphere_clear(motor.core_sweep_origin(), new_core_r) \
				or not motor.core_sphere_clear(model.core_sphere_center(), new_core_r):
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
			passage_state = PassageState.OPEN
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
		var to_center := global_position - Vector3(center.x, global_position.y, center.z)
		var rel := to_center.dot(flow)
		var half: float = m["half_length"]
		# Released only once the TRAILING extent has passed the exit plane. Waiting for
		# "either end outside" would release on the approach, before the squeeze starts.
		var hold_margin := 0.15 if tuning.use_passage_fsm else 0.0
		var cleared := rel - model.semi_b > half + hold_margin

		# Check abandonment: if the slime has backed away, moved sideways, or walked away
		var lat_offset := (to_center - flow * rel).length()
		var passage_w: float = m["width"]
		var rest_radius := model.rest_max_radius * slime_scale
		var moving_away_from_entrance := rel < -half and motor.velocity.dot(flow) < -0.1
		var far_before_entrance := rel < -10.0
		var far_after_exit := rel > 10.0
		var sideways_escape := lat_offset > passage_w * 0.5 + rest_radius + 2.5
		var stopped_outside := rel < -half - 1.0 and motor.velocity.length_squared() < 0.01

		if moving_away_from_entrance or far_before_entrance or far_after_exit or sideways_escape or stopped_outside:
			passage_state = PassageState.OPEN
			_release_passage(0.0)
			return

		# Phase bookkeeping: the latch owns the squeeze from the first approach tick
		# until the trailing end is out. Only the state machine adds the exit margin.
		if rel < -half * 0.5:
			passage_state = PassageState.APPROACHING
		elif rel <= half * 0.5:
			passage_state = PassageState.ENTERING
		elif rel <= half + model.semi_b + hold_margin:
			passage_state = PassageState.INSIDE
		else:
			passage_state = PassageState.EXITING
		# If the body is past the gate center and moving forward into the open, release as soon as the round shape clears
		var rt := _height_ratio_for(liquid_amt, 1.0)
		if rel > half * 0.5:
			if motor.posture_target_is_legal(slime_scale, liquid_amt, rt, 1.0, session_axis):
				passage_state = PassageState.OPEN
				_release_passage(0.35)
				return

		if cleared:
			var free := motor.posture_target_is_legal(slime_scale, liquid_amt, rt, 1.0, session_axis) \
				if tuning.use_passage_fsm \
				else motor.posture_is_legal(slime_scale, liquid_amt, rt, 1.0, session_axis)
			if free or rel > half + 1.5:
				passage_state = PassageState.OPEN
				_release_passage(0.35)
				return
		_passage = m
		return

	if _passage_cooldown > 0.0:
		return
	var hint: Dictionary = props.find_passage(self)
	if hint.is_empty():
		passage_state = PassageState.OPEN
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
	passage_state = PassageState.APPROACHING


func _release_passage(cooldown: float) -> void:
	_passage_session = {}
	_passage = {}
	passage_state = PassageState.OPEN
	cur_gap_w = INF
	_passage_cooldown = maxf(_passage_cooldown, cooldown)


## Squeeze ratio needed to fit a gap with the current liquid footprint.
func _required_squeeze(gap_w: float) -> float:
	var spread_now := pow(maxf(lerpf(1.0, tuning.liquid_height_ratio, liquid_amt), 1e-3), -0.5)
	var full_w := 2.0 * model.rest_max_radius * slime_scale * spread_now
	return (gap_w - 2.0 * tuning.skin) / maxf(full_w, 1e-4)


func _resolve_posture(_dt: float) -> void:
	_passage = {}
	cur_gap_w = INF
	sq_target = 1.0
	squeeze_k = 1.0
	squeeze_v = 0.0
	liquid_request = false
	liquid_amt = 0.0
	height_ratio = 1.0


func _height_ratio_for(_liq: float, _sq: float) -> float:
	return 1.0


func _set_liquid_request(_value: bool) -> void:
	liquid_request = false


# ------------------------------------------------------------------------------------------------
# Role input / AI
# ------------------------------------------------------------------------------------------------

func _process_player_input() -> Vector3:
	liquid_request = false
	engulf_request = false

	var in_z := Input.get_axis("move_back", "move_forward")
	var in_x := Input.get_axis("move_left", "move_right")

	var fwd := Vector3(0.0, 0.0, -1.0)
	if camera:
		fwd = -camera.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
	var right := fwd.cross(Vector3.UP)
	var desired := fwd * in_z + right * in_x

	if Input.is_action_pressed("run"):
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
			props.refresh_follower_slots()
		else:
			_following_flatten = false
			return Vector3.ZERO

	var slot_spacing := model.rest_max_radius * slime_scale * 2.0 + 0.8
	var desired_dist := tuning.follow_distance * (target_leader.slime_scale + slime_scale) * 0.5 + float(follower_slot_index) * slot_spacing

	var target_pt := target_leader.global_position
	var env_ceiling_h := INF
	var env_gap_w := INF

	# Breadcrumbs carry cumulative arc length, so the target for this slot is a
	# binary search over the trail instead of summing up to 120 distances per tick.
	var trail := target_leader.breadcrumbs
	if not trail.is_empty():
		var newest: Dictionary = trail[trail.size() - 1]
		var leader_cum: float = newest["cum_dist"] + (newest["pos"] as Vector3).distance_to(target_leader.global_position)
		var lo := 0
		var hi := trail.size() - 1
		var found := -1
		while lo <= hi:
			var mid := (lo + hi) >> 1
			if leader_cum - float(trail[mid]["cum_dist"]) >= desired_dist:
				found = mid
				lo = mid + 1
			else:
				hi = mid - 1
		if found >= 0:
			var b: Dictionary = trail[found]
			target_pt = b["pos"]
			env_ceiling_h = b.get("ceiling_h", INF)
			env_gap_w = b.get("gap_w", INF)

	if target_pt == target_leader.global_position:
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

	liquid_request = false
	cur_max = tuning.walk_speed
	if dist > tuning.follower_catch_up_distance:
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
			var ang := _rng.randf() * TAU
			var escape_dest := global_position + Vector3(cos(ang) * 12.0, 0.0, sin(ang) * 12.0)
			var flat := Vector2(escape_dest.x, escape_dest.z)
			if flat.length() > tuning.arena_radius * 0.85:
				flat = flat.normalized() * (tuning.arena_radius * 0.75)
				escape_dest.x = flat.x
				escape_dest.z = flat.y
			_ai_target_pos = escape_dest
			_ai_stuck_timer = 0.0
			_ai_recovery_timer = tuning.roamer_recover_time

	liquid_request = false

	if _ai_roam_timer > 0.0 and (global_position.distance_squared_to(_ai_target_pos) < 9.0 or _ai_target_pos == Vector3.ZERO):
		_ai_roam_timer = 0.0
		var base_ang := atan2(_crawl_dir.x, _crawl_dir.z) if _crawl_dir.length_squared() > 0.01 else _rng.randf() * TAU
		var drift := _rng.randf_range(-PI * 0.4, PI * 0.4)
		var new_ang := base_ang + drift
		var wander_dist := _rng.randf_range(6.0, 14.0)
		var wander_dest := global_position + Vector3(sin(new_ang) * wander_dist, 0.0, cos(new_ang) * wander_dist)
		var flat := Vector2(wander_dest.x, wander_dest.z)
		if flat.length() > tuning.arena_radius * 0.85:
			flat = flat.normalized() * (tuning.arena_radius * 0.75)
			wander_dest.x = flat.x
			wander_dest.z = flat.y
		_ai_target_pos = wander_dest
		_ai_roam_timer = -_rng.randf_range(2.0, 4.0)

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
	var sdt := minf(dt, 1.0 / 30.0)
	_lean_vel += lean_target * tuning.lean_stiffness * sdt
	_lean_vel += _lean_vel * (-tuning.lean_damping * sdt)
	_lean += _lean_vel * sdt
	if _time - touch_time < 0.2:
		_lean_vel = Vector3.ZERO
		_lean *= exp(-14.0 * dt)

	if speed > tuning.moving_threshold:
		var diff := atan2(_crawl_dir.x, _crawl_dir.z) - _facing_yaw
		diff = atan2(sin(diff), cos(diff))
		_facing_yaw += diff * (1.0 - exp(-tuning.facing_response * dt))
	var blink := tuning.blink_closed_amount if fmod(_time, tuning.blink_period) > tuning.blink_start else 1.0

	if _mat:
		set_shader_param("uImpulseTime", _impulse_time)
		set_shader_param("uImpulse2Time", _impulse2_time)
		set_shader_param("uMoveDir", _crawl_dir)
		set_shader_param("uMoveAmt", speed01 * (1.0 - 0.95 * calm))
		set_shader_param("uCrawl", _crawl_phase)
		set_shader_param("uLean", _lean)
		set_shader_param("uRippleIntensity", tuning.ripple_base + tuning.ripple_per_speed * speed01 + liquid_amt * 0.15 + press_amt * 0.28)
		set_shader_param("uFacing", _facing_yaw)
		set_shader_param("uBlink", blink)
		set_shader_param("uLiquid", liquid_amt)
		set_shader_param("uLiquidHeight", height_ratio)
		set_shader_param("uLiquidSpread", model.spread)
		set_shader_param("uSqueeze", 0.0)
		set_shader_param("uSqueezeDir", sq_dir)
		set_shader_param("uSqueezeLat", 1.0)
		set_shader_param("uSqueezeLong", 1.0)
		set_shader_param("uSqueezeHeight", 1.0)
		set_shader_param("uSkinLocal", tuning.skin / maxf(slime_scale * model.spread, 1e-3))
		set_shader_param("uGapLocal", Vector3.ZERO)

	if role == Role.PLAYER:
		_breadcrumb_timer += dt
		if _breadcrumb_timer >= tuning.breadcrumb_interval:
			_breadcrumb_timer = 0.0
			var pos := global_position
			var cum := 0.0
			if not breadcrumbs.is_empty():
				var last: Dictionary = breadcrumbs[breadcrumbs.size() - 1]
				cum = float(last["cum_dist"]) + (last["pos"] as Vector3).distance_to(pos)
			# An overhead reading is only meaningful near props or while flattened;
			# skipping it otherwise removes a convex-shape ceiling cast per breadcrumb.
			var ceiling := INF
			if liquid_amt > 0.01 or squeeze_k < 0.999 \
					or (props != null and not props.query_nearby_props(Vector2(pos.x, pos.z), 1.0).is_empty()):
				ceiling = _measure_ceiling_clearance()
			breadcrumbs.append({"pos": pos, "ceiling_h": ceiling, "gap_w": cur_gap_w, "cum_dist": cum, "time": _time})
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
		var puddle_radius := model.rest_max_radius * slime_scale * model.spread
		var my_volume := get_volume()
		var best_score := -INF
		for p in props.query_nearby_props(Vector2(global_position.x, global_position.z), puddle_radius * 1.05):
			if p.is_static:
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
			set_shader_param("uDrapePos", (m.global_position - global_position) / maxf(slime_scale, 1e-4))
			set_shader_param("uDrapeHalf", props._half_of(target_p) / maxf(slime_scale, 1e-4))
			set_shader_param("uDrapeShape", float(target_p.shape) + target_p.sides * 0.01)
			set_shader_param("uDrapeYaw", m.rotation.y)
			set_shader_param("uDrapeAmt", engulf_progress)
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

	_set_scale_anchored(_parent_scale_for(k))
	_resolve_model(0.0, 1.0)

	# Coupled split: both halves draw apart from the shared origin. The parent yields
	# backwards only as far as the preflight found room for, and the clone tracks the
	# parent's live position, so the pair never separates past free space.
	if tuning.use_coupled_split and clone != null and k < 1.0:
		var progress := smoothstep(0.0, SPLIT_SNAP, k)
		if role == Role.PLAYER and not is_merging:
			var desired := _process_player_input() * 0.45
			motor.velocity = motor.velocity.lerp(desired, 1.0 - exp(-tuning.velocity_response * dt))
		else:
			motor.velocity = Vector3.ZERO
		motor.move_horizontal(Vector3(motor.velocity.x, 0.0, motor.velocity.z) * dt)
		var back_needed := fission_d_snap * fission_parent_share * progress
		var back_step := back_needed - fission_back_done
		if back_step > 1e-5:
			fission_back_done = back_needed
			motor.move_horizontal(-fission_fwd * back_step)

	if k < SPLIT_SNAP:
		# Phase 1: tension stretch and neck formation against the separating half.
		var stretch_k := k / SPLIT_SNAP
		var e := sin(stretch_k * PI * 0.5)
		set_shader_param("uSplitAmt", e * 0.95)
	else:
		# Phase 2: the bridge snaps, and the body recoils with an elastic jiggle.
		if not _fission_snapped:
			_fission_snapped = true
			trigger_poke(Vector3(fission_fwd.x, 0.25, fission_fwd.z).normalized() * 1.5, -fission_fwd * 1.6)
			trigger_poke2(Vector3(-fission_fwd.x, -0.1, -fission_fwd.z).normalized() * 1.5, fission_fwd * 0.8)

		var snap_k := (k - SPLIT_SNAP) / (1.0 - SPLIT_SNAP)
		var snap_decay := exp(-snap_k * 5.5) * cos(snap_k * PI * 2.5)
		set_shader_param("uSplitAmt", maxf(0.0, snap_decay * 0.85))

	_update_split_neck(k, clone)

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
		set_shader_param("uSplitNeckRadius", 0.0)
		set_shader_param("uSplitPartnerLocal", Vector3.ZERO)
	_sync_proxy()


## Shared volume budget progress: the clone's fraction of the pre-split volume.
## Coupled splits transfer volume along an S-curve that reaches 0.5 exactly at the
## snap point, so the halves hold their final mass for the whole recoil phase.
func _split_alpha(k: float) -> float:
	if not tuning.use_coupled_split:
		return 0.5 * clampf(k, 0.0, 1.0)
	return 0.5 * smoothstep(0.0, SPLIT_SNAP, k)


func _parent_scale_for(k: float) -> float:
	return fission_start_scale * pow(maxf(1.0 - _split_alpha(k), 0.0), 1.0 / 3.0)


## Publish the world-coupled hourglass to the shader. The neck radius peaks mid-split
## and pinches to zero exactly at SPLIT_SNAP, so both surfaces meet at the seam until
## the instant they separate.
func _update_split_neck(k: float, partner: Slime) -> void:
	if not tuning.use_coupled_split or partner == null or not is_instance_valid(partner) or k >= SPLIT_SNAP:
		set_shader_param("uSplitNeckRadius", 0.0)
		set_shader_param("uSplitPartnerLocal", Vector3.ZERO)
		return
	var ramp := sin(clampf((k - 0.15) / (SPLIT_SNAP - 0.15), 0.0, 1.0) * PI)
	var r_self := model.rest_max_radius * slime_scale
	var r_partner := partner.model.rest_max_radius * partner.slime_scale
	var neck_world := minf(r_self, r_partner) * SPLIT_NECK_RATIO * ramp
	var local_radius := neck_world / maxf(slime_scale * model.spread, 1e-4)
	set_shader_param("uSplitPartnerLocal", model.mesh_local(partner.global_position - global_position))
	set_shader_param("uSplitNeckRadius", local_radius)


## The clone's share of the pre-split volume at shared progress `k`, as a scale.
func _bud_scale_for(k: float) -> float:
	return bud_start_scale * pow(maxf(_split_alpha(k), 0.0), 1.0 / 3.0)


## Apply the clone's volume-budget scale for shared progress `k`. Returns false when
## the requested growth is blocked by level geometry; the scale is held so the parent
## can hold its own progress instead of handing over volume this hull cannot hold.
func set_bud_scale(k: float) -> bool:
	var s := maxf(_bud_scale_for(k), 0.02)
	var ok := true
	bud_growth_blocked = false
	# Single target probe when growing past bucket margin, avoiding multi-step QuickHull loops
	if s > slime_scale + 0.015:
		if not motor.posture_target_is_legal(s, 0.0, 1.0, 1.0, sq_dir):
			ok = false
			bud_growth_blocked = true
			s = slime_scale
	if absf(s - slime_scale) > 1e-6:
		_set_scale_anchored(s)
		_resolve_model(0.0, 1.0, 1.0)
	return ok


func _tick_budding(dt: float) -> void:
	_refresh_exclusions()
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

	var coupled := tuning.use_coupled_split and bud_parent != null and is_instance_valid(bud_parent)
	var progress := smoothstep(0.0, SPLIT_SNAP, k)
	if k < SPLIT_SNAP:
		# Phase 1: the droplet clings to the parent and is drawn out under tension.
		var stretch_k := k / SPLIT_SNAP
		var e := sin(stretch_k * PI * 0.5)
		set_shader_param("uSplitAmt", e * 0.95)
		if bud_parent and is_instance_valid(bud_parent):
			if coupled:
				_bud_separation_step(dt, lerpf(bud_d0, bud_d_snap, progress))
			else:
				var pull := pow(stretch_k, 1.6)
				_bud_separation_step(dt, bud_sep + bud_separation_extra(slime_scale) * 0.25 * pull)
	else:
		# Phase 2: the neck snaps and the free droplet overshoots then settles.
		if not _bud_snapped:
			_bud_snapped = true
			trigger_poke(Vector3(-bud_fwd.x, 0.25, -bud_fwd.z).normalized() * 1.5, bud_fwd * 1.6)
			trigger_poke2(Vector3(bud_fwd.x, -0.1, bud_fwd.z).normalized() * 1.4, -bud_fwd * 0.8)

		var snap_k := (k - SPLIT_SNAP) / (1.0 - SPLIT_SNAP)
		var snap_e := sin(snap_k * PI * 0.5)
		var snap_decay := exp(-snap_k * 5.5) * cos(snap_k * PI * 2.5)
		set_shader_param("uSplitAmt", maxf(0.0, snap_decay * 0.85))
		if bud_parent and is_instance_valid(bud_parent):
			if coupled:
				_bud_separation_step(dt, bud_d_snap + 0.10 * snap_e)
			else:
				_bud_separation_step(dt, bud_sep + bud_separation_extra(slime_scale) * (0.25 + 0.18 * snap_e))
		# Collision stays off until the swept separation has actually cleared both
		# hulls; the pairwise pass finishes any residual overlap first.
		if not _bud_clear and _is_clear_of_parent():
			_bud_clear = true

	_update_split_neck(k, bud_parent)

	_resolve_model(0.0, 1.0, 1.0)
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
		set_shader_param("uSplitNeckRadius", 0.0)
		set_shader_param("uSplitPartnerLocal", Vector3.ZERO)
	_sync_proxy()


## Growth room this pair's separation still needs, in metres scaled to both bodies.
func bud_separation_extra(clone_scale: float) -> float:
	var r := model.rest_max_radius
	if bud_parent == null or not is_instance_valid(bud_parent):
		return r * 2.0 * clone_scale
	return r * (bud_parent.slime_scale + clone_scale)


## Drive the separation like any other locomotion: a capped velocity swept by the
## motor, so the distance covered never depends on the frame rate. Coupled splits
## pass the absolute target instead: the curve already bounds the per-tick delta, and
## a frame-rate dip must not leave the bud stranded inside the parent's hull.
func _bud_separation_step(dt: float, sep: float) -> void:
	if bud_parent == null or not is_instance_valid(bud_parent):
		return
	var target_pos := bud_parent.global_position + bud_fwd * sep
	var delta := target_pos - global_position
	delta.y = 0.0
	if tuning.use_coupled_split:
		motor.move_horizontal(delta)
		return
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
	_resolve_model(0.0, 1.0, 1.0)
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
			props.recycle_slime(self)
		inside_props.clear()
		return
	if merge_timer >= tuning.merge_duration:
		# Volume only moves on contact. A merge that never arrived is cancelled and
		# the body regrows through the ordinary scale pipeline, not by teleport.
		_cancel_merge()
		_update_scale(dt)
		_resolve_model(0.0, 1.0, 1.0)
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
	# A coupled split sculpts the neck from both surfaces, which only reads correctly
	# on a settled, unsqueezed body that is not mid-passage.
	if tuning.use_coupled_split:
		if slime_scale < tuning.min_split_scale or squeeze_k < 0.85 \
				or passage_state != PassageState.OPEN:
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

	# Preflight: the pair must be able to reach the snap separation in this direction.
	# A coupled split lets the parent recoil backwards to pay for forward space it does
	# not have (e.g. splitting against a wall); the legacy split needs the whole
	# tangent offset free for the clone alone.
	_refresh_exclusions()
	var d0 := model.horizontal_support(split_fwd) * 0.45
	var d_snap := d0
	var parent_share := 0.0
	var spawn_offset := Vector3.ZERO
	if tuning.use_coupled_split:
		var found := false
		for deg in SPLIT_ANGLES:
			var d: Vector3 = split_fwd.rotated(Vector3.UP, deg_to_rad(deg))
			var r_dir := model.horizontal_support(d) * (new_target_scale / maxf(slime_scale, 1e-4))
			var need := r_dir * 2.0 + tuning.skin * 2.0
			var reach := need + 0.4
			var fwd_clear := motor.sweep_clear_distance(new_target_scale, d * reach)
			var back_clear := motor.sweep_clear_distance(new_target_scale, -d * reach)
			if fwd_clear + back_clear < need:
				continue
			split_fwd = d
			d_snap = need
			parent_share = clampf(1.0 - fwd_clear / maxf(need, 1e-4), 0.0, 0.75)
			d0 = model.horizontal_support(d) * 0.45
			spawn_offset = d * d0
			found = true
			break
		if not found:
			return
	else:
		var clone_radius := model.rest_max_radius * new_target_scale
		for deg in [0.0, 45.0, -45.0, 90.0, -90.0, 180.0]:
			var d := split_fwd.rotated(Vector3.UP, deg_to_rad(deg))
			var offset := model.horizontal_support(d) + clone_radius + tuning.skin
			if motor.spawn_is_clear(model.foot + d * offset, new_target_scale):
				split_fwd = d
				spawn_offset = d * offset
				d0 = offset
				d_snap = offset
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
	fission_d_snap = d_snap
	fission_parent_share = parent_share
	fission_back_done = 0.0
	clone.bud_d0 = d0
	clone.bud_d_snap = d_snap
	set_volume(half_volume)
	is_fissioning = true
	fission_timer = 0.0
	_fission_snapped = false
	# Apply the parent's matching share on the spawn frame itself, so the pair's
	# volume is conserved from the instant the clone exists.
	var k0 := clampf(get_physics_process_delta_time() / maxf(tuning.fission_duration, 0.01), 0.0, 1.0)
	_set_scale_anchored(_parent_scale_for(k0))


func _spawn_fission_clone(clone_role: Role, fwd_dir: Vector3, clone_target_scale: float, spawn_offset: Vector3) -> Slime:
	var parent_node := get_parent()
	if parent_node == null:
		return null

	var clone: Slime = props.take_pooled_slime() if props != null else null
	var reused := clone != null and is_instance_valid(clone) and clone.get_parent() == parent_node
	if not reused:
		if clone != null and is_instance_valid(clone):
			clone.queue_free()
		if _slime_scene == null:
			_slime_scene = load("res://scenes/slime.tscn") as PackedScene
		if _slime_scene == null:
			return null
		clone = _slime_scene.instantiate() as Slime
		if clone == null:
			return null

	# First frame of the clone's volume-budget curve: the spawn scale the curve
	# itself would produce, so growth starts without a step.
	var k_first := get_physics_process_delta_time() / maxf(tuning.fission_duration, 0.01)
	var clone_start_scale := clampf(slime_scale * pow(maxf(_split_alpha(k_first), 0.0), 1.0 / 3.0), 0.02, clone_target_scale)

	clone.role = clone_role
	clone.tuning = tuning
	clone.props = props
	clone.floor_mesh = floor_mesh
	clone.camera = null
	clone.start_scale = clone_start_scale
	clone.target_scale = clone_target_scale
	if reused:
		clone._activate_from_pool()
	clone.slime_scale = clone_start_scale
	clone.target_scale = clone_target_scale
	if clone.body != null:
		clone.body.mesh = _lod_mesh(1)
	clone._velocity_cache = Vector3.ZERO
	clone.position = global_position + spawn_offset
	# Same floor as the parent, not the same centre height: the halves have
	# different scales, so copying the centre would bury the smaller one.
	clone.position.y = model.foot.y + model.rest_half_height * clone_start_scale
	clone._facing_yaw = _facing_yaw
	clone.target_leader = self if clone_role == Role.FOLLOWER else null

	clone.is_budding = true
	clone.bud_parent = self
	clone.bud_timer = 0.0
	clone.bud_start_scale = slime_scale
	clone.bud_sep = spawn_offset.length()
	clone.bud_target_scale = clone_target_scale
	clone.bud_fwd = fwd_dir

	if reused:
		# A reused node never runs _ready again, so registration and the RNG stream
		# are restored explicitly here.
		clone._rng.seed = props.next_slime_seed() if props != null else clone._rng.seed
		clone.props.register_slime(clone)
		clone._ai_last_pos = clone.global_position
		clone._resolve_model(0.0, 1.0, 1.0)
		clone._apply_transform()
		clone._prev_global_pos = clone.global_position
		clone._prev_scale = clone.slime_scale
		clone._refresh_exclusions()
		clone.motor.recover_overlap()
		clone._sync_proxy()
		return clone

	parent_node.add_child(clone)
	clone._prev_global_pos = clone.global_position
	clone._prev_scale = clone.slime_scale
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
