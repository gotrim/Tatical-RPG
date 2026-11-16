class_name TerrainCellBlock
extends RefCounted
## Dados agregados de um nó do LOD: grade de `cells` x `cells` células (cada célula cobre
## step x step tiles) mais 1 célula de borda ("halo") em cada lado.
##
## O halo deixa o bloco autossuficiente: os vértices na borda do chunk usam exatamente as
## mesmas alturas do chunk vizinho de mesmo nível (sem rachaduras) e nenhum job precisa
## esperar por outro.

const FILE_MAGIC: int = 0x544C4F44
const FILE_VERSION: int = 1
const HEADER_BYTES: int = 12

var level: int = 0
var cx: int = 0
var cz: int = 0
var cells: int = 16
## Altura por célula (já quantizada como no arena), incluindo o halo.
var heights: PackedFloat32Array = PackedFloat32Array()
## Bioma por célula (0 = oceano, ver TerrainSampler.BIOME_*).
var biomes: PackedByteArray = PackedByteArray()
## Profundidade da água por célula (só faz sentido onde bioma == oceano).
var depths: PackedFloat32Array = PackedFloat32Array()


func setup(p_level: int, p_cx: int, p_cz: int, p_cells: int) -> void:
	level = p_level
	cx = p_cx
	cz = p_cz
	cells = p_cells
	var count: int = (cells + 2) * (cells + 2)
	heights.resize(count)
	biomes.resize(count)
	depths.resize(count)


## Índice da célula (cell_x, cell_z); aceita -1 e `cells` (halo).
func index_of(cell_x: int, cell_z: int) -> int:
	return (cell_z + 1) * (cells + 2) + (cell_x + 1)


static func expected_file_size(p_cells: int) -> int:
	return HEADER_BYTES + (p_cells + 2) * (p_cells + 2) * 9


func write_to(file: FileAccess) -> void:
	file.store_32(FILE_MAGIC)
	file.store_32(FILE_VERSION)
	file.store_32(cells)
	file.store_buffer(heights.to_byte_array())
	file.store_buffer(biomes)
	file.store_buffer(depths.to_byte_array())


## Retorna null se o arquivo estiver corrompido ou for de outra configuração.
static func read_from(
	file: FileAccess, p_level: int, p_cx: int, p_cz: int, p_cells: int
) -> TerrainCellBlock:
	if file.get_length() != expected_file_size(p_cells):
		return null
	if file.get_32() != FILE_MAGIC:
		return null
	if file.get_32() != FILE_VERSION:
		return null
	if file.get_32() != p_cells:
		return null
	var count: int = (p_cells + 2) * (p_cells + 2)
	var block := TerrainCellBlock.new()
	block.setup(p_level, p_cx, p_cz, p_cells)
	block.heights = file.get_buffer(count * 4).to_float32_array()
	block.biomes = file.get_buffer(count)
	block.depths = file.get_buffer(count * 4).to_float32_array()
	return block
