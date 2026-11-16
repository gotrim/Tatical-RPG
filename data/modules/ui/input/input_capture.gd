class_name InputCapture
extends Node3D

@export var res: InputCaptureResource = preload("res://data/models/view/control/input/capture/capture.tres")
var serv: InputCaptureService

var debug_ray_mesh: MeshInstance3D
var last_hit_position: Vector3 = Vector3.ZERO
var _tactics_camera: TacticsCamera


func _ready() -> void:
	serv = InputCaptureService.new(res)
	debug_ray_mesh = serv.setup_debug_ray(self)


func _input(event: InputEvent) -> void:
	# Em cache: _input roda a cada evento (movimento do mouse dispara dezenas por segundo).
	if not is_instance_valid(_tactics_camera):
		_tactics_camera = get_tree().get_first_node_in_group(
			"tactics_cameras"
		) as TacticsCamera
	if _tactics_camera and _tactics_camera.camera_travada:
		return
	serv.process_input(event)


func _process(_delta: float) -> void:
	# Continuous ray casting for debugging: só serve para desenhar o raio de depuração.
	# Quem precisa da posição do mouse chama project_mouse_position() por conta própria
	# (ver TacticsControlsInputService.get_3d_canvas_mouse_position), então fora do modo
	# visual_debug este raycast por frame era trabalho descartado.
	if DebugLog.visual_debug:
		project_mouse_position(1, false)  # Adjust collision mask as needed


func _unhandled_input(event: InputEvent) -> void:
	serv.handle_input(event)


func project_mouse_position(collision_mask: int, is_joystick: bool) -> Object:
	return serv.project_mouse_position(collision_mask, is_joystick, self)
