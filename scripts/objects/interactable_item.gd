extends StaticBody3D


func get_interaction_label() -> String:
	return "Note"


func interact():
	print("Player interacted with me!")
	
	# Utusan ang Enemy na pumunta sa lokasyon ng note na ito
	var enemy = get_tree().get_first_node_in_group("enemy")
	if enemy and enemy.has_method("investigate_position"):
		enemy.investigate_position(global_position)
		print("AI triggered! Pumupunta na sa pwesto ng note:", global_position)
	else:
		print("Babala: Walang nahanap na node sa group na 'enemy' o walang investigate_position method.")

	if is_in_group("countable_interactable"):
		queue_free()
