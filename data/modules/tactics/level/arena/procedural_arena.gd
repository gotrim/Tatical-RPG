extends TacticsArena

const GRID_WIDTH: int = 23
const GRID_DEPTH: int = 23
const TILE_DEPTH: float = 0.8
const HEIGHT_INTERVAL: float = 0.25
const BLOCK_AIR: int = 0
const BLOCK_TERRAIN: int = 1
const BLOCK_WATER: int = 2

enum Biome { OCEAN, DESERT, SNOWY_TUNDRA, FOREST, PLAINS }

const TERRAIN_CHUNK_MANAGER_SCRIPT = preload(
	"res://data/modules/tactics/level/arena/terrain_chunk_manager.gd"
)
const GRASS_PLANE_MESH: Mesh = preload(
	"res://assets/environment/grass/grass_blade_mesh.tres"
)
const GRASS_TEXTURE: Texture2D = preload(
	"res://assets/environment/grass/textures/grassleaf.png"
)
const ACCENT_GRASS_TEXTURE: Texture2D = preload(
	"res://assets/environment/grass/textures/accentleaf.png"
)
const ALBEDO2_NOISE: Texture2D = preload(
	"res://assets/environment/grass/textures/Albedo2Noise.tres"
)
const ALBEDO3_NOISE: Texture2D = preload(
	"res://assets/environment/grass/textures/Albedo3Noise.tres"
)
const WIND_NOISE: Texture2D = preload(
	"res://assets/environment/grass/textures/WindNoise.tres"
)
const GRASS_SHADER: Shader = preload(
	"res://assets/environment/grass/Shaders/Grass.gdshader"
)
const FLOOR_SHADER: Shader = preload(
	"res://assets/environment/grass/Shaders/Floor.gdshader"
)

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
@export_range(4, 32, 1) var chunk_size_tiles: int = 16

@export_group("Cores dos biomas")
@export var ocean_color: Color = Color(0.12, 0.30, 0.48)
@export var desert_color: Color = Color(0.72, 0.59, 0.34)
@export var snowy_tundra_color: Color = Color(0.82, 0.87, 0.90)
@export var forest_color: Color = Color(0.18, 0.39, 0.20)
@export var plains_color: Color = Color(0.48, 0.64, 0.32)

@export_group("Oceano")
@export var ocean_surface_height: float = 0.0
@export_range(0.25, 2.0, 0.25) var shallow_water_depth: float = 0.5
@export_range(0.5, 3.0, 0.25) var medium_water_depth: float = 1.0
@export_range(0.75, 4.0, 0.25) var deep_water_depth: float = 1.5
@export_range(0.0, 1.0, 0.01) var submerge_per_depth_unit: float = 1.0
@export_range(0.0, 0.75, 0.01) var maximum_submerge: float = 0.75
@export_range(0.1, 0.9, 0.05) var water_opacity: float = 0.65
@export var ocean_floor_color: Color = Color(0.25, 0.31, 0.30)

@export_group("Rampas")
@export_range(0.25, 2.0, 0.25) var ramp_max_height_difference: float = 0.75
@export_range(2, 8, 1) var ramp_max_length_tiles: int = 4
@export_range(0.25, 2.0, 0.25) var ramp_min_total_rise: float = 0.5
@export_range(0, 32, 1) var grass_clumps_per_tile: int = 16

var _continentality_noise: FastNoiseLite = FastNoiseLite.new()
var _erosion_noise: FastNoiseLite = FastNoiseLite.new()
var _temperature_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _water_surface_mesh: PlaneMesh = PlaneMesh.new()
var _water_material: StandardMaterial3D
var _materials: Dictionary = {}
var _grass_material: ShaderMaterial
var _terrain_meshes: Dictionary = {}
var _terrain_chunk_manager: Node3D
var _ramp_directions: Array[Vector2i] = []
var _ramp_start_heights: PackedFloat32Array = PackedFloat32Array()
var _ramp_rises: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_clear_tiles()
	_clear_terrain_chunks()
	$Terrain.visible = false
	_continentality_noise = _create_noise(0, 4)
	_erosion_noise = _create_noise(100, 3)
	_temperature_noise = _create_noise(200, 2)
	_moisture_noise = _create_noise(300, 2)
	_water_surface_mesh.size = Vector2(1.0, 1.0)
	_generate_tiles()
	_place_pawns_on_tiles()
	super._ready()


func _clear_tiles() -> void:
	for tile: Node in $Tiles.get_children():
		$Tiles.remove_child(tile)
		tile.free()


func _clear_terrain_chunks() -> void:
	var manager: Node = get_node_or_null("TerrainChunkManager")
	if manager:
		remove_child(manager)
		manager.free()
	_terrain_chunk_manager = null


