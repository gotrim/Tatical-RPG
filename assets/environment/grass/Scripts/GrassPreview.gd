extends Control

const TILE_COLOR := Color(0.48, 0.64, 0.32, 1.0)

@onready var grass: MultiMeshInstance3D = $ViewportContainer/SubViewport/Floor/Grass


func _ready() -> void:
	var multimesh: MultiMesh = grass.multimesh
	var rng := RandomNumberGenerator.new()
	rng.seed = 681248

	for index in range(multimesh.instance_count):
		var width_scale := rng.randf_range(0.8, 1.2)
		var height_scale := rng.randf_range(0.8, 1.2)
		var blade_transform := Transform3D(
			Basis.IDENTITY.scaled(Vector3(width_scale, height_scale, width_scale)),
			Vector3(
				rng.randf_range(-12.4, 12.4),
				0.15,
				rng.randf_range(-12.4, 12.4)
			)
		)
		multimesh.set_instance_transform(index, blade_transform)
		multimesh.set_instance_color(index, TILE_COLOR)
