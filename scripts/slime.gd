class_name Slime
extends Node3D

const WorldLandmarks = preload("res://scripts/world_landmarks.gd")
## One jelly slime. Intent -> validated posture -> motor movement -> derived visuals.
##
## This script never writes its own position: SlimeMotor owns the transform, support
## and collision resolution; SlimeShapeModel owns the authoritative dimensions;
## SlimeProps exposes obstacle geometry, passage hints and digestion.

signal poked(local_point: Vector3, impulse: Vector3)
signal died(reason: String)

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
const LAYER_TERRAIN := 1
const LAYER_SLIMES := 2
const LAYER_OBSTACLES := 4
const LAYER_SOLID := LAYER_TERRAIN | LAYER_OBSTACLES | LAYER_SLIMES
## Shared clone prefab and mesh LOD variants (one resource per level, not per slime).
static var _slime_scene: PackedScene = null
static var _lod_meshes: Array[SphereMesh] = []

@export var role: Role = Role.PLAYER
@export var tuning: SlimeTuning

@export_group("LOD & Mesh Optimization")
## Distance from camera beyond which the slime drops to the low-poly mesh.
@export var lod_far_distance: float = 18.0
## Scale threshold below which the slime uses the low-poly mesh.
@export var lod_small_scale: float = 0.22

@export_group("Mitosis & Fission Shape")
## Normalized split progress where the neck pinches to zero. Shared by volume curve, separation, and shader neck.
@export_range(0.1, 0.95, 0.01) var split_snap: float = 0.68
## Neck radius at the seam as a fraction of the smaller half's radius.
@export_range(0.05, 0.8, 0.01) var split_neck_ratio: float = 0.32
## Angles the spawn preflight tries for the bud direction, in degrees.
@export var split_angles: Array[float] = [0.0, 30.0, -30.0, 60.0, -60.0, 90.0, -90.0, 135.0, -135.0, 180.0]

@export_group("Nodes")
@export var body: MeshInstance3D
@export var camera: Camera3D
@export var floor_mesh: MeshInstance3D
@export var props: SlimeProps

@export_group("Agent")
## Spawn scale. Clones are created with their target scale already resolved.
@export var start_scale := 0.36
@export var target_leader: Slime = null

@export_group("Developer Mode")
## Enables free 3D flight, speed multiplier steps, and noclip through terrain/walls (toggle in-game with F4).
@export var dev_mode := false
@export var dev_fly := true
@export var dev_noclip := true
@export var dev_speed := 32.0

const DEV_SPEED_STEPS := [8.0, 16.0, 32.0, 64.0, 128.0, 240.0, 420.0]

var model: SlimeShapeModel
var motor: SlimeMotor

var slime_scale := 1.0
var target_scale := 1.0
var speed01 := 0.0

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

# Jump & charge-hold state.
var is_charging_jump := false
var jump_charge := 0.0
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _air_leap_active := false
var _ai_hop_block_timer := 0.0
var _ai_hop_cooldown := 0.0

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

const SN_IMPULSE_TIME := &"uImpulseTime"
const SN_IMPULSE2_TIME := &"uImpulse2Time"
const SN_IMPULSE2_POS := &"uImpulse2Pos"
const SN_IMPULSE2_VECTOR := &"uImpulse2Vector"
const SN_MOVE_DIR := &"uMoveDir"
const SN_MOVE_AMT := &"uMoveAmt"
const SN_CRAWL := &"uCrawl"
const SN_LEAN := &"uLean"
const SN_SPLAT := &"uSplat"
const SN_SPREAD := &"uSpread"
const SN_RIPPLE_INTENSITY := &"uRippleIntensity"
const SN_FACING := &"uFacing"
const SN_BLINK := &"uBlink"
const SN_LIQUID := &"uLiquid"
const SN_LIQUID_HEIGHT := &"uLiquidHeight"
const SN_LIQUID_SPREAD := &"uLiquidSpread"
const SN_SQUEEZE_DIR := &"uSqueezeDir"
const SN_SKIN_LOCAL := &"uSkinLocal"
const SN_WATER_SUBMERSION := &"uWaterSubmersion"
const SN_WATER_Y := &"uWaterY"
const SN_WETNESS := &"uWetness"
const SN_WATER_VEL := &"uWaterVel"
const SN_REF_RADIUS := &"uRefRadius"
const SN_MELT := &"uMelt"
const SN_SHADER_LOD := &"uShaderLOD"
const SN_IMPULSE_POS := &"uImpulsePos"
const SN_IMPULSE_VECTOR := &"uImpulseVector"
const SN_DRAPE_AMT := &"uDrapeAmt"
const SN_SPLIT_AMT := &"uSplitAmt"
const SN_SPLIT_DIR := &"uSplitDir"
const SN_SPLIT_NECK_RADIUS := &"uSplitNeckRadius"
const SN_SPLIT_PARTNER_LOCAL := &"uSplitPartnerLocal"

# Engulf drape state.
var engulf_target = null
var engulf_progress := 0.0
var _solid_dent_props: Array = []

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
var _follower_sidestep_timer := 0.0
var _follower_sidestep_target := Vector3.ZERO
var _roamer_wall_block_timer := 0.0
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
var _visual_up := Vector3.UP

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
var _dev_speed_idx := 2
var _swim_ripple_timer := 0.0

var is_dead := false
var sea_darkness := 0.0
var death_reason := ""
var _last_safe_pos := Vector3.ZERO
var _terrain_ref: Node = null
var _sea_warned := false
var _last_web_toast_t := -999.0
var _combat_hit_cd := 0.0
var _slam_bounce_cd := 0.0

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
		_proxy.collision_layer = LAYER_SLIMES

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
	_follower_sidestep_timer = 0.0
	_follower_sidestep_target = Vector3.ZERO
	_roamer_wall_block_timer = 0.0
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
	set_shader_param(SN_REF_RADIUS, tuning.reference_radius)
	set_shader_param(SN_SPLIT_AMT, 0.0)
	set_shader_param(SN_SPLIT_NECK_RADIUS, 0.0)
	set_shader_param(SN_SPLIT_PARTNER_LOCAL, Vector3.ZERO)


func get_active_camera() -> Camera3D:
	if is_instance_valid(camera):
		return camera
	var vp := get_viewport()
	if vp != null:
		var cam := vp.get_camera_3d()
		if is_instance_valid(cam):
			camera = cam
			return cam
	var rig_cam := get_node_or_null("../CameraRig/Camera3D") as Camera3D
	if is_instance_valid(rig_cam):
		camera = rig_cam
		return rig_cam
	return null


