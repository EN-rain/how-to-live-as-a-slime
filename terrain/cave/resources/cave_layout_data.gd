@tool
class_name CaveLayoutData
extends Resource
## Serialized cave topology exported from CaveOriginNode (or seeded from CaveLayout constants).
## Consumed by CaveSDF, tools/bake_cave.gd, and CaveSystem without hardcoded script edits.

@export var origin: Vector3 = Vector3(-24.0, 27.2, -52.0)
@export var fwd_xz: Vector2 = Vector2(-0.425105, -0.905144)
@export var right_xz: Vector2 = Vector2(0.905144, -0.425105)
@export var mountain_surface_over_hall: float = 56.5

@export var tunnels: Dictionary = {}
@export var tunnel_leans: Dictionary = {}
@export var chambers: Dictionary = {}
@export var chamber_leans: Dictionary = {}
@export var alcoves: Array = []
@export var pillars: Array = []
@export var ledge_route: Array[Vector3] = []
@export var ledge_width: float = 8.6
@export var ledge_headroom: float = 7.2
@export var stream_ctrl: Array[Vector3] = []

@export var mound: Dictionary = {}
@export var rubble_crest: Dictionary = {}
@export var pool: Dictionary = {}
@export var skylight: Dictionary = {}
@export var waterfall: Vector3 = Vector3.ZERO
@export var underground_lake: Dictionary = {}
@export var lake_abyss_pit: Dictionary = {}
@export var ancient_door: Dictionary = {}
@export var spawn: Vector3 = Vector3(-56.5, 21.4, 62.5)
@export var spawn_look_at: Vector3 = Vector3(-48.0, 18.5, 87.5)

