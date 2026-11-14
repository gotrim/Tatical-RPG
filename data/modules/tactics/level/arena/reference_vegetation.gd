extends Node3D

const GRASS_MESH: ArrayMesh = preload(
	"res://assets/environment/vegetation/meshes/grass_plane_mesh.res"
)
const TALL_GRASS_MESH: ArrayMesh = preload(
	"res://assets/environment/vegetation/meshes/grassTall_plane_mesh.res"
)
const FLOWER_MESH: ArrayMesh = preload(
	"res://assets/environment/vegetation/meshes/flower.res"
)
const GRASS_MATERIAL: ShaderMaterial = preload(
	"res://assets/environment/vegetation/materials/grass.tres"
)
const TALL_GRASS_MATERIAL: ShaderMaterial = preload(
	"res://assets/environment/vegetation/materials/grass_tall.tres"
)
const FLOWER_MATERIAL: ShaderMaterial = preload(
	"res://assets/environment/vegetation/materials/flower.tres"
)

@export_range(0, 32, 1) var clumps_per_tile: int = 7
@export var world_seed: int = 42


func _ready() -> void:
	_populate.call_deferred()


func _populate() -> void:
	await get_tree().physics_frame
	var tiles: Node = get_parent().get_node_or_null("Tiles")
	if not tiles:
		push_error("ReferenceVegetation requires a Tiles node.")
		return

	var excluded_rids: Array[RID] = []
	for node: Node in get_tree().root.find_children(
		"*", "CharacterBody3D", true, false
	):
		var body := node as CollisionObject3D
		if body:
			excluded_rids.append(body.get_rid())

	var grass_transforms: Array[Transform3D] = []
	var tall_grass_transforms: Array[Transform3D] = []
	var flower_transforms: Array[Transform3D] = []
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for tile: Node in tiles.get_children():
		if not tile is TacticsTile:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(Vector3i(
			roundi(tile.position.x) + world_seed,
			roundi(tile.position.y),
			roundi(tile.position.z)
		))
		for _clump_index: int in range(clumps_per_tile):
			var sample_x: float = rng.randf_range(-0.42, 0.42)
			var sample_z: float = rng.randf_range(-0.42, 0.42)
			var sample_origin: Vector3 = tile.global_position + Vector3(
				sample_x, 50.0, sample_z
			)
			var query := PhysicsRayQueryParameters3D.create(
				sample_origin,
				sample_origin + Vector3.DOWN * 100.0,
				1,
				excluded_rids
			)
			var hit: Dictionary = space_state.intersect_ray(query)
			if hit.is_empty():
				continue

			var world_position: Vector3 = hit.position
			var surface_normal: Vector3 = hit.normal
			var surface_basis := Basis(Quaternion(Vector3.UP, surface_normal))
			var rotation: float = rng.randf_range(0.0, TAU)
			var grass_basis := (
				surface_basis * Basis(Vector3.UP, rotation)
			).scaled(Vector3.ONE * rng.randf_range(1.2, 1.8))
			grass_transforms.append(_to_local_transform(world_position, grass_basis))

			if rng.randf() < 0.04:
				var tall_basis := (
					surface_basis * Basis(Vector3.UP, rotation)
				).scaled(Vector3.ONE * rng.randf_range(1.8, 2.4))
				tall_grass_transforms.append(
					_to_local_transform(world_position, tall_basis)
				)

			if rng.randf() < 0.0035:
				var flower_basis := (
					surface_basis
					* Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				).scaled(Vector3.ONE * rng.randf_range(0.7, 1.3))
				flower_transforms.append(
					_to_local_transform(world_position, flower_basis)
				)

	_add_multimesh("Grass", grass_transforms, GRASS_MESH, GRASS_MATERIAL)
	_add_multimesh(
		"TallGrass", tall_grass_transforms, TALL_GRASS_MESH, TALL_GRASS_MATERIAL
	)
	_add_multimesh("Flowers", flower_transforms, FLOWER_MESH, FLOWER_MATERIAL)


func _to_local_transform(world_position: Vector3, world_basis: Basis) -> Transform3D:
	var local_basis: Basis = global_transform.basis.inverse() * world_basis
	return Transform3D(local_basis, to_local(world_position))


func _add_multimesh(
	instance_name: String,
	transforms: Array[Transform3D],
	mesh: ArrayMesh,
	material: ShaderMaterial
) -> void:
	if transforms.is_empty():
		return
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])

	var instance := MultiMeshInstance3D.new()
	instance.name = instance_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
