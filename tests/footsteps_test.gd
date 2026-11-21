extends SceneTree

# Run: Godot --headless --path . --script res://tests/footsteps_test.gd
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

func add_box(world: Node3D, position: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = position
	world.add_child(body)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	add_box(world, Vector3(0, -0.5, 0), Vector3(40, 1, 40))
	add_box(world, Vector3(0, 1.5, -1.25), Vector3(8, 3, 0.5))
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(0, 1.01, 2)
	world.add_child(player)
	player.flashlight_1.set_process(false)
	await tick(3)
	check(not player.footstep_audio.playing, "Idle player should be silent")
	Input.action_press("move_forward")
	await tick(2)
	check(player.footstep_audio.playing and player.footstep_timer > 0.0, "Walking should play footsteps")
	Input.action_release("move_forward")
	await tick()
	check(not player.footstep_audio.playing, "Releasing movement should stop the current clip immediately")
	check(is_zero_approx(player.footstep_timer), "Stopping should reset footstep cadence")
	Input.action_press("move_forward")
	await tick(45)
	var stopped_position: Vector3 = player.global_position
	await tick(15)
	check(player.global_position.distance_to(stopped_position) < 0.01, "Wall should stop player movement")
	check(not player.footstep_audio.playing, "Holding movement into a wall must stay silent")
	check(is_zero_approx(player.footstep_timer), "Blocked movement must not retrigger footsteps")
	Input.action_release("move_forward")
	player.position = Vector3(6, 1.01, 2)
	await tick(2)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await tick()
	check(player.footstep_audio.playing, "Sprinting should play footsteps")
	check(player.footstep_timer <= 0.28 and player.footstep_timer > 0.2, "Sprinting should use sprint cadence at the actual sprint speed")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await tick()
	check(not player.footstep_audio.playing, "Stopping sprint should silence footsteps")
	Input.action_press("move_forward")
	Input.action_press("crouch")
	await tick()
	check(player.footstep_audio.playing and player.footstep_timer > 0.6, "Crouching should keep its slower cadence")
	player.position.y = 5
	await tick(2)
	check(not player.is_on_floor(), "Airborne test should be above the floor")
	check(not player.footstep_audio.playing, "Airborne movement must not play footsteps")
	Input.action_release("move_forward")
	Input.action_release("crouch")
	player.set_physics_process(false)
	player.footstep_audio.stop()
	await create_timer(0.1).timeout
	world.queue_free()
	await tick()
	print("Footstep checks: ", "PASS" if failures == 0 else "%d FAILED" % failures)
	quit(0 if failures == 0 else 1)