func _ready() -> void:
	if tuning == null:
		tuning = load("res://resources/slime_tuning.tres") as SlimeTuning
	if camera == null:
		camera = get_active_camera()
	if floor_mesh == null:
		floor_mesh = get_node_or_null("../Floor") as MeshInstance3D
	if props == null:
		props = get_node_or_null("../Ecosystem") as SlimeProps

	if body and body.material_override is ShaderMaterial:
		_mat = body.material_override.duplicate() as ShaderMaterial
		body.material_override = _mat
		set_shader_param(SN_MELT, tuning.melt)
		set_shader_param(SN_REF_RADIUS, tuning.reference_radius)
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
	var start_surface_y := 1.25
	var terrain_node := get_node_or_null("../TerrainScene")
	if terrain_node != null and terrain_node.has_method("sample_spawn_floor_y"):
		var est_foot_y := global_position.y - model.rest_half_height * slime_scale
		start_surface_y = float(terrain_node.sample_spawn_floor_y(global_position.x, global_position.z, est_foot_y))
	elif terrain_node != null and terrain_node.has_method("sample_height"):
		start_surface_y = terrain_node.sample_height(global_position.x, global_position.z)
	else:
		var space := get_world_3d().direct_space_state if is_inside_tree() else null
		if space != null:
			var ray := PhysicsRayQueryParameters3D.new()
			ray.from = Vector3(global_position.x, 30.0, global_position.z)
			ray.to = Vector3(global_position.x, tuning.floor_y, global_position.z)
			ray.collision_mask = LAYER_OBSTACLES
			var hit := space.intersect_ray(ray)
			if not hit.is_empty():
				start_surface_y = (hit.position as Vector3).y

	global_position.y = start_surface_y + tuning.skin + model.rest_half_height * slime_scale
	motor.support_y = start_surface_y
	motor.on_ground = true
	model.set_foot(global_position + Vector3(0.0, -model.rest_half_height * slime_scale, 0.0))
	_apply_transform()
	_setup_proxy()
	_setup_core_visual()
	_prev_global_pos = global_position
	_prev_scale = slime_scale
	_last_safe_pos = global_position

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
		_core_sphere_mesh.radial_segments = 24
		_core_sphere_mesh.rings = 12
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
	_proxy.collision_layer = LAYER_SLIMES
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
		hi.radial_segments = 28
		hi.rings = 20
		var lo := SphereMesh.new()
		lo.radius = 1.6
		lo.height = 3.2
		lo.radial_segments = 16
		lo.rings = 12
		_lod_meshes = [hi, lo]
	return _lod_meshes[clampi(level, 0, _lod_meshes.size() - 1)]


var force_low_lod: bool = false

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
	if force_low_lod:
		level = 1
	elif role != Role.PLAYER:
		var cam := get_viewport().get_camera_3d()
		var far := cam == null or cam.global_position.distance_to(global_position) > lod_far_distance
		if far or slime_scale < lod_small_scale:
			level = 1
	if level == _lod_level:
		return
	_lod_level = level
	body.mesh = _lod_mesh(level)
	set_shader_param(SN_SHADER_LOD, 1.0 if level == 1 else 0.0)


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
	if props != null:
		for other in props.registered_slimes:
			if other == self or not is_instance_valid(other):
				continue
			if (other.is_merging and other.merge_target == self) or (other.is_budding and other.bud_parent == self):
				rids.append(other.get_proxy_rid())
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
	set_shader_param(&"uEatPos", zeros6)
	set_shader_param(&"uEatParam", zeros6)
	set_shader_param(&"uBoxHalf", small6)
	set_shader_param(&"uActiveEatCount", 0)
	set_shader_param(&"uSolidPos", zeros8)
	set_shader_param(&"uSolidParam", zeros8)
	set_shader_param(&"uSolidHalf", small8)
	set_shader_param(&"uSolidDir", zeros8)
	set_shader_param(&"uActiveSolidCount", 0)
	set_shader_param(&"uDrapeAmt", 0.0)
	set_shader_param(&"uSplitAmt", 0.0)
	set_shader_param(&"uSplitNeckRadius", 0.0)
	set_shader_param(&"uSplitPartnerLocal", Vector3.ZERO)
	set_shader_param(&"uSqueeze", 0.0)
	set_shader_param(&"uSqueezeLat", 1.0)
	set_shader_param(&"uSqueezeLong", 1.0)
	set_shader_param(&"uSqueezeHeight", 1.0)
	set_shader_param(&"uGapLocal", Vector3.ZERO)


# ------------------------------------------------------------------------------------------------
# Input
# ------------------------------------------------------------------------------------------------

func _is_hud_menu_open() -> bool:
	if not is_inside_tree():
		return false
	var hud := get_tree().get_first_node_in_group("hud")
	return hud != null and hud.has_method("is_menu_open") and bool(hud.call("is_menu_open"))


func _unhandled_input(event: InputEvent) -> void:
	if role != Role.PLAYER or is_dead:
		return
	if _is_hud_menu_open():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kev := event as InputEventKey
		if kev.keycode == KEY_F4 or kev.keycode == KEY_QUOTELEFT or kev.physical_keycode == KEY_QUOTELEFT:
			toggle_dev_mode()
			get_viewport().set_input_as_handled()
			return
		if dev_mode:
			if kev.keycode == KEY_N:
				toggle_dev_noclip()
				get_viewport().set_input_as_handled()
				return
			elif kev.keycode == KEY_V:
				toggle_dev_fly()
				get_viewport().set_input_as_handled()
				return
			elif kev.keycode == KEY_BRACKETRIGHT or kev.keycode == KEY_EQUAL or kev.keycode == KEY_KP_ADD:
				adjust_dev_speed(1)
				get_viewport().set_input_as_handled()
				return
			elif kev.keycode == KEY_BRACKETLEFT or kev.keycode == KEY_MINUS or kev.keycode == KEY_KP_SUBTRACT:
				adjust_dev_speed(-1)
				get_viewport().set_input_as_handled()
				return
	if dev_mode and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.alt_pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				adjust_dev_speed(1)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				adjust_dev_speed(-1)
				get_viewport().set_input_as_handled()
				return

	var cam := get_active_camera()
	if event.is_action_pressed("slime_poke") and cam:
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


func is_dev_fly_active() -> bool:
	return role == Role.PLAYER and dev_mode and dev_fly


func is_dev_noclip_active() -> bool:
	return role == Role.PLAYER and dev_mode and dev_noclip


func toggle_dev_mode() -> void:
	dev_mode = not dev_mode
	if dev_mode:
		_dev_speed_idx = clampi(_dev_speed_idx, 0, DEV_SPEED_STEPS.size() - 1)
		dev_speed = DEV_SPEED_STEPS[_dev_speed_idx]
		motor.vertical_vel = 0.0
	else:
		motor.vertical_vel = 0.0
		motor.velocity = Vector3(motor.velocity.x, 0.0, motor.velocity.z) * 0.25
		_sync_proxy()
		if is_inside_tree():
			motor.update_support()


func toggle_dev_fly() -> void:
	dev_fly = not dev_fly
	motor.vertical_vel = 0.0


func toggle_dev_noclip() -> void:
	dev_noclip = not dev_noclip
	if not dev_noclip and is_inside_tree():
		_sync_proxy()
		motor.update_support()


func adjust_dev_speed(step_delta: int) -> void:
	_dev_speed_idx = clampi(_dev_speed_idx + step_delta, 0, DEV_SPEED_STEPS.size() - 1)
	dev_speed = DEV_SPEED_STEPS[_dev_speed_idx]


func _try_poke(screen_pos: Vector2) -> void:
	var cam := get_active_camera()
	if cam == null or model == null:
		return
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
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
	var push := (hit - cam.global_position).normalized() * tuning.poke_strength
	push.y -= tuning.poke_downward
	trigger_poke(local_point, push)


func trigger_poke(local_point: Vector3, impulse: Vector3) -> void:
	_impulse_time = 0.001
	if _mat:
		set_shader_param(SN_IMPULSE_POS, local_point)
		set_shader_param(SN_IMPULSE_VECTOR, impulse)
	poked.emit(local_point, impulse)


