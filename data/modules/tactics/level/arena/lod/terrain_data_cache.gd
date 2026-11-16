class_name TerrainDataCache
extends RefCounted
## Cache dos blocos de células do LOD: memória (LRU) + disco opcional.
##
## Seguro para várias threads do WorkerThreadPool: o dicionário só é tocado com o mutex
## travado, e o cálculo pesado (ruído) acontece FORA do lock. Dois jobs podem calcular o
## mesmo bloco ao mesmo tempo (raro); o resultado é idêntico, então tanto faz quem grava.
##
## A chave é Vector3i(level, cx, cz). Cada bloco ocupa ~3 KB, então 4096 blocos ≈ 12 MB.

const CACHE_ROOT: String = "user://terrain_lod_cache"
const EVICT_BATCH: int = 64

var hits: int = 0
var misses: int = 0
var disk_hits: int = 0

var _mutex: Mutex = Mutex.new()
var _blocks: Dictionary = {}
var _max_blocks: int = 4096
var _origin: Vector2i = Vector2i.ZERO
var _cells: int = 16
var _use_disk: bool = false
var _disk_dir: String = ""


## Chamar na thread principal, antes de qualquer job.
## No disco, cada configuração (seed, ruído, origem, células) usa a sua própria pasta,
## então mudar qualquer parâmetro nunca reaproveita dados antigos.
func configure(
	sampler: TerrainSampler, origin: Vector2i, cells: int, max_blocks: int, use_disk: bool
) -> void:
	_origin = origin
	_cells = cells
	_max_blocks = maxi(max_blocks, 16)
	_use_disk = use_disk
	if _use_disk:
		var folder: String = (
			"%s|%d|%d|%d" % [sampler.signature(), origin.x, origin.y, cells]
		).md5_text()
		_disk_dir = "%s/%s" % [CACHE_ROOT, folder]
		if DirAccess.make_dir_recursive_absolute(_disk_dir) != OK:
			push_warning("TerrainDataCache: sem acesso a %s; cache em disco desativado." % _disk_dir)
			_use_disk = false


## Retorna o bloco do nó `key` (memória -> disco -> cálculo). Chamado dentro do worker.
func fetch(key: Vector3i, sampler: TerrainSampler) -> TerrainCellBlock:
	var block: TerrainCellBlock = _get_cached(key)
	if block != null:
		return block
	if _use_disk:
		block = _read_disk(key)
		if block != null:
			_mutex.lock()
			disk_hits += 1
			_mutex.unlock()
	if block == null:
		block = sampler.build_cell_block(key.x, key.y, key.z, _origin, _cells)
		if _use_disk:
			_write_disk(key, block)
	_put(key, block)
	return block


func size() -> int:
	_mutex.lock()
	var count: int = _blocks.size()
	_mutex.unlock()
	return count


func clear() -> void:
	_mutex.lock()
	_blocks.clear()
	_mutex.unlock()


func _get_cached(key: Vector3i) -> TerrainCellBlock:
	_mutex.lock()
	var block: TerrainCellBlock = _blocks.get(key) as TerrainCellBlock
	if block != null:
		# Move para o fim: o Dictionary preserva a ordem de inserção, e o início é o mais antigo.
		_blocks.erase(key)
		_blocks[key] = block
		hits += 1
	else:
		misses += 1
	_mutex.unlock()
	return block


func _put(key: Vector3i, block: TerrainCellBlock) -> void:
	_mutex.lock()
	_blocks[key] = block
	if _blocks.size() > _max_blocks + EVICT_BATCH:
		var keys: Array = _blocks.keys()
		for index: int in range(EVICT_BATCH):
			_blocks.erase(keys[index])
	_mutex.unlock()


func _disk_path(key: Vector3i) -> String:
	return "%s/L%d_%d_%d.bin" % [_disk_dir, key.x, key.y, key.z]


func _read_disk(key: Vector3i) -> TerrainCellBlock:
	var path: String = _disk_path(key)
	if not FileAccess.file_exists(path):
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return TerrainCellBlock.read_from(file, key.x, key.y, key.z, _cells)


func _write_disk(key: Vector3i, block: TerrainCellBlock) -> void:
	var file: FileAccess = FileAccess.open(_disk_path(key), FileAccess.WRITE)
	if file == null:
		return
	block.write_to(file)
