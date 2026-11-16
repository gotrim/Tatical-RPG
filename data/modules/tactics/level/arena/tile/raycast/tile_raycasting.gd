class_name TacticsTileRaycast
extends Node3D
## Handles raycasting operations for TacticsTile.
##
## This class is responsible for detecting neighboring tiles and objects above the tile.
## It is typically instantiated as a child of TacticsTile.


#region: --- Processing ---
func _ready() -> void:
	# Os 4 raios de vizinhança só são lidos em get_all_neighbors(), que é um fallback usado
	# quando o tile não está dentro de uma TacticsArena (no jogo, TacticsTile.get_neighbors()
	# usa o dicionário da arena). Deixá-los ativos custava 4 raycasts por tile a cada tick de
	# física; agora eles só são atualizados sob demanda, dentro de get_all_neighbors().
	for child: Node in $Neighbors.get_children():
		var ray: RayCast3D = child as RayCast3D
		if ray:
			ray.enabled = false
#endregion


#region: --- Methods ---
## Returns all the neighbouring tiles within a given height range.
## [param height] The maximum height difference to consider for neighbors.
## [returns] An array of neighboring Node3D objects (typically TacticsTiles).
func get_all_neighbors(height: float) -> Array[Node3D]:
	var neighbors: Array[Node3D] = []
	
	for ray: RayCast3D in $Neighbors.get_children() as Array[RayCast3D]:
		ray.force_raycast_update() # O raio está desativado; atualiza só quando for lido
		var obj: Node3D = ray.get_collider() # Get the object hit by the ray
		
		# Check if object exists and is within the specified height range
		if (obj and abs(obj.global_position.y - get_parent().global_position.y) 
				<= height):
			neighbors.append(obj) # Add the object to neighbors list
			
	return neighbors


## Returns the object directly above the tile.
## [returns] The object above the tile, or null if none found.
func get_object_above() -> Object:
	return $Above.get_collider() # Return object hit by the upward-facing ray
#endregion
