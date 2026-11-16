class_name TerrainLodChunk
extends MeshInstance3D
## Um nó folha do horizonte distante: malha única, sem colisão e sem vegetação.
##
## Nasce oculto ("staged") e só aparece quando o manager libera a troca, para nunca
## haver buraco nem sobreposição entre níveis de LOD durante a construção assíncrona.

## (level, cx, cz) do nó no quadtree.
var key: Vector3i = Vector3i.ZERO
## Área coberta, em índices de tile (para testar sobreposição entre nós).
var tile_rect: Rect2i = Rect2i()
var is_live: bool = false


func configure(
	p_key: Vector3i,
	p_tile_rect: Rect2i,
	p_mesh: ArrayMesh,
	p_material: Material,
	corner_position: Vector3,
	casts_shadows: bool
) -> void:
	key = p_key
	tile_rect = p_tile_rect
	name = "Lod_%d_%d_%d" % [key.x, key.y, key.z]
	position = corner_position
	mesh = p_mesh
	material_override = p_material
	cast_shadow = (
		GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if casts_shadows
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	)
	set_live(false)


func set_live(value: bool) -> void:
	is_live = value
	visible = value
