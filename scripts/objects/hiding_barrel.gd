extends StaticBody3D

# The imported drum is two metres tall, with its origin at its centre.
@export var hidden_eye_height: float = 0.2
@export var peek_eye_height: float = 1.3

func _ready() -> void:
	# Use one simple collider for both movement and crosshair interactions.
	for body in $Model.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0

func get_interaction_label() -> String:
	return "Barrel — Press [E] to hide"

func interact_with_player(player: Node3D) -> void:
	player.enter_barrel(self)

func get_eye_position(peeking: bool) -> Vector3:
	return to_global(Vector3(0, peek_eye_height if peeking else hidden_eye_height, 0))