func _generate_tiles() -> void:
	var first_x: int = -floori(float(GRID_WIDTH) / 2.0)
	var first_z: int = -floori(float(GRID_DEPTH) / 2.0)
	var heights: PackedFloat32Array = PackedFloat32Array()
	var biomes: PackedByteArray = PackedByteArray()
	var block_types: PackedByteArray = PackedByteArray()
	var water_depths: PackedFloat32Array = PackedFloat32Array()
	heights.resize(GRID_WIDTH * GRID_DEPTH)
	biomes.resize(GRID_WIDTH * GRID_DEPTH)
	block_types.resize(GRID_WIDTH * GRID_DEPTH)
	water_depths.resize(GRID_WIDTH * GRID_DEPTH)

	for x: int in range(GRID_WIDTH):
		for z: int in range(GRID_DEPTH):
			var grid_x: int = first_x + x
			var grid_z: int = first_z + z
			var column: Vector3 = _get_column(grid_x, grid_z)
			var index: int = _height_index(x, z)
			heights[index] = column.x
			biomes[index] = int(column.y)
			block_types[index] = (
				BLOCK_WATER if int(column.y) == Biome.OCEAN else BLOCK_TERRAIN
			)
			water_depths[index] = column.z

	_flatten_ocean_shores(heights, biomes)
	_build_ramp_runs(heights, biomes)

	var terrain_heights: PackedFloat32Array = heights.duplicate()
	for index: int in range(terrain_heights.size()):
		if _ramp_directions[index] != Vector2i.ZERO:
			terrain_heights[index] = (
				_ramp_start_heights[index] + _ramp_rises[index] / 2.0
			)

	for x: int in range(GRID_WIDTH):
		for z: int in range(GRID_DEPTH):
			var index: int = _height_index(x, z)
			var biome: int = biomes[index]
			var height: float = heights[index]
			var corner_heights: PackedFloat32Array = PackedFloat32Array()
			if biome != Biome.OCEAN:
				corner_heights = _get_tile_corner_heights(
					x, z, terrain_heights, biomes
				)
				height = (corner_heights[1] + corner_heights[3]) / 2.0
			_create_tile(
				first_x + x,
				first_z + z,
				height,
				biome,
				water_depths[index],
				corner_heights
			)
	_build_terrain_chunks(first_x, first_z, terrain_heights, biomes, block_types, water_depths)


func _flatten_ocean_shores(
	heights: PackedFloat32Array, biomes: PackedByteArray
) -> void:
	var directions: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
	]
	for x: int in range(GRID_WIDTH):
		for z: int in range(GRID_DEPTH):
			var index: int = _height_index(x, z)
			if biomes[index] == Biome.OCEAN:
				continue
			for direction: Vector2i in directions:
				var neighbor_x: int = x + direction.x
				var neighbor_z: int = z + direction.y
				if neighbor_x < 0 or neighbor_x >= GRID_WIDTH:
					continue
				if neighbor_z < 0 or neighbor_z >= GRID_DEPTH:
					continue
				if biomes[_height_index(neighbor_x, neighbor_z)] == Biome.OCEAN:
					heights[index] = ocean_surface_height
					break


func _get_tile_corner_heights(
	x: int,
	z: int,
	terrain_heights: PackedFloat32Array,
	biomes: PackedByteArray
) -> PackedFloat32Array:
	return PackedFloat32Array([
		_get_vertex_height(x, z, terrain_heights, biomes),
		_get_vertex_height(x + 1, z, terrain_heights, biomes),
		_get_vertex_height(x + 1, z + 1, terrain_heights, biomes),
		_get_vertex_height(x, z + 1, terrain_heights, biomes)
	])


func _get_vertex_height(
	vertex_x: int,
	vertex_z: int,
	terrain_heights: PackedFloat32Array,
	biomes: PackedByteArray
) -> float:
	var adjacent_cells: Array[Vector2i] = [
		Vector2i(vertex_x - 1, vertex_z - 1),
		Vector2i(vertex_x, vertex_z - 1),
		Vector2i(vertex_x - 1, vertex_z),
		Vector2i(vertex_x, vertex_z)
	]
	var height_sum: float = 0.0
	var sample_count: int = 0
	for cell: Vector2i in adjacent_cells:
		if (
			cell.x < 0 or cell.x >= GRID_WIDTH
			or cell.y < 0 or cell.y >= GRID_DEPTH
		):
			continue
		var index: int = _height_index(cell.x, cell.y)
		if biomes[index] == Biome.OCEAN:
			return ocean_surface_height
		height_sum += terrain_heights[index]
		sample_count += 1
	if sample_count == 0:
		return ocean_surface_height
	return height_sum / float(sample_count)


