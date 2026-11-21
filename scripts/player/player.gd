extends CharacterBody3D

signal stamina_changed(value: float, max_value: float, is_sprinting: bool)
signal vignette_intensity_changed(intensity: float)
signal look_target_changed(target_name: String)
signal countable_interactable_completed(count: int)
signal hiding_changed(hiding: bool, peeking: bool)

const SPRINT_SPEED = 11
var SPEED = 7
const JUMP_VELOCITY = 25
const CROUCH_SPEED = 9
var normal_fov = 75.0
var danger_fov = 100.0
@export_range(0.0, 15.0) var sprint_fov_boost: float = 5.0
var sprint_fov_blend: float = 0.0
var scare_fov_offset: float = 0.0
var scare_fov_tween: Tween

# Stamina system
const MAX_STAMINA = 3.0 # seconds of sprint available
const STAMINA_REGEN_TIME = 5.0 # seconds to fully regen from empty, also the lockout duration
var stamina = MAX_STAMINA
var stamina_locked = false # true while in the post-exhaustion cooldown
var is_sprinting = false

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Camera bob
#const IDLE_BOB_FREQUENCY = 5.0
#const IDLE_BOB_AMPLITUDE = 0.15
#const MOVE_BOB_FREQUENCY = 10.0
#const MOVE_BOB_AMPLITUDE = 0.50
#var bob_timer = 0.0
#var camera_base_y = 0.0

# Footsteps
var footstep_timer = 0.0

const WALK_FOOTSTEP_INTERVAL = 0.45
const SPRINT_FOOTSTEP_INTERVAL = 0.28
const CROUCH_FOOTSTEP_INTERVAL = 0.65

# Enemy proximity audio + vignette
const ENEMY_TIER_FAR = 50.0
const ENEMY_TIER_MID = 15.0
const ENEMY_TIER_CLOSE = 5.0
const AUDIO_FADE_SPEED_DB = 40.0 # dB per second crossfade speed
const AUDIO_SILENT_DB = -80.0
const VIGNETTE_BASE_INTENSITY = 0.25 # always-present atmospheric vignette
const VIGNETTE_MAX_INTENSITY = 0.75 # intensity when enemy is at/closer than ENEMY_TIER_CLOSE
const VIGNETTE_FADE_SPEED = 1.5 # intensity units per second

@onready var camera = $Camera3D
@onready var interaction_ray: RayCast3D = $Camera3D/Interaction_Raytracing
@onready var flashlight_1: SpotLight3D = $Camera3D/flashlight_1
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio
@onready var audio_tiers: Array[AudioStreamPlayer] = [
	$EnemyProximityAudio/AudioFar,
	$EnemyProximityAudio/AudioTier50,
	$EnemyProximityAudio/AudioTier15,
	$EnemyProximityAudio/AudioTier5,
]

@onready var chase_audio: AudioStreamPlayer = $EnemyProximityAudio/ChaseAudio

var current_vignette_intensity = VIGNETTE_BASE_INTENSITY
var current_look_target_name = ""
var hiding_barrel: StaticBody3D = null
var is_peeking: bool = false
var barrel_exit_transform: Transform3D
var normal_camera_transform: Transform3D
var normal_collision_layer: int
var normal_collision_mask: int
var hidden_lights: Dictionary = {}
var held_door: AnimatableBody3D = null
var active_ladder: Node3D = null
var ladder_regrab_delay: float = 0.0
var climb_camera_origin: Vector3
var climb_animation_phase: float = 0.0
var completed_countable_interactable_ids: Dictionary = {}
var completed_countable_interactable_count = 0
var last_logged_tier = -1 # used to only print when the enemy proximity tier changes
const TIER_NAMES = ["FAR (>50m)", "TIER 50m", "TIER 15m", "TIER 5m"]

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	interaction_ray.add_exception(self)
	# camera_base_y = camera.position.y
	for player in audio_tiers:
		player.volume_db = AUDIO_SILENT_DB

