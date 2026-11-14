class_name LivingActor
extends Node3D
## Optimized living entity (Villager NPC, Town Guard, Wildlife, Livestock, or Hostile Mob).
## Uses analytical height clamping, AStar2D gate-aware paths, and manual LOD-sliced animations.

enum Faction {
	NEUTRAL = 0,
	VILLAGE = 1,
	HOSTILE = 2,
}

enum RoleKind {
	GUARD = 0,
	MERCHANT = 1,
	ARTISAN = 2,
	FISHERMAN = 3,
	ANIMAL = 4,
	DOG = 5,
	RAIDER = 6,
	BEAST = 7,
}

enum AttackKind {
	MELEE = 0,
	RANGED_BOW = 1,
	RANGED_SPELL = 2,
}

enum AIState {
	SCHEDULE_IDLE = 0,
	SCHEDULE_MOVE = 1,
	SCHEDULE_WORK = 2,
	SHELTER_RAIN = 3,
	CHASE = 4,
	ATTACK = 5,
	FLEE = 6,
	AWAKEN = 7,
	DEAD = 8,
}

var actor_idx: int = 0
var display_name: String = "Actor"
var category: String = "npc"
var faction: Faction = Faction.NEUTRAL
var role: RoleKind = RoleKind.ARTISAN
var attack_kind: AttackKind = AttackKind.MELEE
var ai_state: AIState = AIState.SCHEDULE_IDLE

var home_xz: Vector2 = Vector2.ZERO
var patrol_points: Array[Vector2] = []
var patrol_cursor: int = 0
var work_anim_hint: String = "Interact"
var facing_hint_yaw: float = 0.0
var is_night_raider: bool = false

var max_hp: float = 100.0
var hp: float = 100.0
var move_speed: float = 3.0
var run_speed: float = 5.8
var attack_range: float = 2.2
var aggro_range: float = 20.0
var attack_damage: float = 16.0
var attack_cooldown: float = 1.25
var body_radius: float = 0.55
var hp_bar_height: float = 2.25

var velocity_xz: Vector2 = Vector2.ZERO
var knockback_xz: Vector2 = Vector2.ZERO
var vertical_vel: float = 0.0
var vertical_offset: float = 0.0
var target_actor: LivingActor = null
var target_slime: Slime = null

var _anim: AnimationPlayer = null
var _notifier: VisibleOnScreenNotifier3D = null
var _meshes: Array[MeshInstance3D] = []
var _muzzle_node: Node3D = null
var _anim_map: Dictionary = {}
var _current_anim: String = ""
var _shadows_on: bool = true
var _on_screen: bool = true

var _path: PackedVector2Array = PackedVector2Array()
var _path_idx: int = 0
var _repath_cd: float = 0.0
var _state_timer: float = 1.5
var _atk_cd: float = 0.0
var _action_lock: float = 0.0
var _flash_timer: float = 0.0
var _flash_col: Color = Color(1.0, 0.25, 0.25, 0.0)
var _combat_show_timer: float = 0.0
var _respawn_timer: float = 0.0
var _anim_accum_dt: float = 0.0
var _slam_grace: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup_visuals(model_root: Node3D, anim_player: AnimationPlayer, meshes: Array[MeshInstance3D], muzzle: Node3D) -> void:
	_rng.seed = actor_idx * 9173 + 131
	add_child(model_root)
	_anim = anim_player
	_meshes = meshes
	_muzzle_node = muzzle

	_notifier = VisibleOnScreenNotifier3D.new()
	_notifier.aabb = AABB(Vector3(-1.1, 0.0, -1.1), Vector3(2.2, 2.6, 2.2))
	_notifier.screen_entered.connect(func(): _on_screen = true)
	_notifier.screen_exited.connect(func(): _on_screen = false)
	add_child(_notifier)

	if _anim != null:
		_anim.callback_mode_process = AnimationPlayer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_build_anim_map()
		_play_anim("awaken" if is_night_raider else "idle", true)
		_anim.advance(0.05)