func trigger_poke2(local_point: Vector3, impulse: Vector3) -> void:
	_impulse2_time = 0.001
	if _mat:
		set_shader_param(SN_IMPULSE2_POS, local_point)
		set_shader_param(SN_IMPULSE2_VECTOR, impulse)


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

func get_visual_position() -> Vector3:
	if not is_inside_tree():
		return position
	if _prev_global_pos.distance_squared_to(global_position) > 400.0:
		return global_position
	return _prev_global_pos.lerp(global_position, Engine.get_physics_interpolation_fraction())


## Visual-only smoothing between physics ticks. `Body` carries the mesh and shadow;
## the node itself keeps the physics transform that gameplay and picking use. The
## engine's built-in interpolation is off, so this is the single interpolator.
func _process(_delta: float) -> void:
	if body == null:
		return
	var f := Engine.get_physics_interpolation_fraction()
	var interp_pos := get_visual_position()
	var s := lerpf(_prev_scale, slime_scale, f)
	var dt_vis := clampf(_delta, 0.0, 0.1)
	if _visual_up.length_squared() < 1e-6 or not _visual_up.is_finite():
		_visual_up = Vector3.UP
	else:
		_visual_up = _visual_up.normalized()
	var target_up := Vector3.UP
	if motor != null and motor.in_water and motor.water_submersion > 0.08:
		var spd_xz := Vector2(motor.velocity.x, motor.velocity.z)
		var spd_len := spd_xz.length()
		var bob_tilt := Vector3(
			sin(_time * 2.35 + interp_pos.z * 0.55) * 0.042,
			0.0,
			cos(_time * 2.05 + interp_pos.x * 0.50) * 0.042
		) * motor.water_submersion
		var pitch_back := Vector3(-spd_xz.x, 0.0, -spd_xz.y).normalized() * clampf(spd_len * 0.015, 0.0, 0.085) if spd_len > 0.25 else Vector3.ZERO
		var cand := Vector3.UP + bob_tilt + pitch_back
		target_up = cand.normalized() if cand.length_squared() > 1e-6 else Vector3.UP
	elif motor != null and motor.on_ground and motor.ground_normal.is_finite() and motor.ground_normal.y > 0.3:
		target_up = motor.ground_normal.normalized()
	var blended_up := _visual_up.lerp(target_up, 1.0 - exp(-14.0 * dt_vis))
	_visual_up = blended_up.normalized() if blended_up.length_squared() > 1e-6 else target_up
	var d_up := clampf(Vector3.UP.dot(_visual_up), -1.0, 1.0)
	var rot_q := Quaternion.IDENTITY
	if d_up > 0.9999:
		rot_q = Quaternion.IDENTITY
	elif d_up < -0.9999:
		rot_q = Quaternion(Vector3.RIGHT, PI)
	else:
		var raw_axis := Vector3.UP.cross(_visual_up)
		if raw_axis.length_squared() > 1e-8:
			var axis := raw_axis.normalized()
			if axis.is_normalized():
				rot_q = Quaternion(axis, acos(d_up)).normalized()

	# Foot-anchored slope alignment:
	# In body local coordinates, foot is at (0, -model.rest_half_height * s, 0).
	# Placing body.global_position at (visual_foot + _visual_up * foot_offset) ensures
	# the bottom of the mesh touches the slope surface at visual_foot, and the entire
	# base disc lies flush against the slope plane without dipping underground.
	var foot_offset := (model.rest_half_height if model != null else 1.28) * s
	var visual_foot := interp_pos - Vector3(0.0, foot_offset, 0.0)
	body.global_position = visual_foot + _visual_up * foot_offset

	# The node already applies slime_scale; undo it on the child so the total visual
	# scale is exactly the interpolated one and never compounds between ticks.
	body.basis = Basis(rot_q).orthonormalized().scaled(Vector3.ONE * (s / maxf(slime_scale, 1e-4)))
	if props != null and not _is_sleeping and not _solid_dent_props.is_empty():
		props._update_solid_uniforms_visual(self)


func _physics_process(delta: float) -> void:
	# Snapshot the physics state before this tick moves it: _process lerps the mesh
	# from here to the committed transform, so 120/144 Hz clients see smooth motion
	# while gameplay stays on the fixed tick.
	_prev_global_pos = global_position
	_prev_scale = slime_scale

	var dt := delta
	_time += dt
	_combat_hit_cd = maxf(0.0, _combat_hit_cd - dt)
	_slam_bounce_cd = maxf(0.0, _slam_bounce_cd - dt)
	_impulse_time = minf(_impulse_time + dt, 4.0)
	_impulse2_time = minf(_impulse2_time + dt, 4.0)
	# Cleared once per tick so posture/growth reasons survive until presentation.
	expansion_blocked = ""

	if role == Role.PLAYER and is_dead:
		motor.velocity = Vector3.ZERO
		motor.vertical_vel = 0.0
		_update_presentation(dt)
		_tick_props(dt)
		return

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
	if role == Role.PLAYER and dev_mode:
		_tick_dev_movement(dt)
		return
	motor.want_run_swim = (role == Role.PLAYER and Input.is_action_pressed("run") and desired.length_squared() > 0.01)
	motor.update_water_state(dt, _is_subterranean_for_water())
	if motor.on_ground or motor.in_water:
		_air_leap_active = false
	if role == Role.PLAYER:
		desired = _tick_player_jump(dt, desired)
	if motor.water_submersion > 0.02:
		desired *= lerpf(1.0, 0.78, motor.water_submersion)
		desired += motor.water_flow_vel * clampf(motor.water_submersion * 1.4, 0.25, 1.0)
	var in_sticky := false
	if role == Role.PLAYER and motor.on_ground and not motor.in_water:
		var t_node := get_tree().get_first_node_in_group("terrain")
		if t_node == null and get_parent() != null:
			t_node = get_parent().get_node_or_null("TerrainScene")
		if t_node != null and t_node.has_method("get_webwood_region"):
			var wreg = t_node.call("get_webwood_region")
			if wreg != null and wreg.has_method("is_in_sticky_web"):
				in_sticky = bool(wreg.call("is_in_sticky_web", global_position))
		else:
			in_sticky = WorldLandmarks.is_in_sticky_web(global_position)
	if in_sticky:
		desired *= tuning.sticky_web_speed_mult
		if _time - _last_web_toast_t > 6.5:
			_last_web_toast_t = _time
			var web_hud := get_tree().get_first_node_in_group("hud")
			if web_hud != null and web_hud.has_method("show_toast"):
				web_hud.call("show_toast", "Sticky Spider Webs! (Jump to break free)", Color(0.92, 0.88, 0.98), 2.2)
	var v_resp := tuning.velocity_response
	if motor.just_jumped:
		pass
	elif not motor.on_ground and not motor.in_water and _air_leap_active:
		# Preserve ballistic arc momentum while airborne; allow gentle mid-air steering or reverse braking.
		var cur_spd := Vector2(motor.velocity.x, motor.velocity.z).length()
		if desired.length_squared() > 0.01 and cur_spd > 0.1:
			var desired_h := Vector3(desired.x, 0.0, desired.z)
			var cur_h := Vector3(motor.velocity.x, 0.0, motor.velocity.z)
			if desired_h.dot(cur_h) < 0.0:
				motor.velocity = motor.velocity.lerp(desired, 1.0 - exp(-v_resp * tuning.jump_air_control * dt))
			else:
				var target_dir := desired_h.normalized()
				var steered_dir := cur_h.normalized().lerp(target_dir, 1.0 - exp(-3.5 * tuning.jump_air_control * dt)).normalized()
				var target_spd := maxf(cur_spd, desired_h.length())
				motor.velocity.x = steered_dir.x * target_spd
				motor.velocity.z = steered_dir.z * target_spd
	else:
		if motor.in_water:
			v_resp = lerpf(v_resp, 5.2, motor.water_submersion)
		elif not motor.on_ground:
			v_resp *= tuning.jump_air_control
		motor.velocity = motor.velocity.lerp(desired, 1.0 - exp(-v_resp * dt))
	pre_move_velocity = motor.velocity
	_update_scale(dt)
	_resolve_posture(dt)
	_resolve_model()

	motor.recover_overlap()
	motor.move_horizontal(Vector3(motor.velocity.x, 0.0, motor.velocity.z) * dt)
	if role != Role.PLAYER:
		_ai_hop_cooldown = maxf(0.0, _ai_hop_cooldown - dt)
		if desired.length_squared() > 0.25 and motor.last_sweep_fraction < 0.25 and (motor.on_ground or motor.in_water):
			_ai_hop_block_timer += dt
			if _ai_hop_block_timer >= 0.18 and _ai_hop_cooldown <= 0.0:
				_ai_hop_block_timer = 0.0
				_ai_hop_cooldown = 1.2
				_execute_jump(0.0, desired)
		else:
			_ai_hop_block_timer = 0.0
	motor.update_support()
	motor.move_vertical(dt, target_scale)
	motor.recover_overlap()
	_clamp_arena()
	_apply_transform()
	_verify_posture_after_move()
	_sync_proxy()

	if role == Role.PLAYER and not is_dev_noclip_active():
		_tick_ocean_boundary(dt)

	_update_presentation(dt)
	_update_engulf(dt)
	_tick_props(dt)


