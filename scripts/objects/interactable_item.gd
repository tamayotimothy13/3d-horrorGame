extends StaticBody3D


func get_interaction_label() -> String:
	return "Note"


func interact():
	print("Player interacted with me!")
	if is_in_group("countable_interactable"):
		queue_free()