func _build_anim_map() -> void:
	if _anim == null:
		return
	var avail: PackedStringArray = _anim.get_animation_list()
	var find_clip := func(candidates: Array, fallback: String = "") -> String:
		for c_raw in candidates:
			var c := String(c_raw)
			if c in avail:
				return c
		for a in avail:
			var low := String(a).to_lower()
			for c_raw in candidates:
				var c := String(c_raw).to_lower()
				if low.ends_with(c) or low.contains(c):
					return String(a)
		return fallback

	var idle_c: String = str(find_clip.call(["Idle", "AnimalArmature|Idle", "SpiderArmature|Spider_Idle", "RatArmature|Rat_Idle", "WaspArmature|Wasp_Flying"], String(avail[0]) if avail.size() > 0 else ""))
	_anim_map["idle"] = idle_c
	_anim_map["walk"] = find_clip.call(["Walking_D_Skeletons" if faction == Faction.HOSTILE else "Walking_A", "Walking_A", "AnimalArmature|Walk", "SpiderArmature|Spider_Walk", "RatArmature|Rat_Walk", "WaspArmature|Wasp_Flying"], idle_c)
	_anim_map["run"] = find_clip.call(["Running_A", "AnimalArmature|Gallop", "RatArmature|Rat_Run", "SpiderArmature|Spider_Walk", "WaspArmature|Wasp_Flying"], _anim_map["walk"])
	_anim_map["attack"] = find_clip.call(["1H_Melee_Attack_Chop", "AnimalArmature|Attack", "AnimalArmature|Attack_Headbutt", "SpiderArmature|Spider_Attack", "RatArmature|Rat_Attack", "WaspArmature|Wasp_Attack"], idle_c)
	_anim_map["ranged"] = find_clip.call(["1H_Ranged_Shoot", "Spellcast_Shoot", "1H_Melee_Attack_Chop"], _anim_map["attack"])
	_anim_map["spell"] = find_clip.call(["Spellcast_Shoot", "1H_Ranged_Shoot"], _anim_map["attack"])
	_anim_map["block"] = find_clip.call(["Block", "Idle_Combat", "Idle"], idle_c)
	_anim_map["hit"] = find_clip.call(["Hit_A", "AnimalArmature|Idle_HitReact_Left"], idle_c)
	_anim_map["death"] = find_clip.call(["Death_A", "AnimalArmature|Death", "SpiderArmature|Spider_Death", "RatArmature|Rat_Death", "WaspArmature|Wasp_Death"], idle_c)
	_anim_map["interact"] = find_clip.call([work_anim_hint, "Interact", "Use_Item", "PickUp", "Cheer", "Idle_2"], idle_c)
	_anim_map["sit"] = find_clip.call(["Sit_Chair_Idle", "Sit_Floor_Idle", "Idle"], idle_c)
	_anim_map["eat"] = find_clip.call(["AnimalArmature|Eating", "AnimalArmature|Idle_2", "Idle"], idle_c)
	_anim_map["awaken"] = find_clip.call(["Skeletons_Awaken_Floor", "Idle"], idle_c)

	# Ensure loop flags are properly set on locomotion & idle clips
	for k in ["idle", "walk", "run", "interact", "sit", "eat", "block"]:
		var cname: String = _anim_map.get(k, "")
		if not cname.is_empty() and _anim.has_animation(cname):
			var anim_res := _anim.get_animation(cname)
			if anim_res != null:
				anim_res.loop_mode = Animation.LOOP_LINEAR
	for k in ["attack", "ranged", "spell", "hit", "death", "awaken"]:
		var cname: String = _anim_map.get(k, "")
		if not cname.is_empty() and _anim.has_animation(cname):
			var anim_res := _anim.get_animation(cname)
			if anim_res != null:
				anim_res.loop_mode = Animation.LOOP_NONE


func _play_anim(key: String, force: bool = false) -> void:
	if _anim == null:
		return
	var clip: String = String(_anim_map.get(key, ""))
	if clip.is_empty():
		return
	if force or _current_anim != clip or not _anim.is_playing():
		_current_anim = clip
		_anim.play(clip, 0.14)


func is_alive() -> bool:
	return ai_state != AIState.DEAD and visible


func get_muzzle_world() -> Vector3:
	if _muzzle_node != null and is_instance_valid(_muzzle_node):
		return _muzzle_node.global_position
	return global_position + Vector3(0.0, 1.35, 0.0)


