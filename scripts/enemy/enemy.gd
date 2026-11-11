extends CharacterBody3D

const NORMAL_SPEED = 5.0
const CHASE_SPEED = 10.0
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
	else:
		if lose_sight_timer > 0:
			lose_sight_timer -= delta
			current_speed = CHASE_SPEED
		else:
			current_speed = NORMAL_SPEED

	# 3. PAGPAPASYA NG DESTINASYON (Hahabol o Magba-patrol)
	if lose_sight_timer > 0:
		# Hahabulin ang player
		nav_agent.target_position = target.global_position
	else:
		# Magpapatrol sa mga point gamit ang distance check para hindi ma-stuck
		if patrol_points.size() > 0:
			var current_marker = patrol_points[current_patrol_index]
			if current_marker:
				# Kapag lumapit ang kalaban sa loob ng 1.5 meters ng marker, lipat sa sunod
				if global_position.distance_to(current_marker.global_position) < 1.5:
					current_patrol_index = (current_patrol_index + 1) % patrol_points.size()
					_set_next_patrol_target()

	# 4. Paggalaw patungo sa kasalukuyang target position ng NavAgent
	var next_path_position = nav_agent.get_next_path_position()
	var direction = global_position.direction_to(next_path_position)
	
	direction.y = 0 
	direction = direction.normalized()

	velocity.x = direction.x * current_speed
	velocity.z = direction.z * current_speed

	move_and_slide()

func _set_next_patrol_target():
	if patrol_points.size() > 0 and patrol_points[current_patrol_index]:
		nav_agent.target_position = patrol_points[current_patrol_index].global_position

# Signals para sa Area3D Vision Cone
func _on_vision_cone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		player_in_vision_area = true

func _on_vision_cone_body_exited(body: Node3D) -> void:
	if body == target:
		player_in_vision_area = false
