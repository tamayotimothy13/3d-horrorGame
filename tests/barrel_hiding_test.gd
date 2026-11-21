extends SceneTree

# Run: Godot --headless --path . --script res://tests/barrel_hiding_test.gd
var failures: int = 0
var player
var barrel
var hud

func _initialize() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func tick() -> void:
	await physics_frame
	await process_frame

func press(action: String) -> void:
	Input.action_press(action)
	await tick()
	Input.action_release(action)
	await tick()

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(30, 1, 30)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	barrel = load("res://scenes/objects/hiding_barrel.tscn").instantiate()
	barrel.position = Vector3(0, 1.01, 0)
	barrel.scale = Vector3.ONE * 0.8
	world.add_child(barrel)
	player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(0, 1.01, 2)
	world.add_child(player)
	hud = load("res://scenes/ui/player_hud.tscn").instantiate()
	world.add_child(hud)
	await tick()
	await tick()
	check(InputMap.action_get_events("peek")[0].physical_keycode == KEY_Q, "Peek must be bound to Q")
	check(player.get_look_target_name().contains("[E]"), "Nearby aimed barrel should show E prompt")
	player.rotation.y = PI
	await tick()
	check(player.get_look_target_name().is_empty(), "Looking away should clear prompt")
	player.rotation.y = 0
	player.position.z = 5
	await tick()
	check(player.get_look_target_name().is_empty(), "Distant barrel should not show prompt")
	player.position.z = 2
	await tick()
	var entry: Transform3D = player.global_transform
	var camera_before: Transform3D = player.camera.transform
	var layer_before: int = player.collision_layer
	var flashlight_before: bool = player.flashlight_1.visible
	await press("interact")
	check(player.is_hiding(), "E should enter aimed barrel")
	check(player.is_hidden_from_enemies(), "Fully hidden player should be concealed")
	check(hud.get_node("BarrelDarkness").visible, "Inside barrel should obscure the world")
	check(not player.flashlight_1.visible, "Flashlight should be off inside barrel")
	check(player.get_look_target_name().contains("Leave [E]"), "Hidden prompt should offer exit")
	var enemy = load("res://scenes/enemies/enemy.tscn").instantiate()
	enemy.position = Vector3(0, 1.01, 5)
	world.add_child(enemy)
	enemy.set_physics_process(false)
	await tick()
	await tick()
	enemy._physics_process(0.016)
	check(enemy.player_in_vision_area, "Enemy vision area must still track the hidden player for peeking")
	check(not enemy.has_line_of_sight, "Enemy must not see fully hidden player")
	var hidden_position: Vector3 = player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await tick()
	check(player.global_position.is_equal_approx(hidden_position), "Movement must be disabled while hiding")
	check(not player.is_sprinting, "Hidden player must not sprint")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await press("peek")
	check(player.is_peeking, "Q should start peeking")
	check(not player.is_hidden_from_enemies(), "Peeking should expose the player")
	check(not hud.get_node("BarrelDarkness").visible, "Peeking should reveal world")
	check(player.camera.global_position.is_equal_approx(barrel.get_eye_position(true)), "Peek camera should be above lid")
	enemy._physics_process(0.016)
	check(enemy.has_line_of_sight, "Enemy should be able to see an unobstructed peeking player")
	var last_seen: Vector3 = enemy.last_seen_position
	await press("peek")
	check(not player.is_peeking and player.is_hidden_from_enemies(), "Q should return to hiding")
	enemy._physics_process(0.016)
	check(not enemy.has_line_of_sight, "Stopping peek should conceal player again")
	check(enemy.nav_agent.target_position.is_equal_approx(last_seen), "Enemy should search last seen position while player hides")
	enemy.queue_free()
	var obstruction := StaticBody3D.new()
	var obstruction_shape := CollisionShape3D.new()
	obstruction_shape.shape = BoxShape3D.new()
	obstruction.add_child(obstruction_shape)
	obstruction.position = entry.origin
	world.add_child(obstruction)
	await tick()
	await press("interact")
	check(player.is_hiding(), "Blocked exit should keep player safely inside")
	check(player.get_look_target_name().contains("Exit blocked"), "Blocked exit should explain why E failed")
	obstruction.queue_free()
	await tick()
	await press("peek")
	await press("interact")
	check(not player.is_hiding() and not player.is_peeking, "E should leave while peeking")
	check(player.global_position.distance_to(entry.origin) < 0.05, "Exit should restore entry position")
	check(player.camera.transform.is_equal_approx(camera_before), "Exit should restore camera")
	check(player.collision_layer == layer_before, "Exit should restore collision")
	check(player.flashlight_1.visible == flashlight_before, "Exit should restore flashlight")
	check(not hud.get_node("BarrelDarkness").visible, "Exit should clear barrel overlay")
	# A wall between the crosshair and barrel must prevent interacting through it.
	obstruction = StaticBody3D.new()
	obstruction_shape = CollisionShape3D.new()
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(3, 3, 0.1)
	obstruction_shape.shape = wall_shape
	obstruction.add_child(obstruction_shape)
	obstruction.position = Vector3(0, 1.5, 1)
	world.add_child(obstruction)
	await tick()
	await press("interact")
	check(not player.is_hiding(), "Walls must block barrel interaction")
	check(player.get_look_target_name().is_empty(), "Walls must block barrel prompt")
	world.queue_free()
	await tick()
	print("Barrel hiding checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
