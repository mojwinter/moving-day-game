extends Node2D
## Wires together the couch interaction, TV selector, and puzzle switcher.

@onready var _player: CharacterBody2D = $Player
@onready var _couch_interaction: Area2D = $CouchInteraction
@onready var _tv_selector: Control = $TvSelectorLayer/TvSelector
@onready var _puzzle_switcher: Node2D = $PuzzleSwitcher
@onready var _tv: AnimatedSprite2D = $ObjectLayers/TV


func _ready() -> void:
	_couch_interaction.interacted.connect(_on_couch_interacted)
	_tv_selector.play_pressed.connect(_on_play_pressed)
	_tv_selector.transition_finished.connect(_on_transition_finished)
	_tv_selector.closed.connect(_on_selector_closed)
	_puzzle_switcher.puzzle_exited.connect(_on_puzzle_exited)


func _on_couch_interacted() -> void:
	_player.can_move = false
	_tv.set_process(false)
	_tv_selector.open()


func _on_play_pressed(scene_path: String) -> void:
	_puzzle_switcher.launch_puzzle(scene_path)


func _on_transition_finished() -> void:
	_tv_selector.visible = false


func _on_selector_closed() -> void:
	_player.can_move = true
	_tv.set_process(true)


func _on_puzzle_exited() -> void:
	_tv_selector.open()