func _build_ramp_runs(heights: PackedFloat32Array, biomes: PackedByteArray) -> void:
	var tile_count: int = GRID_WIDTH * GRID_DEPTH
	_ramp_directions.resize(tile_count)
	_ramp_start_heights = heights.duplicate()
	_ramp_rises.resize(tile_count)
	_ramp_rises.fill(0.0)
	for index: int in range(tile_count):
		_ramp_directions[index] = Vector2i.ZERO

	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]

	for x: int in range(GRID_WIDTH):
		for z: int in range(GRID_DEPTH):
			var start_index: int = _height_index(x, z)
			if (
				biomes[start_index] == Biome.OCEAN
				or _ramp_directions[start_index] != Vector2i.ZERO
			):
				continue
			var best_direction: Vector2i = Vector2i.ZERO
			var best_length: int = 0
			var best_rise: float = 0.0

			for direction: Vector2i in directions:
				for length: int in range(ramp_max_length_tiles, 1, -1):
					var total_rise: float = _get_ramp_run_rise(
						x, z, direction, length, heights, biomes
					)
					if total_rise < 0.0:
						continue
					if length > best_length or (length == best_length and total_rise > best_rise):
						best_direction = direction
						best_length = length
						best_rise = total_rise

			if best_length > 0:
				_assign_ramp_run(
					x, z, best_direction, best_length, best_rise
				)

	for x: int in range(GRID_WIDTH):
		for z: int in range(GRID_DEPTH):
			var index: int = _height_index(x, z)
			if _ramp_directions[index] != Vector2i.ZERO or biomes[index] == Biome.OCEAN:
				continue
			var direction: Vector2i = _get_single_ramp_direction(x, z, heights, biomes)
			if direction == Vector2i.ZERO:
				continue
			var neighbor_index: int = _height_index(x + direction.x, z + direction.y)
			_ramp_directions[index] = direction
			_ramp_start_heights[index] = heights[index]
			_ramp_rises[index] = heights[neighbor_index] - heights[index]


func _get_ramp_run_rise(
	start_x: int,
	start_z: int,
	direction: Vector2i,
	length: int,
	heights: PackedFloat32Array,
	biomes: PackedByteArray
) -> float:
	var end_x: int = start_x + direction.x * length
	var end_z: int = start_z + direction.y * length
	if end_x < 0 or end_x >= GRID_WIDTH or end_z < 0 or end_z >= GRID_DEPTH:
		return -1.0

	var start_index: int = _height_index(start_x, start_z)
	var end_index: int = _height_index(end_x, end_z)
	if (
		biomes[end_index] == Biome.OCEAN
		or _ramp_directions[end_index] != Vector2i.ZERO
	):
		return -1.0
	var start_height: float = heights[start_index]
	var end_height: float = heights[end_index]
	var total_rise: float = end_height - start_height
	var segment_rise: float = total_rise / float(length)
	if total_rise < ramp_min_total_rise or segment_rise > ramp_max_height_difference:
		return -1.0

	var previous_height: float = start_height
	for step: int in range(1, length):
		var tile_x: int = start_x + direction.x * step
		var tile_z: int = start_z + direction.y * step
		var index: int = _height_index(tile_x, tile_z)
		if biomes[index] == Biome.OCEAN or _ramp_directions[index] != Vector2i.ZERO:
			return -1.0

		var sample_height: float = heights[index]
		var expected_height: float = start_height + segment_rise * float(step)
		if sample_height < previous_height:
			return -1.0
		if absf(sample_height - expected_height) > ramp_max_height_difference:
			return -1.0
		previous_height = sample_height

	if end_height < previous_height:
		return -1.0
	return total_rise


func _assign_ramp_run(
	start_x: int,
	start_z: int,
	direction: Vector2i,
	length: int,
	total_rise: float
) -> void:
	var start_height: float = _ramp_start_heights[_height_index(start_x, start_z)]
	var segment_rise: float = total_rise / float(length)
	for step in range(length):
		var x: int = start_x + direction.x * step
		var z: int = start_z + direction.y * step
		var index: int = _height_index(x, z)
		_ramp_directions[index] = direction
		_ramp_start_heights[index] = start_height + segment_rise * float(step)
		_ramp_rises[index] = segment_rise


func _get_single_ramp_direction(
	x: int, z: int, heights: PackedFloat32Array, biomes: PackedByteArray
) -> Vector2i:
	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]
	var best_direction: Vector2i = Vector2i.ZERO
	var best_rise: float = 0.0
	var current_index: int = _height_index(x, z)
	for direction: Vector2i in directions:
		var neighbor_x: int = x + direction.x
		var neighbor_z: int = z + direction.y
		if neighbor_x < 0 or neighbor_x >= GRID_WIDTH:
			continue
		if neighbor_z < 0 or neighbor_z >= GRID_DEPTH:
			continue
		var neighbor_index: int = _height_index(neighbor_x, neighbor_z)
		if biomes[neighbor_index] == Biome.OCEAN:
			continue
		if _ramp_directions[neighbor_index] != Vector2i.ZERO:
			continue
		var rise: float = heights[neighbor_index] - heights[current_index]
		if rise >= HEIGHT_INTERVAL and rise <= ramp_max_height_difference and rise > best_rise:
			best_direction = direction
			best_rise = rise
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
				pawn.global_position = nearest_tile.get_standing_position()
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


