class_name ProceduralTerrain
extends Node3D
## Gera uma malha contínua e determinística de terreno. Posicione este nó no
## centro X/Z do chunk; mantenha rotação zero e escala unitária.

@export_group("Geração")
@export var seed: int = 2026
@export_range(16.0, 4096.0, 1.0) var chunk_size: float = 256.0
@export_range(2, 512, 1) var resolution: int = 129
## Distância característica das colinas. Valores maiores criam colinas largas.
@export_range(8.0, 2048.0, 1.0) var hill_scale: float = 160.0
@export_range(0.0, 256.0, 0.5) var height_amplitude: float = 24.0
@export_range(1, 8, 1) var octaves: int = 5
@export_range(1.5, 4.0, 0.05) var lacunarity: float = 2.0
@export_range(0.0, 1.0, 0.01) var gain: float = 0.5

@export_group("Pontos de interesse")
@export var points_of_interest: Array[TerrainPointOfInterest] = []

@export_group("Inclinação e bioma")
@export_range(0.0, 89.0, 0.5) var grass_max_slope_degrees: float = 28.0
@export_range(0.0, 89.0, 0.5) var rock_full_slope_degrees: float = 48.0
@export_range(0.0, 89.0, 0.5) var max_tree_slope_degrees: float = 30.0
@export var grass_color: Color = Color(0.28, 0.48, 0.20)
@export var rock_color: Color = Color(0.38, 0.36, 0.33)

@export_group("Colisão")
@export var generate_collision: bool = true

var _noise: FastNoiseLite = FastNoiseLite.new()
var _sample_spacing: float = 1.0


func _ready() -> void:
	rebuild_terrain()


## Recria a malha e a colisão com os parâmetros exportados atuais.
func rebuild_terrain() -> void:
	_configure_noise()
	_sample_spacing = chunk_size / float(resolution - 1)

	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)
	for z in range(resolution):
		for x in range(resolution):
			var world_x: float = global_position.x + _local_coordinate(x)
			var world_z: float = global_position.z + _local_coordinate(z)
			heights[_index(x, z)] = _get_height(world_x, world_z)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(resolution * resolution)
	normals.resize(resolution * resolution)
	colors.resize(resolution * resolution)

	for z in range(resolution):
		for x in range(resolution):
			var index: int = _index(x, z)
			var local_x: float = _local_coordinate(x)
			var local_z: float = _local_coordinate(z)
			var height: float = heights[index]

			vertices[index] = Vector3(local_x, height - global_position.y, local_z)
			var slope: float = _get_grid_slope_degrees(heights, x, z)
			normals[index] = Vector3(
				-_get_grid_height_gradient_x(heights, x, z),
				1.0,
				-_get_grid_height_gradient_z(heights, x, z)
			).normalized()
			colors[index] = _get_biome_color(slope)

	var indices := PackedInt32Array()
	indices.resize((resolution - 1) * (resolution - 1) * 6)
	var index_cursor: int = 0
	for z in range(resolution - 1):
		for x in range(resolution - 1):
			var a: int = _index(x, z)
			var b: int = _index(x + 1, z)
			var c: int = _index(x, z + 1)
			var d: int = _index(x + 1, z + 1)
			# Ordem dos vértices voltada para cima (eixo Y).
			indices[index_cursor] = a
			indices[index_cursor + 1] = c
			indices[index_cursor + 2] = b
			indices[index_cursor + 3] = b
			indices[index_cursor + 4] = c
			indices[index_cursor + 5] = d
			index_cursor += 6

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var generated_mesh := ArrayMesh.new()
	generated_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	generated_mesh.surface_set_material(0, material)

	_remove_generated_nodes()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "GeneratedTerrainMesh"
	mesh_instance.mesh = generated_mesh
	add_child(mesh_instance)

	if generate_collision:
		var static_body := StaticBody3D.new()
		static_body.name = "GeneratedTerrainCollision"
		var collision := CollisionShape3D.new()
		collision.shape = generated_mesh.create_trimesh_shape()
		static_body.add_child(collision)
		add_child(static_body)


## Retorna a altura do terreno para uma coordenada global X/Z.
func get_height_at_world_position(world_position: Vector2) -> float:
	return _get_height(world_position.x, world_position.y)


## Retorna a inclinação em graus na coordenada global X/Z.
func get_slope_degrees_at_world_position(world_position: Vector2) -> float:
	var delta: float = maxf(_sample_spacing, 0.5)
	var derivative_x: float = (
		_get_height(world_position.x + delta, world_position.y)
		- _get_height(world_position.x - delta, world_position.y)
	) / (2.0 * delta)
	var derivative_z: float = (
		_get_height(world_position.x, world_position.y + delta)
		- _get_height(world_position.x, world_position.y - delta)
	) / (2.0 * delta)
	var normal := Vector3(-derivative_x, 1.0, -derivative_z).normalized()
	return rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))


