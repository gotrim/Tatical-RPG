class_name TacticsTerrainChunkManager
extends Node3D

var chunks: Array[TacticsTerrainChunk] = []
var _grass_material: ShaderMaterial
var _character_update_timer: float = 0.0

const MAX_GRASS_CHARACTERS: int = 64
const GRASS_DISPLACEMENT_RADIUS: float = 1.2


func add_chunk(
	chunk_name: String,
	chunk_position: Vector3,
	render_mesh: ArrayMesh,
	collision_mesh: ArrayMesh,
	arena: TacticsArena,
	grass_multimesh: MultiMesh,
	grass_material: ShaderMaterial
) -> void:
	_grass_material = grass_material
	var chunk := TacticsTerrainChunk.new()
	chunk.configure(
		chunk_name, chunk_position, render_mesh, collision_mesh, arena,
		grass_multimesh, grass_material
	)
	add_child(chunk)
	chunks.append(chunk)


func _process(delta: float) -> void:
	if not _grass_material:
		return
	_character_update_timer -= delta
	if _character_update_timer > 0.0:
		return
	_character_update_timer = 0.1

	var character_positions: Array[Vector4] = []
	character_positions.resize(MAX_GRASS_CHARACTERS)
	for index: int in range(MAX_GRASS_CHARACTERS):
		character_positions[index] = Vector4.ZERO

	var character_nodes: Array[Node] = get_tree().root.find_children(
		"*", "CharacterBody3D", true, false
	)
	var character_index: int = 0
	for character: Node in character_nodes:
		if not character is TacticsPawn:
			continue
		var pawn: TacticsPawn = character
		character_positions[character_index] = Vector4(
			pawn.global_position.x,
			pawn.global_position.y,
			pawn.global_position.z,
			GRASS_DISPLACEMENT_RADIUS
		)
		character_index += 1
		if character_index >= MAX_GRASS_CHARACTERS:
			break
	_grass_material.set_shader_parameter("character_positions", character_positions)


func clear_chunks() -> void:
	for chunk: TacticsTerrainChunk in chunks:
		remove_child(chunk)
		chunk.free()
	chunks.clear()