func _get_column(x: int, z: int) -> Vector3:
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
	var water_depth: float = 0.0
	if biome == Biome.OCEAN:
		height = ocean_surface_height
		water_depth = _get_ocean_depth(continentality)
	return Vector3(height, float(biome), water_depth)


func _get_ocean_depth(continentality: float) -> float:
	if continentality < -0.65:
		return deep_water_depth
	if continentality < -0.4:
		return medium_water_depth
	return shallow_water_depth


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
	water_depth: float,
	corner_heights: PackedFloat32Array
) -> void:
	var tile: TacticsTile = TacticsTile.new()
	tile.name = "Tile_%d_%d" % [x, z]
	var is_ocean: bool = biome == Biome.OCEAN
	tile.position = Vector3(x, height, z)
	tile.set_meta("chunked_terrain", true)
	tile.set_meta("biome", biome)
	tile.set_meta("water_depth", water_depth)
	tile.set_meta(
		"water_submerge",
		minf(water_depth * submerge_per_depth_unit, maximum_submerge)
	)
	tile.collision_layer = 0
	tile.collision_mask = 0

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Tile"
	mesh_instance.mesh = (
		_water_surface_mesh if is_ocean else _get_terrain_mesh(corner_heights, height, 0)
	)
	mesh_instance.material_override = _get_material(biome)
	if is_ocean:
		mesh_instance.position.y = 0.005
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tile.add_child(mesh_instance)
	tile.visible_as_floor = false
	tile.configure_tile()
	$Tiles.add_child(tile)


func _build_terrain_chunks(
	first_x: int,
	first_z: int,
	terrain_heights: PackedFloat32Array,
	biomes: PackedByteArray,
	block_types: PackedByteArray,
	water_depths: PackedFloat32Array
) -> void:
	var manager_script: Script = TERRAIN_CHUNK_MANAGER_SCRIPT
	_terrain_chunk_manager = manager_script.new() as Node3D
	_terrain_chunk_manager.name = "TerrainChunkManager"
	add_child(_terrain_chunk_manager)

	for start_x in range(0, GRID_WIDTH, chunk_size_tiles):
		for start_z in range(0, GRID_DEPTH, chunk_size_tiles):
			var meshes: Dictionary = _build_chunk_meshes(
				start_x,
				start_z,
				terrain_heights,
				biomes,
				block_types,
				water_depths
			)
			_terrain_chunk_manager.call(
				"add_chunk",
				"Chunk_%d_%d" % [start_x, start_z],
				Vector3(first_x + start_x, 0.0, first_z + start_z),
				meshes.render,
				meshes.collision,
				self,
				meshes.grass,
				_get_grass_material()
			)


func _build_chunk_meshes(
	chunk_start_x: int,
	chunk_start_z: int,
	terrain_heights: PackedFloat32Array,
	biomes: PackedByteArray,
	block_types: PackedByteArray,
	water_depths: PackedFloat32Array
) -> Dictionary:
	var render_tools: Dictionary = {}
	var grass_transforms: Array[Transform3D] = []
	var grass_colors: Array[Color] = []
	var water_tool: SurfaceTool
	var collision_tool := SurfaceTool.new()
	collision_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var chunk_end_x: int = mini(chunk_start_x + chunk_size_tiles, GRID_WIDTH)
	var chunk_end_z: int = mini(chunk_start_z + chunk_size_tiles, GRID_DEPTH)

	for x in range(chunk_start_x, chunk_end_x):
		for z in range(chunk_start_z, chunk_end_z):
			var index: int = _height_index(x, z)
			var local_x: float = float(x - chunk_start_x)
			var local_z: float = float(z - chunk_start_z)
			var top: Array[Vector3] = []
			var uv: Array[Vector2] = [
				Vector2(local_x - 0.5, local_z - 0.5),
				Vector2(local_x + 0.5, local_z - 0.5),
				Vector2(local_x + 0.5, local_z + 0.5),
				Vector2(local_x - 0.5, local_z + 0.5)
			]

			if block_types[index] == BLOCK_WATER:
				var floor_height: float = ocean_surface_height - water_depths[index]
				top = _get_flat_cell_vertices(local_x, local_z, floor_height)
				var ocean_tool: SurfaceTool = _get_chunk_surface_tool(
					render_tools, Biome.OCEAN
				)
				_add_chunk_top(ocean_tool, top, uv)
				_add_ocean_floor_sides(
					x, z, local_x, local_z, floor_height,
					block_types, water_depths, render_tools
				)

				if water_tool == null:
					water_tool = SurfaceTool.new()
					water_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				var water_top: Array[Vector3] = _get_flat_cell_vertices(
					local_x, local_z, ocean_surface_height
				)
				_add_chunk_top(water_tool, water_top, uv)
				continue

			var corner_heights: PackedFloat32Array = _get_tile_corner_heights(
				x, z, terrain_heights, biomes
			)
			for corner in range(4):
				top.append(
					Vector3(
						uv[corner].x,
						corner_heights[corner],
						uv[corner].y
					)
				)
			var terrain_tool: SurfaceTool = _get_chunk_surface_tool(
				render_tools, biomes[index]
			)
			_add_chunk_top(terrain_tool, top, uv)
			_add_chunk_top(collision_tool, top, uv)
			_add_terrain_sides(
				x, z, top, block_types, water_depths,
				render_tools, biomes[index], collision_tool
			)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(Vector3i(x + world_seed, z, biomes[index]))
			var grass_tint: Color = _get_grass_color(biomes[index])
			for clump_index: int in range(grass_clumps_per_tile):
				var offset := Vector2(
					rng.randf_range(-0.5, 0.5),
					rng.randf_range(-0.5, 0.5)
				)
				var tile_progress := offset + Vector2(0.5, 0.5)
				var grass_position := Vector3(
					local_x + offset.x,
					_get_tile_surface_height(corner_heights, tile_progress),
					local_z + offset.y
				)
				var grass_normal: Vector3 = _get_tile_surface_normal(
					corner_heights, tile_progress
				)
				var base_angle: float = rng.randf_range(0.0, TAU)
				var grass_height_scale: float = rng.randf_range(1.2, 1.8)
				if rng.randf() < 0.25:
					grass_height_scale = rng.randf_range(1.8, 2.4)
				var grass_scale := Vector3(
					rng.randf_range(0.9, 1.2),
					grass_height_scale,
					1.0
				)
				var align_to_surface := Basis(Quaternion(Vector3.UP, grass_normal))
				for crossing: int in range(2):
					var grass_basis := (
						align_to_surface
						* Basis(Vector3.UP, base_angle + float(crossing) * PI / 2.0)
					).scaled(grass_scale)
					var grass_transform := Transform3D(grass_basis, grass_position)
					grass_transforms.append(grass_transform)
					grass_colors.append(grass_tint)

	var render_mesh := ArrayMesh.new()
	for biome_id: int in render_tools:
		_append_surface_tool(
			render_mesh, render_tools[biome_id], _get_material(biome_id)
		)
	if water_tool:
		_append_surface_tool(render_mesh, water_tool, _get_water_material())
	var grass_multimesh: MultiMesh = _build_grass_multimesh(
		grass_transforms, grass_colors
	)
	return {
		"render": render_mesh,
		"collision": collision_tool.commit(),
		"grass": grass_multimesh
	}


