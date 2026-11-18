class_name ActorArchetype
extends Resource
## Inspector-editable stats and model configuration for a LivingActor archetype.

@export var archetype_name: String = ""
@export_file("*.glb", "*.gltf") var glb_path: String = ""
@export_range(0.05, 3.0, 0.01) var scale_factor: float = 0.42
@export_range(5.0, 1000.0, 1.0) var max_hp: float = 95.0
@export_range(0.0, 100.0, 0.5) var attack_damage: float = 14.0
@export_range(0.5, 15.0, 0.1) var walk_speed: float = 3.0
@export_range(0.5, 20.0, 0.1) var run_speed: float = 6.6
@export_range(2.0, 60.0, 0.5) var aggro_radius: float = 21.0
@export_range(4.0, 200.0, 1.0) var territory_radius: float = 42.0
@export_range(6.0, 240.0, 1.0) var leash_radius: float = 105.0
@export_range(0.2, 5.0, 0.05) var hp_bar_height: float = 1.30
@export_range(0.2, 3.0, 0.02) var body_radius: float = 0.62
