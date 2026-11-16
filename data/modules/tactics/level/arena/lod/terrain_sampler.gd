class_name TerrainSampler
extends RefCounted
## Amostrador determinístico do mundo: altura, bioma e profundidade da água.
##
## Reproduz exatamente `_get_column()` do procedural_arena.gd (mesmas seeds, oitavas,
## quantização e regras de bioma), mas sem depender do nó da arena. Assim o horizonte
## pode ser gerado em threads do WorkerThreadPool.
##
## THREAD-SAFETY: cada job usa o seu próprio clone() e, portanto, as suas próprias
## instâncias de FastNoiseLite. Nunca compartilhe uma instância entre threads.

## Precisa ser igual a HEIGHT_INTERVAL do procedural_arena.gd.
const HEIGHT_INTERVAL: float = 0.25
const BIOME_OCEAN: int = 0
const BIOME_DESERT: int = 1
const BIOME_SNOWY_TUNDRA: int = 2
const BIOME_FOREST: int = 3
const BIOME_PLAINS: int = 4
const BIOME_COUNT: int = 5

var world_seed: int = 42
var noise_scale: float = 18.0
var base_height: float = 0.0
var continentality_height: float = 1.5
var erosion_strength: float = 0.75
var minimum_height: float = -1.0
var maximum_height: float = 2.0
var noise_persistence: float = 0.5
var ocean_surface_height: float = 0.0
var shallow_water_depth: float = 0.5
var medium_water_depth: float = 1.0
var deep_water_depth: float = 1.5
## Máximo de amostras por eixo dentro de uma célula agregada (LOD > 0).
## O relevo é suave (escala de ~18 tiles), então 3x3 já representa bem células de 8x8.
var sub_samples: int = 3
## Cores LINEARES por bioma (índice = bioma). O oceano guarda a cor efetiva da água
## translúcida sobre o fundo, para o horizonte parecer com o oceano da arena.
var palette: PackedColorArray = PackedColorArray([
	Color(0.1, 0.3, 0.5), Color(0.7, 0.6, 0.35), Color(0.8, 0.85, 0.9),
	Color(0.18, 0.39, 0.2), Color(0.1, 0.69, 0.21)
])

var _continentality: FastNoiseLite
var _erosion: FastNoiseLite
var _temperature: FastNoiseLite
var _moisture: FastNoiseLite


## Lê os parâmetros exportados do procedural_arena.gd (fonte única da verdade).
static func from_arena(arena: Object) -> TerrainSampler:
	var sampler := TerrainSampler.new()
	sampler.world_seed = int(arena.get("world_seed"))
	sampler.noise_scale = float(arena.get("noise_scale"))
	sampler.base_height = float(arena.get("base_height"))
	sampler.continentality_height = float(arena.get("continentality_height"))
	sampler.erosion_strength = float(arena.get("erosion_strength"))
	sampler.minimum_height = float(arena.get("minimum_height"))
	sampler.maximum_height = float(arena.get("maximum_height"))
	sampler.noise_persistence = float(arena.get("noise_persistence"))
	sampler.ocean_surface_height = float(arena.get("ocean_surface_height"))
	sampler.shallow_water_depth = float(arena.get("shallow_water_depth"))
	sampler.medium_water_depth = float(arena.get("medium_water_depth"))
	sampler.deep_water_depth = float(arena.get("deep_water_depth"))

	var water_opacity: float = float(arena.get("water_opacity"))
	var ocean_color: Color = arena.get("ocean_color")
	var ocean_floor_color: Color = arena.get("ocean_floor_color")
	var desert_color: Color = arena.get("desert_color")
	var snowy_color: Color = arena.get("snowy_tundra_color")
	var forest_color: Color = arena.get("forest_color")
	var plains_color: Color = arena.get("plains_color")
	sampler.palette = PackedColorArray([
		ocean_color.lerp(ocean_floor_color, 1.0 - water_opacity).srgb_to_linear(),
		desert_color.srgb_to_linear(),
		snowy_color.srgb_to_linear(),
		forest_color.srgb_to_linear(),
		plains_color.srgb_to_linear()
	])
	return sampler


## Cópia leve (sem os ruídos) para ser usada por UMA thread.
func clone() -> TerrainSampler:
	var copy := TerrainSampler.new()
	copy.world_seed = world_seed
	copy.noise_scale = noise_scale
	copy.base_height = base_height
	copy.continentality_height = continentality_height
	copy.erosion_strength = erosion_strength
	copy.minimum_height = minimum_height
	copy.maximum_height = maximum_height
	copy.noise_persistence = noise_persistence
	copy.ocean_surface_height = ocean_surface_height
	copy.shallow_water_depth = shallow_water_depth
	copy.medium_water_depth = medium_water_depth
	copy.deep_water_depth = deep_water_depth
	copy.sub_samples = sub_samples
	copy.palette = palette
	return copy


## Assinatura dos parâmetros que afetam os DADOS do cache (cores não entram).
func signature() -> String:
	return "%d|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%f|%d" % [
		world_seed, noise_scale, base_height, continentality_height, erosion_strength,
		minimum_height, maximum_height, noise_persistence, ocean_surface_height,
		shallow_water_depth, medium_water_depth, deep_water_depth, sub_samples
	]