func _get_tile_surface_height(
	corner_heights: PackedFloat32Array, progress: Vector2
) -> float:
	var x: float = clampf(progress.x, 0.0, 1.0)
	var z: float = clampf(progress.y, 0.0, 1.0)
	if x + z <= 1.0:
		return (
			corner_heights[0] * (1.0 - x - z)
			+ corner_heights[1] * x
			+ corner_heights[3] * z
		)
	return (
		corner_heights[1] * (1.0 - z)
		+ corner_heights[3] * (1.0 - x)
		+ corner_heights[2] * (x + z - 1.0)
	)


func _get_tile_surface_normal(
	corner_heights: PackedFloat32Array, progress: Vector2
) -> Vector3:
	var corner_0 := Vector3(-0.5, corner_heights[0], -0.5)
	var corner_1 := Vector3(0.5, corner_heights[1], -0.5)
	var corner_2 := Vector3(0.5, corner_heights[2], 0.5)
	var corner_3 := Vector3(-0.5, corner_heights[3], 0.5)
	var normal: Vector3
	if progress.x + progress.y <= 1.0:
		normal = (corner_3 - corner_0).cross(corner_1 - corner_0).normalized()
	else:
		normal = (corner_3 - corner_1).cross(corner_2 - corner_1).normalized()
	return normal if normal.y >= 0.0 else -normal


func _build_grass_multimesh(
	transforms: Array[Transform3D], colors: Array[Color]
) -> MultiMesh:
	if transforms.is_empty():
		return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = GRASS_PLANE_MESH
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_color(index, colors[index])
	return multimesh


