class_name TacticsPawnHudService
extends RefCounted
## Service class for managing the HUD (Heads-Up Display) of a pawn in the tactics game


## Tint used when the pawn can still act / can no longer act
const TINT_CAN_ACT: Color = Color(1, 1, 1)
const TINT_CANNOT_ACT: Color = Color(0.5, 0.5, 0.5)

## Cache: o serviço é criado por pawn, mas a chave por instância evita surpresas se for reaproveitado
var _cached_pawn_id: int = 0
var _health_label: Label3D
var _shown_curr_health: int = -1
var _shown_max_health: int = -1


## Updates the health display of the pawn's character UI
##
## O texto só é reatribuído quando a vida muda: Label3D refaz o layout do texto a cada
## atribuição, e isto rodava para todo pawn a cada tick de física.
##
## @param pawn: The TacticsPawn whose health display needs to be updated
func update_character_health(pawn: TacticsPawn) -> void:
	if _cached_pawn_id != pawn.get_instance_id() or not is_instance_valid(_health_label):
		_cached_pawn_id = pawn.get_instance_id()
		_health_label = pawn.get_node("Character/CharacterUI/HealthLabel")
		_shown_curr_health = -1
		_shown_max_health = -1
	
	var _curr_health: int = pawn.stats.curr_health
	var _max_health: int = pawn.stats.max_health
	if _curr_health == _shown_curr_health and _max_health == _shown_max_health:
		return
	
	_shown_curr_health = _curr_health
	_shown_max_health = _max_health
	_health_label.text = str(_curr_health) + "/" + str(_max_health)


## Applies a tint to the pawn's sprite when it's unable to act
##
## @param pawn: The TacticsPawn to apply the tint to
func tint_when_unable_to_act(pawn: TacticsPawn) -> void:
	var _char_node: TacticsPawnSprite = pawn.character
	var _tint: Color = TINT_CAN_ACT if pawn.can_act() else TINT_CANNOT_ACT
	# Atribuir modulate força o Sprite3D a se redesenhar; só atribui se mudou.
	if _char_node.modulate != _tint:
		_char_node.modulate = _tint
