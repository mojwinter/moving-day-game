extends Node2D
## Manages loading and unloading puzzle scenes.
## In debug builds, press 1/2/3 to switch puzzles directly.
## Press Escape to return from a puzzle.

signal puzzle_exited

var _puzzle_scenes := {
	KEY_1: "res://scenes/net_puzzle/net_puzzle.tscn",
	KEY_2: "res://scenes/tracks_puzzle/tracks_puzzle.tscn",
	KEY_3: "res://scenes/loopy_puzzle/loopy_puzzle.tscn",
}

var _current_child: Node = null
var _current_key: int = -1
var _is_embedded: bool = false


func _ready() -> void:
	_is_embedded = get_parent() != get_tree().root
	if _is_embedded:
		visible = false
	else:
		_load_puzzle(KEY_2)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _is_embedded and _current_child:
			exit_puzzle()
		elif OS.is_debug_build():
			if event.keycode in _puzzle_scenes and event.keycode != _current_key:
				_load_puzzle(event.keycode)


func launch_puzzle(scene_path: String) -> void:
	if _current_child:
		_current_child.queue_free()
		_current_child = null

	_current_key = -1
	var scene := load(scene_path) as PackedScene
	_current_child = scene.instantiate()
	add_child(_current_child)
	visible = true
	if _is_embedded:
		_set_siblings_visible(false)


func exit_puzzle() -> void:
	if _current_child:
		_current_child.queue_free()
		_current_child = null
	_current_key = -1
	visible = false
	_set_siblings_visible(true)
	puzzle_exited.emit()


func _load_puzzle(key: int) -> void:
	if _current_child:
		_current_child.queue_free()
		_current_child = null

	_current_key = key
	var scene := load(_puzzle_scenes[key]) as PackedScene
	_current_child = scene.instantiate()
	add_child(_current_child)
	visible = true
	if _is_embedded:
		_set_siblings_visible(false)
	queue_redraw()


func _set_siblings_visible(should_show: bool) -> void:
	for sibling in get_parent().get_children():
		if sibling != self and sibling is CanvasItem:
			sibling.visible = should_show
