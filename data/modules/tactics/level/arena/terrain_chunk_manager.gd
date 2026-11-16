class_name TacticsTerrainChunkManager
extends Node3D
## Gerencia os chunks detalhados da arena e o horizonte distante (LOD estilo Distant Horizons).
##
## DUAS CAMADAS
##  1) Chunks detalhados (add_chunk, como antes): malha + colisão + vegetação. Quando ficam
##     longe da câmera passam a DISTANT (sem colisão nem vegetação), a menos que haja um
##     pawn em cima deles.
##  2) Horizonte (setup_horizon): quadtree de chunks de LOD ao redor da câmera, FORA da
##     arena. Cada folha é uma malha única de ~16x16 células, sem colisão e sem vegetação.
##     Nível L: cada célula agrega 2^L x 2^L tiles e a folha cobre (células * 2^L) tiles.
##
## ASSÍNCRONO
##  Ruído, agregação e geração dos arrays de malha rodam no WorkerThreadPool (TerrainLodJob).
##  Na thread principal só são feitos: seleção do quadtree, ArrayMesh.add_surface_from_arrays
##  (com orçamento por frame) e a troca de nós.
##
## TROCA SEM BURACOS
##  Folhas novas nascem ocultas. Um grupo de folhas antigas (visíveis) só é trocado quando
##  TODAS as folhas novas que o substituem estão prontas; a troca acontece num único frame.

const LOD_SHADER_PATH: String = "res://assets/environment/vegetation/shaders/terrain_lod.gdshader"
const MAX_GRASS_CHARACTERS: int = 64
const GRASS_DISPLACEMENT_RADIUS: float = 1.2

@export_group("Raio ativo (malha detalhada)")
## Chunks da arena a mais que isto da câmera perdem colisão e vegetação.
@export_range(8.0, 512.0, 1.0) var detail_radius: float = 64.0
@export_range(0.0, 64.0, 0.5) var detail_hysteresis: float = 8.0

@export_group("Horizonte (LOD)")
@export var horizon_enabled: bool = true
## Distância máxima (em tiles) a partir da câmera em que há terreno.
@export_range(32.0, 2048.0, 1.0) var horizon_radius: float = 320.0
## Nível máximo do quadtree. A folha do nível L cobre (lod_cells_per_chunk * 2^L) tiles.
@export_range(0, 6, 1) var max_lod_level: int = 4
@export_range(4, 64, 1) var lod_cells_per_chunk: int = 16
## Um nó se divide em 4 se a distância < tamanho * este fator. Maior = mais detalhe perto.
@export_range(1.0, 6.0, 0.1) var lod_split_factor: float = 1.5
## Histerese contra "pisca-pisca" de LOD quando a câmera está na fronteira de um anel.
@export_range(1.0, 2.0, 0.05) var lod_split_hysteresis: float = 1.25
## Profundidade das saias que escondem frestas entre níveis (use >= variação de altura).
@export_range(0.0, 16.0, 0.25) var lod_skirt_depth: float = 3.0
@export var lod_cast_shadows: bool = false
## Pinta cada nível com uma cor diferente (vermelho = LOD 0, laranja = 1, ...).
@export var debug_tint_levels: bool = false

@export_group("Streaming assíncrono")
@export_range(1, 16, 1) var max_concurrent_jobs: int = 4
## Quantos ArrayMesh por frame podem ser enviados para a GPU.
@export_range(1, 16, 1) var max_mesh_commits_per_frame: int = 4
@export_range(0.05, 2.0, 0.05) var update_interval: float = 0.2
## A seleção do quadtree só é refeita quando a câmera anda pelo menos isto (em tiles).
@export_range(0.25, 32.0, 0.25) var refresh_distance: float = 2.0

@export_group("Cache de terreno")
## Persiste os blocos em user://terrain_lod_cache (por configuração de mundo).
@export var use_disk_cache: bool = false
@export_range(64, 65536, 64) var max_cached_blocks: int = 4096

var chunks: Array[TacticsTerrainChunk] = []

var _grass_material: ShaderMaterial
var _tall_grass_material: ShaderMaterial
var _character_update_timer: float = 0.0
var _pawns: Array[TacticsPawn] = []
var _character_positions: Array[Vector4] = []
## Últimas posições enviadas ao shader (evita reenviar o mesmo array enquanto ninguém se mexe).
var _sent_character_positions: Array[Vector4] = []
var _sent_character_count: int = -1

