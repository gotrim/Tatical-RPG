class_name TacticsTerrainChunkManager
extends Node3D

var chunks: Array[TacticsTerrainChunk] = []


func add_chunk(
	chunk_name: String,
	chunk_position: Vector3,
	render_mesh: ArrayMesh,
	collision_mesh: ArrayMesh,
	arena: TacticsArena,
	grass_multimesh: MultiMesh,
	grass_material: Material
) -> void:
	var chunk := TacticsTerrainChunk.new()
	chunk.configure(
		chunk_name, chunk_position, render_mesh, collision_mesh, arena,
		grass_multimesh, grass_material
	)
	add_child(chunk)
	chunks.append(chunk)


func clear_chunks() -> void:
	for chunk: TacticsTerrainChunk in chunks:
		remove_child(chunk)
		chunk.free()
	chunks.clear()