func _tick_ocean_boundary(dt: float) -> void:
	if is_dead or _is_subterranean_for_water():
		if _is_subterranean_for_water():
			sea_darkness = maxf(0.0, sea_darkness - dt * 0.65)
		return
	if _terrain_ref == null or not is_instance_valid(_terrain_ref):
		var parent_node := get_parent()
		if parent_node != null:
			_terrain_ref = parent_node.get_node_or_null("TerrainScene")
	if _terrain_ref == null or not _terrain_ref.has_method("sample_coast_distance"):
		return

	var coast_dist := float(_terrain_ref.sample_coast_distance(global_position.x, global_position.z))
	var sl := float(_terrain_ref.get("sea_level"))
	if not motor.in_water and motor.on_ground and coast_dist < -20.0 and global_position.y >= sl + 0.6:
		_last_safe_pos = global_position

	var warn_d := tuning.ocean_warning_distance
	var lethal_d := tuning.get_validated_ocean_lethal_distance()
	var in_ocean_zone := motor.in_water or global_position.y < sl + 14.0
	if in_ocean_zone and coast_dist >= warn_d and not _sea_warned:
		_sea_warned = true
		var hud := get_tree().get_first_node_in_group("hud")
		if hud != null and hud.has_method("show_toast"):
			hud.show_toast("Something stirs in the abyssal sea... turn back!", Color(1.0, 0.52, 0.48), 4.0)

	if in_ocean_zone and coast_dist >= lethal_d:
		var darken_rate := clampf(0.18 + (coast_dist - lethal_d) * 0.0014, 0.18, 0.42)
		sea_darkness = clampf(sea_darkness + darken_rate * dt, 0.0, 1.0)
		if sea_darkness >= 1.0:
			trigger_death("You were killed by an unknown creature")
	else:
		sea_darkness = maxf(0.0, sea_darkness - dt * 0.48)
		if coast_dist < maxf(warn_d - 25.0, 5.0):
			_sea_warned = false


func apply_combat_hit(volume_loss: float, impulse: Vector3, attacker_name: String, bypass_cd: bool = false) -> void:
	if is_dead:
		return
	if role == Role.PLAYER and is_dev_noclip_active():
		return
	if not impulse.is_finite() or is_nan(volume_loss) or is_inf(volume_loss):
		return
	if not bypass_cd and _combat_hit_cd > 0.0:
		return
	_combat_hit_cd = 0.32
	var clamped_loss := clampf(volume_loss, 0.0, maxf(get_volume() * 0.25, 0.5))
	var new_vol := maxf(0.05, get_volume() - clamped_loss)
	set_volume(new_vol)
	if motor != null:
		motor.apply_knockback_impulse(impulse)
	var local_pt := Vector3(0.0, 0.3, 0.6)
	if impulse.length_squared() > 1e-4 and body != null and absf(body.global_transform.basis.determinant()) > 1e-5:
		local_pt = (body.global_transform.basis.inverse() * (-impulse.normalized() * 0.7)).limit_length(1.1)
	var poke_vec := (impulse * 0.45).limit_length(1.2)
	trigger_poke(local_pt, poke_vec)
	if target_scale <= tuning.lethal_scale_threshold:
		trigger_death("You were overwhelmed by %s" % attacker_name)


func trigger_death(reason: String = "You were killed by an unknown creature") -> void:
	if is_dead:
		return
	is_dead = true
	sea_darkness = 1.0
	death_reason = reason
	if motor != null:
		motor.velocity = Vector3.ZERO
		motor.vertical_vel = 0.0
	died.emit(reason)


func revive_at_safe_pos() -> void:
	var fallback := Vector3(0.0, 22.0, 0.0)
	var safe := _last_safe_pos if _last_safe_pos.length_squared() > 0.001 else fallback
	target_scale = maxf(target_scale, start_scale)
	slime_scale = maxf(slime_scale, start_scale)
	if _terrain_ref == null or not is_instance_valid(_terrain_ref):
		if get_parent() != null:
			_terrain_ref = get_parent().get_node_or_null("TerrainScene")
	var foot_y := safe.y
	if _terrain_ref != null and _terrain_ref.has_method("sample_height"):
		foot_y = float(_terrain_ref.sample_height(safe.x, safe.z))
	else:
		var half_h := (model.rest_half_height if model != null else 1.28) * slime_scale
		foot_y = safe.y - half_h
	is_dead = false
	sea_darkness = 0.0
	death_reason = ""
	_sea_warned = false
	_combat_hit_cd = 0.0
	_slam_bounce_cd = 0.0
	_release_passage(0.0)
	if motor != null:
		motor.teleport_to(Vector3(safe.x, foot_y + tuning.skin, safe.z))
	_prev_global_pos = global_position
	_apply_transform()
	_sync_proxy()
	if is_inside_tree():
		var eco := get_tree().get_first_node_in_group("world_ecosystem")
		if eco != null and eco.has_method("clear_all_slime_aggro"):
			eco.call("clear_all_slime_aggro")


