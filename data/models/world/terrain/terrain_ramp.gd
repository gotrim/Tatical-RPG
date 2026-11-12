class_name TerrainRamp
extends Resource
## Rampa entre dois pontos globais do terreno procedural.

## Extremidade baixa, em coordenadas globais X/Z.
@export var start: Vector2 = Vector2.ZERO
## Extremidade alta, em coordenadas globais X/Z.
@export var end: Vector2 = Vector2(16.0, 0.0)
## Metade da largura plana da rampa.
@export_range(0.1, 256.0, 0.1) var half_width: float = 3.0
## Margem lateral que mistura a rampa com o terreno natural.
@export_range(0.0, 256.0, 0.1) var blend_width: float = 2.0
