class_name TacticsTerrainChunkManager
extends Node3D

var chunks: Array[TacticsTerrainChunk] = []
var _grass_material: ShaderMaterial
var _tall_grass_material: ShaderMaterial
var _character_update_timer: float = 0.0
var _pawns: Array[TacticsPawn] = []
var _character_positions: Array[Vector4] = []

const MAX_GRASS_CHARACTERS: int = 64
const GRASS_DISPLACEMENT_RADIUS: float = 1.2


func _ready() -> void:
	var scene_tree: SceneTree = get_tree()
	scene_tree.node_added.connect(_on_node_added)
	scene_tree.node_removed.connect(_on_node_removed)
	_character_positions.resize(MAX_GRASS_CHARACTERS)
	for index: int in range(MAX_GRASS_CHARACTERS):
		_character_positions[index] = Vector4.ZERO
	for node: Node in scene_tree.root.find_children(
		"*", "CharacterBody3D", true, false
	):
		_register_pawn(node)


func add_chunk(
	chunk_name: String,
	chunk_position: Vector3,
	render_mesh: ArrayMesh,
	collision_mesh: ArrayMesh,
	arena: TacticsArena,
	grass_multimesh: MultiMesh,
	grass_material: ShaderMaterial,
	tall_grass_multimesh: MultiMesh,
	tall_grass_material: ShaderMaterial,
	flower_multimesh: MultiMesh,
	flower_material: ShaderMaterial
) -> void:
	_grass_material = grass_material
	_tall_grass_material = tall_grass_material
	var chunk := TacticsTerrainChunk.new()
	chunk.configure(
		chunk_name, chunk_position, render_mesh, collision_mesh, arena,
		grass_multimesh, grass_material, tall_grass_multimesh,
		tall_grass_material, flower_multimesh, flower_material
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

	for index: int in range(MAX_GRASS_CHARACTERS):
		_character_positions[index] = Vector4.ZERO
	var character_index: int = 0
	for pawn: TacticsPawn in _pawns:
		if not is_instance_valid(pawn):
			continue
		_character_positions[character_index] = Vector4(
			pawn.global_position.x,
			pawn.global_position.y,
			pawn.global_position.z,
			GRASS_DISPLACEMENT_RADIUS
		)
		character_index += 1
		if character_index >= MAX_GRASS_CHARACTERS:
			break

	_set_character_positions(
		_grass_material, _character_positions, character_index
	)
	_set_character_positions(
		_tall_grass_material, _character_positions, character_index
	)


func _on_node_added(node: Node) -> void:
	_register_pawn(node)


func _on_node_removed(node: Node) -> void:
	var pawn := node as TacticsPawn
	if pawn:
		_pawns.erase(pawn)


func _register_pawn(node: Node) -> void:
	var pawn := node as TacticsPawn
	if pawn and not _pawns.has(pawn):
		_pawns.append(pawn)


func _set_character_positions(
	material: ShaderMaterial,
	character_positions: Array[Vector4],
	character_count: int
) -> void:
	if not material:
		return
	material.set_shader_parameter("character_positions", character_positions)
	material.set_shader_parameter("character_count", character_count)


func clear_chunks() -> void:
	for chunk: TacticsTerrainChunk in chunks:
		remove_child(chunk)
		chunk.free()
	chunks.clear()
