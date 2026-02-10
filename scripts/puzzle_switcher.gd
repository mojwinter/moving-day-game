extends Node2D
## Debug scene switcher for testing puzzles.
## Press 1 for Net Puzzle, 2 for Tracks Puzzle.

const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")

var _puzzle_scenes := {
	KEY_1: "res://scenes/net_puzzle/net_puzzle.tscn",
	KEY_2: "res://scenes/tracks_puzzle/tracks_puzzle.tscn",
}

var _current_key: int = KEY_2
var _current_child: Node = null


func _ready() -> void:
	_load_puzzle(_current_key)


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in _puzzle_scenes and event.keycode != _current_key:
			_load_puzzle(event.keycode)


func _load_puzzle(key: int) -> void:
	if _current_child:
		_current_child.queue_free()
		_current_child = null

	_current_key = key
	var scene := load(_puzzle_scenes[key]) as PackedScene
	_current_child = scene.instantiate()
	add_child(_current_child)
	queue_redraw()


func _draw() -> void:
	var hint: String = "[1] Circuit  [2] Tracks"
	draw_string(PIXEL_FONT, Vector2(2, 178), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.5, 0.5, 0.5, 0.6))
