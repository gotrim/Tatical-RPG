class_name TacticsTerrainChunk
extends StaticBody3D

var arena: TacticsArena


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

	_add_vegetation("Grass", grass_multimesh, grass_material)
	_add_vegetation("TallGrass", tall_grass_multimesh, tall_grass_material)
	_add_vegetation("Flowers", flower_multimesh, flower_material)

	if collision_mesh.get_surface_count() > 0:
		var collision := CollisionShape3D.new()
		collision.name = "Collision"
		collision.shape = collision_mesh.create_trimesh_shape()
		add_child(collision)


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


func resolve_tile_hit(world_position: Vector3) -> TacticsTile:
	return arena.get_tile_at_world_position(world_position) if arena else null
