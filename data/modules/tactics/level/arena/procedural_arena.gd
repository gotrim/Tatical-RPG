extends TacticsArena

const GRID_WIDTH: int = 23
const GRID_DEPTH: int = 23
const TILE_SIZE: float = 1.01
const TILE_DEPTH: float = 0.8
const HEIGHT_INTERVAL: float = 0.25

enum Biome { OCEAN, DESERT, SNOWY_TUNDRA, FOREST, PLAINS }

@export_group("Geração de terreno")
@export var world_seed: int = 42
## Escala menor que 50 para mostrar variedade neste tabuleiro tático de 23x23.
@export_range(4.0, 100.0, 1.0) var noise_scale: float = 18.0
@export_range(-2.0, 2.0, 0.25) var base_height: float = 0.0
@export_range(0.0, 4.0, 0.25) var continentality_height: float = 1.5
@export_range(0.0, 2.0, 0.25) var erosion_strength: float = 0.75
@export_range(-4.0, 0.0, 0.25) var minimum_height: float = -1.0
@export_range(0.25, 4.0, 0.25) var maximum_height: float = 2.0
@export_range(0.1, 0.9, 0.05) var noise_persistence: float = 0.5

@export_group("Cores dos biomas")
@export var ocean_color: Color = Color(0.12, 0.30, 0.48)
@export var desert_color: Color = Color(0.72, 0.59, 0.34)
@export var snowy_tundra_color: Color = Color(0.82, 0.87, 0.90)
@export var forest_color: Color = Color(0.18, 0.39, 0.20)
@export var plains_color: Color = Color(0.48, 0.64, 0.32)

@export_group("Rampas")
@export_range(0.25, 2.0, 0.25) var ramp_max_height_difference: float = 0.75

var _continentality_noise: FastNoiseLite = FastNoiseLite.new()
var _erosion_noise: FastNoiseLite = FastNoiseLite.new()
var _temperature_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _tile_mesh: BoxMesh = BoxMesh.new()
var _tile_shape: BoxShape3D = BoxShape3D.new()
var _materials: Dictionary = {}
var _ramp_meshes: Dictionary = {}


func _ready() -> void:
	_clear_tiles()
	$Terrain.visible = false
	_continentality_noise = _create_noise(0, 4)
	_erosion_noise = _create_noise(100, 3)
	_temperature_noise = _create_noise(200, 2)
	_moisture_noise = _create_noise(300, 2)
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
	var biomes := PackedInt32Array()
	heights.resize(GRID_WIDTH * GRID_DEPTH)
	biomes.resize(GRID_WIDTH * GRID_DEPTH)

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var grid_x: int = first_x + x
			var grid_z: int = first_z + z
			var column: Vector2 = _get_column(grid_x, grid_z)
			var index: int = _height_index(x, z)
			heights[index] = column.x
			biomes[index] = int(column.y)

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var index: int = _height_index(x, z)
			var height: float = heights[index]
			var biome: int = biomes[index]
			var ramp_direction: Vector2i = _get_ramp_direction(x, z, heights)
			var ramp_height: float = 0.0
			if ramp_direction != Vector2i.ZERO:
				var higher_x: int = x + ramp_direction.x
				var higher_z: int = z + ramp_direction.y
				ramp_height = heights[_height_index(higher_x, higher_z)] - height
			_create_tile(
				first_x + x, first_z + z, height, biome, ramp_direction, ramp_height
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


func _create_noise(seed_offset: int, octave_count: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed + seed_offset
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 1.0 / maxf(noise_scale, 0.001)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octave_count
	noise.fractal_gain = noise_persistence
	noise.fractal_lacunarity = 2.0
	return noise


func _get_column(x: int, z: int) -> Vector2:
	var world_x: float = float(x)
	var world_z: float = float(z)
	var continentality: float = _continentality_noise.get_noise_2d(world_x, world_z)
	var erosion: float = _erosion_noise.get_noise_2d(world_x, world_z)
	var temperature: float = _temperature_noise.get_noise_2d(world_x, world_z)
	var moisture: float = _moisture_noise.get_noise_2d(world_x, world_z)

	var height: float = clampf(
		base_height
		+ continentality * continentality_height
		- erosion * erosion_strength,
		minimum_height,
		maximum_height
	)
	height = roundf(height / HEIGHT_INTERVAL) * HEIGHT_INTERVAL
	var biome: int = _get_biome(continentality, temperature, moisture)
	return Vector2(height, float(biome))


func _get_biome(continentality: float, temperature: float, moisture: float) -> int:
	if continentality < -0.2:
		return Biome.OCEAN
	if temperature > 0.3 and moisture < -0.2:
		return Biome.DESERT
	if temperature < -0.3:
		return Biome.SNOWY_TUNDRA
	if moisture > 0.2:
		return Biome.FOREST
	return Biome.PLAINS


func _create_tile(
	x: int,
	z: int,
	height: float,
	biome: int,
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
	mesh_instance.material_override = _get_material(biome)
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
	var ramp_normal := Vector3(
		-direction.x * rise / TILE_SIZE,
		1.0,
		-direction.y * rise / TILE_SIZE
	).normalized()
	_add_ramp_triangle(surface, top[0], top[3], top[1], ramp_normal)
	_add_ramp_triangle(surface, top[1], top[3], top[2], ramp_normal)
	_add_ramp_quad(surface, top[0], top[1], bottom[1], bottom[0], Vector3.FORWARD)
	_add_ramp_quad(surface, top[1], top[2], bottom[2], bottom[1], Vector3.RIGHT)
	_add_ramp_quad(surface, top[2], top[3], bottom[3], bottom[2], Vector3.BACK)
	_add_ramp_quad(surface, top[3], top[0], bottom[0], bottom[3], Vector3.LEFT)
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
	# Godot trata a face frontal com winding horário; as normais continuam apontando para fora.
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	surface.set_normal(outward.normalized())
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)


func _get_material(biome: int) -> StandardMaterial3D:
	if _materials.has(biome):
		return _materials[biome]

	var material: StandardMaterial3D = StandardMaterial3D.new()
	match biome:
		Biome.OCEAN:
			material.albedo_color = ocean_color
		Biome.DESERT:
			material.albedo_color = desert_color
		Biome.SNOWY_TUNDRA:
			material.albedo_color = snowy_tundra_color
		Biome.FOREST:
			material.albedo_color = forest_color
		_:
			material.albedo_color = plains_color
	material.metallic_specular = 0.0
	material.roughness = 1.0
	_materials[biome] = material
	return material