func trigger_hit_flash(col: Color) -> void:
	_flash_col = col
	_flash_timer = 0.20
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.set_instance_shader_parameter(&"hit_flash", Vector4(col.r, col.g, col.b, 0.82))


func apply_damage(amount: float, push_xz: Vector2, attacker: Node = null, is_slime_hit: bool = false) -> bool:
	if not is_alive():
		return false
	hp -= amount
	_combat_show_timer = 7.0
	knockback_xz += push_xz
	if hp <= 0.0:
		hp = 0.0
		_enter_death(is_slime_hit)
		return true

	trigger_hit_flash(Color(1.0, 0.25, 0.20))
	if _action_lock <= 0.0:
		_play_anim("hit", true)
		_action_lock = 0.22

	if attacker is LivingActor:
		var la := attacker as LivingActor
		if la.faction != faction and role != RoleKind.ANIMAL:
			target_actor = la
			target_slime = null
	elif is_slime_hit and attacker is Slime:
		if faction == Faction.HOSTILE:
			target_slime = attacker as Slime
			target_actor = null
		elif role == RoleKind.ANIMAL:
			ai_state = AIState.FLEE
			_state_timer = 4.5
	return false


func _enter_death(killed_by_slime: bool = false) -> void:
	ai_state = AIState.DEAD
	velocity_xz = Vector2.ZERO
	target_actor = null
	target_slime = null
	_combat_show_timer = 0.0
	trigger_hit_flash(Color(1.0, 0.15, 0.15))
	_play_anim("death", true)
	if _anim != null:
		_anim.advance(0.02)
	_respawn_timer = _rng.randf_range(24.0, 38.0)
	if killed_by_slime and (faction == Faction.HOSTILE or role == RoleKind.ANIMAL):
		# Reward player slime small volume recovery on hunt/defeat
		var eco := get_parent()
		if eco != null and eco.has_method("_on_slime_defeated_actor"):
			eco.call("_on_slime_defeated_actor", self)


func respawn(ecosystem: Node) -> void:
	hp = max_hp
	knockback_xz = Vector2.ZERO
	vertical_vel = 0.0
	vertical_offset = 0.0
	target_actor = null
	target_slime = null
	_combat_show_timer = 0.0
	visible = true
	var spawn_y: float = float(ecosystem.sample_ground_y(home_xz.x, home_xz.y, role == RoleKind.FISHERMAN))
	global_position = Vector3(home_xz.x, spawn_y, home_xz.y)
	ai_state = AIState.AWAKEN if is_night_raider else AIState.SCHEDULE_IDLE
	_state_timer = 1.1 if is_night_raider else 1.5
	_play_anim("awaken" if is_night_raider else "idle", true)
	if _anim != null:
		_anim.advance(0.05)


