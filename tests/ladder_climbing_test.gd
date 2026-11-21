extends SceneTree

# Run: Godot --headless --path . --script res://tests/ladder_climbing_test.gd
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func tick(frames: int = 1) -> void:
	for frame in frames:
		await physics_frame
		await process_frame

func _run() -> void:
	var map = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(map)
	var player = map.get_node("Player")
	var ladder = map.get_node("NavigationRegion3D/ladder")
	player.flashlight_1.set_process(false)
	map.get_node("NavigationRegion3D/Enemy").set_physics_process(false)
	await tick(3)
	player.global_position = ladder.to_global(ladder.bottom)
	var camera_origin: Vector3 = player.camera.position
	await tick(2)
	Input.action_press("move_forward")
	await tick(24)
	check(player.active_ladder == ladder, "W near the ladder should attach automatically")
	check(ladder.to_local(player.global_position).y > 1.5, "Holding W should climb up")
	check(not player.camera.position.is_equal_approx(camera_origin), "Climbing should animate the camera")
	check(not player.footstep_audio.playing, "Climbing must not play walking sounds")
	check(not player.is_sprinting, "Climbing must not sprint")
	Input.action_release("move_forward")
	var held_position: Vector3 = player.global_position
	await tick(20)
	check(player.global_position.is_equal_approx(held_position), "Releasing W/S should hold position without falling")
	Input.action_press("move_back")
	await tick(8)
	check(player.global_position.y < held_position.y - 0.1, "Holding S should descend")
	Input.action_release("move_back")
	Input.action_press("move_forward")
	for frame in 240:
		await tick()
		if not is_instance_valid(player.active_ladder):
			break
	Input.action_release("move_forward")
	check(not is_instance_valid(player.active_ladder), "Reaching the top should step onto the loft and detach")
	check(player.global_position.distance_to(ladder.to_global(ladder.top_exit)) < 0.1, "Top exit must reach the real barn loft")
	check(player.camera.position.is_equal_approx(camera_origin), "Dismount should restore camera position")
	check(player.get_collision_exceptions().is_empty(), "Dismount should restore ladder collisions")
	await tick(30)
	check(player.is_on_floor(), "Player should stand on the loft after dismount")
	check(player.global_position.y > 6.0, "Player must not fall through the loft")
	Input.action_press("move_back")
	await tick(2)
	check(player.active_ladder == ladder, "S at the top should attach for descent")
	for frame in 240:
		await tick()
		if not is_instance_valid(player.active_ladder):
			break
	Input.action_release("move_back")
	check(not is_instance_valid(player.active_ladder), "Reaching the bottom should detach")
	check(player.global_position.distance_to(ladder.to_global(ladder.bottom)) < 0.1, "S should return player to the ground")
	await tick(30)
	Input.action_press("move_forward")
	await tick(12)
	Input.action_release("move_forward")
	Input.action_press("interact")
	await tick()
	Input.action_release("interact")
	check(not is_instance_valid(player.active_ladder), "E should let go of the ladder")
	check(player.camera.position.is_equal_approx(camera_origin), "Letting go should clear climbing animation")
	player.set_physics_process(false)
	player.footstep_audio.stop()
	await create_timer(0.1).timeout
	map.queue_free()
	await tick()
	print("Ladder climbing checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