func get_hud_state() -> Dictionary:
	return {
		"stamina": stamina,
		"max_stamina": MAX_STAMINA,
		"is_sprinting": is_sprinting,
		"vignette_intensity": current_vignette_intensity,
		"countable_interactable_count": completed_countable_interactable_count,
		"hiding": is_hiding(),
		"peeking": is_peeking,
	}

func _process(delta: float) -> void:
	var actual_velocity := get_real_velocity()
	var moving_sprint := is_sprinting and Vector2(actual_velocity.x, actual_velocity.z).length() > 0.5
	sprint_fov_blend = move_toward(sprint_fov_blend, 1.0 if moving_sprint else 0.0, delta * 4.0)
	camera.fov = normal_fov + sprint_fov_boost * sprint_fov_blend + scare_fov_offset

func get_look_target_name() -> String:
	return current_look_target_name

func _unhandled_input(event):
	if event.is_action_released("grab"):
		_release_door()
	if event.is_action_pressed("grab") and not is_hiding() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_try_grab_door()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and (not is_hiding() or is_peeking):
		if is_instance_valid(held_door):
			held_door.drag_mouse(event.screen_relative)
			return
		rotate_y(-event.relative.x * 0.005)
		camera.rotate_x(-event.relative.y * 0.005)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	if event.is_action_pressed("ui_cancel"):
		_release_door()
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_release_door()

func _try_grab_door() -> void:
	if is_hiding() or is_instance_valid(active_ladder):
		return
	interaction_ray.force_raycast_update()
	if interaction_ray.is_colliding():
		var target = interaction_ray.get_collider()
		if target.is_in_group("drag_door") and target.can_grab_at(interaction_ray.get_collision_point()):
			held_door = target
			held_door.begin_grab(self, camera)
			_set_look_target("Holding knob — Move / drag | Release [LMB]")

func _release_door() -> void:
	if is_instance_valid(held_door):
		held_door.end_grab()
	held_door = null

func _physics_process(delta): # all movment code inside this
	if is_hiding():
		_process_barrel_hiding(delta)
		return
	ladder_regrab_delay = maxf(ladder_regrab_delay - delta, 0.0)
	if not is_instance_valid(active_ladder) and ladder_regrab_delay <= 0.0:
		var climb_direction := Input.get_axis("move_back", "move_forward")
		if not is_zero_approx(climb_direction):
			for ladder in get_tree().get_nodes_in_group("climbable_ladder"):
				if ladder.can_climb(self, climb_direction):
					_start_climbing(ladder)
					break
	if is_instance_valid(active_ladder):
		_process_climbing(delta)
		return
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# handle jump
	#if Input.is_action_just_pressed("jump") and is_on_floor():
		#velocity.y = JUMP_VELOCITY 
		
	# Make sure you mapped these actions in Project Settings -> Input Map
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Handles sprint and crouch mechanic/speed
	var regen_rate = MAX_STAMINA / STAMINA_REGEN_TIME
	# Bug fix: only consider the player "sprinting" (and draining stamina) if
	# they are actually holding a movement direction, not just holding shift in place.
	var wants_to_sprint = Input.is_action_pressed("sprint") and not stamina_locked and stamina > 0.0 and direction != Vector3.ZERO
	is_sprinting = wants_to_sprint

	if wants_to_sprint:
		SPEED = SPRINT_SPEED
		stamina = max(stamina - delta, 0.0)
		if stamina <= 0.0:
			stamina_locked = true
	else:
		if Input.is_action_pressed("crouch"):
			SPEED = CROUCH_SPEED
		else:
			SPEED = 7
		stamina = min(stamina + regen_rate * delta, MAX_STAMINA)
		if stamina_locked and stamina >= MAX_STAMINA:
			stamina_locked = false

	stamina_changed.emit(stamina, MAX_STAMINA, is_sprinting)

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	#_update_camera_bob(delta)
	_update_enemy_proximity(delta)
	if is_instance_valid(held_door):
		if not Input.is_action_pressed("grab") or camera.global_position.distance_to(held_door.handle.global_position) > interaction_ray.target_position.length():
			_release_door()
	_update_look_target()

	# Handles the interaction mechanic
	if Input.is_action_just_pressed("interact"):
		if interaction_ray.is_colliding():
			var item = interaction_ray.get_collider()
			
			if item.is_in_group("interactable"):
				if item.has_method("interact_with_player"):
					item.interact_with_player(self)
				else:
					item.interact()
				if item.is_in_group("countable_interactable"):
					var item_id = item.get_instance_id()
					if not completed_countable_interactable_ids.has(item_id):
						completed_countable_interactable_ids[item_id] = true
						completed_countable_interactable_count += 1
						countable_interactable_completed.emit(completed_countable_interactable_count)

	if not is_hiding():
		if is_instance_valid(held_door):
			held_door.drag_movement(Vector3(velocity.x, 0, velocity.z) * delta)
		move_and_slide()
		_update_footsteps(delta)

