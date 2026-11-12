class_name TacticsCamera
extends CharacterBody3D
## Handles camera movement features
##
## Camera movement methods:[br]
## - [code]rotate_camera[/code]: "Cardinal Points" mode [i](Q,E)[/i][br]
## - [code]move_camera[/code]: "Panning" mode [i](W,A,S,D)[/i][br]
## - [code]free_look[/code]: "Free Look" mode [i](MMB or Right Stick movement)[/i][br]
## - [code]follow[/code]: "Focus" mode [i](programmatically called)[/i][br][br]
## 
## Resource Interface: [TacticsCameraResource] -- Service: [TacticsCameraService]

## Resource containing camera attributes and signals
@export var res: TacticsCameraResource = load("res://data/models/view/camera/tactics/camera.tres")
## Resource containing control settings
@export var controls: TacticsControlsResource = load("res://data/models/view/control/tactics/control.tres")

## Service handling camera operations
static var serv: TacticsCameraService
var camera_travada: bool = false
var ultima_transform: Transform3D

## Node for horizontal rotation
@onready var t_pivot: Node3D = $TwistPivot
## Node for vertical rotation
@onready var p_pivot: Node3D = $TwistPivot/PitchPivot
## Main camera node
@onready var cam_node: Camera3D = $TwistPivot/PitchPivot/Camera3D


func _ready() -> void:
	add_to_group("tactics_cameras")
	serv = TacticsCameraService.new(res, controls) # Initialize camera service
	serv.setup(self, cam_node) # Set up camera service
	res.boundary_center = global_position  # Set the initial boundary center
	# Connect signals
	res.connect("called_rotate_camera", rotate_camera)
	res.connect("called_move_camera", move_camera)


func _process(delta: float) -> void:
	if camera_travada:
		cam_node.global_transform = ultima_transform
		return
	serv.process(delta, self) # Process camera service


func alternar_camera_travada() -> void:
	set_camera_travada(not camera_travada)


func set_camera_travada(value: bool) -> void:
	if camera_travada == value:
		return
	camera_travada = value
	if camera_travada:
		ultima_transform = cam_node.global_transform
		_clear_camera_input()


func _clear_camera_input() -> void:
	InputCaptureResource.cam_direction = Vector2.ZERO
	InputCaptureResource.twist_input = 0.0
	InputCaptureResource.pitch_input = 0.0
	InputCaptureResource.free_look_pressed = false
	InputCaptureResource.left_stick_x = 0.0
	InputCaptureResource.left_stick_y = 0.0
	InputCaptureResource.right_stick_x = 0.0
	InputCaptureResource.right_stick_y = 0.0


## Moves the camera based on input
func move_camera(h: float, v: float, joystick: bool, delta: float) -> void:
	if camera_travada:
		cam_node.global_transform = ultima_transform
		return
	serv.move.move_camera(h, v, joystick, delta, self)


## Rotates the camera
func rotate_camera(delta: float, twist: int = 0) -> void:
	if camera_travada:
		cam_node.global_transform = ultima_transform
		return
	res.is_rotating = true
	serv.rotate.add_angle_to_horiz_rotation(twist)
	serv.rotate.rotate_camera(delta, t_pivot, p_pivot)


## Enables free look mode
func free_look(delta: float) -> void:
	if camera_travada:
		cam_node.global_transform = ultima_transform
		return
	serv.rotate.free_look(delta, t_pivot, p_pivot)


## Zooms the camera
static func zoom_camera(zoom_increment: float) -> void:
	serv.zoom.zoom_camera(zoom_increment)


## Resets camera zoom to default
func reset_cam_zoom() -> void:
	if camera_travada:
		cam_node.global_transform = ultima_transform
		return
	serv.zoom.reset_cam_zoom(cam_node, self)
