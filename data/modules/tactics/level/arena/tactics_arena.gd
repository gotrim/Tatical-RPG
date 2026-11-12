class_name TacticsArena
extends Node3D
## Tile config & sorting, neighbours, hover & reach UI overlay, pathfinding and targeting utilities.
## 
## Resource Interface: [TacticsArenaResource] -- Service: [TacticsArenaService]
## Dependency: [TacticsTile] -- Service: [TacticsTileService]

## Resource containing arena-related data and configurations
@export var res: TacticsArenaResource = load("res://data/models/world/combat/arena/arena.tres")
## Service handling arena-related operations
var serv: TacticsArenaService
var _tiles_by_grid_position: Dictionary = {}


func _ready() -> void:
	add_to_group("tactics_arenas")
	_rebuild_tile_lookup()
	serv = TacticsArenaService.new(res) # Initialize the arena service
	serv.setup(self) # Set up the arena


## Resets all tile markers in the arena
func reset_all_tile_markers() -> void:
	serv.reset_all_tile_markers(self)


## Configures all tiles in the arena
func configure_tiles() -> void:
	serv.configure_tiles(self)
	_rebuild_tile_lookup()


func get_tile_at_world_position(world_position: Vector3) -> TacticsTile:
	var local_position: Vector3 = to_local(world_position)
	var grid_position := Vector2i(roundi(local_position.x), roundi(local_position.z))
	return _tiles_by_grid_position.get(grid_position) as TacticsTile


func get_neighbor_tiles(tile: TacticsTile, height: float) -> Array[TacticsTile]:
	var local_position: Vector3 = to_local(tile.global_position)
	var grid_position := Vector2i(roundi(local_position.x), roundi(local_position.z))
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]
	var neighbors: Array[TacticsTile] = []
	for direction: Vector2i in directions:
		var neighbor: TacticsTile = _tiles_by_grid_position.get(
			grid_position + direction
		) as TacticsTile
		if neighbor and absf(neighbor.global_position.y - tile.global_position.y) <= height:
			neighbors.append(neighbor)
	return neighbors


func _rebuild_tile_lookup() -> void:
	_tiles_by_grid_position.clear()
	var tiles: Node = get_node_or_null("Tiles")
	if not tiles:
		return
	for child: Node in tiles.get_children():
		if not child is TacticsTile:
			continue
		var local_position: Vector3 = to_local((child as TacticsTile).global_position)
		var grid_position := Vector2i(roundi(local_position.x), roundi(local_position.z))
		_tiles_by_grid_position[grid_position] = child


## Processes tiles surrounding a given root tile
## [param root_tile] The central tile to process around
## [param height] The height to consider for processing
## [param allies_on_map] Array of allied pawns on the map (optional)
func process_surrounding_tiles(root_tile: TacticsTile, height: float, allies_on_map: Array = []) -> void:
	serv.process_surrounding_tiles(root_tile, height, allies_on_map)


## Returns an array of tiles representing the pathfinding stack to a given tile
## [param to] The destination tile
## [returns] Array of tiles forming the path
func get_pathfinding_tilestack(to: TacticsTile) -> Array:
	return serv.get_pathfinding_tilestack(to)


## Finds the nearest tile adjacent to any target pawn
## [param pawn] The pawn seeking a target
## [param target_pawns] Array of potential target pawns
## [returns] The nearest adjacent tile to a target
func get_nearest_target_adjacent_tile(pawn: TacticsPawn, target_pawns: Array) -> TacticsTile:
	return serv.get_nearest_target_adjacent_tile(pawn, target_pawns)


## Identifies the weakest attackable pawn from an array of pawns
## [param pawn_arr] Array of pawns to evaluate
## [returns] The weakest attackable pawn
func get_weakest_attackable_pawn(pawn_arr: Array) -> TacticsPawn:
	return serv.get_weakest_attackable_pawn(pawn_arr)


## Marks a tile as hovered
## [param tile] The tile to mark as hovered
func mark_hover_tile(tile: TacticsTile) -> void:
	serv.mark_hover_tile(self, tile)


## Marks tiles reachable within a certain distance from a root tile
## [param root] The starting tile
## [param distance] The maximum distance to consider
func mark_reachable_tiles(root: TacticsTile, distance: float) -> void:
	serv.mark_reachable_tiles(self, root, distance)


## Marks tiles attackable within a certain distance from a root tile
## [param root] The starting tile
## [param distance] The maximum attack distance
func mark_attackable_tiles(root: TacticsTile, distance: float) -> void:
	serv.mark_attackable_tiles(self, root, distance)