func teleport_to_world(target_xz: Vector2, force_y: float = NAN, is_underground: bool = false) -> void:
	if not target_xz.is_finite():
		return
	if _terrain_ref == null or not is_instance_valid(_terrain_ref):
		if get_parent() != null:
			_terrain_ref = get_parent().get_node_or_null("TerrainScene")
		if _terrain_ref == null and is_inside_tree():
			_terrain_ref = get_tree().get_first_node_in_group("terrain")
	var dest_foot_y := 22.0
	if is_finite(force_y):
		dest_foot_y = force_y
	elif _terrain_ref != null:
		if is_underground and _terrain_ref.has_method(&"sample_spawn_floor_y"):
			dest_foot_y = float(_terrain_ref.sample_spawn_floor_y(target_xz.x, target_xz.y, 12.0))
		elif _terrain_ref.has_method(&"sample_height"):
			dest_foot_y = float(_terrain_ref.sample_height(target_xz.x, target_xz.y))

	is_dead = false
	sea_darkness = 0.0
	death_reason = ""
	_sea_warned = false
	_combat_hit_cd = 0.0
	_slam_bounce_cd = 0.0
	_release_passage(0.0)
	breadcrumbs.clear()
	_breadcrumb_timer = 0.0
	if motor != null:
		motor.teleport_to(Vector3(target_xz.x, dest_foot_y + tuning.skin, target_xz.y))
	_prev_global_pos = global_position
	_apply_transform()
	_sync_proxy()

	if _terrain_ref != null and "_grass_recenter_cooldown" in _terrain_ref:
		_terrain_ref.set("_grass_recenter_cooldown", 0.0)

	if is_inside_tree():
		var eco := get_tree().get_first_node_in_group("world_ecosystem")
		if eco != null and eco.has_method("clear_all_slime_aggro"):
			eco.call("clear_all_slime_aggro")
		var cave_atm := get_tree().get_first_node_in_group("cave_atmosphere")
		if cave_atm == null and _terrain_ref != null:
			cave_atm = _terrain_ref.get_node_or_null("Cave/CaveAtmosphere")
		if cave_atm != null:
			cave_atm.set("_last_cam_pos", Vector3(1e9, 1e9, 1e9))
			cave_atm.set("_settled", false)

	var rig := get_node_or_null("../CameraRig")
	if rig != null and rig.has_method("snap_to_follow"):
		rig.call("snap_to_follow")


func _is_subterranean_for_water() -> bool:
	var cl := CaveLayout.to_local(global_position)
	return cl.z > -4.0 and cl.z < 245.0 and cl.x > -225.0 and cl.x < 80.0 and global_position.y < 52.0


func _tick_props(dt: float) -> void:
	if props:
		props.slime_ticked(self, dt)


## A clone that wants nothing, holds a settled posture and has no moving neighbour
## cannot change this tick: skip exclusions, posture probes, sweeps and presentation.
func _can_sleep(desired: Vector3) -> bool:
	if role == Role.PLAYER or props == null:
		return false
	if motor.in_water:
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
		var new_sweep_orig := model.foot + Vector3(0.0, new_core_r + 0.04, 0.0)
		var new_center := model.foot + Vector3(0.0, model.rest_half_height * new_scale, 0.0)
		if not motor.core_sphere_clear(new_sweep_orig, new_core_r) \
				or not motor.core_sphere_clear(new_center, new_core_r):
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
	var floor_sq := tuning.min_normal_squeeze
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
	liquid_amt = 0.0
	height_ratio = 1.0


func _height_ratio_for(_liq: float, _sq: float) -> float:
	return 1.0


# ------------------------------------------------------------------------------------------------
# Role input / AI
# ------------------------------------------------------------------------------------------------

func _process_player_input() -> Vector3:
	if _is_hud_menu_open():
		return Vector3.ZERO
	var in_z := Input.get_axis("move_back", "move_forward")
	var in_x := Input.get_axis("move_left", "move_right")

	var cam := get_active_camera()
	var fwd := Vector3(0.0, 0.0, -1.0)
	var right := Vector3(1.0, 0.0, 0.0)
	if cam != null:
		fwd = -cam.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() < 0.0001:
			fwd = -cam.global_transform.basis.y
			fwd.y = 0.0
		if fwd.length_squared() > 0.0001:
			fwd = fwd.normalized()
		else:
			fwd = Vector3(0.0, 0.0, -1.0)

		right = cam.global_transform.basis.x
		right.y = 0.0
		if right.length_squared() > 0.0001:
			right = right.normalized()
		else:
			right = fwd.cross(Vector3.UP).normalized()
	else:
		right = fwd.cross(Vector3.UP).normalized()

	var desired := fwd * in_z + right * in_x

	if dev_mode:
		cur_max = dev_speed * (2.5 if Input.is_action_pressed("run") else 1.0)
	elif Input.is_action_pressed("run"):
		cur_max = tuning.run_speed
	else:
		cur_max = tuning.walk_speed

	if desired.length_squared() > 0.0:
		desired = desired.normalized() * cur_max
	return desired


## Compute vertical launch speed (m/s) for a target apex height, scaling gently with sqrt(slime_scale).
func jump_impulse_for_height(height_m: float) -> float:
	return sqrt(maxf(0.0, 2.0 * tuning.gravity * height_m * sqrt(maxf(slime_scale, 0.1))))


func _execute_jump(charge: float, move_dir: Vector3 = Vector3.ZERO) -> void:
	var c := clampf(charge, 0.0, 1.0)
	var min_h := tuning.jump_water_min_height if motor.in_water else tuning.jump_min_height
	var max_h := tuning.jump_water_max_height if motor.in_water else tuning.jump_max_height
	var target_h := lerpf(min_h, max_h, pow(c, 0.85))
	motor.jump(jump_impulse_for_height(target_h))

	var horiz_dir := Vector3(move_dir.x, 0.0, move_dir.z)
	if horiz_dir.length_squared() > 0.01:
		horiz_dir = horiz_dir.normalized()
		var scale_boost := pow(maxf(slime_scale, 0.1), 0.25)
		var leap_speed := lerpf(tuning.jump_forward_min_speed, tuning.jump_forward_max_speed, pow(c, 0.85)) * scale_boost
		var cur_horiz_speed := Vector2(motor.velocity.x, motor.velocity.z).length()
		var final_speed := maxf(cur_horiz_speed, leap_speed)
		motor.velocity.x = horiz_dir.x * final_speed
		motor.velocity.z = horiz_dir.z * final_speed
		_air_leap_active = true
	else:
		_air_leap_active = false

	is_charging_jump = false
	jump_charge = 0.0
	_coyote_timer = 0.0
	_jump_buffer_timer = 0.0
	splat_x = minf(splat_x, -0.18)
	splat_v -= 6.8 + 4.5 * c
	spread_v -= 3.6 + 2.2 * c
	var poke_dir := Vector3(0.0, 1.05 + 0.85 * c, 0.0) + horiz_dir * (0.55 + 0.50 * c)
	trigger_poke(Vector3(0.0, -0.65 * tuning.reference_radius, 0.0), poke_dir)
	if role == Role.PLAYER and has_node("/root/SettingsManager"):
		get_node("/root/SettingsManager").play_ui_sound("jump")


func _tick_player_jump(dt: float, desired: Vector3) -> Vector3:
	var raw_desired := desired
	var can_jump_now := motor.on_ground or motor.in_water
	if can_jump_now:
		_coyote_timer = tuning.jump_coyote_time
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - dt)
	_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - dt)

	var jump_pressed := Input.is_action_pressed("jump")
	var jump_just_pressed := Input.is_action_just_pressed("jump")

	if jump_just_pressed:
		if _coyote_timer > 0.0:
			is_charging_jump = true
			jump_charge = 0.0
		else:
			_jump_buffer_timer = tuning.jump_buffer_time

	if is_charging_jump:
		if jump_pressed and (_coyote_timer > 0.0 or can_jump_now):
			jump_charge = minf(1.0, jump_charge + dt / maxf(tuning.jump_charge_time, 0.05))
			desired *= tuning.jump_charge_move_mult
		else:
			_execute_jump(jump_charge, raw_desired)
	elif _jump_buffer_timer > 0.0 and can_jump_now:
		_jump_buffer_timer = 0.0
		if jump_pressed:
			is_charging_jump = true
			jump_charge = 0.0
		else:
			_execute_jump(0.0, raw_desired)

	return desired