## Use antes de instanciar árvores; áreas de cidades e suas margens são excluídas.
func can_spawn_tree(world_position: Vector2) -> bool:
	if get_slope_degrees_at_world_position(world_position) > max_tree_slope_degrees:
		return false
	for poi: TerrainPointOfInterest in points_of_interest:
		if not is_instance_valid(poi):
			continue
		var exclusion_radius: float = poi.radius + poi.transition_width
		if world_position.distance_to(poi.world_position) < exclusion_radius:
			return false
	return true


func _configure_noise() -> void:
	_noise.seed = seed
	_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	_noise.frequency = 1.0 / maxf(hill_scale, 0.001)
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = octaves
	_noise.fractal_lacunarity = lacunarity
	_noise.fractal_gain = gain


func _get_height(world_x: float, world_z: float) -> float:
	var height_offset: float = global_position.y
	var raw_height: float = (
		_noise.get_noise_2d(world_x, world_z) * height_amplitude + height_offset
	)
	var best_weight: float = 0.0
	var best_flat_height: float = raw_height

	for poi: TerrainPointOfInterest in points_of_interest:
		if not is_instance_valid(poi) or poi.radius <= 0.0:
			continue
		var distance: float = Vector2(world_x, world_z).distance_to(poi.world_position)
		var weight: float = 0.0
		if distance <= poi.radius:
			weight = 1.0
		elif poi.transition_width > 0.0 and distance < poi.radius + poi.transition_width:
			var transition_t: float = (distance - poi.radius) / poi.transition_width
			weight = 1.0 - _smoothstep01(transition_t)

		if weight > best_weight:
			best_weight = weight
			best_flat_height = _noise.get_noise_2d(
				poi.world_position.x, poi.world_position.y
			) * height_amplitude + height_offset

	return lerpf(raw_height, best_flat_height, best_weight)


func _get_grid_height_gradient_x(heights: PackedFloat32Array, x: int, z: int) -> float:
	var world_x: float = global_position.x + _local_coordinate(x)
	var world_z: float = global_position.z + _local_coordinate(z)
	if x == 0 or x == resolution - 1:
		return (
			_get_height(world_x + _sample_spacing, world_z)
			- _get_height(world_x - _sample_spacing, world_z)
		) / (2.0 * _sample_spacing)
	return (
		heights[_index(x + 1, z)] - heights[_index(x - 1, z)]
	) / (2.0 * _sample_spacing)


func _get_grid_height_gradient_z(heights: PackedFloat32Array, x: int, z: int) -> float:
	var world_x: float = global_position.x + _local_coordinate(x)
	var world_z: float = global_position.z + _local_coordinate(z)
	if z == 0 or z == resolution - 1:
		return (
			_get_height(world_x, world_z + _sample_spacing)
			- _get_height(world_x, world_z - _sample_spacing)
		) / (2.0 * _sample_spacing)
	return (
		heights[_index(x, z + 1)] - heights[_index(x, z - 1)]
	) / (2.0 * _sample_spacing)


func _get_grid_slope_degrees(heights: PackedFloat32Array, x: int, z: int) -> float:
	var normal := Vector3(
		-_get_grid_height_gradient_x(heights, x, z),
		1.0,
		-_get_grid_height_gradient_z(heights, x, z)
	).normalized()
	return rad_to_deg(acos(clampf(normal.y, -1.0, 1.0)))


func _get_biome_color(slope_degrees: float) -> Color:
	var transition_width: float = maxf(
		rock_full_slope_degrees - grass_max_slope_degrees, 0.001
	)
	var rock_weight: float = _smoothstep01(
		(slope_degrees - grass_max_slope_degrees) / transition_width
	)
	return grass_color.lerp(rock_color, rock_weight)


func _smoothstep01(value: float) -> float:
	var t: float = clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _local_coordinate(index: int) -> float:
	return -chunk_size * 0.5 + float(index) * _sample_spacing


func _index(x: int, z: int) -> int:
	return z * resolution + x


func _remove_generated_nodes() -> void:
	for node_name: String in ["GeneratedTerrainMesh", "GeneratedTerrainCollision"]:
		var generated_node: Node = get_node_or_null(node_name)
		if generated_node:
			remove_child(generated_node)
			generated_node.free()
