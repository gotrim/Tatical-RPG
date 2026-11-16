class_name TacticsArenaService
extends RefCounted
## Service class for TacticsArena

## The service we inject into every tile
const TILE_SERVICE = preload("res://data/models/world/combat/arena/tile_service/service.gd")

var res: TacticsArenaResource

## Tiles cujo estado de pathfinding/marcação (pf_root, pf_distance, reachable, attackable)
## pode ser diferente do padrão. Todo tile fora deste conjunto já está no estado resetado,
## então [method reset_all_tile_markers] só precisa visitar estes (usado como set: tile -> true).
var _dirty_tiles: Dictionary = {}
## Tiles que estão com [member TacticsTile.hover] ligado (usado como set: tile -> true).
var _hovered_tiles: Dictionary = {}


## Initialize the service with a TacticsArenaResource
## [param _res] The TacticsArenaResource to use
func _init(_res: TacticsArenaResource) -> void:
	res = _res


## Set up the arena by connecting signals
## [param arena] The TacticsArena to set up
func setup(arena: TacticsArena) -> void:
	if not res:
		push_error("TacticsArena precisa de um ArenaResource de /data/models/world/combat/arena/")
	else:
		res.connect("called_reset_all_tile_markers", arena.reset_all_tile_markers)
		res.connect("called_get_pathfinding_tilestack", arena.get_pathfinding_tilestack)
		res.connect("called_mark_hover_tile", arena.mark_hover_tile)


## Reset markers for all tiles in the arena
## [param _arena] The TacticsArena containing the tiles (unused: the service tracks its own tiles)
func reset_all_tile_markers(_arena: TacticsArena) -> void:
	# Roda a cada tick de física durante a seleção; só os tiles marcados precisam de reset.
	for _dirty: Variant in _dirty_tiles:
		if is_instance_valid(_dirty):
			(_dirty as TacticsTile).reset_markers()
	_dirty_tiles.clear()


## Configure tiles in the arena
## [param arena] The TacticsArena to configure
func configure_tiles(arena: TacticsArena) -> void:
	arena.get_node("Tiles").visible = true
	var _tiles: Node3D = arena.get_node("Tiles")
	TILE_SERVICE.tiles_into_staticbodies(_tiles)


## Process tiles surrounding a root tile
## [param root_tile] The starting tile
## [param height] The height to consider for neighbors
## [param allies_on_map] Array of allied pawns on the map
func process_surrounding_tiles(root_tile: TacticsTile, height: float, allies_on_map: Array = []) -> void:
	# Fila FIFO com índice de leitura (pop_front() em Array é O(n)).
	var _tiles_process_q: Array[TacticsTile] = [root_tile]
	var _next_index: int = 0
	var _has_allies: bool = allies_on_map.size() > 0
	
	while _next_index < _tiles_process_q.size():
		var _curr_tile: TacticsTile = _tiles_process_q[_next_index]
		_next_index += 1
		
		for _neighbor: TacticsTile in _curr_tile.get_neighbors(height):
			if _neighbor.pf_root or _neighbor == root_tile:
				continue
			
			# Só há o que checar quando existem aliados (movimento): tile ocupado bloqueia.
			# Sem aliados (alcance de ataque) o tile sempre entra, então nem consulta a física:
			# "ocupante in []" é sempre falso.
			var _passable: bool = true
			if _has_allies:
				_passable = _neighbor.get_tile_occupier() == null
			
			if _passable:
				_neighbor.pf_root = _curr_tile
				_neighbor.pf_distance = _curr_tile.pf_distance + 1
				_tiles_process_q.push_back(_neighbor)
				_dirty_tiles[_neighbor] = true


## Get the pathfinding tilestack to a target tile
## [param to] The target tile
## [returns] Array of global positions forming the path
func get_pathfinding_tilestack(to: TacticsTile) -> Array:
	var _path_tiles_stack: Array = []
	
	while to:
		to.hover = true
		_hovered_tiles[to] = true
		_path_tiles_stack.push_front(to.get_standing_position())
		to = to.pf_root
		
	res.path_tiles_stack = _path_tiles_stack
	return _path_tiles_stack