func step_ai(dt: float, ecosystem: Node, rain_intensity: float, is_night: bool, village_provoked: bool) -> void:
	_slam_grace = maxf(0.0, _slam_grace - dt)
	_atk_cd = maxf(0.0, _atk_cd - dt)
	_repath_cd = maxf(0.0, _repath_cd - dt)
	_action_lock = maxf(0.0, _action_lock - dt)
	_combat_show_timer = maxf(0.0, _combat_show_timer - dt)

	if _flash_timer > 0.0:
		_flash_timer = maxf(0.0, _flash_timer - dt)
		var a := (_flash_timer / 0.20) * 0.82
		for mi in _meshes:
			if is_instance_valid(mi):
				mi.set_instance_shader_parameter(&"hit_flash", Vector4(_flash_col.r, _flash_col.g, _flash_col.b, a))

	if ai_state == AIState.DEAD:
		_respawn_timer -= dt
		if _respawn_timer <= 0.0:
			if is_night_raider and not is_night:
				visible = false
				_respawn_timer = 4.0
			else:
				respawn(ecosystem)
		return

	# Raiders that linger past dawn scatter back out or crumble softly if heavily sun-exposed
	if is_night_raider and not is_night:
		ai_state = AIState.FLEE
	if ai_state == AIState.AWAKEN:
		_state_timer -= dt
		_play_anim("awaken")
		if _state_timer <= 0.0:
			ai_state = AIState.SCHEDULE_MOVE
		return

	var pos_xz := Vector2(global_position.x, global_position.z)

	# 1. Threat / Target Scanning
	if role != RoleKind.ANIMAL:
		_acquire_combat_target(pos_xz, ecosystem, village_provoked)
	elif ai_state != AIState.FLEE:
		# Wildlife flees predators & fast-charging slime
		var predator: LivingActor = ecosystem.find_nearest_enemy_in_radius(pos_xz, Faction.HOSTILE, 15.0)
		if predator != null:
			target_actor = predator
			ai_state = AIState.FLEE
			_state_timer = 4.0
		else:
			var sl: Node3D = ecosystem.player_slime
			if sl != null and not bool(sl.get("is_dead")):
				var sl_xz := Vector2(sl.global_position.x, sl.global_position.z)
				var motor_ref: Object = sl.get("motor")
				var spd_sl: float = Vector2(motor_ref.velocity.x, motor_ref.velocity.z).length() if motor_ref != null else 0.0
				if pos_xz.distance_to(sl_xz) < 11.0 and spd_sl > 5.5:
					target_slime = sl
					ai_state = AIState.FLEE
					_state_timer = 3.5

	# 2. Check Rain Sheltering for peaceful villagers / artisans / fisherman
	var raining := rain_intensity > 0.36
	if raining and (role == RoleKind.MERCHANT or role == RoleKind.ARTISAN or role == RoleKind.FISHERMAN) and target_actor == null and target_slime == null:
		if ai_state != AIState.SHELTER_RAIN and ai_state != AIState.FLEE:
			ai_state = AIState.SHELTER_RAIN
			var sh: Vector2 = ecosystem.nav_graph.get_nearest_shelter(pos_xz)
			_set_destination(sh, ecosystem.nav_graph)

	var desired_vel := Vector2.ZERO
	var desired_yaw := rotation.y

	match ai_state:
		AIState.SHELTER_RAIN:
			var sh: Vector2 = ecosystem.nav_graph.get_nearest_shelter(pos_xz)
			if pos_xz.distance_to(sh) > 2.2:
				desired_vel = _follow_path(pos_xz, move_speed * 1.35, ecosystem.nav_graph)
				_play_anim("run")
			else:
				_play_anim("idle")
			if not raining:
				ai_state = AIState.SCHEDULE_IDLE
				_state_timer = 1.0

		AIState.FLEE:
			_state_timer -= dt
			var away_from := home_xz
			if target_actor != null and is_instance_valid(target_actor):
				away_from = Vector2(target_actor.global_position.x, target_actor.global_position.z)
			elif target_slime != null and is_instance_valid(target_slime):
				away_from = Vector2(target_slime.global_position.x, target_slime.global_position.z)
			var dir := (pos_xz - away_from)
			dir = dir.normalized() if dir.length_squared() > 0.01 else Vector2(1.0, 0.0)
			if is_night_raider and not is_night:
				dir = (home_xz - pos_xz).normalized()
				if pos_xz.distance_to(home_xz) < 4.0:
					visible = false
					ai_state = AIState.DEAD
					_respawn_timer = 5.0
					return
			desired_vel = dir * run_speed
			_play_anim("run")
			if _state_timer <= 0.0:
				target_actor = null
				target_slime = null
				ai_state = AIState.SCHEDULE_IDLE
				_state_timer = 1.5

		AIState.CHASE, AIState.ATTACK:
			var tgt_xz := Vector2.ZERO
			var tgt_valid := false
			var tgt_rad := 0.55
			if target_actor != null and is_instance_valid(target_actor) and target_actor.is_alive():
				tgt_xz = Vector2(target_actor.global_position.x, target_actor.global_position.z)
				tgt_rad = target_actor.body_radius
				tgt_valid = true
			elif target_slime != null and is_instance_valid(target_slime) and not target_slime.is_dead:
				tgt_xz = Vector2(target_slime.global_position.x, target_slime.global_position.z)
				tgt_rad = 1.15 * target_slime.slime_scale
				tgt_valid = true

			if not tgt_valid:
				target_actor = null
				target_slime = null
				ai_state = AIState.SCHEDULE_IDLE
				_state_timer = 1.0
			else:
				var dist := pos_xz.distance_to(tgt_xz)
				if dist > aggro_range * 1.45:
					target_actor = null
					target_slime = null
					ai_state = AIState.SCHEDULE_IDLE
					_state_timer = 1.0
				elif dist <= attack_range + tgt_rad:
					ai_state = AIState.ATTACK
					var look_d := (tgt_xz - pos_xz)
					if look_d.length_squared() > 0.001:
						desired_yaw = atan2(look_d.x, look_d.y)
					if _atk_cd <= 0.0 and _action_lock <= 0.0:
						_perform_attack(ecosystem)
						_atk_cd = attack_cooldown * _rng.randf_range(0.88, 1.15)
						_action_lock = 0.42
					elif _action_lock <= 0.0:
						_play_anim("block" if role == RoleKind.GUARD else "idle")
				else:
					ai_state = AIState.CHASE
					if _repath_cd <= 0.0:
						_set_destination(tgt_xz, ecosystem.nav_graph)
						_repath_cd = 0.45
					desired_vel = _follow_path(pos_xz, run_speed, ecosystem.nav_graph)
					if _action_lock <= 0.0:
						_play_anim("run")

		AIState.SCHEDULE_MOVE:
			if _path.is_empty() or _path_idx >= _path.size():
				_pick_next_schedule_destination(pos_xz, ecosystem, is_night)
			else:
				var goal_xz := _path[_path.size() - 1]
				if pos_xz.distance_to(goal_xz) < 1.35:
					_path = PackedVector2Array()
					ai_state = AIState.SCHEDULE_WORK if (role == RoleKind.MERCHANT or role == RoleKind.ARTISAN or role == RoleKind.FISHERMAN) else AIState.SCHEDULE_IDLE
					_state_timer = _rng.randf_range(2.8, 6.2)
					if facing_hint_yaw != 0.0:
						desired_yaw = facing_hint_yaw
				else:
					desired_vel = _follow_path(pos_xz, move_speed, ecosystem.nav_graph)
					_play_anim("walk")

		AIState.SCHEDULE_WORK:
			_state_timer -= dt
			if facing_hint_yaw != 0.0:
				desired_yaw = facing_hint_yaw
			if work_anim_hint == "Sit_Chair_Idle":
				_play_anim("sit")
			else:
				_play_anim("interact")
			if _state_timer <= 0.0:
				ai_state = AIState.SCHEDULE_MOVE
				_pick_next_schedule_destination(pos_xz, ecosystem, is_night)

		AIState.SCHEDULE_IDLE:
			_state_timer -= dt
			if role == RoleKind.ANIMAL and _rng.randf() < 0.04:
				_play_anim("eat")
			else:
				_play_anim("eat" if (role == RoleKind.ANIMAL and _current_anim == _anim_map.get("eat", "")) else "idle")
			if _state_timer <= 0.0:
				ai_state = AIState.SCHEDULE_MOVE
				_pick_next_schedule_destination(pos_xz, ecosystem, is_night)

	# 3. Spatial-hash crowd & obstacle separation (no CharacterBody3D physics sweep needed!)
	var sep: Vector2 = ecosystem.compute_separation(self, pos_xz)
	desired_vel += sep * 2.4

	# Decay knockback & integrate XZ position
	knockback_xz = knockback_xz.move_toward(Vector2.ZERO, dt * 16.0)
	var step_v := desired_vel + knockback_xz
	if desired_vel.length_squared() > 0.09:
		desired_yaw = atan2(desired_vel.x, desired_vel.y)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clampf(dt * 9.0, 0.0, 1.0))

	var new_xz := pos_xz + step_v * dt
	# Keep ground actors on island landmass (avoid walking out into deep ocean water)
	var ground_y: float = float(ecosystem.sample_ground_y(new_xz.x, new_xz.y, role == RoleKind.FISHERMAN))
	if ground_y < 0.15 and role != RoleKind.BEAST:
		# Steer softly back inland away from surf
		new_xz = pos_xz
	else:
		global_position.x = new_xz.x
		global_position.z = new_xz.y

	if vertical_offset > 0.0 or vertical_vel > 0.0:
		vertical_vel -= 22.0 * dt
		vertical_offset += vertical_vel * dt
		if vertical_offset <= 0.0:
			vertical_offset = 0.0
			vertical_vel = 0.0

	global_position.y = ecosystem.sample_ground_y(global_position.x, global_position.z, role == RoleKind.FISHERMAN) + vertical_offset