# --- Horizonte ---
var _horizon_ready: bool = false
var _sampler: TerrainSampler
var _cache: TerrainDataCache
var _lod_material: ShaderMaterial
var _horizon_root: Node3D
## Retângulo (em tiles) da arena detalhada; o LOD nunca desenha dentro dele.
var _footprint: Rect2i = Rect2i()
## Tile inicial do grid do LOD (alinha o quadtree com os chunks da arena).
var _origin: Vector2i = Vector2i.ZERO
var _cells: int = 16
## Folhas desejadas agora: Vector3i(level, cx, cz) -> distância até a câmera.
var _wanted: Dictionary = {}
## Nós que foram divididos na última seleção (para a histerese).
var _prev_split: Dictionary = {}
## Folhas já construídas (ocultas ou visíveis): Vector3i -> TerrainLodChunk.
var _leaves: Dictionary = {}
## Jobs em andamento: Vector3i -> TerrainLodJob.
var _jobs: Dictionary = {}
## Folhas desejadas ainda sem job, da mais próxima para a mais distante.
var _pending: Array[Vector3i] = []
var _stream_timer: float = 0.0
var _last_focus: Vector2 = Vector2.ZERO
var _force_refresh: bool = true
var _swap_dirty: bool = false
var _camera_ref: Node3D


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


func _exit_tree() -> void:
	# Tarefas do WorkerThreadPool precisam ser aguardadas antes de o nó sumir.
	_wait_all_jobs()
	_force_refresh = true


## Mesma assinatura de antes: o procedural_arena.gd continua chamando assim.
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


## Liga o horizonte distante. `footprint` é a área da arena em índices de tile:
## Rect2i(first_x, first_z, GRID_WIDTH, GRID_DEPTH). Deve ser chamado com o manager já
## dentro da árvore (o pai precisa ser a arena para a checagem de paridade em debug).
func setup_horizon(sampler: TerrainSampler, footprint: Rect2i) -> void:
	if not horizon_enabled:
		return
	if not ResourceLoader.exists(LOD_SHADER_PATH):
		push_error("TerrainLOD: shader ausente em %s; horizonte desativado." % LOD_SHADER_PATH)
		return
	clear_horizon()
	_sampler = sampler
	_footprint = footprint
	_origin = footprint.position
	_cells = lod_cells_per_chunk
	_cache = TerrainDataCache.new()
	_cache.configure(_sampler, _origin, _cells, max_cached_blocks, use_disk_cache)
	_lod_material = _create_lod_material()
	_horizon_root = Node3D.new()
	_horizon_root.name = "HorizonLOD"
	add_child(_horizon_root)
	_horizon_ready = true
	_force_refresh = true
	if OS.is_debug_build():
		_debug_check_parity()


func clear_chunks() -> void:
	for chunk: TacticsTerrainChunk in chunks:
		remove_child(chunk)
		chunk.free()
	chunks.clear()
	clear_horizon()


func clear_horizon() -> void:
	_horizon_ready = false
	_wait_all_jobs()
	if is_instance_valid(_horizon_root):
		_horizon_root.queue_free()  # leva as folhas junto
	_horizon_root = null
	_leaves.clear()
	_wanted.clear()
	_pending.clear()
	_prev_split.clear()
	_force_refresh = true
	_swap_dirty = false


## Números para depuração (ex.: DebugLog).
func get_stats() -> Dictionary:
	var live_count: int = 0
	for key: Vector3i in _leaves:
		if (_leaves[key] as TerrainLodChunk).is_live:
			live_count += 1
	var distant_chunks: int = 0
	for chunk: TacticsTerrainChunk in chunks:
		if chunk.detail_state == TacticsTerrainChunk.DetailState.DISTANT:
			distant_chunks += 1
	return {
		"lod_wanted": _wanted.size(),
		"lod_built": _leaves.size(),
		"lod_visible": live_count,
		"lod_jobs_running": _jobs.size(),
		"lod_jobs_pending": _pending.size(),
		"cache_blocks": _cache.size() if _cache else 0,
		"cache_hits": _cache.hits if _cache else 0,
		"cache_misses": _cache.misses if _cache else 0,
		"cache_disk_hits": _cache.disk_hits if _cache else 0,
		"detailed_chunks": chunks.size() - distant_chunks,
		"distant_chunks": distant_chunks,
	}