func _get_grass_material() -> ShaderMaterial:
	if _grass_material:
		return _grass_material
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = GRASS_SHADER
	_grass_material.set_shader_parameter("albedo_texture", GRASS_TEXTURE)
	_grass_material.set_shader_parameter("albedo1", Color(0.443137, 0.635294, 0.0))
	_grass_material.set_shader_parameter("albedo2", Color(0.556863, 0.678431, 0.211765))
	_grass_material.set_shader_parameter("albedo2_scale", 0.11)
	_grass_material.set_shader_parameter("albedo2_threshold", 0.537)
	_grass_material.set_shader_parameter("albedo2_noise", ALBEDO2_NOISE)
	_grass_material.set_shader_parameter("albedo3", Color(0.501961, 0.654902, 0.223529))
	_grass_material.set_shader_parameter("albedo3_scale", 0.1)
	_grass_material.set_shader_parameter("albedo3_threshold", 0.471)
	_grass_material.set_shader_parameter("albedo3_noise", ALBEDO3_NOISE)
	_grass_material.set_shader_parameter("accent_frequency1", 0.001)
	_grass_material.set_shader_parameter("accent_texture1", GRASS_TEXTURE)
	_grass_material.set_shader_parameter("accent_albedo1", Color(0.603922, 0.717647, 0.0))
	_grass_material.set_shader_parameter("accent_height1", 0.1)
	_grass_material.set_shader_parameter("accent_scale1", 1.0)
	_grass_material.set_shader_parameter("accent_probability2", 0.0001)
	_grass_material.set_shader_parameter("accent_texture2", ACCENT_GRASS_TEXTURE)
	_grass_material.set_shader_parameter("accent_albedo2", Color(0.423529, 0.603922, 0.0))
	_grass_material.set_shader_parameter("accent_height2", 0.185)
	_grass_material.set_shader_parameter("accent_scale2", 1.0)
	_grass_material.set_shader_parameter("framerate", 5.0)
	_grass_material.set_shader_parameter("quantised", true)
	_grass_material.set_shader_parameter("world_space_sway", true)
	_grass_material.set_shader_parameter("world_sway_angle", 60.0)
	_grass_material.set_shader_parameter("fake_perspective_scale", 0.3)
	_grass_material.set_shader_parameter("wind_noise", WIND_NOISE)
	_grass_material.set_shader_parameter("wind_noise_threshold", 0.365)
	_grass_material.set_shader_parameter("wind_noise_scale", 0.071)
	_grass_material.set_shader_parameter("wind_noise_speed", 0.025)
	_grass_material.set_shader_parameter("wind_noise_direction", Vector2(0.0, 1.0))
	_grass_material.set_shader_parameter("noise_diverge_angle", 10.0)
	_grass_material.set_shader_parameter("view_space_sway", true)
	_grass_material.set_shader_parameter("view_sway_speed", 0.1)
	_grass_material.set_shader_parameter("view_sway_angle", 10.0)
	_grass_material.set_shader_parameter("character_displacement", true)
	_grass_material.set_shader_parameter("player_displacement_angle_z", 60.0)
	_grass_material.set_shader_parameter("player_displacement_angle_x", 62.7)
	_grass_material.set_shader_parameter("radius_exponent", 0.9)
	_grass_material.set_shader_parameter("cuts", 3)
	_grass_material.set_shader_parameter("wrap", 0.0)
	_grass_material.set_shader_parameter("steepness", 1.0)
	_grass_material.set_shader_parameter("threshold_gradient_size", 0.255)
	var empty_character_positions: Array[Vector4] = []
	empty_character_positions.resize(64)
	for index: int in range(64):
		empty_character_positions[index] = Vector4.ZERO
	_grass_material.set_shader_parameter(
		"character_positions", empty_character_positions
	)
	return _grass_material


func _get_grass_color(biome: int) -> Color:
	match biome:
		Biome.DESERT:
			return desert_color.lerp(Color(0.95, 0.82, 0.48), 0.45)
		Biome.SNOWY_TUNDRA:
			return snowy_tundra_color.lerp(Color.WHITE, 0.2)
		Biome.FOREST:
			return forest_color.lerp(Color(0.48, 0.76, 0.28), 0.4)
		_:
			return plains_color.lerp(Color(0.78, 0.88, 0.38), 0.3)


func _get_chunk_surface_tool(
	surface_tools: Dictionary, material_id: int
) -> SurfaceTool:
	if not surface_tools.has(material_id):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface_tools[material_id] = surface
	return surface_tools[material_id] as SurfaceTool


func _append_surface_tool(
	mesh: ArrayMesh, surface: SurfaceTool, material: Material
) -> void:
	var partial_mesh: ArrayMesh = surface.commit()
	for surface_index in range(partial_mesh.get_surface_count()):
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES,
			partial_mesh.surface_get_arrays(surface_index)
		)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)


func _get_flat_cell_vertices(
	x: float, z: float, height: float
) -> Array[Vector3]:
	return [
		Vector3(x - 0.5, height, z - 0.5),
		Vector3(x + 0.5, height, z - 0.5),
		Vector3(x + 0.5, height, z + 0.5),
		Vector3(x - 0.5, height, z + 0.5)
	]


func _add_chunk_top(
	surface: SurfaceTool, vertices: Array[Vector3], uvs: Array[Vector2]
) -> void:
	var first_normal: Vector3 = (
		(vertices[3] - vertices[0]).cross(vertices[1] - vertices[0]).normalized()
	)
	if first_normal.y < 0.0:
		first_normal = -first_normal
	var second_normal: Vector3 = (
		(vertices[3] - vertices[1]).cross(vertices[2] - vertices[1]).normalized()
	)
	if second_normal.y < 0.0:
		second_normal = -second_normal
	_add_chunk_triangle(
		surface, vertices[0], vertices[3], vertices[1],
		uvs[0], uvs[3], uvs[1], first_normal
	)
	_add_chunk_triangle(
		surface, vertices[1], vertices[3], vertices[2],
		uvs[1], uvs[3], uvs[2], second_normal
	)


