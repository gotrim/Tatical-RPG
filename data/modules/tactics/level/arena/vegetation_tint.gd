class_name TacticsVegetationTint
extends RefCounted
## Faz a grama de cada tile acompanhar a cor do marcador do tile (hover, alcance de movimento e de ataque).
##
## Cada tile registra grupos de instâncias contíguas de um [MultiMesh]. Quando o marcador do tile muda
## ([signal TacticsTile.marker_changed]), só as instâncias daquele tile têm a cor atualizada; ao
## desmarcar, elas voltam à cor original do grupo (a cor do bioma).
##
## Usado por: procedural_arena.gd e reference_vegetation.gd

## 0 = a grama ignora os marcadores. 1 = a cor do marcador substitui a do bioma, proporcional ao alfa
## do marcador (o mesmo resultado que o tile translúcido teria sobre o terreno).
var strength: float = 1.0

## TacticsTile -> Array de grupos: { "multimesh": MultiMesh, "first": int, "count": int, "color": Color }
var _groups: Dictionary = {}


## Registra [param count] instâncias de [param multimesh], a partir de [param first_index],
## que pertencem a [param tile] e têm [param base_color] quando o tile não está marcado.
func register(
	tile: TacticsTile,
	multimesh: MultiMesh,
	first_index: int,
	count: int,
	base_color: Color
) -> void:
	if not tile or not multimesh or count <= 0:
		return
	if not _groups.has(tile):
		_groups[tile] = []
		tile.marker_changed.connect(_on_tile_marker_changed)
	var groups: Array = _groups[tile]
	groups.append({
		"multimesh": multimesh,
		"first": first_index,
		"count": count,
		"color": base_color
	})


func _on_tile_marker_changed(tile: TacticsTile) -> void:
	var groups: Array = _groups.get(tile, [])
	var marker: Color = tile.get_marker_color()
	var weight: float = clampf(marker.a * strength, 0.0, 1.0)
	for group: Dictionary in groups:
		var color: Color = group["color"]
		if weight > 0.0:
			color = color.lerp(Color(marker.r, marker.g, marker.b, color.a), weight)
		var multimesh: MultiMesh = group["multimesh"]
		var first: int = group["first"]
		for index: int in range(first, first + int(group["count"])):
			multimesh.set_instance_color(index, color)
