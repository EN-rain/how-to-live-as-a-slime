class_name SlimeTuning
extends Resource
## Single authored source of truth for slime gameplay tuning.
##
## Every size-sensitive subsystem (collision envelope, shader, picking, shadows,
## coverage, AI clearance) reads resolved dimensions from SlimeShapeModel, which is
## configured from this resource. Runtime state (velocity, posture, timers) lives on
## the actor, never here. Share one immutable instance between actors; do not mutate
## it at runtime.

@export_group("Movement")
@export var walk_speed := 3.0
@export var run_speed := 10.0
@export var liquid_speed := 2.2
@export var velocity_response := 8.0
@export var arena_radius := 190.0
## Max horizontal travel per physics tick as a fraction of body radius (sweep budget, not a teleport cap).
@export var max_step_fraction := 0.3
@export var gravity := 22.0
## How far above the foot the motor may step/climb onto support, per unit scale.
@export var climb_reach := 0.08
@export var liquid_climb_reach := 0.08
@export var slide_iterations := 4
@export var recovery_iterations := 6
## Resolve slime-vs-slime overlap analytically from the shape model instead of
## relying on the static proxies and the generic sweep. Partner hulls stay in the
## sweep for movement intent; separation itself only tests level geometry.
@export var use_analytic_slime_collision := true

@export_group("Size")
@export var start_scale := 1.0
@export var scale_response := 3.5
## Radius of the reference sphere mesh the shader deforms (mesh-local units).
@export var reference_radius := 1.6
## Shader melt; drives the rest profile used by BOTH physics and visuals.
@export var melt := 0.28
## Authoritative gameplay volume per scale^3. Conserved scalar; the stylized mesh
## deformation is not required to match it exactly.
@export var volume_radius := 1.6

@export_group("World")
@export var floor_y := -1.2

@export_group("Shape and Traversal")
## Liquid height as a fraction of rest height.
@export_range(0.05, 1.0, 0.01) var liquid_height_ratio := 0.22
## Liquid horizontal spread multiplier. Authored (may be non-volume-preserving);
## applied identically to collision, shader, picking, shadows and coverage.
@export var liquid_spread_ratio := 2.13
## Minimum legal lateral squeeze for normal posture, as a fraction of rest width.
## Matches the visible Core Sphere radius (0.18 * 2.0m = 0.36m radius, 0.72m diameter at scale 1.0).
@export_range(0.05, 1.0, 0.01) var min_normal_squeeze := 0.18
## Minimum legal lateral squeeze for liquid posture, as a fraction of rest width.
@export_range(0.05, 1.0, 0.01) var min_liquid_squeeze := 0.12
## Inner clearance sphere radius ratio relative to the legal minimum squeeze.
## Represents the invisible core: if an area fits this sphere, the slime's body conforms and goes through.
@export var core_sphere_radius_ratio := 0.95
## Minimum legal liquid height ratio under overhead compression.
@export_range(0.02, 1.0, 0.01) var min_liquid_height_ratio := 0.22
## Permit normal (non-liquid) posture to compress vertically under a low ceiling.
@export var allow_normal_vertical_compression := true
## Skin gap kept between the collision envelope and obstacles.
@export var skin := 0.02
## Latch passages through a 5-state machine (approach ramp, inside/exiting hold).
## Off reverts to the legacy "any latched hint" behaviour.
@export var use_passage_fsm := true
## Visual longitudinal stretch per unit of lateral squeeze. Stylized: the collision
## envelope stays a compact ellipse, otherwise a stretched neck would block itself.
@export var squeeze_elongation := 0.0
## Vertical gain per unit of lateral squeeze in normal posture.
@export var squeeze_height_gain := 0.0
@export var squeeze_in_rate := 36.0
@export var squeeze_out_rate := 8.0
## Liquid blend rate (1/s) driving the Z-key melt/reform transition.
@export var liquid_blend_rate := 2.8

@export_group("Crawl and lean")
@export var crawl_rate := 2.6
@export var speed_for_full_crawl := 3.0
@export var lean_gain := 0.35
@export var lean_stiffness := 60.0
@export var lean_damping := 7.0
@export var ripple_base := 0.12
@export var ripple_per_speed := 0.45

@export_group("Poke")
@export var poke_strength := 0.55
@export var poke_downward := 0.25

@export_group("Eyes")
@export var facing_response := 8.0
@export var moving_threshold := 0.3
@export var blink_period := 4.0
@export var blink_start := 3.85
@export var blink_closed_amount := 0.12
@export var start_facing := 0.45

@export_group("Consumption")
@export var devour_duration := 1.6
@export var eat_time := 0.8
@export var eat_linger := 2.0
## Prop volume must be <= this fraction of slime volume to be push-edible.
@export var edible_volume_ratio := 0.98

@export_group("Fission and Merge")
@export var fission_duration := 0.58
@export var bud_duration := 0.58
@export var merge_duration := 0.42
@export var min_split_scale := 0.45
## Bilateral coupled split: the bud spawns inside the parent's silhouette, both
## halves separate from their shared centre, and the facing surfaces are sculpted
## into a world-space hourglass that pinches to zero at the snap point.
@export var use_coupled_split := true
@export var merge_range_factor := 2.5

@export_group("AI")
@export var follow_distance := 3.2
@export var follower_catch_up_distance := 8.0
@export var follower_stuck_time := 3.0
@export var roamer_stuck_time := 2.5
@export var roamer_recover_time := 2.5
@export var breadcrumb_interval := 0.1
@export var breadcrumb_limit := 120

@export_group("Camera")
## Camera starts following once the slime exceeds this speed (0..1 of walk_speed).
@export var follow_speed_threshold := 0.01


func volume_per_scale_cubed() -> float:
	return (4.0 / 3.0) * PI * pow(volume_radius, 3.0)


## Clamp authored values into the ranges the solver can honor. Runs whenever a shape
## model is configured, so a bad Inspector value degrades to a safe bound instead of
## producing a divide-by-zero, a zero-size step budget or a negative duration.
func validate() -> void:
	reference_radius = maxf(reference_radius, 0.1)
	volume_radius = maxf(volume_radius, 0.1)
	arena_radius = maxf(arena_radius, 1.0)
	max_step_fraction = clampf(max_step_fraction, 0.05, 1.0)
	slide_iterations = maxi(slide_iterations, 1)
	recovery_iterations = maxi(recovery_iterations, 1)
	gravity = maxf(gravity, 0.0)
	scale_response = maxf(scale_response, 0.1)
	velocity_response = maxf(velocity_response, 0.1)
	climb_reach = maxf(climb_reach, 0.0)
	liquid_climb_reach = maxf(liquid_climb_reach, 0.0)
	skin = clampf(skin, 0.0, 0.25)
	melt = clampf(melt, 0.0, 1.5)
	liquid_height_ratio = clampf(liquid_height_ratio, 0.02, 1.0)
	liquid_spread_ratio = maxf(liquid_spread_ratio, 0.2)
	min_liquid_squeeze = clampf(min_liquid_squeeze, 0.05, 1.0)
	min_normal_squeeze = clampf(min_normal_squeeze, min_liquid_squeeze, 1.0)
	min_liquid_height_ratio = clampf(min_liquid_height_ratio, 0.02,
			minf(1.0, liquid_height_ratio))
	fission_duration = maxf(fission_duration, 0.1)
	bud_duration = maxf(bud_duration, 0.1)
	merge_duration = maxf(merge_duration, 0.05)
	min_split_scale = clampf(min_split_scale, 0.05, 0.99)