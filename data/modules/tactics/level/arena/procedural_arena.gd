extends TacticsArena

const GRID_WIDTH: int = 23
const GRID_DEPTH: int = 23
const TILE_SIZE: float = 1.01
const TILE_DEPTH: float = 0.8
const HEIGHT_INTERVAL: float = 0.25

@export_group("Rampas")
@export_range(0.25, 2.0, 0.25) var ramp_max_height_difference: float = 0.75

var _height_noise: FastNoiseLite = FastNoiseLite.new()
var _tile_mesh: BoxMesh = BoxMesh.new()
var _tile_shape: BoxShape3D = BoxShape3D.new()
var _materials: Dictionary = {}
var _ramp_meshes: Dictionary = {}


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
	var heights := PackedFloat32Array()
	heights.resize(GRID_WIDTH * GRID_DEPTH)

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var grid_x: int = first_x + x
			var grid_z: int = first_z + z
			heights[_height_index(x, z)] = _get_height(grid_x, grid_z)

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var height: float = heights[_height_index(x, z)]
			var ramp_direction: Vector2i = _get_ramp_direction(x, z, heights)
			var ramp_height: float = 0.0
			if ramp_direction != Vector2i.ZERO:
				var higher_x: int = x + ramp_direction.x
				var higher_z: int = z + ramp_direction.y
				ramp_height = heights[_height_index(higher_x, higher_z)] - height
			_create_tile(
				first_x + x, first_z + z, height, ramp_direction, ramp_height
			)


func _get_ramp_direction(x: int, z: int, heights: PackedFloat32Array) -> Vector2i:
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]
	var best_direction: Vector2i = Vector2i.ZERO
	var best_rise: float = 0.0
	var current_height: float = heights[_height_index(x, z)]

	for direction: Vector2i in directions:
		var neighbor_x: int = x + direction.x
		var neighbor_z: int = z + direction.y
		if neighbor_x < 0 or neighbor_x >= GRID_WIDTH:
			continue
		if neighbor_z < 0 or neighbor_z >= GRID_DEPTH:
			continue
		var rise: float = heights[_height_index(neighbor_x, neighbor_z)] - current_height
		if (
			rise >= HEIGHT_INTERVAL
			and rise <= ramp_max_height_difference
			and rise > best_rise
		):
			best_rise = rise
			best_direction = direction

	return best_direction


func _height_index(x: int, z: int) -> int:
	return z * GRID_WIDTH + x


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


func _create_tile(
	x: int,
	z: int,
	height: float,
	ramp_direction: Vector2i = Vector2i.ZERO,
	ramp_height: float = 0.0
) -> void:
	var tile: TacticsTile = TacticsTile.new()
	tile.name = "Tile_%d_%d" % [x, z]
	var is_ramp: bool = ramp_direction != Vector2i.ZERO
	var tile_center_height: float = height + ramp_height / 2.0 if is_ramp else height
	tile.position = Vector3(x, tile_center_height, z)
	tile.collision_layer = 1
	tile.collision_mask = 1

	var collision: CollisionShape3D = CollisionShape3D.new()
	var tile_mesh: Mesh = (
		_get_ramp_mesh(ramp_direction, ramp_height) if is_ramp else _tile_mesh
	)
	if is_ramp:
		collision.shape = tile_mesh.create_trimesh_shape()
	else:
		collision.shape = _tile_shape
		collision.position.y = -TILE_DEPTH / 2.0
	tile.add_child(collision)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Tile"
	mesh_instance.mesh = tile_mesh
	mesh_instance.material_override = _get_material(tile_center_height)
	if not is_ramp:
		mesh_instance.position.y = -TILE_DEPTH / 2.0
	tile.add_child(mesh_instance)
	tile.visible_as_floor = true

	tile.configure_tile()
	$Tiles.add_child(tile)


func _get_ramp_mesh(direction: Vector2i, rise: float) -> ArrayMesh:
	var rise_band: int = roundi(rise / HEIGHT_INTERVAL)
	var cache_key: String = "%d_%d_%d" % [direction.x, direction.y, rise_band]
	if _ramp_meshes.has(cache_key):
		return _ramp_meshes[cache_key]

	var half_size: float = TILE_SIZE / 2.0
	var half_rise: float = rise / 2.0
	var bottom_y: float = -TILE_DEPTH - half_rise
	var corners: Array[Vector2] = [
		Vector2(-half_size, -half_size),
		Vector2(half_size, -half_size),
		Vector2(half_size, half_size),
		Vector2(-half_size, half_size)
	]
	var top: Array[Vector3] = []
	var bottom: Array[Vector3] = []
	for corner: Vector2 in corners:
		var high_side: bool = corner.dot(Vector2(direction.x, direction.y)) > 0.0
		top.append(Vector3(corner.x, half_rise if high_side else -half_rise, corner.y))
		bottom.append(Vector3(corner.x, bottom_y, corner.y))

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_ramp_triangle(surface, top[0], top[3], top[1], Vector3.UP)
	_add_ramp_triangle(surface, top[1], top[3], top[2], Vector3.UP)
	_add_ramp_triangle(surface, bottom[0], bottom[1], bottom[3], Vector3.DOWN)
	_add_ramp_triangle(surface, bottom[1], bottom[2], bottom[3], Vector3.DOWN)
	_add_ramp_quad(surface, top[0], top[1], bottom[1], bottom[0], Vector3.FORWARD)
	_add_ramp_quad(surface, top[1], top[2], bottom[2], bottom[1], Vector3.RIGHT)
	_add_ramp_quad(surface, top[2], top[3], bottom[3], bottom[2], Vector3.BACK)
	_add_ramp_quad(surface, top[3], top[0], bottom[0], bottom[3], Vector3.LEFT)
	surface.generate_normals()
	var ramp_mesh: ArrayMesh = surface.commit()
	_ramp_meshes[cache_key] = ramp_mesh
	return ramp_mesh


func _add_ramp_quad(
	surface: SurfaceTool,
	top_start: Vector3,
	top_end: Vector3,
	bottom_end: Vector3,
	bottom_start: Vector3,
	outward: Vector3
) -> void:
	_add_ramp_triangle(surface, top_start, top_end, bottom_end, outward)
	_add_ramp_triangle(surface, top_start, bottom_end, bottom_start, outward)


func _add_ramp_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	outward: Vector3
) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


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