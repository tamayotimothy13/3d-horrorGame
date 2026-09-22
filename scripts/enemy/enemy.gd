extends CharacterBody3D

const SPEED = 4.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var target: Node3D 
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

func _ready():
	# Godot 4 quirk: Kailangan mag-antay ng isang frame para mag-sync ang NavMesh
	await get_tree().physics_frame
	
	target = get_tree().get_first_node_in_group("player")
	if target:
		print("Hinahabol ko si: ", target.name, " sa posisyon na: ", target.global_position)

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if target == null:
		return

	nav_agent.target_position = target.global_position
	
	var next_path_position = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_position)
	
	direction.y = 0 
	direction = direction.normalized()

	velocity.x = direction.x * SPEED
	velocity.z = direction.z * SPEED

	move_and_slide()