func _tick_dev_movement(dt: float) -> void:
	var desired_horiz := _process_player_input()
	var in_y := 0.0
	if dev_fly:
		if Input.is_key_pressed(KEY_SPACE):
			in_y += 1.0
		if Input.is_key_pressed(KEY_C) or Input.is_key_pressed(KEY_CTRL):
			in_y -= 1.0
	var active_speed := dev_speed * (2.5 if Input.is_action_pressed("run") else 1.0)
	cur_max = active_speed
	var desired := desired_horiz + Vector3(0.0, in_y * active_speed, 0.0)
	if desired.length_squared() > active_speed * active_speed and dev_fly:
		desired = desired.normalized() * active_speed

	motor.velocity = motor.velocity.lerp(desired, 1.0 - exp(-18.0 * dt))
	pre_move_velocity = motor.velocity
	_update_scale(dt)
	_resolve_posture(dt)
	_resolve_model()

	if dev_noclip:
		# Noclip: ignore walls, terrain, caves, and arena boundaries in all 3 axes.
		if dev_fly:
			global_position += motor.velocity * dt
			motor.vertical_vel = 0.0
			motor.on_ground = false
			motor.ground_normal = Vector3.UP
			motor.support_y = global_position.y - model.rest_half_height * model.scale
		else:
			# Ground-follow noclip (walks through cave walls & props while hugging terrain/cave floor).
			global_position += Vector3(motor.velocity.x, 0.0, motor.velocity.z) * dt
			motor.update_support()
			motor.move_vertical(dt, target_scale)
	else:
		# Clip-enabled Dev Fly / Dev Sprint: collides solidly with cave walls and terrain.
		motor.recover_overlap()
		if dev_fly:
			motor.move_horizontal(Vector3(motor.velocity.x, 0.0, motor.velocity.z) * dt)
			var dy := motor.velocity.y * dt
			if absf(dy) > 1e-6:
				motor._sync_foot()
				var fr_v := motor._cast(model.foot, Vector3(0.0, dy, 0.0), true, null, LAYER_SOLID)
				var safe_v: float = 1.0 if float(fr_v[1]) >= 0.999999 else clampf(float(fr_v[0]), 0.0, 1.0)
				global_position.y += dy * safe_v
			motor.vertical_vel = 0.0
			motor.on_ground = false
			motor.ground_normal = Vector3.UP
			motor.support_y = global_position.y - model.rest_half_height * model.scale
		else:
			motor.move_horizontal(Vector3(motor.velocity.x, 0.0, motor.velocity.z) * dt)
			motor.update_support()
			motor.move_vertical(dt, target_scale)
		motor.recover_overlap()

	if dev_noclip:
		motor.in_water = false
		motor.water_y = -9999.0
		motor.water_depth = 0.0
		motor.water_submersion = 0.0
		motor.water_flow_vel = Vector3.ZERO
		motor.water_wetness = maxf(0.0, motor.water_wetness - dt * 0.5)
		motor.just_splashed = false
	else:
		motor.update_water_state(dt, _is_subterranean_for_water())
	if _mat:
		set_shader_param(SN_WATER_SUBMERSION, motor.water_submersion)
		set_shader_param(SN_WATER_Y, motor.water_y if motor.in_water else -9999.0)
		set_shader_param(SN_WETNESS, motor.water_wetness)
		set_shader_param(SN_WATER_VEL, Vector3(motor.velocity.x, motor.vertical_vel, motor.velocity.z))

	_apply_transform()
	_verify_posture_after_move()


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
	if _ai_last_pos.distance_squared_to(global_position) > 0.08:
		_follower_stuck_timer = 0.0
		_ai_last_pos = global_position
	if _follower_sidestep_timer > 0.0:
		_follower_sidestep_timer = maxf(0.0, _follower_sidestep_timer - dt)
		target_pt = _follower_sidestep_target
		to_target = target_pt - global_position
		to_target.y = 0.0
		dist = to_target.length()
	elif (_follower_stuck_timer > minf(tuning.follower_stuck_time, 0.85) or motor.last_sweep_fraction < 0.15) and dist > 0.8:
		var fwd_n := to_target.normalized() if dist > 1e-4 else Vector3.FORWARD
		var perp := fwd_n.cross(Vector3.UP).normalized()
		var opt_a := perp * 2.4 + fwd_n * 1.6
		var opt_b := -perp * 2.4 + fwd_n * 1.6
		var clear_a := motor.sweep_clear_distance(slime_scale, opt_a)
		var clear_b := motor.sweep_clear_distance(slime_scale, opt_b)
		var chosen := opt_a if clear_a >= clear_b else opt_b
		_follower_sidestep_target = global_position + chosen
		_follower_sidestep_timer = 0.75
		_follower_stuck_timer = 0.0
		target_pt = _follower_sidestep_target
		to_target = target_pt - global_position
		to_target.y = 0.0
		dist = to_target.length()

	cur_max = tuning.walk_speed
	if dist > tuning.follower_catch_up_distance:
		cur_max = tuning.run_speed * 0.9

	var stop_dist := slime_scale * 0.35 + 0.16
	var slow_dist := stop_dist + 1.8
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

	if _ai_last_pos.distance_squared_to(global_position) > 0.08:
		_ai_stuck_timer = 0.0
		_ai_last_pos = global_position

	if motor.last_sweep_fraction < 0.18:
		_roamer_wall_block_timer += dt
	else:
		_roamer_wall_block_timer = 0.0

	# 1. Actively forage nearby edible crystal fragments & props within 13 m
	if props != null and _ai_recovery_timer <= 0.0:
		var near_props := props.query_nearby_props(Vector2(global_position.x, global_position.z), 13.0)
		var best_p = null
		var best_d2 := INF
		for p in near_props:
			if not props.is_edible_by_push(self, p) or p.mesh == null or not is_instance_valid(p.mesh):
				continue
			var ppos: Vector3 = p.mesh.global_position
			if absf(ppos.y - global_position.y) > 2.4:
				continue
			var d2 := global_position.distance_squared_to(ppos)
			if d2 < best_d2:
				var to_p := Vector3(ppos.x - global_position.x, 0.0, ppos.z - global_position.z)
				if to_p.length() < 1.2 or motor.sweep_clear_distance(slime_scale, to_p) >= to_p.length() * 0.75:
					best_d2 = d2
					best_p = p
		if best_p != null:
			var f_dir: Vector3 = best_p.mesh.global_position - global_position
			f_dir.y = 0.0
			if f_dir.length_squared() > 0.001:
				cur_max = tuning.walk_speed
				return f_dir.normalized() * cur_max

	# 2. Wall-aware wander target selection (re-picks immediately if blocked by wall/boulder)
	var need_new_target := (_ai_target_pos == Vector3.ZERO) \
		or (global_position.distance_squared_to(_ai_target_pos) < 2.25) \
		or (_ai_roam_timer > 0.0) \
		or (_roamer_wall_block_timer > 0.32) \
		or (_ai_stuck_timer > minf(tuning.roamer_stuck_time, 1.1))

	if need_new_target:
		_ai_roam_timer = -_rng.randf_range(2.2, 4.2)
		_roamer_wall_block_timer = 0.0
		_ai_stuck_timer = 0.0
		var base_ang := atan2(_crawl_dir.x, _crawl_dir.z) if _crawl_dir.length_squared() > 0.01 else _rng.randf() * TAU
		var wander_dist := _rng.randf_range(5.5, 11.5)
		var best_dest := global_position
		var best_clear := -1.0
		var cand_offsets := [0.0, 0.55, -0.55, 1.15, -1.15, 1.85, -1.85, 2.65, -2.65, PI]
		for ci in range(cand_offsets.size()):
			var ang := base_ang + float(cand_offsets[ci]) + _rng.randf_range(-0.22, 0.22)
			var step_v := Vector3(sin(ang) * wander_dist, 0.0, cos(ang) * wander_dist)
			var clear_d := motor.sweep_clear_distance(slime_scale, step_v)
			# Slight preference for forward/diagonal headings when clearance is comparable
			var score := clear_d - float(ci) * 0.15
			if score > best_clear:
				best_clear = score
				var use_d := maxf(clear_d * 0.85, 1.5)
				best_dest = global_position + Vector3(sin(ang) * use_d, 0.0, cos(ang) * use_d)
		var flat := Vector2(best_dest.x, best_dest.z)
		if flat.length() > tuning.arena_radius * 0.85:
			flat = flat.normalized() * (tuning.arena_radius * 0.75)
			best_dest.x = flat.x
			best_dest.z = flat.y
		_ai_target_pos = best_dest

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
	if not motor.on_ground and not motor.in_water:
		var arc_lean := Vector3(motor.velocity.x, 0.0, motor.velocity.z) * clampf(motor.vertical_vel / 14.0, -0.8, 1.2) * 0.16
		lean_target = arc_lean - _lean
	var sdt := minf(dt, 1.0 / 30.0)
	_lean_vel += lean_target * tuning.lean_stiffness * sdt
	_lean_vel += _lean_vel * (-tuning.lean_damping * sdt)
	_lean += _lean_vel * sdt
	if _time - touch_time < 0.2:
		_lean_vel = Vector3.ZERO
		_lean *= exp(-14.0 * dt)

	if motor.just_landed:
		var imp := clampf(motor.landing_impact_speed / 15.0, 0.22, 1.45)
		splat_v += imp * 7.5
		spread_v += imp * 5.2
		trigger_poke(Vector3(0.0, 0.85 * tuning.reference_radius, 0.0), Vector3(0.0, -imp * 1.65, 0.0))
		trigger_poke2(Vector3(0.0, -0.45 * tuning.reference_radius, 0.0), Vector3(0.0, imp * 1.05, 0.0))

	if motor.just_splashed:
		var simp := clampf(absf(motor.vertical_vel) * 0.12 + speed * 0.08, 0.24, 1.15)
		splat_v += simp * 4.4
		spread_v += simp * 4.8
		trigger_poke(Vector3(0.0, -0.55 * tuning.reference_radius, 0.0), Vector3(0.0, simp * 1.15, 0.0))
	elif motor.in_water and speed > 1.6:
		_swim_ripple_timer += dt
		if _swim_ripple_timer >= 0.34:
			_swim_ripple_timer = 0.0
			var fdir := Vector3(_crawl_dir.x, 0.0, _crawl_dir.z).normalized()
			trigger_poke2(fdir * 1.1 * tuning.reference_radius, -fdir * 0.32 + Vector3(0.0, 0.18, 0.0))
	else:
		_swim_ripple_timer = 0.34

	var air_stretch := clampf((absf(motor.vertical_vel) - 0.8) / 14.0, 0.0, 0.42) if (not motor.on_ground and not motor.in_water) else 0.0
	var splat_target := 0.56 * jump_charge if is_charging_jump else -air_stretch
	splat_v += (splat_target - splat_x) * 48.0 * sdt - splat_v * 8.5 * sdt
	splat_x = clampf(splat_x + splat_v * sdt, -0.44, 0.68)
	var spread_target := 0.36 * jump_charge if is_charging_jump else (-0.14 * (air_stretch / 0.42))
	spread_v += (spread_target - spread_x) * 34.0 * sdt - spread_v * 7.2 * sdt
	spread_x = clampf(spread_x + spread_v * sdt, -0.24, 0.58)

	if speed > tuning.moving_threshold:
		var diff := atan2(_crawl_dir.x, _crawl_dir.z) - _facing_yaw
		diff = atan2(sin(diff), cos(diff))
		_facing_yaw += diff * (1.0 - exp(-tuning.facing_response * dt))
	var blink := tuning.blink_closed_amount if fmod(_time, tuning.blink_period) > tuning.blink_start else 1.0

	if _mat:
		var air_crawl_mult := 0.15 if (not motor.on_ground and not motor.in_water) else 1.0
		var charge_tremble := 0.25 * jump_charge if is_charging_jump else 0.0
		set_shader_param(SN_IMPULSE_TIME, _impulse_time)
		set_shader_param(SN_IMPULSE2_TIME, _impulse2_time)
		set_shader_param(SN_MOVE_DIR, _crawl_dir)
		set_shader_param(SN_MOVE_AMT, speed01 * (1.0 - 0.95 * calm) * air_crawl_mult)
		set_shader_param(SN_CRAWL, _crawl_phase)
		set_shader_param(SN_LEAN, _lean)
		set_shader_param(SN_SPLAT, splat_x)
		set_shader_param(SN_SPREAD, spread_x)
		set_shader_param(SN_RIPPLE_INTENSITY, tuning.ripple_base + tuning.ripple_per_speed * speed01 + liquid_amt * 0.15 + press_amt * 0.28 + absf(splat_x) * 0.35 + charge_tremble)
		set_shader_param(SN_FACING, _facing_yaw)
		set_shader_param(SN_BLINK, blink)
		set_shader_param(SN_LIQUID, liquid_amt)
		set_shader_param(SN_LIQUID_HEIGHT, height_ratio)
		set_shader_param(SN_LIQUID_SPREAD, model.spread)
		set_shader_param(SN_SQUEEZE_DIR, sq_dir)
		set_shader_param(SN_SKIN_LOCAL, tuning.skin / maxf(slime_scale * model.spread, 1e-3))
		set_shader_param(SN_WATER_SUBMERSION, motor.water_submersion)
		set_shader_param(SN_WATER_Y, motor.water_y if motor.in_water else -9999.0)
		set_shader_param(SN_WETNESS, motor.water_wetness)
		set_shader_param(SN_WATER_VEL, Vector3(motor.velocity.x, motor.vertical_vel, motor.velocity.z))

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

	if engulf_progress > 0.0:
		engulf_progress = maxf(0.0, engulf_progress - dt * 2.0)
		set_shader_param(SN_DRAPE_AMT, engulf_progress)
		if engulf_progress <= 0.001:
			engulf_progress = 0.0
			engulf_target = null
			set_shader_param(SN_DRAPE_AMT, 0.0)
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
		var progress := smoothstep(0.0, split_snap, k)
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

	if k < split_snap:
		# Phase 1: tension stretch and neck formation against the separating half.
		var stretch_k := k / split_snap
		var e := sin(stretch_k * PI * 0.5)
		set_shader_param(SN_SPLIT_AMT, e * 0.95)
	else:
		# Phase 2: the bridge snaps, and the body recoils with an elastic jiggle.
		if not _fission_snapped:
			_fission_snapped = true
			trigger_poke(Vector3(fission_fwd.x, 0.25, fission_fwd.z).normalized() * 1.5, -fission_fwd * 1.6)
			trigger_poke2(Vector3(-fission_fwd.x, -0.1, -fission_fwd.z).normalized() * 1.5, fission_fwd * 0.8)

		var snap_k := (k - split_snap) / (1.0 - split_snap)
		var snap_decay := exp(-snap_k * 5.5) * cos(snap_k * PI * 2.5)
		set_shader_param(SN_SPLIT_AMT, maxf(0.0, snap_decay * 0.85))

	_update_split_neck(k, clone)

	motor.update_support()
	motor.move_vertical(dt, target_scale)
	_apply_transform()
	set_shader_param(SN_SPLIT_DIR, fission_fwd)

	if k >= 1.0:
		is_fissioning = false
		if clone != null and is_instance_valid(clone) and clone.is_budding:
			clone._finish_budding()
		fission_clone = null
		_set_scale_anchored(fission_target_scale)
		_resolve_model(0.0, 1.0, 1.0)
		_apply_transform()
		set_shader_param(SN_SPLIT_AMT, 0.0)
		set_shader_param(SN_SPLIT_NECK_RADIUS, 0.0)
		set_shader_param(SN_SPLIT_PARTNER_LOCAL, Vector3.ZERO)
	_sync_proxy()