func is_hiding() -> bool:
	return is_instance_valid(hiding_barrel)

func _start_climbing(ladder: Node3D) -> void:
	_release_door()
	active_ladder = ladder
	climb_camera_origin = camera.position
	climb_animation_phase = 0.0
	velocity = Vector3.ZERO
	is_sprinting = false
	footstep_timer = 0.0
	footstep_audio.stop()
	for body in ladder.get_ladder_bodies():
		add_collision_exception_with(body)
	_set_look_target("Ladder — Up [W] | Down [S] | Let go [E]")

func _stop_climbing() -> void:
	if is_instance_valid(active_ladder):
		for body in active_ladder.get_ladder_bodies():
			remove_collision_exception_with(body)
	active_ladder = null
	ladder_regrab_delay = 0.4
	camera.position = climb_camera_origin
	velocity = Vector3.ZERO
	_set_look_target("")

func _process_climbing(delta: float) -> void:
	_update_enemy_proximity(delta)
	stamina = minf(stamina + MAX_STAMINA / STAMINA_REGEN_TIME * delta, MAX_STAMINA)
	if stamina >= MAX_STAMINA:
		stamina_locked = false
	stamina_changed.emit(stamina, MAX_STAMINA, false)
	if Input.is_action_just_pressed("interact"):
		_stop_climbing()
		return
	var direction := Input.get_axis("move_back", "move_forward")
	var local: Vector3 = active_ladder.to_local(global_position)
	var previous_position := global_position
	velocity = Vector3.ZERO
	if not is_zero_approx(direction):
		var target: Vector3 = active_ladder.get_climb_position(local.y + direction * active_ladder.climb_speed * delta)
		if direction > 0.0 and local.y >= active_ladder.top.y - 0.03:
			target = active_ladder.top_exit
		var next_position := global_position.move_toward(active_ladder.to_global(target), active_ladder.climb_speed * delta)
		velocity = (next_position - global_position) / delta
		move_and_slide()
	var distance := global_position.distance_to(previous_position)
	climb_animation_phase += distance * 9.0
	var camera_offset := Vector3.ZERO
	if distance > 0.0001:
		camera_offset = Vector3(sin(climb_animation_phase) * 0.025, sin(climb_animation_phase * 2.0) * 0.035, 0)
	camera.position = camera.position.lerp(climb_camera_origin + camera_offset, minf(delta * 12.0, 1.0))
	local = active_ladder.to_local(global_position)
	if direction < 0.0 and local.distance_to(active_ladder.bottom) < 0.05:
		_stop_climbing()
	elif direction > 0.0 and local.distance_to(active_ladder.top_exit) < 0.05:
		_stop_climbing()

func is_hidden_from_enemies() -> bool:
	return is_hiding() and not is_peeking

