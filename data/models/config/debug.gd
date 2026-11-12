class_name DebugLog
extends RefCounted
## Static class for handling debug logging functionality.
##
## This class provides methods to enable/disable debugging and log various game states
## without spamming the console. It uses color-coded rich text for better readability.

## Enables or disables debug mode.
static var debug_enabled: bool = true
static var visual_debug: bool = false # mouse cursor raycast, etc -- false by default (because visually invasive)

## Dictionary of color codes for different debug message types.
const DEBUG_COLORS: Dictionary = {
	"magenta": "FF00FF",
	"yellow": "FFFF00",
	"green": "00FF00",
	"cyan": "00FFFF",
	"purple": "800080",
	"orange": "FFA500",
	"red": "FF0000"
}

## Dictionary to store temporary and old values for various debug states.
static var debug_dict: Dictionary = {
	"participant_turn": {
		"tmp": null, "old": null,
		"message": "[ --- Atualização de turno --- ] 👾 Participante ativo: ",
		"color": "magenta",
		"type": "bool",
		"bool_strings": ["Jogador", "Oponente"]
		},
	"turn_stage": {
		"tmp": null, "old": null,
		"message": "🎮 -> Etapa do turno: ",
		"color": "yellow",
		"type": "concat1"
		},
	"pawn": {
		"tmp": null, "old": null,
		"message": "[ 👾 ] Novo personagem selecionado: ",
		"color": "green",
		"type": "concat1"
		},
	"cam": {
		"tmp": null, "old": null,
		"message": "[ 📷 ] Câmera direcionada para: ",
		"color": "cyan",
		"type": "concat1"
		},
	"player_can_act": {
		"tmp": null, "old": null,
		"message": "[ 👾 ] O jogador pode agir? ",
		"color": "purple",
		"type": "bool",
		"bool_strings": ["-> SIM", "-x NÃO"]
		},
	"nearest_target_found": {
		"tmp": null, "old": null, "type": "concat1",
		"string": "[ 🏒 ] Destino encontrado: ",
		"color": "orange"
		},
	"nearest_target": {
		"tmp": null, "old": null, "type": "concat1",
		"string": "[ 🏒 ] Movimento cancelado. Nenhum alvo próximo encontrado para ",
		"color": "red"
		},
	"quad_snap": {
		"tmp": null, "old": null,
		"message": "[ 📷 ] Ajuste cardinal (is_snapping_to_quad): ",
		"color": "cyan",
		"type": "bool",
		"bool_strings": ["Ativado (VERDADEIRO)", "Desativado (FALSO)"]
		},
	"cam_rotating": {
		"tmp": null, "old": null,
		"message": "[ 📷 ] Câmera em rotação (is_rotating): ",
		"color": "cyan",
		"type": "bool",
		"bool_strings": ["Ativado (VERDADEIRO)", "Desativado (FALSO)"]
		},
	"in_free_look": {
		"tmp": null, "old": null,
		"message": "[ 📷 ] Visão livre (in_free_look): ",
		"color": "cyan",
		"type": "bool",
		"bool_strings": ["Ativado (VERDADEIRO)", "Desativado (FALSO)"]
		},
	"joystick_free_look": {
		"tmp": null, "old": null,
		"message": "[ 🕹️ ] Visão livre pelo analógico ",
		"color": "cyan",
		"type": "bool",
		"bool_strings": ["Ativado (VERDADEIRO)", "Desativado (FALSO)"]
		},
}


## Enables or disables debug logging.
##
## @param enabled: Boolean value to enable (true) or disable (false) debug logging.
static func set_debug_enabled(enabled: bool) -> void:
	debug_enabled = enabled


## Logs debug messages without spamming the console.
##
## This function checks if the debug state has changed before logging,
## preventing repeated messages for unchanged states.
##
## @param debug_name: The name of the debug state to update.
## @param argument: The new value of the debug state.
static func debug_nospam(debug_name: String, argument: Variant) -> void:
	if not debug_enabled:
		return
	
	if debug_name in debug_dict:
		var _d: Dictionary = debug_dict[debug_name]
		
		match _d.type:
			"bool":
				debug_log_bool(_d, argument)
			"concat1":
				debug_log_concat1(_d, argument)


static func debug_log_bool(dict_entry: Dictionary, argument: Variant) -> void:
	dict_entry.tmp = argument
	
	if dict_entry.old != dict_entry.tmp:
		var open_color: String = "[color=#" + DEBUG_COLORS[dict_entry.color] + "]"
		var close_color: String = "[/color]"
		
		var parse_bool: String = dict_entry.bool_strings[0] if argument else dict_entry.bool_strings[1]
		
		if dict_entry.has('message'): # todo: got a crash 'cause no dict_entry.message
			print_rich(open_color, dict_entry.message, "[i][u]", parse_bool, "[/u][/i]", close_color) # Print color-coded message
		
	if dict_entry.old == null or dict_entry.old != dict_entry.tmp:
		dict_entry.old = dict_entry.tmp # Update old value if it's null or different from tmp


static func debug_log_concat1(dict_entry: Dictionary, argument: Variant) -> void:
	dict_entry.tmp = argument
	
	if dict_entry.old != dict_entry.tmp:
		var open_color: String = "[color=#" + DEBUG_COLORS[dict_entry.color] + "]"
		var close_color: String = "[/color]"
		
		if dict_entry.has('message'): # todo: got a crash 'cause no dict_entry.message
			print_rich(open_color, dict_entry.message, "[i][u]", dict_entry.tmp, "[/u][/i]", close_color) # Print color-coded message
		
	if dict_entry.old == null or dict_entry.old != dict_entry.tmp:
		dict_entry.old = dict_entry.tmp # Update old value if it's null or different from tmp
