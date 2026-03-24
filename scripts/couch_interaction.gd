extends Area2D
## Detects when the player is near the couch and shows an interact prompt.
## Emits "interacted" when the player presses the interact key.

signal interacted

var _player_inside := false
var _bounce_tween: Tween

@onready var _prompt: Label = $Prompt


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_prompt.visible = false


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = true
		_prompt.visible = true
		_start_bounce()


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_inside = false
		_prompt.visible = false
		_stop_bounce()


func _input(event: InputEvent) -> void:
	if _player_inside and event.is_action_pressed("interact"):
		interacted.emit()
		get_viewport().set_input_as_handled()


func _start_bounce() -> void:
	_stop_bounce()
	_bounce_tween = create_tween().set_loops()
	_bounce_tween.tween_property(_prompt, "position:y", _prompt.position.y - 2.0, 0.3)
	_bounce_tween.tween_property(_prompt, "position:y", _prompt.position.y, 0.3)


func _stop_bounce() -> void:
	if _bounce_tween:
		_bounce_tween.kill()
		_bounce_tween = null
