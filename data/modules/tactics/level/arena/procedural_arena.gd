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

@export_group("Oceano")
@export var ocean_surface_height: float = 0.0
@export_range(0.25, 2.0, 0.25) var shallow_water_depth: float = 0.5
@export_range(0.5, 3.0, 0.25) var medium_water_depth: float = 1.0
@export_range(0.75, 4.0, 0.25) var deep_water_depth: float = 1.5
@export_range(0.0, 0.5, 0.01) var submerge_per_depth_unit: float = 0.15
@export_range(0.0, 0.75, 0.01) var maximum_submerge: float = 0.3
@export_range(0.1, 0.9, 0.05) var water_opacity: float = 0.65
@export var ocean_floor_color: Color = Color(0.25, 0.31, 0.30)

@export_group("Rampas")
@export_range(0.25, 2.0, 0.25) var ramp_max_height_difference: float = 0.75
@export_range(2, 8, 1) var ramp_max_length_tiles: int = 4
@export_range(0.25, 2.0, 0.25) var ramp_min_total_rise: float = 0.5

var _continentality_noise: FastNoiseLite = FastNoiseLite.new()
var _erosion_noise: FastNoiseLite = FastNoiseLite.new()
var _temperature_noise: FastNoiseLite = FastNoiseLite.new()
var _moisture_noise: FastNoiseLite = FastNoiseLite.new()
var _tile_mesh: BoxMesh = BoxMesh.new()
var _tile_shape: BoxShape3D = BoxShape3D.new()
var _water_surface_mesh: PlaneMesh = PlaneMesh.new()
var _water_material: StandardMaterial3D
var _materials: Dictionary = {}
var _terrain_meshes: Dictionary = {}
var _ramp_directions: Array[Vector2i] = []
var _ramp_start_heights: PackedFloat32Array = PackedFloat32Array()
var _ramp_rises: PackedFloat32Array = PackedFloat32Array()


func _ready() -> void:
	_clear_tiles()
	$Terrain.visible = false
	_continentality_noise = _create_noise(0, 4)
	_erosion_noise = _create_noise(100, 3)
	_temperature_noise = _create_noise(200, 2)
	_moisture_noise = _create_noise(300, 2)
	_tile_mesh.size = Vector3(TILE_SIZE, TILE_DEPTH, TILE_SIZE)
	_tile_shape.size = _tile_mesh.size
	_water_surface_mesh.size = Vector2(1.0, 1.0)
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
	var water_depths := PackedFloat32Array()
	heights.resize(GRID_WIDTH * GRID_DEPTH)
	biomes.resize(GRID_WIDTH * GRID_DEPTH)
	water_depths.resize(GRID_WIDTH * GRID_DEPTH)

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var grid_x: int = first_x + x
			var grid_z: int = first_z + z
			var column: Vector3 = _get_column(grid_x, grid_z)
			var index: int = _height_index(x, z)
			heights[index] = column.x
			biomes[index] = int(column.y)
			water_depths[index] = column.z

	_flatten_ocean_shores(heights, biomes)
	_build_ramp_runs(heights, biomes)

	var terrain_heights: PackedFloat32Array = heights.duplicate()
	for index in range(terrain_heights.size()):
		if _ramp_directions[index] != Vector2i.ZERO:
			terrain_heights[index] = (
				_ramp_start_heights[index] + _ramp_rises[index] / 2.0
			)

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
			var index: int = _height_index(x, z)
			var biome: int = biomes[index]
			var height: float = heights[index]
			var corner_heights := PackedFloat32Array()
			var exposed_sides: int = 0
			if biome != Biome.OCEAN:
				corner_heights = _get_tile_corner_heights(
					x, z, terrain_heights, biomes
				)
				height = (corner_heights[1] + corner_heights[3]) / 2.0
				exposed_sides = _get_exposed_side_mask(x, z, biomes)
			_create_tile(
				first_x + x,
				first_z + z,
				height,
				biome,
				water_depths[index],
				corner_heights,
				exposed_sides
			)