func _process(delta: float) -> void:
	_update_grass_characters(delta)

	_stream_timer -= delta
	if _stream_timer <= 0.0:
		_stream_timer = update_interval
		_refresh_streaming()

	if _horizon_ready:
		_collect_finished_jobs()
		_start_jobs()
		if _swap_dirty:
			_commit_swaps()


# ---------------------------------------------------------------------------
# Câmera, raio ativo e seleção do quadtree
# ---------------------------------------------------------------------------

func _refresh_streaming() -> void:
	if chunks.is_empty() and not _horizon_ready:
		return
	var focus: Vector2 = _get_focus_xz()
	_update_detail_states(focus)
	if not _horizon_ready:
		return
	if not _force_refresh and focus.distance_to(_last_focus) < refresh_distance:
		return
	_force_refresh = false
	_last_focus = focus
	_reselect(focus)


## Ponto de foco da câmera tática (o corpo TacticsCamera, no chão), em coordenadas da arena.
## Se não houver TacticsCamera, usa a Camera3D ativa.
func _get_focus_xz() -> Vector2:
	if not is_instance_valid(_camera_ref):
		_camera_ref = null
		var cameras: Array[Node] = get_tree().get_nodes_in_group("tactics_cameras")
		if not cameras.is_empty():
			_camera_ref = cameras[0] as Node3D
	var world_position: Vector3 = global_position
	if _camera_ref:
		world_position = _camera_ref.global_position
	else:
		var active_camera: Camera3D = get_viewport().get_camera_3d()
		if active_camera:
			world_position = active_camera.global_position
	var local_position: Vector3 = to_local(world_position)
	return Vector2(local_position.x, local_position.z)


func _update_detail_states(focus: Vector2) -> void:
	for chunk: TacticsTerrainChunk in chunks:
		var distance: float = chunk.distance_to_xz(focus)
		var target: TacticsTerrainChunk.DetailState = chunk.detail_state
		if chunk.detail_state == TacticsTerrainChunk.DetailState.DETAILED:
			if distance > detail_radius + detail_hysteresis and not _chunk_has_pawn(chunk):
				target = TacticsTerrainChunk.DetailState.DISTANT
		elif distance <= detail_radius or _chunk_has_pawn(chunk):
			target = TacticsTerrainChunk.DetailState.DETAILED
		chunk.set_detail_state(target)


## A colisão do chunk é o que o raycast dos pawns usa para achar o tile; nunca a desligue
## debaixo de um pawn.
func _chunk_has_pawn(chunk: TacticsTerrainChunk) -> bool:
	var area: Rect2 = chunk.get_footprint().grow(1.0)
	for pawn: TacticsPawn in _pawns:
		if not is_instance_valid(pawn):
			continue
		var local_position: Vector3 = to_local(pawn.global_position)
		if area.has_point(Vector2(local_position.x, local_position.z)):
			return true
	return false


## Recalcula quais folhas devem existir e enfileira as que faltam (mais próximas primeiro).
func _reselect(focus: Vector2) -> void:
	var leaves: Dictionary = {}
	var split: Dictionary = {}
	var root_tiles: float = float(_cells << max_lod_level)
	var min_cx: int = floori((focus.x - horizon_radius - float(_origin.x)) / root_tiles)
	var max_cx: int = floori((focus.x + horizon_radius - float(_origin.x)) / root_tiles)
	var min_cz: int = floori((focus.y - horizon_radius - float(_origin.y)) / root_tiles)
	var max_cz: int = floori((focus.y + horizon_radius - float(_origin.y)) / root_tiles)
	for cz: int in range(min_cz, max_cz + 1):
		for cx: int in range(min_cx, max_cx + 1):
			_select_node(max_lod_level, cx, cz, focus, leaves, split)
	_prev_split = split
	_wanted = leaves

	_pending.clear()
	for key: Vector3i in _wanted:
		if not _leaves.has(key) and not _jobs.has(key):
			_pending.append(key)
	_pending.sort_custom(
		func(a: Vector3i, b: Vector3i) -> bool:
			return float(_wanted[a]) < float(_wanted[b])
	)
	_swap_dirty = true