func _add_terrain_sides(
	x: int,
	z: int,
	top: Array[Vector3],
	block_types: PackedByteArray,
	water_depths: PackedFloat32Array,
	render_tools: Dictionary,
	biome: int,
	collision_tool: SurfaceTool
) -> void:
	var directions: Array[Vector2i] = [
		Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
	]
	var edge_starts: Array[int] = [0, 1, 2, 3]
	var edge_ends: Array[int] = [1, 2, 3, 0]
	var edge_normals: Array[Vector3] = [
		Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT
	]
	var surface: SurfaceTool = _get_chunk_surface_tool(render_tools, biome)

	for side in range(4):
		var neighbor_x: int = x + directions[side].x
		var neighbor_z: int = z + directions[side].y
		var neighbor_type: int = _get_block_type(neighbor_x, neighbor_z, block_types)
		if not _is_face_visible(BLOCK_TERRAIN, neighbor_type):
			continue
		var start: int = edge_starts[side]
		var end: int = edge_ends[side]
		var bottom_start_y: float = top[start].y - TILE_DEPTH
		var bottom_end_y: float = top[end].y - TILE_DEPTH
		if neighbor_type == BLOCK_WATER:
			var neighbor_floor: float = (
				ocean_surface_height
				- water_depths[_height_index(neighbor_x, neighbor_z)]
			)
			bottom_start_y = minf(bottom_start_y, neighbor_floor)
			bottom_end_y = minf(bottom_end_y, neighbor_floor)
		var bottom_start := Vector3(top[start].x, bottom_start_y, top[start].z)
		var bottom_end := Vector3(top[end].x, bottom_end_y, top[end].z)
		var side_uvs: Array[Vector2] = [
			Vector2(top[start].x + top[start].z, top[start].y),
			Vector2(top[end].x + top[end].z, top[end].y),
			Vector2(top[end].x + top[end].z, bottom_end.y),
			Vector2(top[start].x + top[start].z, bottom_start.y)
		]
		_add_chunk_quad(
			surface, top[start], top[end], bottom_end, bottom_start,
			edge_normals[side], side_uvs
		)
		if neighbor_type != BLOCK_WATER:
			_add_chunk_quad(
				collision_tool, top[start], top[end], bottom_end, bottom_start,
				edge_normals[side], side_uvs
			)


func _add_ocean_floor_sides(
	x: int,
	z: int,
	local_x: float,
	local_z: float,
	floor_height: float,
	block_types: PackedByteArray,
	water_depths: PackedFloat32Array,
	render_tools: Dictionary
) -> void:
	var directions: Array[Vector2i] = [
		Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
	]
	var edge_starts: Array[int] = [0, 1, 2, 3]
	var edge_ends: Array[int] = [1, 2, 3, 0]
	var edge_normals: Array[Vector3] = [
		Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT
	]
	var top: Array[Vector3] = _get_flat_cell_vertices(local_x, local_z, floor_height)
	var surface: SurfaceTool = _get_chunk_surface_tool(render_tools, Biome.OCEAN)

	for side in range(4):
		var neighbor_x: int = x + directions[side].x
		var neighbor_z: int = z + directions[side].y
		var neighbor_type: int = _get_block_type(neighbor_x, neighbor_z, block_types)
		if not _is_face_visible(BLOCK_WATER, neighbor_type):
			continue
		var bottom_y: float = floor_height - TILE_DEPTH
		if neighbor_type == BLOCK_WATER:
			var neighbor_floor: float = (
				ocean_surface_height
				- water_depths[_height_index(neighbor_x, neighbor_z)]
			)
			if neighbor_floor >= floor_height:
				continue
			bottom_y = neighbor_floor
		var start: int = edge_starts[side]
		var end: int = edge_ends[side]
		var bottom_start := Vector3(top[start].x, bottom_y, top[start].z)
		var bottom_end := Vector3(top[end].x, bottom_y, top[end].z)
		var side_uvs: Array[Vector2] = [
			Vector2(top[start].x + top[start].z, floor_height),
			Vector2(top[end].x + top[end].z, floor_height),
			Vector2(top[end].x + top[end].z, bottom_y),
			Vector2(top[start].x + top[start].z, bottom_y)
		]
		_add_chunk_quad(
			surface, top[start], top[end], bottom_end, bottom_start,
			edge_normals[side], side_uvs
		)


func _get_block_type(x: int, z: int, block_types: PackedByteArray) -> int:
	if x < 0 or x >= GRID_WIDTH or z < 0 or z >= GRID_DEPTH:
		return BLOCK_AIR
	return block_types[_height_index(x, z)]


func _is_face_visible(block_type: int, neighbor_type: int) -> bool:
	return (
		neighbor_type == BLOCK_AIR
		or (neighbor_type == BLOCK_WATER and block_type != BLOCK_AIR)
	)