func step_animation_lod(delta: float, dist_sq: float, frame_idx: int, cave_hidden: bool) -> void:
	if _anim == null or not visible:
		return
	var show_shadows := _on_screen and not cave_hidden and dist_sq < 3025.0  # < 55 m
	if show_shadows != _shadows_on:
		_shadows_on = show_shadows
		var mode := GeometryInstance3D.SHADOW_CASTING_SETTING_ON if show_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for mi in _meshes:
			if is_instance_valid(mi):
				mi.cast_shadow = mode

	if cave_hidden or not _on_screen or dist_sq >= 9025.0:  # >= 95 m or offscreen -> freeze animation eval!
		_anim_accum_dt = 0.0
		return

	_anim_accum_dt += delta
	if dist_sq < 576.0:  # Tier 0: < 24 m -> full rate
		_anim.advance(_anim_accum_dt)
		_anim_accum_dt = 0.0
	elif dist_sq < 3025.0:  # Tier 1: 24-55 m -> 1/2 rate
		if ((actor_idx + frame_idx) & 1) == 0:
			_anim.advance(_anim_accum_dt)
			_anim_accum_dt = 0.0
	else:  # Tier 2: 55-95 m -> 1/5 rate
		if ((actor_idx + frame_idx) % 5) == 0:
			_anim.advance(_anim_accum_dt)
			_anim_accum_dt = 0.0


