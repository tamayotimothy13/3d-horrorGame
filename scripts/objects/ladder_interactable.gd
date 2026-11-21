extends Node3D

@export var climb_speed: float = 2.5
@export var bottom: Vector3 = Vector3(-0.95, 1.01, 0)
@export var top: Vector3 = Vector3(-0.05, 6.15, 0)
@export var top_exit: Vector3 = Vector3(1.05, 6.15, 0)

func get_climb_position(height: float) -> Vector3:
	var progress := clampf((height - bottom.y) / (top.y - bottom.y), 0.0, 1.0)
	return bottom.lerp(top, progress)

func can_climb(player: Node3D, direction: float) -> bool:
	var local := to_local(player.global_position)
	if local.y < bottom.y - 0.25 or local.y > top.y + 0.25:
		return false
	if direction < 0.0 and local.distance_to(top_exit) < 0.75:
		return true
	var path := get_climb_position(local.y)
	return absf(local.x - path.x) < 0.65 and absf(local.z) < 0.9

func get_ladder_bodies() -> Array[Node]:
	return $Model.find_children("*", "PhysicsBody3D", true, false)