func _add_chunk_quad(
	surface: SurfaceTool,
	top_start: Vector3,
	top_end: Vector3,
	bottom_end: Vector3,
	bottom_start: Vector3,
	normal: Vector3,
	uvs: Array[Vector2]
) -> void:
	_add_chunk_triangle(
		surface, top_start, top_end, bottom_end,
		uvs[0], uvs[1], uvs[2], normal
	)
	_add_chunk_triangle(
		surface, top_start, bottom_end, bottom_start,
		uvs[0], uvs[2], uvs[3], normal
	)


func _add_chunk_triangle(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	uv_a: Vector2,
	uv_b: Vector2,
	uv_c: Vector2,
	normal: Vector3
) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var swap_vertex: Vector3 = b
		b = c
		c = swap_vertex
		var swap_uv: Vector2 = uv_b
		uv_b = uv_c
		uv_c = swap_uv
	surface.set_normal(normal.normalized())
	surface.set_uv(uv_a)
	surface.add_vertex(a)
	surface.set_normal(normal.normalized())
	surface.set_uv(uv_b)
	surface.add_vertex(b)
	surface.set_normal(normal.normalized())
	surface.set_uv(uv_c)
	surface.add_vertex(c)


func _get_terrain_mesh(
	corner_heights: PackedFloat32Array, center_height: float, exposed_sides: int
) -> ArrayMesh:
	var half_cell: float = 0.5
	var top: Array[Vector3] = [
		Vector3(-half_cell, corner_heights[0] - center_height, -half_cell),
		Vector3(half_cell, corner_heights[1] - center_height, -half_cell),
		Vector3(half_cell, corner_heights[2] - center_height, half_cell),
		Vector3(-half_cell, corner_heights[3] - center_height, half_cell)
	]
	var cache_key: String = "%d_%d_%d_%d_%d" % [
		roundi((corner_heights[0] - center_height) * 10000.0),
		roundi((corner_heights[1] - center_height) * 10000.0),
		roundi((corner_heights[2] - center_height) * 10000.0),
		roundi((corner_heights[3] - center_height) * 10000.0),
		exposed_sides
	]
	if _terrain_meshes.has(cache_key):
		return _terrain_meshes[cache_key]

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_terrain_triangle(surface, top[0], top[3], top[1])
	_add_terrain_triangle(surface, top[1], top[3], top[2])

	var edge_starts: Array[int] = [0, 1, 2, 3]
	var edge_ends: Array[int] = [1, 2, 3, 0]
	var edge_normals: Array[Vector3] = [
		Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT
	]
	for side in range(4):
		if (exposed_sides & (1 << side)) == 0:
			continue
		var start: int = edge_starts[side]
		var end: int = edge_ends[side]
		var bottom_start: Vector3 = top[start] + Vector3.DOWN * TILE_DEPTH
		var bottom_end: Vector3 = top[end] + Vector3.DOWN * TILE_DEPTH
		_add_ramp_quad(
			surface, top[start], top[end], bottom_end, bottom_start, edge_normals[side]
		)

	var terrain_mesh: ArrayMesh = surface.commit()
	_terrain_meshes[cache_key] = terrain_mesh
	return terrain_mesh


func _add_terrain_triangle(
	surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3
) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	if normal.y < 0.0:
		normal = -normal
	_add_ramp_triangle(surface, a, b, c, normal)


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


func _get_material(biome: int) -> ShaderMaterial:
	if _materials.has(biome):
		return _materials[biome] as ShaderMaterial

	var base_color: Color
	match biome:
		Biome.OCEAN:
			base_color = ocean_floor_color
		Biome.DESERT:
			base_color = desert_color
		Biome.SNOWY_TUNDRA:
			base_color = snowy_tundra_color
		Biome.FOREST:
			base_color = forest_color
		_:
			base_color = plains_color
	var material := ShaderMaterial.new()
	material.shader = FLOOR_SHADER
	material.set_shader_parameter("albedo1", base_color)
	material.set_shader_parameter("albedo2", base_color.lightened(0.16))
	material.set_shader_parameter("albedo2_noise", ALBEDO2_NOISE)
	material.set_shader_parameter("albedo2_scale", 0.11)
	material.set_shader_parameter("albedo2_threshold", 0.537)
	material.set_shader_parameter("albedo3", base_color.lightened(0.09))
	material.set_shader_parameter("albedo3_noise", ALBEDO3_NOISE)
	material.set_shader_parameter("albedo3_scale", 0.1)
	material.set_shader_parameter("albedo3_threshold", 0.471)
	material.set_shader_parameter("cuts", 3)
	material.set_shader_parameter("wrap", 0.0)
	material.set_shader_parameter("steepness", 1.0)
	_materials[biome] = material
	return material


func _get_water_material() -> StandardMaterial3D:
	if _water_material:
		return _water_material

	_water_material = StandardMaterial3D.new()
	_water_material.albedo_color = Color(
		ocean_color.r, ocean_color.g, ocean_color.b, water_opacity
	)
	_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	_water_material.render_priority = -1
	_water_material.roughness = 0.2
	return _water_material