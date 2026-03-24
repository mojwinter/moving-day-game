extends Control
## Fullscreen TV puzzle selector with Geometry Dash-style carousel.
## Opened from the couch interaction, shows puzzle cards to browse and launch.

signal play_pressed(scene_path: String)
signal transition_finished
signal closed

const CARD_WIDTH := 240.0
const SLIDE_DURATION := 0.3
const COMING_SOON_DURATION := 1.5
const CRT_EXPAND_DURATION := 0.8

var _puzzle_data := [
	{"name": "NET PUZZLE", "path": "res://scenes/net_puzzle/net_puzzle.tscn", "color": Color(0.12, 0.18, 0.35)},
	{"name": "TRACKS", "path": "res://scenes/tracks_puzzle/tracks_puzzle.tscn", "color": Color(0.12, 0.3, 0.15)},
	{"name": "LOOPY", "path": "res://scenes/loopy_puzzle/loopy_puzzle.tscn", "color": Color(0.25, 0.12, 0.35)},
]

var _current_index := 0
var _tweening := false
var _expanding := false
var _button_focused := 0  # 0 = Play, 1 = Custom
var _accept_input_after := 0.0

@onready var _cards: Array[Control] = []
@onready var _card_container: Control = $ViewportContainer/SubViewport/CardContainer
@onready var _arrow_left: Label = $TextOverlay/ArrowLeft
@onready var _arrow_right: Label = $TextOverlay/ArrowRight
@onready var _play_btn: Label = $TextOverlay/ButtonRow/PlayButton
@onready var _custom_btn: Label = $TextOverlay/ButtonRow/CustomButton
@onready var _dots: HBoxContainer = $TextOverlay/PageDots
@onready var _coming_soon: Label = $TextOverlay/ComingSoon
@onready var _text_overlay: Control = $TextOverlay
@onready var _static_player: AnimatedSprite2D = $StaticTransition
@onready var _crt_overlay: ColorRect = $ViewportContainer/SubViewport/CRTOverlay
@onready var _wipe_overlay: ColorRect = $WipeOverlay

var _arrow_tween_l: Tween
var _arrow_tween_r: Tween
var _crt_defaults: Dictionary


const _CRT_PARAMS := [&"warp_amount", &"vignette_opacity", &"scanlines_opacity",
	&"aberration", &"grille_opacity", &"static_mix", &"static_opacity", &"scanline_wipe", &"brightness"]


func _ready() -> void:
	visible = false
	_coming_soon.visible = false
	_static_player.visible = false
	# Capture default CRT shader values for reset
	var mat: ShaderMaterial = _crt_overlay.material
	for p in _CRT_PARAMS:
		_crt_defaults[p] = mat.get_shader_parameter(p)
	for child in _card_container.get_children():
		_cards.append(child as Control)
	_update_cards()
	_update_dots()
	_update_buttons()
	_start_arrow_pulse()


func _reset_crt_params() -> void:
	var mat: ShaderMaterial = _crt_overlay.material
	for p in _crt_defaults:
		mat.set_shader_parameter(p, _crt_defaults[p])


func open() -> void:
	_current_index = 0
	_button_focused = 0
	_update_cards()
	_update_dots()
	_update_buttons()
	visible = true
	_accept_input_after = Time.get_ticks_msec() + 200.0
	_play_power_on()


func close() -> void:
	visible = false
	closed.emit()


