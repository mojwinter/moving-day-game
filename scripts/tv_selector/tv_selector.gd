extends Control
## Fullscreen TV puzzle selector with Geometry Dash-style carousel.
## Opened from the couch interaction, shows puzzle cards to browse and launch.

signal play_pressed(scene_path: String)
signal closed

const CARD_WIDTH := 240.0
const SLIDE_DURATION := 0.3
const COMING_SOON_DURATION := 1.5

var _puzzle_data := [
	{"name": "NET PUZZLE", "path": "res://scenes/net_puzzle/net_puzzle.tscn", "color": Color(0.12, 0.18, 0.35)},
	{"name": "TRACKS", "path": "res://scenes/tracks_puzzle/tracks_puzzle.tscn", "color": Color(0.12, 0.3, 0.15)},
	{"name": "LOOPY", "path": "res://scenes/loopy_puzzle/loopy_puzzle.tscn", "color": Color(0.25, 0.12, 0.35)},
]

var _current_index := 0
var _tweening := false
var _button_focused := 0  # 0 = Play, 1 = Custom

@onready var _cards: Array[Control] = []
@onready var _card_container: Control = $ViewportContainer/SubViewport/CardContainer
@onready var _arrow_left: Label = $ViewportContainer/SubViewport/ArrowLeft
@onready var _arrow_right: Label = $ViewportContainer/SubViewport/ArrowRight
@onready var _play_btn: Label = $ViewportContainer/SubViewport/ButtonRow/PlayButton
@onready var _custom_btn: Label = $ViewportContainer/SubViewport/ButtonRow/CustomButton
@onready var _dots: HBoxContainer = $ViewportContainer/SubViewport/PageDots
@onready var _coming_soon: Label = $ViewportContainer/SubViewport/ComingSoon
@onready var _static_player: AnimatedSprite2D = $StaticTransition

var _arrow_tween_l: Tween
var _arrow_tween_r: Tween


func _ready() -> void:
	visible = false
	_coming_soon.visible = false
	_static_player.visible = false
	for child in _card_container.get_children():
		_cards.append(child as Control)
	_update_cards()
	_update_dots()
	_update_buttons()
	_start_arrow_pulse()


func open() -> void:
	_current_index = 0
	_button_focused = 0
	_update_cards()
	_update_dots()
	_update_buttons()
	visible = true
	_play_static_transition()


func close() -> void:
	visible = false
	closed.emit()


func _play_static_transition() -> void:
	_static_player.visible = true
	_static_player.play(&"static")
	# Hide cards during static, show after
	_card_container.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_interval(0.35)
	tween.tween_callback(func():
		_static_player.visible = false
		_card_container.modulate.a = 1.0
	)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_left"):
		_cycle(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_cycle(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
		_button_focused = 1 - _button_focused
		_update_buttons()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("interact"):
		_on_button_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _cycle(dir: int) -> void:
	if _tweening:
		return
	var new_index := wrapi(_current_index + dir, 0, _cards.size())
	if new_index == _current_index:
		return

	_tweening = true
	var old_card := _cards[_current_index]
	var new_card := _cards[new_index]

	# Position new card off-screen on the side we're coming from
	new_card.visible = true
	new_card.position.x = CARD_WIDTH * dir

	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(old_card, "position:x", -CARD_WIDTH * dir, SLIDE_DURATION)
	tween.tween_property(new_card, "position:x", 0.0, SLIDE_DURATION)
	tween.chain().tween_callback(func():
		old_card.visible = false
		_current_index = new_index
		_tweening = false
		_update_dots()
	)


func _on_button_pressed() -> void:
	if _button_focused == 0:
		# Play
		var path: String = _puzzle_data[_current_index]["path"]
		play_pressed.emit(path)
	else:
		# Custom - coming soon
		_show_coming_soon()


func _show_coming_soon() -> void:
	_coming_soon.visible = true
	_coming_soon.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.8)
	tween.tween_property(_coming_soon, "modulate:a", 0.0, 0.7)
	tween.tween_callback(func(): _coming_soon.visible = false)


func _update_cards() -> void:
	for i in _cards.size():
		_cards[i].visible = (i == _current_index)
		_cards[i].position.x = 0.0


func _update_dots() -> void:
	var dot_index := 0
	for child in _dots.get_children():
		var dot := child as ColorRect
		if dot == null:
			continue
		dot.color = Color.WHITE if dot_index == _current_index else Color(0.4, 0.4, 0.4)
		dot_index += 1


func _update_buttons() -> void:
	_play_btn.modulate = Color.WHITE if _button_focused == 0 else Color(0.5, 0.5, 0.5)
	_custom_btn.modulate = Color.WHITE if _button_focused == 1 else Color(0.5, 0.5, 0.5)
	# Underline or highlight the focused button
	if _button_focused == 0:
		_play_btn.text = "> PLAY <"
		_custom_btn.text = "CUSTOM"
	else:
		_play_btn.text = "PLAY"
		_custom_btn.text = "> CUSTOM <"


func _start_arrow_pulse() -> void:
	_arrow_tween_l = create_tween().set_loops()
	_arrow_tween_l.tween_property(_arrow_left, "modulate:a", 0.4, 0.5)
	_arrow_tween_l.tween_property(_arrow_left, "modulate:a", 1.0, 0.5)
	_arrow_tween_r = create_tween().set_loops()
	_arrow_tween_r.tween_property(_arrow_right, "modulate:a", 0.4, 0.5)
	_arrow_tween_r.tween_property(_arrow_right, "modulate:a", 1.0, 0.5)
