class_name TerrainLodMeshBuilder
extends RefCounted
## Converte um TerrainCellBlock em arrays de malha (vértices/normais/cores).
##
## Só manipula dados (Packed*Array): NÃO cria ArrayMesh nem toca na árvore de cena, então
## é seguro rodar em worker threads. O ArrayMesh é montado na thread principal.
##
## Estilo igual ao do arena: sombreamento plano (1 normal por triângulo), mesma diagonal
## (canto 1 -> canto 3) e mesma regra de altura de vértice (vizinho oceano => nível do mar,
## senão média das células vizinhas). Em LOD 0 cada célula é um tile.
##
## Saias (skirts): faixas verticais nas bordas do chunk e junto à área excluída (arena).
## Elas escondem as frestas entre chunks de níveis diferentes. Usam normal para cima para
## manter a mesma iluminação/cor do terreno.


## Retorna {"vertices", "normals", "colors"} ou um Dictionary vazio se não há nada a desenhar.
## Coordenadas dos vértices são locais ao canto do chunk: x/z em [0, cells * step].
static func build(
	block: TerrainCellBlock,
	origin: Vector2i,
	exclude: Rect2i,
	sampler: TerrainSampler,
	skirt_depth: float,
	tint: Color
) -> Dictionary:
	var cells: int = block.cells
	var step: int = 1 << block.level
	var step_f: float = float(step)
	var first_tile_x: int = origin.x + block.cx * cells * step
	var first_tile_z: int = origin.y + block.cz * cells * step
	var vertex_count: int = cells + 1

	# 1) Altura dos (cells+1)² vértices.
	var vertex_heights := PackedFloat32Array()
	vertex_heights.resize(vertex_count * vertex_count)
	for vz: int in range(vertex_count):
		for vx: int in range(vertex_count):
			var height_sum: float = 0.0
			var touches_ocean: bool = false
			for corner: int in range(4):
				var cell_index: int = block.index_of(
					vx - 1 + (corner & 1), vz - 1 + (corner >> 1)
				)
				if block.biomes[cell_index] == TerrainSampler.BIOME_OCEAN:
					touches_ocean = true
					break
				height_sum += block.heights[cell_index]
			vertex_heights[vz * vertex_count + vx] = (
				sampler.ocean_surface_height if touches_ocean else height_sum * 0.25
			)

	# 2) Triângulos do topo + saias.
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for cell_z: int in range(cells):
		for cell_x: int in range(cells):
			var tile_x: int = first_tile_x + cell_x * step
			var tile_z: int = first_tile_z + cell_z * step
			if _is_excluded(exclude, tile_x, tile_z, step):
				continue
			var x0: float = float(cell_x) * step_f
			var z0: float = float(cell_z) * step_f
			var x1: float = x0 + step_f
			var z1: float = z0 + step_f
			# Cantos como no arena: 0 = (x-, z-), 1 = (x+, z-), 2 = (x+, z+), 3 = (x-, z+).
			var p0 := Vector3(x0, vertex_heights[cell_z * vertex_count + cell_x], z0)
			var p1 := Vector3(x1, vertex_heights[cell_z * vertex_count + cell_x + 1], z0)
			var p2 := Vector3(x1, vertex_heights[(cell_z + 1) * vertex_count + cell_x + 1], z1)
			var p3 := Vector3(x0, vertex_heights[(cell_z + 1) * vertex_count + cell_x], z1)

			var cell_index: int = block.index_of(cell_x, cell_z)
			var color: Color = _cell_color(
				sampler, block.biomes[cell_index], block.depths[cell_index]
			) * tint
			_add_top_triangle(vertices, normals, colors, p0, p1, p3, color)
			_add_top_triangle(vertices, normals, colors, p1, p2, p3, color)

			if skirt_depth <= 0.0:
				continue
			if cell_x == 0 or _is_excluded(exclude, tile_x - step, tile_z, step):
				_add_skirt(vertices, normals, colors, p3, p0, Vector3.LEFT, skirt_depth, color)
			if cell_x == cells - 1 or _is_excluded(exclude, tile_x + step, tile_z, step):
				_add_skirt(vertices, normals, colors, p1, p2, Vector3.RIGHT, skirt_depth, color)
			if cell_z == 0 or _is_excluded(exclude, tile_x, tile_z - step, step):
				_add_skirt(vertices, normals, colors, p0, p1, Vector3.FORWARD, skirt_depth, color)
			if cell_z == cells - 1 or _is_excluded(exclude, tile_x, tile_z + step, step):
				_add_skirt(vertices, normals, colors, p2, p3, Vector3.BACK, skirt_depth, color)

	if vertices.is_empty():
		return {}
	return {"vertices": vertices, "normals": normals, "colors": colors}


## A célula é pulada se estiver INTEIRA dentro do retângulo excluído (a arena detalhada).
## O quadtree do manager garante que só nós de LOD 0 tocam a arena, então aqui step == 1.
static func _is_excluded(exclude: Rect2i, tile_x: int, tile_z: int, step: int) -> bool:
	return exclude.encloses(Rect2i(tile_x, tile_z, step, step))


static func _cell_color(sampler: TerrainSampler, biome: int, depth: float) -> Color:
	var color: Color = sampler.palette[biome]
	if biome == TerrainSampler.BIOME_OCEAN:
		var depth_ratio: float = clampf(depth / maxf(sampler.deep_water_depth, 0.001), 0.0, 1.0)
		color = color.darkened(depth_ratio * 0.4)
	return color


## (a, b, c) já está na ordem que o Godot trata como face frontal (horário visto de cima),
## igual ao `_add_chunk_top` da arena. A normal é calculada do próprio triângulo.
static func _add_top_triangle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	color: Color
) -> void:
	var normal: Vector3 = (c - a).cross(b - a).normalized()
	_push(vertices, normals, colors, a, normal, color)
	_push(vertices, normals, colors, b, normal, color)
	_push(vertices, normals, colors, c, normal, color)


static func _add_skirt(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	top_start: Vector3,
	top_end: Vector3,
	outward: Vector3,
	depth: float,
	color: Color
) -> void:
	var bottom_start: Vector3 = top_start + Vector3.DOWN * depth
	var bottom_end: Vector3 = top_end + Vector3.DOWN * depth
	_add_skirt_triangle(vertices, normals, colors, top_start, top_end, bottom_end, outward, color)
	_add_skirt_triangle(vertices, normals, colors, top_start, bottom_end, bottom_start, outward, color)


## Mesma regra do `_add_chunk_triangle` da arena: a face frontal tem (b-a)x(c-a) oposto
## à direção "para fora". A normal gravada é para cima (continuidade de iluminação).
static func _add_skirt_triangle(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	a: Vector3,
	b: Vector3,
	c: Vector3,
	outward: Vector3,
	color: Color
) -> void:
	if (b - a).cross(c - a).dot(outward) > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	_push(vertices, normals, colors, a, Vector3.UP, color)
	_push(vertices, normals, colors, b, Vector3.UP, color)
	_push(vertices, normals, colors, c, Vector3.UP, color)


static func _push(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	colors: PackedColorArray,
	vertex: Vector3,
	normal: Vector3,
	color: Color
) -> void:
	vertices.append(vertex)
	normals.append(normal)
	colors.append(color)
