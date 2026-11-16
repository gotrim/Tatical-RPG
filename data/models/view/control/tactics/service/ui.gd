class_name TacticsUIService
extends RefCounted
## Service class for managing UI-related functionalities in the Tactics game.

## Reference to the TacticsControlsResource.
var controls: TacticsControlsResource
## Último layout de hints aplicado (-1 = ainda não aplicado, 0 = PC, 1 = controle).
var _applied_hints_layout: int = -1


## Initializes the TacticsUIService with the necessary controls resource.
func _init(_controls: TacticsControlsResource) -> void:
	controls = _controls


## Updates the controller hints based on the current input device.
func update_controller_hints(ctrl: TacticsControls) -> void:
	# Só mexe no nó quando o dispositivo muda (antes: busca por nome + atribuição a cada physics frame).
	var hints_layout: int = 1 if controls.is_joystick else 0
	if hints_layout == _applied_hints_layout:
		return
	_applied_hints_layout = hints_layout
	if controls.is_joystick:
		ctrl.get_node("%ControllerHints").texture = ctrl.layout_xbox # Set Xbox layout if using joystick
	else:
		ctrl.get_node("%ControllerHints").texture = ctrl.layout_pc # Set PC layout otherwise


## Sets the visibility of the actions menu and updates action button states.
func set_actions_menu_visibility(v: bool, p: TacticsPawn, ctrl: TacticsControls) -> void:
	if not ctrl.get_node("HBox/Actions").visible:
		ctrl.get_node("HBox/Actions/Move").grab_focus() # Focus on Move action if menu wasn't visible
	
	ctrl.get_node("HBox/Actions").visible = v and p.can_act() # Show menu if pawn can act
	
	if not p:
		return # Exit if no pawn is provided
	
	# Update action button states based on pawn's capabilities
	ctrl.get_node("HBox/Actions/Move").disabled = not p.res.can_move
	ctrl.get_node("HBox/Actions/Attack").disabled = not p.res.can_attack
