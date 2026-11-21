extends AnimatableBody3D

@export var maximum_angle: float = 90.0
@export var drag_sensitivity: float = 0.008
@export var handle_grab_radius: float = 0.2

var requested_angle: float = 0.0
var grab_side: float = 1.0
var held_by: Node3D = null
@onready var handle: Marker3D = $Handle

func _ready() -> void:
	# The imported mesh includes a static collider; only the hinged body should collide.
	for body in $Model.find_children("*", "CollisionObject3D", true, false):
		body.collision_layer = 0
		body.collision_mask = 0
	requested_angle = rotation.y

func can_grab_at(hit_position: Vector3) -> bool:
	var local_hit := to_local(hit_position)
	return Vector2(local_hit.y - handle.position.y, local_hit.z - handle.position.z).length() <= handle_grab_radius

func get_interaction_label() -> String:
	return "Door knob — Hold [LMB] + move or drag"

func begin_grab(player: Node3D, view: Camera3D) -> void:
	held_by = player
	# Down pulls toward the player; up pushes away, from either face of the door.
	grab_side = -1.0 if to_local(view.global_position).x > 0.0 else 1.0
	requested_angle = rotation.y

func drag_mouse(relative: Vector2) -> void:
	if is_instance_valid(held_by):
		requested_angle = clampf(requested_angle + relative.y * grab_side * drag_sensitivity, 0.0, deg_to_rad(maximum_angle))

func drag_movement(world_motion: Vector3) -> void:
	if not is_instance_valid(held_by):
		return
	# Project intended walking onto the handle's swing tangent. Use intended
	# movement so pushing still works when the closed panel stops the player.
	var hinge_axis := global_basis.y.normalized()
	var radius := handle.global_position - global_position
	radius -= hinge_axis * radius.dot(hinge_axis)
	if radius.length_squared() > 0.001:
		var angle_delta := world_motion.dot(hinge_axis.cross(radius)) / radius.length_squared()
		requested_angle = clampf(requested_angle + angle_delta, 0.0, deg_to_rad(maximum_angle))

func end_grab() -> void:
	held_by = null
	requested_angle = rotation.y

func _physics_process(_delta: float) -> void:
	if not is_instance_valid(held_by):
		return
	# Small steps stop a fast drag from swinging through thin walls or the player.
	while absf(requested_angle - rotation.y) > 0.0001:
		var next_angle := move_toward(rotation.y, requested_angle, deg_to_rad(2.0))
		var candidate := transform
		candidate.basis = Basis(Vector3.UP, next_angle)
		var candidate_global: Transform3D = get_parent().global_transform * candidate
		if _is_blocked(candidate_global):
			requested_angle = rotation.y
			break
		transform = candidate

func _is_blocked(candidate: Transform3D) -> bool:
	for shape_node in [$PanelCollision, $HandleCollision]:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape_node.shape
		query.transform = candidate * shape_node.transform
		query.collision_mask = collision_mask
		query.exclude = [get_rid()]
		query.margin = 0.0
		if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			return true
	return false
