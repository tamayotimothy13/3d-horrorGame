extends CharacterBody3D

const NORMAL_SPEED = 3.0
const CHASE_SPEED = 6.0
var current_speed = NORMAL_SPEED

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var target: Node3D 

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var vision_cone: Area3D = $VisionCone
@onready var ray_cast: RayCast3D = $RayCast3D

var player_in_vision_area: bool = false
var has_line_of_sight: bool = false

# Timer para sa 3 seconds chase grace period
var lose_sight_timer: float = 0.0
const CHASE_DELAY: float = 3.0 

# Patrol System Variables
@export var patrol_points: Array[Node3D] = []
var current_patrol_index: int = 0

# Flag para malaman kung nag-iinvestigate siya ng note
var is_investigating: bool = false

func _ready():
	await get_tree().physics_frame
	
	target = get_tree().get_first_node_in_group("player")
	
	if vision_cone:
		vision_cone.body_entered.connect(_on_vision_cone_body_entered)
		vision_cone.body_exited.connect(_on_vision_cone_body_exited)
		
	if ray_cast:
		ray_cast.add_exception(self)
		
	# Pumili ng unang patrol point kung mayroon man
	_set_next_patrol_target()
	
func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if target == null:
		return

	# 1. RayCast Check kung may harang na pader patungo sa player
	if target and ray_cast:
		ray_cast.target_position = ray_cast.to_local(target.global_position + Vector3(0, 1, 0))
		ray_cast.force_raycast_update()
		
		if ray_cast.is_colliding() and ray_cast.get_collider() == target:
			has_line_of_sight = true
		else:
			has_line_of_sight = false

	# 2. CHASE MEMORY AT SPEED LOGIC
	if player_in_vision_area and has_line_of_sight:
		lose_sight_timer = CHASE_DELAY 
		current_speed = CHASE_SPEED
		is_investigating = false # Nakita ka na ulit, kaya itigil muna ang note investigation
	else:
		if lose_sight_timer > 0:
			lose_sight_timer -= delta 
			current_speed = CHASE_SPEED 
		else:
			# Kung tapos na ang chase timer at hindi rin nag-iinvestigate ng note, mag-patrol na
			if not is_investigating:
				current_speed = NORMAL_SPEED 

	# 3. PAGPAPASYA NG DESTINASYON
	if player_in_vision_area and has_line_of_sight:
		# Nakita ka, kaya ikaw ang habulin
		nav_agent.target_position = target.global_position
	elif lose_sight_timer > 0 and not is_investigating:
		# Grace period habang hinahabol ang huling posisyon mo
		nav_agent.target_position = target.global_position
	elif is_investigating:
		# Papunta siya sa note. Kapag malapit na siya sa note, ibalik sa normal/patrol
		if nav_agent.is_navigation_finished() or global_position.distance_to(nav_agent.target_position) < 1.5:
			is_investigating = false
	else:
		# Magpapatrol sa mga point
		if patrol_points.size() > 0:
			var current_marker = patrol_points[current_patrol_index]
			if current_marker:
				if global_position.distance_to(current_marker.global_position) < 1.5:
					current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
					_set_next_patrol_target()

	# 4. Paggalaw patungo sa kasalukuyang target position ng NavAgent
	var next_path_position = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_position)
	
	direction.y = 0 
	direction = direction.normalized()

	var target_velocity = direction * current_speed
	
	velocity.x = move_toward(velocity.x, target_velocity.x, current_speed * delta * 10.0)
	velocity.z = move_toward(velocity.z, target_velocity.z, current_speed * delta * 10.0)

	move_and_slide()

func _set_next_patrol_target():
	if patrol_points.size() > 0 and patrol_points[current_patrol_index]:
		nav_agent.target_position = patrol_points[current_patrol_index].global_position

# Function na tatawagin ng Note para pumunta roon
func investigate_position(pos: Vector3):
	is_investigating = true
	nav_agent.target_position = pos
	current_speed = CHASE_SPEED

# Signals para sa Area3D Vision Cone
func _on_vision_cone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_vision_area = true

func _on_vision_cone_body_exited(body: Node3D) -> void:
	if body == target:
		player_in_vision_area = false
