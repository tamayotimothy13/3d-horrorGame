extends OmniLight3D

@export var normal_energy := 5.0

func _process(_delta):
	var chance = randf()

	if chance < 0.03:
		light_energy = 0.0
	elif chance < 0.10:
		light_energy = randf_range(0.1, 0.4)
	else:
		light_energy = normal_energy
