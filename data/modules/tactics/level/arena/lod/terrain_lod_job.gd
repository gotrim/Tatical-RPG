class_name TerrainLodJob
extends RefCounted
## Tarefa de construção de UM chunk de LOD, executada no WorkerThreadPool.
##
## Contrato de threads: a thread principal preenche os campos de entrada ANTES de chamar
## WorkerThreadPool.add_task(job.run) e só lê os campos de saída DEPOIS de
## wait_for_task_completion(). Nesse intervalo, run() é o único que toca no job.
## O worker não usa a árvore de cena nem cria Resources de renderização.

# --- entrada (definida na thread principal) ---
var key: Vector3i = Vector3i.ZERO  # (level, cx, cz)
var task_id: int = -1
var sampler: TerrainSampler
var cache: TerrainDataCache
var origin: Vector2i = Vector2i.ZERO
var exclude: Rect2i = Rect2i()
var skirt_depth: float = 3.0
var tint: Color = Color.WHITE

# --- saída (preenchida por run()) ---
var succeeded: bool = false
var vertices: PackedVector3Array = PackedVector3Array()
var normals: PackedVector3Array = PackedVector3Array()
var colors: PackedColorArray = PackedColorArray()


func run() -> void:
	var block: TerrainCellBlock = cache.fetch(key, sampler)
	if block == null:
		return
	var result: Dictionary = TerrainLodMeshBuilder.build(
		block, origin, exclude, sampler, skirt_depth, tint
	)
	if not result.is_empty():
		vertices = result["vertices"]
		normals = result["normals"]
		colors = result["colors"]
	succeeded = true
