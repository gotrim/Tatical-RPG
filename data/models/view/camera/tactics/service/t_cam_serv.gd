class_name TacticsCameraService
extends RefCounted
## Service class for TacticsCamera

var res: TacticsCameraResource
var controls: TacticsControlsResource
var move: TacticsCameraMovementService
var zoom: TacticsCameraZoomService
var rotate: TacticsCameraRotationService
var pan: TacticsCameraPanningService

const DELTA_SMOOTHING: int = 10
const MIN_VEL: float = 0.01


## Initialize the service and its sub-services
func _init(_res: TacticsCameraResource, _controls: TacticsControlsResource) -> void:
	res = _res
	controls = _controls
	move = TacticsCameraMovementService.new(res, controls)
	zoom = TacticsCameraZoomService.new(res)
	rotate = TacticsCameraRotationService.new(res, controls)
	pan = TacticsCameraPanningService.new(res)


## Set up initial camera properties
func setup(camera: TacticsCamera, cam_node: Camera3D) -> void:
	if not controls:
		push_error("TacticsControls precisa de um ControlResource de /data/models/view/control/tactics/")
	if not res:
		push_error("TacticsCamera precisa de um CameraResource (T Cam) de /data/models/view/camera/tactics/")
	else:
		res.target_fov = cam_node.fov
		res.viewport_size = camera.get_viewport().size


## Main processing function for camera behavior
func process(delta: float, camera: TacticsCamera) -> void:
	rotate.check_free_look_activation(delta, camera)
	
	if res.in_free_look:
		rotate.free_look(delta, camera.t_pivot, camera.p_pivot)
	elif not res.is_snapping_to_quad:
		rotate.rotate_camera(delta, camera.t_pivot, camera.p_pivot)
	
	var input_dir: Vector2 = InputCaptureResource.cam_direction
	if (
		input_dir == Vector2.ZERO
		and pan.is_cursor_near_edge(camera)
		and not controls.is_joystick
		and not TacticsCameraResource.mouse_camera_locked
	):
		pan.edge_pan(delta, camera)
	elif input_dir == Vector2.ZERO:
		res.panning_timer = 0.0
		move.stabilize_camera(delta, camera)
	else:
		res.panning_timer = 0.0
	
	if camera.velocity.length() < MIN_VEL:
		camera.velocity = Vector3.ZERO
	
	move.focus_on_target(camera)
	zoom.apply_zoom_smoothing(camera, delta)