## Shared volume budget progress: the clone's fraction of the pre-split volume.
## Coupled splits transfer volume along an S-curve that reaches 0.5 exactly at the
## snap point, so the halves hold their final mass for the whole recoil phase.
func _split_alpha(k: float) -> float:
	if not tuning.use_coupled_split:
		return 0.5 * clampf(k, 0.0, 1.0)
	return 0.5 * smoothstep(0.0, split_snap, k)


func _parent_scale_for(k: float) -> float:
	return fission_start_scale * pow(maxf(1.0 - _split_alpha(k), 0.0), 1.0 / 3.0)


## Publish the world-coupled hourglass to the shader. The neck radius peaks mid-split
## and pinches to zero exactly at split_snap, so both surfaces meet at the seam until
## the instant they separate.
func _update_split_neck(k: float, partner: Slime) -> void:
	if not tuning.use_coupled_split or partner == null or not is_instance_valid(partner) or k >= split_snap:
		set_shader_param(SN_SPLIT_NECK_RADIUS, 0.0)
		set_shader_param(SN_SPLIT_PARTNER_LOCAL, Vector3.ZERO)
		return
	var ramp := sin(clampf((k - 0.15) / (split_snap - 0.15), 0.0, 1.0) * PI)
	var r_self := model.rest_max_radius * slime_scale
	var r_partner := partner.model.rest_max_radius * partner.slime_scale
	var neck_world := minf(r_self, r_partner) * split_neck_ratio * ramp
	var local_radius := neck_world / maxf(slime_scale * model.spread, 1e-4)
	set_shader_param(SN_SPLIT_PARTNER_LOCAL, model.mesh_local(partner.global_position - global_position))
	set_shader_param(SN_SPLIT_NECK_RADIUS, local_radius)


