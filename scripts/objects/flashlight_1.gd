extends SpotLight3D

@onready var flashlight = self
@export var normal_energy := 1.0

func _input(event):
	if event.is_action_pressed("flashlight"):
		flashlight.visible = !flashlight.visible
		
var malfunction_timer := 0.0
var malfunctioning := false

func _ready():
	randomize()
	malfunction_timer = randf_range(5.0, 12.0)
	light_energy = normal_energy

func _process(delta):
	if not malfunctioning:
		malfunction_timer -= delta

		if malfunction_timer <= 0:
			start_malfunction()

func start_malfunction():
	malfunctioning = true
	
	# Broken flashlight sputtering
	for i in range(randi_range(3, 7)):
		light_energy = randf_range(0.1, 0.5)
		await get_tree().create_timer(randf_range(0.03, 0.12)).timeout
		
		light_energy = normal_energy
		await get_tree().create_timer(randf_range(0.03, 0.15)).timeout
	
	# Back to normal
	light_energy = normal_energy
	malfunctioning = false
	
	# Wait several seconds before another malfunction
	malfunction_timer = randf_range(5.0, 15.0)
