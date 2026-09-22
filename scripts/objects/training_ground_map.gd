extends Node3D # Ito ang script ng MAPA, hindi ng Player

var enemy_scene = preload("res://scenes/enemies/enemy.tscn")
@onready var spawn_point = $SpawnPoint
@onready var trigger_zone = $TriggerZone

var is_already_triggered = false

func _on_trigger_zone_body_entered(body: Node3D) -> void:
	if is_already_triggered:
		return 
		
	if body.is_in_group("player"):
		is_already_triggered = true
		print("Na-trigger ng Player ang zone! Nag-i-spawn ng Enemy...")
		
		var new_enemy = enemy_scene.instantiate()
		
		# THE FIX: Tinanggal natin ang 'global_' sa new_enemy
		new_enemy.position = spawn_point.global_position
		
		call_deferred("add_child", new_enemy)
