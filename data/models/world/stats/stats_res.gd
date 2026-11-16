class_name StatsResource
extends Resource
## The attributes of a game actor.

#region Properties
## Override name for the actor
@export var override_name: String = ""
## Expertise of the actor
@export var expertise: String = ""

@export_category("Inicialização")
## Strategy type of the actor
@export_enum("Tanque", "Flanqueador", "Físico", "À distância", "Suporte") var strategy: int
## Current level of the actor
@export var level: int = 1
## Path to the actor's sprite
@export_file("*.png") var sprite: String = "res://assets/textures/actor/"

#region Base Stats
@export_category("Atributos básicos")
## Movement. Average: 3-5 (base). Endgame: 9 max.
@export var movement: int = 3
## Jump height, calculated as half of movement
@export var jump: float = movement / 2.0
## Maximum health of the actor
@export var max_health: int = 5
#endregion

#region Offensive Stats
@export_category("Ofensiva")
## How far you can project your basic attack.
@export var attack_range: int = 1
## Attack power of the actor
@export var attack_power: int = 1
#endregion


#region Methods
## Calculates and sets the jump height based on mp
func set_jump() -> void:
	jump = floor(movement / 2.0)
#endregion