func enter_barrel(barrel: StaticBody3D) -> void:
	if is_hiding():
		return
	if is_instance_valid(active_ladder):
		_stop_climbing()
	_release_door()
	barrel_exit_transform = global_transform
	normal_camera_transform = camera.transform
	normal_collision_layer = collision_layer
	normal_collision_mask = collision_mask
	hiding_barrel = barrel
	is_peeking = false
	velocity = Vector3.ZERO
	is_sprinting = false
	footstep_timer = 0.0
	footstep_audio.stop()
	# Keep area detection active so enemies can notice the player when peeking.
	collision_mask = 0
	for light in [flashlight_1, $Camera3D/passive_light]:
		hidden_lights[light] = light.visible
		light.hide()
	flashlight_1.set_process_input(false)
	global_position = barrel.global_position
	camera.global_position = barrel.get_eye_position(false)
	_set_look_target("Inside barrel — Leave [E] | Peek [Q]")
	hiding_changed.emit(true, false)

func _process_barrel_hiding(delta: float) -> void:
	velocity = Vector3.ZERO
	stamina = min(stamina + MAX_STAMINA / STAMINA_REGEN_TIME * delta, MAX_STAMINA)
	if stamina >= MAX_STAMINA:
		stamina_locked = false
	stamina_changed.emit(stamina, MAX_STAMINA, false)
	_update_enemy_proximity(delta)
	if Input.is_action_just_pressed("interact"):
		_leave_barrel()
	elif Input.is_action_just_pressed("peek"):
		is_peeking = not is_peeking
		camera.global_position = hiding_barrel.get_eye_position(is_peeking)
		_set_look_target("Peeking — Leave [E] | Stop peeking [Q]" if is_peeking else "Inside barrel — Leave [E] | Peek [Q]")
		hiding_changed.emit(true, is_peeking)

func _leave_barrel() -> void:
	# Keep the player inside if another body has occupied the entry position.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = $CollisionShape3D.shape
	query.transform = barrel_exit_transform * $CollisionShape3D.transform
	query.collision_mask = normal_collision_mask
	query.exclude = [get_rid()]
	query.margin = 0.0
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		_set_look_target("Exit blocked — Retry [E] | %s [Q]" % ("Stop peeking" if is_peeking else "Peek"))
		return
	global_transform = barrel_exit_transform
	camera.transform = normal_camera_transform
	collision_layer = normal_collision_layer
	collision_mask = normal_collision_mask
	for light in hidden_lights:
		light.visible = hidden_lights[light]
	hidden_lights.clear()
	flashlight_1.set_process_input(true)
	hiding_barrel = null
	is_peeking = false
	velocity = Vector3.ZERO
	hiding_changed.emit(false, false)
	interaction_ray.force_raycast_update()
	_update_look_target()

func _set_look_target(target_name: String) -> void:
	if target_name != current_look_target_name:
		current_look_target_name = target_name
		look_target_changed.emit(current_look_target_name)

func _update_look_target() -> void:
	if is_instance_valid(held_door):
		_set_look_target("Holding knob — Move / drag | Release [LMB]")
		return
	interaction_ray.force_raycast_update()
	var target_name := ""
	if interaction_ray.is_colliding():
		var target := interaction_ray.get_collider() as Node
		if target != null and target.is_in_group("look_indicated") and target.has_method("get_interaction_label"):
			if not target.is_in_group("drag_door") or target.can_grab_at(interaction_ray.get_collision_point()):
				target_name = str(target.call("get_interaction_label"))
	if target_name.is_empty() and ladder_regrab_delay <= 0.0:
		for ladder in get_tree().get_nodes_in_group("climbable_ladder"):
			if ladder.can_climb(self, -1.0):
				target_name = "Ladder — Hold [W] to climb up | [S] to climb down"
				break

	_set_look_target(target_name)

#func _update_camera_bob(delta):
	#var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	#var is_moving = horizontal_speed > 0.1 and is_on_floor()

	#if is_moving:
		# Bob faster/stronger the faster the player is going (walk vs sprint vs crouch)
		#var speed_ratio = clamp(horizontal_speed / SPRINT_SPEED, 0.0, 1.0)
		#bob_timer += delta * MOVE_BOB_FREQUENCY * (1.0 + speed_ratio)
		#camera.position.y = camera_base_y + sin(bob_timer) * MOVE_BOB_AMPLITUDE * (0.5 + speed_ratio)
	#else:
		# Subtle idle "breathing" bob while standing still
		#bob_timer += delta * IDLE_BOB_FREQUENCY
		#camera.position.y = camera_base_y + sin(bob_timer) * IDLE_BOB_AMPLITUDE
		
