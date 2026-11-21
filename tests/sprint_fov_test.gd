extends SceneTree

# Run: Godot --headless --path . --script res://tests/sprint_fov_test.gd
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
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	world.add_child(floor_body)
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position.y = 1.01
	world.add_child(player)
	player.flashlight_1.set_process(false)
	var hud = load("res://scenes/ui/player_hud.tscn").instantiate()
	world.add_child(hud)
	await tick(3)
	check(not hud.has_node("SprintSpeedLines"), "HUD should not include the removed anime overlay")
	Input.action_press("sprint")
	await tick(10)
	check(is_equal_approx(player.camera.fov, player.normal_fov), "Shift while stationary must not zoom the camera")
	Input.action_press("move_forward")
	await tick(15)
	check(player.camera.fov > player.normal_fov and player.camera.fov <= player.normal_fov + player.sprint_fov_boost, "Sprinting should subtly widen the FOV")
	Input.action_release("sprint")
	var fov_before: float = player.camera.fov
	await tick(5)
	check(player.camera.fov < fov_before, "Stopping sprint should begin easing the FOV back")
	await tick(24)
	check(is_equal_approx(player.camera.fov, player.normal_fov), "Stopping sprint should ease back to normal FOV")
	# A wall directly in front blocks movement even while sprint is requested.
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	var wall_box := BoxShape3D.new()
	wall_box.size = Vector3(8, 3, 0.5)
	wall_shape.shape = wall_box
	wall.add_child(wall_shape)
	wall.position = player.position + Vector3(0, 0, -1.0)
	world.add_child(wall)
	Input.action_press("sprint")
	await tick(35)
	check(is_equal_approx(player.camera.fov, player.normal_fov), "A blocked sprint should restore normal FOV")
	wall.queue_free()
	await tick(15)
	check(player.camera.fov > player.normal_fov, "Resuming sprint movement should widen the FOV")
	player.stamina = 0.001
	await tick(30)
	check(is_equal_approx(player.camera.fov, player.normal_fov), "Exhausted sprint should restore normal FOV")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	player.monster_seen()
	check(player.camera.fov >= player.danger_fov, "Monster reaction should still override normal sprint FOV")
	await tick(40)
	check(is_equal_approx(player.camera.fov, player.normal_fov), "Monster reaction should settle back to normal FOV")
	player.set_physics_process(false)
	player.footstep_audio.stop()
	await create_timer(0.1).timeout
	world.queue_free()
	await tick()
	print("Sprint FOV checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