func _flatten_ocean_shores(
	heights: PackedFloat32Array, biomes: PackedInt32Array
) -> void:
	var directions: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-1, 0), Vector2i(1, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)
	]
	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
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
	biomes: PackedInt32Array
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
	biomes: PackedInt32Array
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


func _get_exposed_side_mask(x: int, z: int, biomes: PackedInt32Array) -> int:
	var directions: Array[Vector2i] = [
		Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT
	]
	var side_mask: int = 0
	for side in range(directions.size()):
		var neighbor_x: int = x + directions[side].x
		var neighbor_z: int = z + directions[side].y
		if (
			neighbor_x < 0 or neighbor_x >= GRID_WIDTH
			or neighbor_z < 0 or neighbor_z >= GRID_DEPTH
			or biomes[_height_index(neighbor_x, neighbor_z)] == Biome.OCEAN
		):
			side_mask |= 1 << side
	return side_mask


func _build_ramp_runs(heights: PackedFloat32Array, biomes: PackedInt32Array) -> void:
	var tile_count: int = GRID_WIDTH * GRID_DEPTH
	_ramp_directions.resize(tile_count)
	_ramp_start_heights = heights.duplicate()
	_ramp_rises.resize(tile_count)
	_ramp_rises.fill(0.0)
	for index in range(tile_count):
		_ramp_directions[index] = Vector2i.ZERO

	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP
	]

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
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
				for length in range(ramp_max_length_tiles, 1, -1):
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

	for x in range(GRID_WIDTH):
		for z in range(GRID_DEPTH):
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
	biomes: PackedInt32Array
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
	for step in range(1, length):
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
	x: int, z: int, heights: PackedFloat32Array, biomes: PackedInt32Array
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
	corner_heights: PackedFloat32Array,
	exposed_sides: int
) -> void:
	var tile: TacticsTile = TacticsTile.new()
	tile.name = "Tile_%d_%d" % [x, z]
	var is_ocean: bool = biome == Biome.OCEAN
	tile.position = Vector3(x, height, z)
	tile.set_meta("biome", biome)
	tile.set_meta("water_depth", water_depth)
	tile.set_meta(
		"water_submerge",
		minf(water_depth * submerge_per_depth_unit, maximum_submerge)
	)
	tile.collision_layer = 1
	tile.collision_mask = 1

	var collision: CollisionShape3D = CollisionShape3D.new()
	var tile_mesh: Mesh = _tile_mesh
	if is_ocean:
		collision.shape = _tile_shape
		collision.position.y = -TILE_DEPTH / 2.0
		collision.position.y -= water_depth
	else:
		tile_mesh = _get_terrain_mesh(corner_heights, height, exposed_sides)
		collision.shape = tile_mesh.create_trimesh_shape()
	tile.add_child(collision)

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Tile"
	mesh_instance.mesh = tile_mesh
	mesh_instance.material_override = _get_material(biome)
	if is_ocean:
		mesh_instance.position.y = -TILE_DEPTH / 2.0
		mesh_instance.position.y -= water_depth
	tile.add_child(mesh_instance)

	if is_ocean:
		var water_surface := MeshInstance3D.new()
		water_surface.name = "WaterSurface"
		water_surface.mesh = _water_surface_mesh
		water_surface.material_override = _get_water_material()
		water_surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		water_surface.position.y = ocean_surface_height - height
		tile.add_child(water_surface)

	tile.visible_as_floor = true

	tile.configure_tile()
	$Tiles.add_child(tile)


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


func _get_material(biome: int) -> StandardMaterial3D:
	if _materials.has(biome):
		return _materials[biome]

	var material: StandardMaterial3D = StandardMaterial3D.new()
	match biome:
		Biome.OCEAN:
			material.albedo_color = ocean_floor_color
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


func _get_water_material() -> StandardMaterial3D:
	if _water_material:
		return _water_material

	_water_material = StandardMaterial3D.new()
	_water_material.albedo_color = Color(
		ocean_color.r, ocean_color.g, ocean_color.b, water_opacity
	)
	_water_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_material.roughness = 0.2
	return _water_material