func _play_power_on() -> void:
	_expanding = true
	_crt_overlay.visible = true
	var mat: ShaderMaterial = _crt_overlay.material
	# Start dark, flat (no warp), with full static at low opacity
	mat.set_shader_parameter("brightness", 0.0)
	mat.set_shader_parameter("static_mix", 1.0)
	mat.set_shader_parameter("static_opacity", 0.3)
	mat.set_shader_parameter("warp_amount", 0.0)
	mat.set_shader_parameter("vignette_opacity", 0.0)
	mat.set_shader_parameter("scanlines_opacity", 0.0)
	# Text overlay starts invisible
	_text_overlay.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel()
	# Slowly fade brightness up
	tween.tween_method(func(v: float): mat.set_shader_parameter("brightness", v),
		0.0, _crt_defaults[&"brightness"], 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Fade static opacity out
	tween.tween_method(func(v: float): mat.set_shader_parameter("static_opacity", v),
		0.3, 0.0, 1.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Fade text in alongside brightness
	tween.tween_property(_text_overlay, "modulate:a", 1.0, 1.2
		).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Warp back into CRT shape
	tween.tween_method(func(v: float): mat.set_shader_parameter("warp_amount", v),
		0.0, _crt_defaults[&"warp_amount"], 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(v: float): mat.set_shader_parameter("vignette_opacity", v),
		0.0, _crt_defaults[&"vignette_opacity"], 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(func(v: float): mat.set_shader_parameter("scanlines_opacity", v),
		0.0, _crt_defaults[&"scanlines_opacity"], 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.chain().tween_callback(func():
		mat.set_shader_parameter("static_mix", 0.0)
		mat.set_shader_parameter("static_opacity", 1.0)
		_expanding = false)



func _input(event: InputEvent) -> void:
	if not visible or _expanding:
		return
	if Time.get_ticks_msec() < _accept_input_after:
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
		# Play — animate CRT warp to fullscreen, then emit
		var path: String = _puzzle_data[_current_index]["path"]
		_play_crt_expand(path)
	else:
		# Custom - coming soon
		_show_coming_soon()


func _play_crt_expand(scene_path: String) -> void:
	_expanding = true
	_crt_overlay.visible = true
	_text_overlay.modulate.a = 1.0
	var mat: ShaderMaterial = _crt_overlay.material

	# Phase 1: CRT unwarp + fade out text (parallel)
	var unwarp := create_tween().set_parallel()
	unwarp.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	unwarp.tween_property(_text_overlay, "modulate:a", 0.0, CRT_EXPAND_DURATION)
	unwarp.tween_method(func(v: float): mat.set_shader_parameter("warp_amount", v),
		_crt_defaults[&"warp_amount"], 0.0, CRT_EXPAND_DURATION)
	unwarp.tween_method(func(v: float): mat.set_shader_parameter("vignette_opacity", v),
		_crt_defaults[&"vignette_opacity"], 0.0, CRT_EXPAND_DURATION)
	unwarp.tween_method(func(v: float): mat.set_shader_parameter("scanlines_opacity", v),
		_crt_defaults[&"scanlines_opacity"], 0.0, CRT_EXPAND_DURATION * 0.6)
	unwarp.tween_method(func(v: float): mat.set_shader_parameter("aberration", v),
		_crt_defaults[&"aberration"], 0.0, CRT_EXPAND_DURATION * 0.5)
	unwarp.tween_method(func(v: float): mat.set_shader_parameter("grille_opacity", v),
		_crt_defaults[&"grille_opacity"], 0.0, CRT_EXPAND_DURATION * 0.6)
	await unwarp.finished

	# Launch puzzle underneath, hide the TV UI, use screen-level wipe overlay
	play_pressed.emit(scene_path)
	$ViewportContainer.visible = false
	_wipe_overlay.visible = true
	var wipe_mat: ShaderMaterial = _wipe_overlay.material
	wipe_mat.set_shader_parameter("scanline_wipe", -0.1)

	# Phase 2: Scanline wipe reveals the puzzle below
	var wipe := create_tween()
	wipe.tween_method(func(v: float): wipe_mat.set_shader_parameter("scanline_wipe", v),
		-0.1, 1.1, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await wipe.finished

	_expanding = false
	_wipe_overlay.visible = false
	$ViewportContainer.visible = true
	_crt_overlay.visible = false
	_reset_crt_params()
	wipe_mat.set_shader_parameter("scanline_wipe", -0.1)
	transition_finished.emit()


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
