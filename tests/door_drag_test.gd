extends SceneTree

# Run: Godot --headless --path . --script res://tests/door_drag_test.gd
var failures: int = 0
var player
var door

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func tick() -> void:
	await physics_frame
	await process_frame

func aim_at(point: Vector3) -> void:
	player.camera.look_at(point)
	await tick()

func hold(pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	if DisplayServer.get_name() == "headless":
		# Headless displays cannot capture the mouse; dispatch the same grab intent.
		if pressed:
			check(event.is_action_pressed("grab"), "Left mouse must map to grab")
			Input.action_press("grab")
			player._try_grab_door()
		else:
			Input.action_release("grab")
			player._release_door()
	else:
		Input.parse_input_event(event)
	await tick()
	await tick()

func drag(amount: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(0, amount)
	event.screen_relative = Vector2(0, amount)
	if DisplayServer.get_name() == "headless":
		if is_instance_valid(player.held_door):
			player.held_door.drag_mouse(event.screen_relative)
	else:
		Input.parse_input_event(event)
	await tick()
	await tick()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var door_root = load("res://scenes/objects/drag_door.tscn").instantiate()
	world.add_child(door_root)
	door = door_root.get_node("Hinge")
	player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(-2, 1.01, -0.625)
	world.add_child(player)
	player.flashlight_1.set_process(false)
	await tick()
	await aim_at(door.handle.global_position)
	check(player.get_look_target_name().contains("[LMB]"), "Aimed nearby knob should offer hold prompt")
	await aim_at(Vector3(0, 2.1, 0.3))
	check(player.get_look_target_name().is_empty(), "Door panel away from knob should not offer grab")
	await hold(true)
	check(not is_instance_valid(player.held_door), "Clicking panel should not grab knob")
	await hold(false)
	await aim_at(door.handle.global_position)
	Input.action_press("interact")
	await tick()
	Input.action_release("interact")
	check(is_zero_approx(door.rotation.y), "E should not toggle a drag door")
	await hold(true)
	check(player.held_door == door, "Holding LMB on knob should grab door")
	var camera_before: Transform3D = player.camera.transform
	await drag(70)
	check(door.rotation.y > 0.4, "Dragging down from front should pull door open")
	check(player.camera.transform.is_equal_approx(camera_before), "Dragging door should not rotate camera")
	await drag(-70)
	check(is_zero_approx(door.rotation.y), "Reverse drag should close door")
	await drag(500)
	check(is_equal_approx(door.rotation.y, deg_to_rad(door.maximum_angle)), "Door should stop at hinge limit")
	await hold(false)
	var released_angle: float = door.rotation.y
	await drag(-20)
	check(is_equal_approx(door.rotation.y, released_angle), "Released door must stay in place")
	# Verify the same interaction works from the other face of the closed door.
	door.rotation.y = 0.0
	door.requested_angle = 0.0
	player.position = Vector3(2, 1.01, -0.625)
	await tick()
	await aim_at(door.handle.global_position)
	await hold(true)
	check(player.held_door == door, "Knob should be grabbable from the back")
	await drag(-70)
	check(door.rotation.y > 0.4, "Pushing from back should open door")
	await drag(70)
	check(is_zero_approx(door.rotation.y), "Pulling from back should close door")
	# Put an obstacle in the swing arc and ensure fast input cannot tunnel through it.
	var blocker := StaticBody3D.new()
	var blocker_shape := CollisionShape3D.new()
	var blocker_box := BoxShape3D.new()
	blocker_box.size = Vector3(0.25, 2, 0.25)
	blocker_shape.shape = blocker_box
	blocker.add_child(blocker_shape)
	blocker.position = Vector3(-0.75, 1.1, -0.15)
	world.add_child(blocker)
	await tick()
	await drag(-500)
	check(door.rotation.y > 0.05 and door.rotation.y < 1.1, "Door should stop against an obstacle in its swing")
	await hold(false)
	blocker.queue_free()
	await tick()
	door.rotation.y = 0.0
	door.requested_angle = 0.0
	await aim_at(door.handle.global_position)
	await hold(true)
	player.position = Vector3(-0.75, 1.01, -0.15)
	await tick()
	await drag(-500)
	check(door.rotation.y < 1.1, "Door must not swing through the player")
	player._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not is_instance_valid(player.held_door), "Losing focus should release knob")
	await hold(false)
	player.position = Vector3(2, 1.01, -0.625)
	await tick()
	await aim_at(door.handle.global_position)
	await hold(true)
	check(player.held_door == door, "Player should be able to grab again after release")
	player.position.x = 8
	await tick()
	check(not is_instance_valid(player.held_door), "Walking out of reach should release knob")
	await hold(false)
	await aim_at(door.handle.global_position)
	check(player.get_look_target_name().is_empty(), "Distant knob should not show prompt")
	await hold(true)
	check(not is_instance_valid(player.held_door), "Distant knob cannot be grabbed")
	await hold(false)
	world.queue_free()
	await tick()
	await _check_barn_door()
	print("Door drag checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)

func walk(action: String, frames: int) -> void:
	Input.action_press(action)
	for frame in frames:
		await tick()
	Input.action_release(action)
	await tick()

func _check_barn_door() -> void:
	# Test the actual map as well as the fixture: the barn jamb originally
	# overlapped the leaf and stopped every rotation despite fixture tests passing.
	var map = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(map)
	player = map.get_node("Player")
	player.flashlight_1.set_process(false)
	door = map.get_node("NavigationRegion3D/door/Hinge")
	await tick()
	await tick()
	var origin: Vector3 = map.get_node("NavigationRegion3D/door").global_position
	player.global_position = origin + Vector3(1.8, 1.01, -0.5875)
	player.rotation.y = PI / 2.0
	await tick()
	var visual = door.get_node("Model/Cube_009")
	var visual_bounds: AABB = visual.get_aabb()
	var minimum_z: float = INF
	var maximum_z: float = -INF
	for corner in 8:
		var z: float = visual.to_global(visual_bounds.get_endpoint(corner)).z - origin.z
		minimum_z = minf(minimum_z, z)
		maximum_z = maxf(maximum_z, z)
	# These are the inner jamb faces in the barn asset, relative to the doorway.
	check(minimum_z >= -0.744348 and minimum_z < -0.739348, "Closed door should fit latch jamb within 5 mm")
	check(maximum_z <= 0.755651 and maximum_z > 0.750651, "Closed door should fit hinge jamb within 5 mm")
	for angle in range(0, int(door.maximum_angle) + 1, 5):
		var candidate: Transform3D = door.transform
		candidate.basis = Basis(Vector3.UP, deg_to_rad(angle))
		check(not door._is_blocked(door.get_parent().global_transform * candidate), "Barn frame should clear swing at %d degrees" % angle)
	await aim_at(door.handle.global_position)
	check(player.get_look_target_name().contains("[LMB]"), "Barn knob must be reachable through the real doorway")
	await hold(true)
	await drag(-70)
	check(door.rotation.y > 0.4, "Barn frame must not block mouse opening")
	await drag(70)
	check(is_zero_approx(door.rotation.y), "Barn door should close with mouse drag")
	await walk("move_forward", 8)
	check(door.rotation.y > 0.2, "Walking forward while holding should push barn door open")
	await walk("move_back", 10)
	check(door.rotation.y < 0.05, "Walking backward while holding should pull barn door closed")
	await hold(false)
	player.global_position = origin + Vector3(-1.8, 1.01, -0.5875)
	player.rotation.y = -PI / 2.0
	await tick()
	await aim_at(door.handle.global_position)
	await hold(true)
	check(player.held_door == door, "Barn knob should be usable from outside")
	await walk("move_back", 8)
	check(door.rotation.y > 0.2, "Walking backward outside should pull barn door open")
	await walk("move_forward", 10)
	check(door.rotation.y < 0.05, "Walking forward outside should push barn door closed")
	await hold(false)
	player.set_physics_process(false)
	player.footstep_audio.stop()
	await create_timer(0.1).timeout
	map.queue_free()
	await tick()