func _acquire_combat_target(pos_xz: Vector2, ecosystem: Node, village_provoked: bool) -> void:
	if target_actor != null and is_instance_valid(target_actor) and target_actor.is_alive():
		if pos_xz.distance_to(Vector2(target_actor.global_position.x, target_actor.global_position.z)) <= aggro_range * 1.4:
			return
		target_actor = null

	if faction == Faction.VILLAGE:
		var mob: LivingActor = ecosystem.find_nearest_enemy_in_radius(pos_xz, Faction.HOSTILE, aggro_range)
		if mob != null:
			if role == RoleKind.GUARD or role == RoleKind.DOG or (role == RoleKind.ARTISAN and pos_xz.distance_to(Vector2(mob.global_position.x, mob.global_position.z)) < 10.0):
				target_actor = mob
				target_slime = null
				ai_state = AIState.CHASE
				return
			else:
				# Non-combatant merchants/fishermen flee close mobs
				if pos_xz.distance_to(Vector2(mob.global_position.x, mob.global_position.z)) < 11.0:
					target_actor = mob
					ai_state = AIState.FLEE
					_state_timer = 3.5
				return
		if village_provoked and role == RoleKind.GUARD:
			var sl: Node3D = ecosystem.player_slime
			if sl != null and not bool(sl.get("is_dead")):
				if pos_xz.distance_to(Vector2(sl.global_position.x, sl.global_position.z)) <= aggro_range:
					target_slime = sl
					ai_state = AIState.CHASE
					return
		if not village_provoked:
			target_slime = null

	elif faction == Faction.HOSTILE:
		# Raiders & beasts attack closest Village NPC OR Player Slime!
		var npc: LivingActor = ecosystem.find_nearest_enemy_in_radius(pos_xz, Faction.VILLAGE, aggro_range)
		var d_npc := INF if npc == null else pos_xz.distance_to(Vector2(npc.global_position.x, npc.global_position.z))
		var sl: Node3D = ecosystem.player_slime
		var d_slime := INF
		if sl != null and not bool(sl.get("is_dead")):
			d_slime = pos_xz.distance_to(Vector2(sl.global_position.x, sl.global_position.z))
		if d_slime <= aggro_range and d_slime < d_npc:
			target_slime = sl
			target_actor = null
			ai_state = AIState.CHASE
		elif npc != null:
			target_actor = npc
			target_slime = null
			ai_state = AIState.CHASE


