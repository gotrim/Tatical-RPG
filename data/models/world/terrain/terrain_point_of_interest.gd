class_name TerrainPointOfInterest
extends Resource
## Área que deve ser achatada para acomodar uma cidade ou estrutura.

## Coordenadas globais X/Z do centro da área.
@export var world_position: Vector2 = Vector2.ZERO
## Raio completamente plano, em unidades do mundo.
@export_range(0.0, 10000.0, 0.5) var radius: float = 24.0
## Largura da transição suave depois do raio plano.
@export_range(0.0, 10000.0, 0.5) var transition_width: float = 16.0