func _select_node(
	level: int, cx: int, cz: int, focus: Vector2, leaves: Dictionary, split: Dictionary
) -> void:
	var key := Vector3i(level, cx, cz)
	var rect: Rect2i = _leaf_rect(key)
	# Totalmente dentro da arena: quem desenha é a malha detalhada.
	if _footprint.encloses(rect):
		return
	var distance: float = _distance_to_tile_rect(focus, rect)
	if distance > horizon_radius:
		return
	if level > 0:
		# Nós que tocam a arena descem até o nível 0, assim a "borda" do buraco do LOD
		# coincide exatamente com a borda dos tiles.
		var must_split: bool = _footprint.intersects(rect)
		if not must_split:
			var threshold: float = float(rect.size.x) * lod_split_factor
			if _prev_split.has(key):
				threshold *= lod_split_hysteresis
			must_split = distance < threshold
		if must_split:
			split[key] = true
			for offset_z: int in range(2):
				for offset_x: int in range(2):
					_select_node(
						level - 1, cx * 2 + offset_x, cz * 2 + offset_z,
						focus, leaves, split
					)
			return
	leaves[key] = distance


## Área da folha em índices de tile. O tile i ocupa o mundo [i - 0.5, i + 0.5].
func _leaf_rect(key: Vector3i) -> Rect2i:
	var size_tiles: int = _cells << key.x
	return Rect2i(
		_origin.x + key.y * size_tiles,
		_origin.y + key.z * size_tiles,
		size_tiles,
		size_tiles
	)


func _distance_to_tile_rect(point: Vector2, rect: Rect2i) -> float:
	var min_x: float = float(rect.position.x) - 0.5
	var min_z: float = float(rect.position.y) - 0.5
	var max_x: float = float(rect.end.x) - 0.5
	var max_z: float = float(rect.end.y) - 0.5
	var delta_x: float = maxf(maxf(min_x - point.x, point.x - max_x), 0.0)
	var delta_z: float = maxf(maxf(min_z - point.y, point.y - max_z), 0.0)
	return sqrt(delta_x * delta_x + delta_z * delta_z)


# ---------------------------------------------------------------------------
# Jobs assíncronos (WorkerThreadPool)
# ---------------------------------------------------------------------------

func _start_jobs() -> void:
	while _jobs.size() < max_concurrent_jobs and not _pending.is_empty():
		var key: Vector3i = _pending.pop_front()
		var job := TerrainLodJob.new()
		job.key = key
		job.sampler = _sampler.clone()
		job.cache = _cache
		job.origin = _origin
		job.exclude = _footprint
		job.skirt_depth = lod_skirt_depth
		job.tint = _level_tint(key.x) if debug_tint_levels else Color.WHITE
		job.task_id = WorkerThreadPool.add_task(
			job.run, false, "TerrainLOD %s" % str(key)
		)
		_jobs[key] = job


## Recolhe jobs concluídos (sem bloquear) e envia as malhas para a GPU com orçamento por frame.
func _collect_finished_jobs() -> void:
	var finished: Array[Vector3i] = []
	for key: Vector3i in _jobs:
		var job: TerrainLodJob = _jobs[key]
		if WorkerThreadPool.is_task_completed(job.task_id):
			finished.append(key)
	var commits: int = 0
	for key: Vector3i in finished:
		if commits >= max_mesh_commits_per_frame:
			break  # o resto fica para o próximo frame
		var job: TerrainLodJob = _jobs[key]
		WorkerThreadPool.wait_for_task_completion(job.task_id)
		_jobs.erase(key)
		if not _wanted.has(key):
			continue  # a câmera já foi embora; os dados continuam no cache
		_create_leaf(job)
		commits += 1


func _create_leaf(job: TerrainLodJob) -> void:
	var key: Vector3i = job.key
	var rect: Rect2i = _leaf_rect(key)
	var mesh: ArrayMesh = null
	if job.succeeded and not job.vertices.is_empty():
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = job.vertices
		arrays[Mesh.ARRAY_NORMAL] = job.normals
		arrays[Mesh.ARRAY_COLOR] = job.colors
		mesh = ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	elif not job.succeeded:
		push_warning("TerrainLOD: job %s falhou; usando folha vazia." % str(key))
	var chunk := TerrainLodChunk.new()
	# Os vértices são locais ao canto do chunk (o tile i começa em i - 0.5).
	chunk.configure(
		key, rect, mesh, _lod_material,
		Vector3(float(rect.position.x) - 0.5, 0.0, float(rect.position.y) - 0.5),
		lod_cast_shadows
	)
	_horizon_root.add_child(chunk)
	_leaves[key] = chunk
	_swap_dirty = true


func _wait_all_jobs() -> void:
	for key: Vector3i in _jobs:
		WorkerThreadPool.wait_for_task_completion((_jobs[key] as TerrainLodJob).task_id)
	_jobs.clear()


