class_name TacticsTerrainChunk
extends StaticBody3D

var arena: TacticsArena


func configure(
	chunk_name: String,
	chunk_position: Vector3,
	render_mesh: ArrayMesh,
	collision_mesh: ArrayMesh,
	owner_arena: TacticsArena
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

	var collision := CollisionShape3D.new()
	collision.name = "Collision"
	collision.shape = collision_mesh.create_trimesh_shape()
	add_child(collision)


func resolve_tile_hit(world_position: Vector3) -> TacticsTile:
	return arena.get_tile_at_world_position(world_position) if arena else null