func _perform_attack(ecosystem: Node) -> void:
	if attack_kind == AttackKind.MELEE:
		_play_anim("attack", true)
		var pos_xz := Vector2(global_position.x, global_position.z)
		if target_actor != null and is_instance_valid(target_actor) and target_actor.is_alive():
			var t_xz := Vector2(target_actor.global_position.x, target_actor.global_position.z)
			var push := (t_xz - pos_xz).normalized() * 4.5
			target_actor.apply_damage(attack_damage, push, self, false)
		elif target_slime != null and is_instance_valid(target_slime) and not target_slime.is_dead:
			var s_xz := Vector2(target_slime.global_position.x, target_slime.global_position.z)
			var dir := (s_xz - pos_xz).normalized()
			ecosystem.damage_player_slime(target_slime, Vector3(dir.x * 5.2, 2.2, dir.y * 5.2), attack_damage * 0.045, display_name)
	else:
		var anim_key := "spell" if attack_kind == AttackKind.RANGED_SPELL else "ranged"
		_play_anim(anim_key, true)
		var origin := get_muzzle_world()
		var aim_pos := origin + Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * 8.0
		if target_actor != null and is_instance_valid(target_actor):
			aim_pos = target_actor.global_position + Vector3(0.0, 1.05, 0.0)
		elif target_slime != null and is_instance_valid(target_slime):
			aim_pos = target_slime.global_position + Vector3(0.0, 0.5, 0.0)
		ecosystem.spawn_projectile(self, origin, (aim_pos - origin).normalized(), attack_kind == AttackKind.RANGED_SPELL, attack_damage)


func _set_destination(dest_xz: Vector2, nav: VillageNavGraph) -> void:
	var from_xz := Vector2(global_position.x, global_position.z)
	_path = nav.compute_path_2d(from_xz, dest_xz)
	_path_idx = 0


func _follow_path(pos_xz: Vector2, spd: float, _nav: VillageNavGraph) -> Vector2:
	while _path_idx < _path.size() and pos_xz.distance_to(_path[_path_idx]) < 1.25:
		_path_idx += 1
	if _path_idx >= _path.size():
		return Vector2.ZERO
	var d := _path[_path_idx] - pos_xz
	return d.normalized() * spd if d.length_squared() > 0.001 else Vector2.ZERO


func _pick_next_schedule_destination(_pos_xz: Vector2, ecosystem: Node, is_night: bool) -> void:
	facing_hint_yaw = 0.0
	if not patrol_points.is_empty():
		patrol_cursor = (patrol_cursor + 1) % patrol_points.size()
		_set_destination(patrol_points[patrol_cursor], ecosystem.nav_graph)
		return

	if role == RoleKind.RAIDER:
		# Raiders push toward village gates & grand plaza
		var gates: Array[Vector2] = ecosystem.nav_graph.get_gate_approaches()
		var target_pt := VillageBuilder.VILLAGE_CENTER
		var dest_xz := Vector2(target_pt.x, target_pt.z)
		if is_night and _rng.randf() < 0.72:
			dest_xz += Vector2(_rng.randf_range(-18.0, 18.0), _rng.randf_range(-18.0, 18.0))
		elif not gates.is_empty():
			dest_xz = gates[_rng.randi_range(0, gates.size() - 1)]
		_set_destination(dest_xz, ecosystem.nav_graph)
		return

	if role == RoleKind.ANIMAL or role == RoleKind.BEAST:
		var ang := _rng.randf_range(0.0, TAU)
		var rad := _rng.randf_range(4.0, 16.0 if role == RoleKind.ANIMAL else 24.0)
		var dest := home_xz + Vector2(cos(ang) * rad, sin(ang) * rad)
		if float(ecosystem.sample_ground_y(dest.x, dest.y, false)) < 0.6:
			dest = home_xz
		_set_destination(dest, ecosystem.nav_graph)
		return

	# Default villager wandering between plaza stalls & social spots
	var social: Array[Dictionary] = ecosystem.nav_graph.get_social_spots()
	if not social.is_empty():
		var pick: Dictionary = social[_rng.randi_range(0, social.size() - 1)]
		facing_hint_yaw = float(pick["yaw"])
		work_anim_hint = String(pick["anim"])
		_set_destination(pick["pos"] as Vector2, ecosystem.nav_graph)
	else:
		_set_destination(home_xz, ecosystem.nav_graph)