## Get the nearest tile adjacent to a target pawn
## [param pawn] The pawn seeking a target
## [param target_pawns] Array of potential target pawns
## [returns] The nearest adjacent tile or the pawn's current tile if no target found
func get_nearest_target_adjacent_tile(pawn: TacticsPawn, target_pawns: Array) -> TacticsTile:
	var _nearest_target: Node3D = null
	
	for _p: TacticsPawn in target_pawns:
		if _p.stats.curr_health <= 0: continue
		for _n: TacticsTile in _p.get_tile().get_neighbors(pawn.stats.jump):
			if not _nearest_target or _n.pf_distance < _nearest_target.pf_distance:
				if _n.pf_distance > 0 and not _n.is_taken():
					_nearest_target = _n
	
	while _nearest_target and not _nearest_target.reachable: 
		_nearest_target = _nearest_target.pf_root
	
	if _nearest_target:
		return _nearest_target 
	else:
		DebugLog.debug_nospam("nearest_target", pawn)
		return pawn.get_tile()


## Get the weakest attackable pawn from an array of pawns
## [param pawn_arr] Array of pawns to evaluate
## [returns] The weakest attackable pawn or null if none found
func get_weakest_attackable_pawn(pawn_arr: Array) -> TacticsPawn:
	var _weakest: TacticsPawn = null
	
	for _p: TacticsPawn in pawn_arr:
		if not _weakest or _p.stats.curr_health < _weakest.stats.curr_health:
			if _p.stats.curr_health > 0 and _p.get_tile().attackable:
				_weakest = _p
	
	return _weakest


## Mark a tile as hovered and unmark others
## [param _arena] The TacticsArena containing the tiles (unused: the service tracks its own tiles)
## [param tile] The tile to mark as hovered
func mark_hover_tile(_arena: TacticsArena, tile: TacticsTile) -> void:
	# Roda a cada tick de física durante a seleção. Se o tile pedido já é o único com
	# hover, o estado final é o atual: evita o liga/desliga (e o _update_marker duplo).
	if tile and tile.hover and _hovered_tiles.size() == 1 and _hovered_tiles.has(tile):
		return
	
	for _hovered: Variant in _hovered_tiles:
		if is_instance_valid(_hovered):
			(_hovered as TacticsTile).hover = false
	_hovered_tiles.clear()
	
	if tile:
		tile.hover = true
		_hovered_tiles[tile] = true


## Mark reachable tiles within a certain distance from a root tile
## [param arena] The TacticsArena containing the tiles
## [param root] The starting tile
## [param distance] The maximum distance to consider
func mark_reachable_tiles(arena: TacticsArena, root: TacticsTile, distance: float) -> void:
	for _t: TacticsTile in arena.get_node("Tiles").get_children():
		var _is_root: bool = _t == root
		var _within_range: bool = _t.pf_distance > 0 and _t.pf_distance <= distance
		
		# is_taken() faz uma consulta de física; só é preciso quando o resultado decide algo.
		_t.reachable = _is_root or (_within_range and not _t.is_taken())
		if _t.reachable:
			_dirty_tiles[_t] = true


## Mark attackable tiles within a certain distance from a root tile
## [param arena] The TacticsArena containing the tiles
## [param root] The starting tile
## [param distance] The maximum attack distance
func mark_attackable_tiles(arena: TacticsArena, root: TacticsTile, distance: float) -> void:
	for _t: TacticsTile in arena.get_node("Tiles").get_children():
		var _has_dist: bool = _t.pf_distance > 0
		var _reachable: bool = _t.pf_distance <= distance
		var _is_root: bool = _t == root
		
		_t.attackable = _has_dist and _reachable or _is_root
		if _t.attackable:
			_dirty_tiles[_t] = true
