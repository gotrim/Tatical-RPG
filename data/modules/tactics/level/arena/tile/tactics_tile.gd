class_name TacticsTile
extends StaticBody3D
## Handles tiles, hover colors, tile state, pathfinding.
## 
## This is ultimately a module, as it is programatically appended onto every tile by way of the TacticsTileService.
## Dependencies: [TacticsTileService] [br]
## Used by: [TacticsArena]

#region: --- Props ---
## Whether the tile is reachable
var reachable: bool = false:
	set(value):
		if reachable == value:
			return
		reachable = value
		_update_marker()
## Whether the tile is attackable
var attackable: bool = false:
	set(value):
		if attackable == value:
			return
		attackable = value
		_update_marker()
## Whether the tile is being hovered over
var hover: bool = false:
	set(value):
		if hover == value:
			return
		hover = value
		_update_marker()
## Whether the tile mesh stays visible when it has no marker
var visible_as_floor: bool = false

## Pathfinding starting point.[br]Used by [TacticsArena]
var pf_root: TacticsTile
## The distance to cover.[br]Used by [TacticsArena]
var pf_distance: float

## Material for hover state
var hover_mat: StandardMaterial3D = TacticsConfig.mat_color.hover
## Material for reachable state
var reachable_mat: StandardMaterial3D = TacticsConfig.mat_color.reachable
## Material for hover and reachable state
var hover_reachable_mat: StandardMaterial3D = TacticsConfig.mat_color.reachable_hover
## Material for attackable state
var attackable_mat: StandardMaterial3D = TacticsConfig.mat_color.attackable
## Material for hover and attackable state
var hover_attackable_mat: StandardMaterial3D = TacticsConfig.mat_color.hover_attackable
## Material assigned to the tile before hover or range markers
var base_material: Material
#endregion

#region: --- Methods ---
# Getters
## Returns all 4 directly adjacent tiles
func get_neighbors(height: float) -> Array:
	var arena: TacticsArena = _get_arena()
	if arena:
		return arena.get_neighbor_tiles(self, height)
	var raycasting: Node = get_node_or_null("RayCasting")
	return raycasting.get_all_neighbors(height) if raycasting else []


## Returns any collider directly (<=1m) above
func get_tile_occupier() -> Object:
	var raycasting: Node = get_node_or_null("RayCasting")
	if raycasting:
		return raycasting.get_object_above()
	var standing_position: Vector3 = get_standing_position()
	var query := PhysicsRayQueryParameters3D.create(
		standing_position + Vector3.UP * 0.1,
		standing_position + Vector3.UP * 1.6,
		2
	)
	return get_world_3d().direct_space_state.intersect_ray(query).get("collider")


## Returns the position where a pawn should stand or swim on this tile.
func get_standing_position() -> Vector3:
	var standing_position: Vector3 = global_position
	if float(get_meta("water_depth", 0.0)) > 0.0:
		standing_position.y -= float(get_meta("water_submerge", 0.0))
	return standing_position


## Return whether target tile is occupied
func is_taken() -> bool:
	return get_tile_occupier() != null


func _get_arena() -> TacticsArena:
	var node: Node = get_parent()
	while node:
		if node is TacticsArena:
			return node as TacticsArena
		node = node.get_parent()
	return null


func _update_marker() -> void:
	var tile: MeshInstance3D = get_node_or_null("Tile") as MeshInstance3D
	if not tile:
		return
	tile.visible = visible_as_floor or attackable or reachable or hover
	if hover:
		if reachable:
			tile.material_override = hover_reachable_mat
		elif attackable:
			tile.material_override = hover_attackable_mat
		else:
			tile.material_override = hover_mat
	elif reachable:
		tile.material_override = reachable_mat
	elif attackable:
		tile.material_override = attackable_mat
	else:
		tile.material_override = base_material


# Setters
## Resets the tile's markers (pf_root, pf_distance, reachable, attackable)
func reset_markers() -> void:
	pf_root = null
	pf_distance = 0
	reachable = false
	attackable = false


## Initializes tile (disable hover, instantiate raycast & reset state)
func configure_tile() -> void:
	hover = false
	var tile: MeshInstance3D = get_node_or_null("Tile") as MeshInstance3D
	if tile:
		base_material = tile.material_override
	if not has_meta("chunked_terrain"):
		var raycast_scene: Resource = load(
			"res://data/modules/tactics/level/arena/tile/raycast/tile_raycasting.tscn"
		)
		add_child(raycast_scene.instantiate())
	reset_markers() # Reset tile markers
	_update_marker()
#endregion
