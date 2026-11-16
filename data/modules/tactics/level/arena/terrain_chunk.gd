class_name TacticsTerrainChunk
extends StaticBody3D
## Chunk detalhado da arena (tiles, rampas, colisão e vegetação).
##
## Além de renderizar, o chunk agora sabe alternar entre dois estados, controlados pelo
## TacticsTerrainChunkManager conforme a distância da câmera:
##   DETAILED: malha + colisão + vegetação (grass, tall grass, flores).
##   DISTANT:  só a malha do terreno. A colisão e a vegetação, que são as partes caras
##             (física e milhares de instâncias de grama), ficam desligadas.

enum DetailState { DETAILED, DISTANT }

var arena: TacticsArena
var detail_state: DetailState = DetailState.DETAILED

var _collision_shape: CollisionShape3D
var _vegetation: Array[MultiMeshInstance3D] = []
## Retângulo XZ do chunk no espaço do nó pai (o manager, que tem a mesma origem da arena).
var _footprint: Rect2 = Rect2()


func configure(
	chunk_name: String,
	chunk_position: Vector3,
	render_mesh: ArrayMesh,
	collision_mesh: ArrayMesh,
	owner_arena: TacticsArena,
	grass_multimesh: MultiMesh,
	grass_material: ShaderMaterial,
	tall_grass_multimesh: MultiMesh,
	tall_grass_material: ShaderMaterial,
	flower_multimesh: MultiMesh,
	flower_material: ShaderMaterial
) -> void:
	name = chunk_name
	position = chunk_position
	arena = owner_arena
	collision_layer = 1
	collision_mask = 1

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = render_mesh
	add_child(mesh_instance)

	var bounds: AABB = render_mesh.get_aabb()
	_footprint = Rect2(
		chunk_position.x + bounds.position.x,
		chunk_position.z + bounds.position.z,
		bounds.size.x,
		bounds.size.z
	)

	_add_vegetation("Grass", grass_multimesh, grass_material)
	_add_vegetation("TallGrass", tall_grass_multimesh, tall_grass_material)
	_add_vegetation("Flowers", flower_multimesh, flower_material)

	if collision_mesh.get_surface_count() > 0:
		_collision_shape = CollisionShape3D.new()
		_collision_shape.name = "Collision"
		_collision_shape.shape = collision_mesh.create_trimesh_shape()
		add_child(_collision_shape)


## Troca entre malha detalhada e distante. Retorna true se o estado mudou.
func set_detail_state(new_state: DetailState) -> bool:
	if new_state == detail_state:
		return false
	detail_state = new_state
	var detailed: bool = new_state == DetailState.DETAILED
	if _collision_shape:
		_collision_shape.disabled = not detailed
	for instance: MultiMeshInstance3D in _vegetation:
		instance.visible = detailed
	return true


## Retângulo XZ ocupado pelo chunk (espaço do manager / arena).
func get_footprint() -> Rect2:
	return _footprint


## Distância 2D de um ponto (x, z) até o retângulo do chunk; 0 se estiver dentro.
func distance_to_xz(point: Vector2) -> float:
	var delta_x: float = maxf(
		maxf(_footprint.position.x - point.x, point.x - _footprint.end.x), 0.0
	)
	var delta_z: float = maxf(
		maxf(_footprint.position.y - point.y, point.y - _footprint.end.y), 0.0
	)
	return sqrt(delta_x * delta_x + delta_z * delta_z)


func _add_vegetation(
	instance_name: String, multimesh: MultiMesh, material: ShaderMaterial
) -> void:
	if not multimesh:
		return
	var instance := MultiMeshInstance3D.new()
	instance.name = instance_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	_vegetation.append(instance)


func resolve_tile_hit(world_position: Vector3) -> TacticsTile:
	return arena.get_tile_at_world_position(world_position) if arena else null