# ---------------------------------------------------------------------------
# Troca de LOD sem buracos nem sobreposição
# ---------------------------------------------------------------------------

## Folhas visíveis que ninguém mais quer ("obsoletas") só saem quando TODAS as folhas
## desejadas que cobrem a mesma área estão prontas; aí a troca acontece num único frame.
## Num quadtree, folhas antigas e novas que se sobrepõem formam sempre uma "estrela"
## (1 antiga -> N novas num split, N antigas -> 1 nova num merge), então basta tratar
## cada folha antiga isoladamente.
func _commit_swaps() -> void:
	_swap_dirty = false

	var obsolete: Array[Vector3i] = []
	var discard: Array[Vector3i] = []
	for key: Vector3i in _leaves:
		if _wanted.has(key):
			continue
		if (_leaves[key] as TerrainLodChunk).is_live:
			obsolete.append(key)
		else:
			discard.append(key)  # pronta mas ainda oculta, e já não é desejada
	for key: Vector3i in discard:
		_free_leaf(key)

	var wanted_keys: Array = _wanted.keys()
	var replacing: Dictionary = {}  # desejadas que ocupam a área de uma folha obsoleta
	for old_key: Vector3i in obsolete:
		var old_rect: Rect2i = (_leaves[old_key] as TerrainLodChunk).tile_rect
		var successors: Array[Vector3i] = []
		var successors_ready: bool = true
		for new_key: Vector3i in wanted_keys:
			if not old_rect.intersects(_leaf_rect(new_key)):
				continue
			successors.append(new_key)
			replacing[new_key] = true
			if not _leaves.has(new_key):
				successors_ready = false
		if not successors_ready:
			continue  # a folha antiga continua na tela até todas as novas ficarem prontas
		for new_key: Vector3i in successors:
			(_leaves[new_key] as TerrainLodChunk).set_live(true)
		_free_leaf(old_key)

	# Folhas desejadas que não substituem nada (ex.: área nova no limite do horizonte).
	for new_key: Vector3i in wanted_keys:
		if replacing.has(new_key):
			continue
		var chunk: TerrainLodChunk = _leaves.get(new_key) as TerrainLodChunk
		if chunk and not chunk.is_live:
			chunk.set_live(true)


func _free_leaf(key: Vector3i) -> void:
	var chunk: TerrainLodChunk = _leaves.get(key) as TerrainLodChunk
	_leaves.erase(key)
	if chunk:
		chunk.queue_free()


func _create_lod_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load(LOD_SHADER_PATH) as Shader
	material.set_shader_parameter("fade_start", horizon_radius * 0.6)
	material.set_shader_parameter("fade_end", horizon_radius * 0.98)
	return material


func _level_tint(level: int) -> Color:
	var tints: Array[Color] = [
		Color(1.0, 0.55, 0.55), Color(1.0, 0.8, 0.5), Color(1.0, 1.0, 0.55),
		Color(0.55, 1.0, 0.6), Color(0.55, 0.85, 1.0), Color(0.75, 0.65, 1.0),
		Color(1.0, 0.6, 1.0)
	]
	return tints[mini(level, tints.size() - 1)]


## Só em builds de debug: avisa se o TerrainSampler divergiu do `_get_column()` da arena
## (por exemplo, se alguém mexer num dos dois e esquecer do outro).
func _debug_check_parity() -> void:
	var arena: Node = get_parent()
	if arena == null or not arena.has_method("_get_column"):
		return
	var mismatches: int = 0
	for sample_index: int in range(48):
		var sample_x: int = sample_index * 7 - 120
		var sample_z: int = sample_index * 13 - 200
		var expected: Vector3 = arena.call("_get_column", sample_x, sample_z)
		var actual: Vector3 = _sampler.get_column(float(sample_x), float(sample_z))
		if not expected.is_equal_approx(actual):
			mismatches += 1
	if mismatches > 0:
		push_warning(
			"TerrainLOD: TerrainSampler diverge de _get_column() em %d/48 amostras. "
			% mismatches + "O horizonte não vai casar com a arena."
		)


# ---------------------------------------------------------------------------
# Grama reativa aos pawns (lógica original, sem mudanças)
# ---------------------------------------------------------------------------

func _update_grass_characters(delta: float) -> void:
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

	if (
		character_index == _sent_character_count
		and _character_positions == _sent_character_positions
	):
		return
	_sent_character_count = character_index
	_sent_character_positions.assign(_character_positions)

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
