extends CharacterBody3D

signal stamina_changed(value: float, max_value: float, is_sprinting: bool)
signal vignette_intensity_changed(intensity: float)
signal look_target_changed(target_name: String)
signal countable_interactable_completed(count: int)

const SPRINT_SPEED = 11
var SPEED = 7
const JUMP_VELOCITY = 25
const CROUCH_SPEED = 9
var normal_fov = 75.0
var danger_fov = 100.0

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
var completed_countable_interactable_ids: Dictionary = {}
var completed_countable_interactable_count = 0
var last_logged_tier = -1 # used to only print when the enemy proximity tier changes
const TIER_NAMES = ["FAR (>50m)", "TIER 50m", "TIER 15m", "TIER 5m"]

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
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
	}

func get_look_target_name() -> String:
	return current_look_target_name

func _unhandled_input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * 0.005)
		camera.rotate_x(-event.relative.y * 0.005)
		camera.rotation.x = clamp(camera.rotation.x, deg_to_rad(-80), deg_to_rad(80))
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta): # all movment code inside this
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
	_update_footsteps(delta)
	_update_enemy_proximity(delta)
	_update_look_target()

	# Handles the interaction mechanic
	if Input.is_action_just_pressed("interact"):
		if interaction_ray.is_colliding():
			var item = interaction_ray.get_collider()
			
			if item.is_in_group("interactable"):
				item.interact()
				if item.is_in_group("countable_interactable"):
					var item_id = item.get_instance_id()
					if not completed_countable_interactable_ids.has(item_id):
						completed_countable_interactable_ids[item_id] = true
						completed_countable_interactable_count += 1
						countable_interactable_completed.emit(completed_countable_interactable_count)

	move_and_slide()

func _update_look_target() -> void:
	var target_name := ""
	if interaction_ray.is_colliding():
		var target := interaction_ray.get_collider() as Node
		if target != null and target.is_in_group("look_indicated") and target.has_method("get_interaction_label"):
			target_name = str(target.call("get_interaction_label"))

	if target_name != current_look_target_name:
		current_look_target_name = target_name
		look_target_changed.emit(current_look_target_name)

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
	var horizontal_speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = horizontal_speed > 0.1 and is_on_floor()

	if not is_moving:
		footstep_timer = 0.0
		return

	var footstep_interval = WALK_FOOTSTEP_INTERVAL

	if Input.is_action_pressed("sprint") and horizontal_speed > 20.0:
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
	camera.fov = 100.0
	
	var tween = create_tween()
	tween.tween_property(camera, "fov", 75.0, 0.5)
	# FOV movement when player saw the monster/enemy

func _input(event): #for menu ui or basically ui
	if event.is_action_pressed("menu"):
		get_tree().quit()