## Equivalente ao `_get_column()` da arena. Retorna (altura, bioma, profundidade da água).
## Com coordenadas inteiras o resultado é idêntico ao da arena.
func get_column(world_x: float, world_z: float) -> Vector3:
	_ensure_noise()
	var continentality: float = _continentality.get_noise_2d(world_x, world_z)
	if continentality < -0.2:
		# Oceano: a altura vira ocean_surface_height, então pula os outros 3 ruídos.
		return Vector3(
			ocean_surface_height, float(BIOME_OCEAN), _get_ocean_depth(continentality)
		)
	var erosion: float = _erosion.get_noise_2d(world_x, world_z)
	var temperature: float = _temperature.get_noise_2d(world_x, world_z)
	var moisture: float = _moisture.get_noise_2d(world_x, world_z)
	var height: float = clampf(
		base_height + continentality * continentality_height - erosion * erosion_strength,
		minimum_height,
		maximum_height
	)
	height = roundf(height / HEIGHT_INTERVAL) * HEIGHT_INTERVAL
	return Vector3(height, float(_get_land_biome(temperature, moisture)), 0.0)


## Amostra uma célula de `step` x `step` tiles cujo primeiro tile é (first_tile_x, first_tile_z).
## Com step == 1 devolve exatamente a coluna do tile. Com step > 1 agrega
## `sub_samples`² amostras: oceano se for maioria (empate = oceano), senão o bioma mais
## frequente e a média das alturas de terra.
func sample_cell(first_tile_x: int, first_tile_z: int, step: int) -> Vector3:
	var per_axis: int = clampi(mini(step, sub_samples), 1, 8)
	var spacing: float = float(step) / float(per_axis)
	var start_x: float = float(first_tile_x) - 0.5 + spacing * 0.5
	var start_z: float = float(first_tile_z) - 0.5 + spacing * 0.5
	var land_count: int = 0
	var ocean_count: int = 0
	var land_height_sum: float = 0.0
	var ocean_depth_sum: float = 0.0
	var votes: PackedInt32Array = PackedInt32Array([0, 0, 0, 0, 0])

	for sub_z: int in range(per_axis):
		for sub_x: int in range(per_axis):
			var column: Vector3 = get_column(
				start_x + float(sub_x) * spacing, start_z + float(sub_z) * spacing
			)
			var biome: int = int(column.y)
			if biome == BIOME_OCEAN:
				ocean_count += 1
				ocean_depth_sum += column.z
			else:
				land_count += 1
				land_height_sum += column.x
				votes[biome] += 1

	if ocean_count >= land_count:
		return Vector3(
			ocean_surface_height,
			float(BIOME_OCEAN),
			ocean_depth_sum / float(ocean_count)
		)
	var best_biome: int = BIOME_DESERT
	for biome_id: int in range(BIOME_DESERT, BIOME_COUNT):
		if votes[biome_id] > votes[best_biome]:
			best_biome = biome_id
	return Vector3(land_height_sum / float(land_count), float(best_biome), 0.0)


## Monta o bloco (com halo) do nó de LOD (level, cx, cz).
## `origin` é o tile inicial do grid do LOD (primeiro tile da arena), que alinha os
## chunks do horizonte com os chunks da arena.
func build_cell_block(
	level: int, cx: int, cz: int, origin: Vector2i, cells: int
) -> TerrainCellBlock:
	var block := TerrainCellBlock.new()
	block.setup(level, cx, cz, cells)
	var step: int = 1 << level
	var size_tiles: int = cells * step
	var first_tile_x: int = origin.x + cx * size_tiles
	var first_tile_z: int = origin.y + cz * size_tiles
	for cell_z: int in range(-1, cells + 1):
		for cell_x: int in range(-1, cells + 1):
			var column: Vector3 = sample_cell(
				first_tile_x + cell_x * step, first_tile_z + cell_z * step, step
			)
			var index: int = block.index_of(cell_x, cell_z)
			block.heights[index] = column.x
			block.biomes[index] = int(column.y)
			block.depths[index] = column.z
	return block


func _ensure_noise() -> void:
	if _continentality != null:
		return
	_continentality = _create_noise(0, 4)
	_erosion = _create_noise(100, 3)
	_temperature = _create_noise(200, 2)
	_moisture = _create_noise(300, 2)


func _create_noise(seed_offset: int, octave_count: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = world_seed + seed_offset
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.frequency = 1.0 / maxf(noise_scale, 0.001)
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octave_count
	noise.fractal_gain = noise_persistence
	noise.fractal_lacunarity = 2.0
	return noise


func _get_ocean_depth(continentality: float) -> float:
	if continentality < -0.65:
		return deep_water_depth
	if continentality < -0.4:
		return medium_water_depth
	return shallow_water_depth


## Mesma ordem de decisão do `_get_biome()` da arena (para continentality >= -0.2).
func _get_land_biome(temperature: float, moisture: float) -> int:
	if temperature > 0.3 and moisture < -0.2:
		return BIOME_DESERT
	if temperature < -0.3:
		return BIOME_SNOWY_TUNDRA
	if moisture > 0.2:
		return BIOME_FOREST
	return BIOME_PLAINS