func _update_footsteps(delta):
	# Check movement after collision resolution, rather than the requested speed.
	var actual_velocity := get_real_velocity()
	var horizontal_speed := Vector2(actual_velocity.x, actual_velocity.z).length()
	var has_movement_input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO
	var is_moving := has_movement_input and horizontal_speed > 0.1 and is_on_floor()

	if not is_moving:
		footstep_timer = 0.0
		footstep_audio.stop()
		return

	var footstep_interval = WALK_FOOTSTEP_INTERVAL

	if is_sprinting:
		footstep_interval = SPRINT_FOOTSTEP_INTERVAL
	elif Input.is_action_pressed("crouch"):
		footstep_interval = CROUCH_FOOTSTEP_INTERVAL

	footstep_timer -= delta

	if footstep_timer <= 0.0:
		footstep_audio.play()
		footstep_timer = footstep_interval

func _update_enemy_proximity(delta):
	# Find the nearest enemy (supports multiple enemies in the "enemy" group)
	var nearest_distance = INF
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy is Node3D:
			var dist = global_position.distance_to(enemy.global_position)
			if dist < nearest_distance:
				nearest_distance = dist

	# Pick the audio tier: 0 = far/no enemy, 1 = within 50m, 2 = within 15m, 3 = within 5m
	var tier = 0
	if nearest_distance <= ENEMY_TIER_CLOSE:
		tier = 3
	elif nearest_distance <= ENEMY_TIER_MID:
		tier = 2
	elif nearest_distance <= ENEMY_TIER_FAR:
		tier = 1

	# Log only when the tier actually changes, to avoid spamming the console every frame
	if tier != last_logged_tier:
		if nearest_distance < INF:
			print("Enemy proximity: ", TIER_NAMES[tier], " - distance: ", snapped(nearest_distance, 0.1), "m")
		else:
			print("Enemy proximity: ", TIER_NAMES[tier], " - no enemy in range")
		last_logged_tier = tier

	for i in audio_tiers.size():
		var player = audio_tiers[i]
		var target_db = 0.0 if i == tier else AUDIO_SILENT_DB
		player.volume_db = move_toward(player.volume_db, target_db, AUDIO_FADE_SPEED_DB * delta)
		if player.stream and player.volume_db > AUDIO_SILENT_DB + 1.0 and not player.playing:
			player.play()
		elif player.volume_db <= AUDIO_SILENT_DB + 0.1 and player.playing:
			player.stop()

	# Vignette gets stronger the closer the enemy is, on top of the base atmospheric vignette
	var proximity_ratio = 0.0
	if nearest_distance < INF:
		proximity_ratio = clamp(1.0 - (nearest_distance / ENEMY_TIER_FAR), 0.0, 1.0)
	var target_intensity = lerp(VIGNETTE_BASE_INTENSITY, VIGNETTE_MAX_INTENSITY, proximity_ratio)
	current_vignette_intensity = move_toward(current_vignette_intensity, target_intensity, VIGNETTE_FADE_SPEED * delta)
	vignette_intensity_changed.emit(current_vignette_intensity)

func _on_trigger_zone_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		print("Na-trigger ng Player ang zone!")
		# Dito mo ilalagay yung code pang-spawn ng kalaban sa susunod
		
func monster_seen():
	if scare_fov_tween != null and scare_fov_tween.is_valid():
		scare_fov_tween.kill()
	scare_fov_offset = danger_fov - normal_fov
	camera.fov = danger_fov + sprint_fov_boost * sprint_fov_blend
	scare_fov_tween = create_tween()
	scare_fov_tween.tween_property(self, "scare_fov_offset", 0.0, 0.5)
	# FOV movement when player saw the monster/enemy

func _input(event): #for menu ui or basically ui
	if event.is_action_pressed("menu"):
		get_tree().quit()
