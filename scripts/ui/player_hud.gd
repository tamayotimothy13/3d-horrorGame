extends CanvasLayer

const STAMINA_BAR_FADE_IN_SPEED = 6.0
const STAMINA_BAR_FADE_OUT_SPEED = 1.5

@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var vignette_material: ShaderMaterial = $Vignette.material
@onready var look_target_label: Label = $LookTargetLabel
@onready var note_counter_label: Label = $NoteCounterLabel

var stamina_bar_target_alpha = 0.0
var total_notes = 0
var completed_notes = 0

func _ready() -> void:
	var players = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		push_error("Player HUD could not find a node in the player group.")
		return

	var player = players[0]
	player.connect("stamina_changed", _on_stamina_changed)
	player.connect("vignette_intensity_changed", _on_vignette_intensity_changed)
	player.connect("look_target_changed", _on_look_target_changed)
	player.connect("countable_interactable_completed", _on_countable_interactable_completed)

	var state: Dictionary = player.call("get_hud_state")
	_on_stamina_changed(state["stamina"], state["max_stamina"], state["is_sprinting"])
	_on_vignette_intensity_changed(state["vignette_intensity"])
	_on_look_target_changed(player.call("get_look_target_name"))
	_on_countable_interactable_completed(state["countable_interactable_count"])
	call_deferred("_refresh_note_total")

func _process(delta: float) -> void:
	var fade_speed = STAMINA_BAR_FADE_IN_SPEED if stamina_bar_target_alpha > stamina_bar.modulate.a else STAMINA_BAR_FADE_OUT_SPEED
	stamina_bar.modulate.a = move_toward(stamina_bar.modulate.a, stamina_bar_target_alpha, fade_speed * delta)

func _on_stamina_changed(value: float, max_value: float, is_sprinting: bool) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
	stamina_bar_target_alpha = 1.0 if is_sprinting else 0.0

func _on_vignette_intensity_changed(intensity: float) -> void:
	vignette_material.set_shader_parameter("intensity", intensity)

func _on_look_target_changed(target_name: String) -> void:
	look_target_label.text = target_name
	look_target_label.visible = not target_name.is_empty()

func _on_countable_interactable_completed(count: int) -> void:
	completed_notes = count
	_update_note_counter()

func _refresh_note_total() -> void:
	total_notes = get_tree().get_nodes_in_group("countable_interactable").size()
	_update_note_counter()

func _update_note_counter() -> void:
	note_counter_label.text = "Notes: %d / %d" % [completed_notes, total_notes]
	note_counter_label.visible = total_notes > 0