## The clone's share of the pre-split volume at shared progress `k`, as a scale.
func _bud_scale_for(k: float) -> float:
	return bud_start_scale * pow(maxf(_split_alpha(k), 0.0), 1.0 / 3.0)


## Apply the clone's volume-budget scale for shared progress `k`. Returns false when
## the requested growth is blocked by level geometry; the scale is held so the parent
## can hold its own progress instead of handing over volume this hull cannot hold.
func set_bud_scale(k: float) -> bool:
	var s := maxf(_bud_scale_for(k), 0.02)
	bud_growth_blocked = false
	if absf(s - slime_scale) > 1e-6:
		_set_scale_anchored(s)
		_resolve_model(0.0, 1.0, 1.0)
	return true


func _finish_budding() -> void:
	is_budding = false
	bud_parent = null
	_set_scale_anchored(bud_target_scale)
	_resolve_model(0.0, 1.0, 1.0)
	_apply_transform()
	set_shader_param(SN_SPLIT_AMT, 0.0)
	set_shader_param(SN_SPLIT_NECK_RADIUS, 0.0)
	set_shader_param(SN_SPLIT_PARTNER_LOCAL, Vector3.ZERO)
	_sync_proxy()


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
	var progress := smoothstep(0.0, split_snap, k)
	if k < split_snap:
		# Phase 1: the droplet clings to the parent and is drawn out under tension.
		var stretch_k := k / split_snap
		var e := sin(stretch_k * PI * 0.5)
		set_shader_param(SN_SPLIT_AMT, e * 0.95)
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

		var snap_k := (k - split_snap) / (1.0 - split_snap)
		var snap_e := sin(snap_k * PI * 0.5)
		var snap_decay := exp(-snap_k * 5.5) * cos(snap_k * PI * 2.5)
		set_shader_param(SN_SPLIT_AMT, maxf(0.0, snap_decay * 0.85))
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
	set_shader_param(SN_SPLIT_DIR, -bud_fwd)

	if k >= 1.0:
		_finish_budding()
	else:
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
	if liquid_amt > 0.1 or engulf_target != null:
		return
	# A coupled split sculpts the neck from both surfaces, which only reads correctly
	# on a settled, unsqueezed body that is not mid-passage.
	if tuning.use_coupled_split:
		if slime_scale < tuning.min_split_scale or squeeze_k < 0.85 \
				or passage_state != PassageState.OPEN:
			return

	var cam := get_active_camera()
	var fwd: Vector3
	if motor.velocity.length() > 0.3:
		fwd = _crawl_dir.normalized()
	elif cam:
		fwd = -cam.global_transform.basis.z
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
		for deg in split_angles:
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
	if liquid_amt > 0.1:
		return

	var merge_rad := maxf(model.rest_max_radius * slime_scale * tuning.merge_range_factor + 1.0, 14.0)
	var to_merge: Array[Slime] = []

	for s in props.registered_slimes:
		if s == self or not is_instance_valid(s) or s.is_merging or s.is_fissioning or s.is_budding:
			continue
		if s.liquid_amt > 0.1:
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
		s.set_shader_param(SN_DRAPE_AMT, 0.0)

	trigger_poke(Vector3(0.0, 0.3, 0.0), Vector3(0.0, -0.6, 0.0))


func _merge_path_clear(other: Slime) -> bool:
	var from := other.motor.core_sweep_origin() + Vector3(0.0, 0.18, 0.0)
	var to := motor.core_sweep_origin() + Vector3(0.0, 0.18, 0.0)
	var fr := other.motor.cast_core_sphere(from, to - from)
	return float(fr[1]) >= 0.95 or from.distance_to(to) <= 5.0


# ------------------------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------------------------

## The motor owns the transform; clamping is just another swept move.
func _clamp_arena() -> void:
	motor.clamp_to_arena(Vector3.ZERO, tuning.arena_radius)


func _apply_transform() -> void:
	scale = Vector3.ONE * slime_scale
