class_name TacticsPawnMovementService
extends RefCounted
## Service class for handling pawn movement in the tactics game

const STANDING_HEIGHT_ADJUSTMENT_SPEED: float = 3.0


## Rotates the pawn to face the given direction
##
## @param pawn: The TacticsPawn to rotate
## @param dir: The direction vector to face
func look_at_direction(pawn: TacticsPawn, dir: Vector3) -> void:
	var _fixed_dir: Vector3 = dir * (Vector3(1, 0, 0) if abs(dir.x) > abs(dir.z) else Vector3(0, 0, 1))
	var _angle: float = Vector3.FORWARD.signed_angle_to(_fixed_dir.normalized(), Vector3.UP) + PI
	var _new_rot: Vector3 = Vector3.UP * _angle
	pawn.set_rotation(_new_rot)


## Moves the pawn along its pathfinding stack
##
## @param pawn: The TacticsPawn to move
## @param delta: Time elapsed since the last frame
func move_along_path(pawn: TacticsPawn, delta: float) -> void:
	var current_tile: TacticsTile = _update_water_state(pawn)
	if pawn.res.pathfinding_tilestack.is_empty() or not pawn.res.can_move:
		_adjust_standing_height(pawn, current_tile, delta)
		return
	
	start_movement(pawn)
	
	if pawn.res.move_direction.length() > 0.5:
		perform_movement(pawn, delta)
	else:
		_adjust_standing_height(pawn, current_tile, delta)

	var _first_tile_in_stack: Vector3 = pawn.res.pathfinding_tilestack.front()
	var _distance_to_target: float = pawn.global_position.distance_to(_first_tile_in_stack)
	if absf(pawn.res.move_direction.y) <= TacticsPawnResource.MIN_HEIGHT_TO_JUMP:
		_distance_to_target = CalcVector.distance_without_y(
			_first_tile_in_stack, pawn.global_position
		)
	if _distance_to_target >= 0.15:
		return
	
	pawn.res.pathfinding_tilestack.pop_front()
	reset_movement_state(pawn)
	check_movement_completion(pawn)


## Initiates the pawn's movement
##
## @param pawn: The TacticsPawn to start moving
func start_movement(pawn: TacticsPawn) -> void:
	pawn.res.set_moving(true)
	if pawn.res.move_direction == Vector3.ZERO:
		pawn.res.move_direction = pawn.res.pathfinding_tilestack.front() - pawn.global_position


## Performs the actual movement of the pawn
##
## @param pawn: The TacticsPawn to move
## @param delta: Time elapsed since the last frame
func perform_movement(pawn: TacticsPawn, delta: float) -> void:
	look_at_direction(pawn, pawn.res.move_direction)
	var _p_velocity: Vector3 = calculate_velocity(pawn, delta)
	var _curr_speed: float = calculate_speed(pawn)
	
	pawn.set_velocity(_p_velocity * _curr_speed)
	pawn.set_up_direction(Vector3.UP)
	pawn.move_and_slide()
	var current_tile: TacticsTile = _update_water_state(pawn)
	_adjust_standing_height(pawn, current_tile, delta)


## Calculates the velocity vector for the pawn's movement
##
## @param pawn: The TacticsPawn to calculate velocity for
## @param delta: Time elapsed since the last frame
## @return: The calculated velocity vector
func calculate_velocity(pawn: TacticsPawn, delta: float) -> Vector3:
	var _p_velocity: Vector3 = pawn.res.move_direction.normalized()
	
	if pawn.res.move_direction.y < -TacticsPawnResource.MIN_HEIGHT_TO_JUMP:
		var _first_tile_in_stack : Vector3 = pawn.res.pathfinding_tilestack.front()
		if CalcVector.distance_without_y(_first_tile_in_stack, pawn.global_position) <= 0.2:
			pawn.res.gravity += Vector3.DOWN * delta * TacticsPawnResource.GRAVITY_STRENGTH
			_p_velocity = (pawn.res.pathfinding_tilestack.front() - pawn.global_position).normalized() + pawn.res.gravity
		else:
			_p_velocity = CalcVector.remove_y(pawn.res.move_direction).normalized()
	
	return _p_velocity


## Calculates the current speed of the pawn
##
## @param pawn: The TacticsPawn to calculate speed for
## @return: The calculated speed
func calculate_speed(pawn: TacticsPawn) -> float:
	var _curr_speed: float = float(pawn.res.walk_speed)
	
	if pawn.res.move_direction.y > TacticsPawnResource.MIN_HEIGHT_TO_JUMP:
		_curr_speed = clamp(abs(pawn.res.move_direction.y) * 2.3, 3, INF)
		pawn.res.is_jumping = true
	
	if pawn.res.is_swimming:
		_curr_speed *= TacticsPawnResource.SWIM_SPEED_MULTIPLIER

	return _curr_speed


func _update_water_state(pawn: TacticsPawn) -> TacticsTile:
	var tile_raycast: RayCast3D = pawn.get_node("Tile") as RayCast3D
	tile_raycast.force_raycast_update()
	var current_tile: TacticsTile = pawn.get_tile()
	pawn.res.is_swimming = (
		current_tile != null
		and float(current_tile.get_meta("water_depth", 0.0)) > 0.0
		and pawn.global_position.y < current_tile.global_position.y
	)
	return current_tile


func _adjust_standing_height(
	pawn: TacticsPawn, current_tile: TacticsTile, delta: float
) -> void:
	if not current_tile:
		return
	if absf(pawn.res.move_direction.y) > TacticsPawnResource.MIN_HEIGHT_TO_JUMP:
		return
	pawn.global_position.y = move_toward(
		pawn.global_position.y,
		current_tile.get_standing_position().y,
		STANDING_HEIGHT_ADJUSTMENT_SPEED * delta
	)


## Resets the movement state of the pawn
##
## @param pawn: The TacticsPawn to reset
func reset_movement_state(pawn: TacticsPawn) -> void:
	pawn.res.move_direction = Vector3.ZERO
	pawn.res.is_jumping = false
	pawn.res.gravity = Vector3.ZERO
	pawn.res.can_move = pawn.res.pathfinding_tilestack.size() > 0


## Checks if the pawn has completed its movement and adjusts accordingly
##
## @param pawn: The TacticsPawn to check
func check_movement_completion(pawn: TacticsPawn) -> void:
	if not pawn.res.can_move:
		pawn.res.set_moving(false)
		pawn.character.adjust_to_center(pawn)
