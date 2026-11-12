extends TacticsArena

const GRID_WIDTH: int = 23
const GRID_DEPTH: int = 23
const TILE_SIZE: float = 1.01
const TILE_DEPTH: float = 0.8
const HEIGHT_INTERVAL: float = 0.25

var _height_noise: FastNoiseLite = FastNoiseLite.new()
var _tile_mesh: BoxMesh = BoxMesh.new()
var _tile_shape: BoxShape3D = BoxShape3D.new()
var _materials: Dictionary = {}


func _ready() -> void:
	_clear_tiles()
	$Terrain.visible = false
	_height_noise.seed = 2026
	_height_noise.frequency = 0.075
	_height_noise.fractal_octaves = 3
	_tile_mesh.size = Vector3(TILE_SIZE, TILE_DEPTH, TILE_SIZE)
	_tile_shape.size = _tile_mesh.size
	_generate_tiles()
	_place_pawns_on_tiles()
	super._ready()


func _clear_tiles() -> void:
	for tile: Node in $Tiles.get_children():
		$Tiles.remove_child(tile)
		tile.free()


func _generate_tiles() -> void:
	var first_x: int = -int(GRID_WIDTH / 2)
	var first_z: int = -int(GRID_DEPTH / 2)

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var grid_x: int = first_x + x
			var grid_z: int = first_z + z
			var height: float = _get_height(grid_x, grid_z)
			_create_tile(grid_x, grid_z, height)


func _place_pawns_on_tiles() -> void:
	var participants: Node = get_parent().get_node_or_null("TacticsParticipant")
	if not participants:
		return

	var occupied_tiles: Array[TacticsTile] = []
	for team_name: String in ["TacticsPlayer", "TacticsOpponent"]:
		var team: Node = participants.get_node_or_null(team_name)
		if not team:
			continue

		for pawn: Node in team.get_children():
			if not pawn is TacticsPawn:
				continue

			var pawn_position: Vector2 = Vector2(pawn.global_position.x, pawn.global_position.z)
			var nearest_tile: TacticsTile = null
			var nearest_distance: float = INF
			for tile: TacticsTile in $Tiles.get_children():
				if tile in occupied_tiles:
					continue
				var tile_position: Vector2 = Vector2(tile.global_position.x, tile.global_position.z)
				var distance: float = pawn_position.distance_squared_to(tile_position)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_tile = tile

			if nearest_tile:
				pawn.global_position = nearest_tile.global_position
				occupied_tiles.append(nearest_tile)
				(pawn.get_node("Tile") as RayCast3D).force_raycast_update()


func _get_height(x: int, z: int) -> float:
	var noise_value: float = _height_noise.get_noise_2d(float(x), float(z)) * 2.0
	return roundf(noise_value / HEIGHT_INTERVAL) * HEIGHT_INTERVAL


func _create_tile(x: int, z: int, height: float) -> void:
	var tile: TacticsTile = TacticsTile.new()
	tile.name = "Tile_%d_%d" % [x, z]
	tile.position = Vector3(x, height, z)
	tile.collision_layer = 1
	tile.collision_mask = 1

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = _tile_shape
	collision.position.y = -TILE_DEPTH / 2.0
	tile.add_child(collision)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Tile"
	mesh_instance.mesh = _tile_mesh
	mesh_instance.material_override = _get_material(height)
	mesh_instance.position.y = -TILE_DEPTH / 2.0
	tile.add_child(mesh_instance)
	tile.visible_as_floor = true

	tile.configure_tile()
	$Tiles.add_child(tile)


func _get_material(height: float) -> StandardMaterial3D:
	var height_band: int = roundi(height / HEIGHT_INTERVAL)
	if _materials.has(height_band):
		return _materials[height_band]

	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.670588, 0.839216, 0.784314, 1.0)
	material.metallic_specular = 0.0
	material.roughness = 0.0
	_materials[height_band] = material
	return material