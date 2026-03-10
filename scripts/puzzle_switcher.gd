extends Node2D
## Debug scene switcher for testing puzzles.
## Press 1 for Net Puzzle, 2 for Tracks Puzzle, 3 for Loopy.
## Press Escape to return to the main screen.


var _puzzle_scenes := {
	KEY_1: "res://scenes/net_puzzle/net_puzzle.tscn",
	KEY_2: "res://scenes/tracks_puzzle/tracks_puzzle.tscn",
	KEY_3: "res://scenes/loopy_puzzle/loopy_puzzle.tscn",
}

var _current_key: int = -1
var _current_child: Node = null
var _is_embedded: bool = false


func _ready() -> void:
	_is_embedded = get_parent() != get_tree().root
	if _is_embedded:
		visible = false
	else:
		_load_puzzle(KEY_2)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in _puzzle_scenes and event.keycode != _current_key:
			_load_puzzle(event.keycode)
		elif event.keycode == KEY_ESCAPE and _is_embedded and _current_child:
			_unload_puzzle()


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


func _unload_puzzle() -> void:
	if _current_child:
		_current_child.queue_free()
		_current_child = null
	_current_key = -1
	visible = false
	_set_siblings_visible(true)


func _set_siblings_visible(should_show: bool) -> void:
	for sibling in get_parent().get_children():
		if sibling != self and sibling is CanvasItem:
			sibling.visible = should_show
