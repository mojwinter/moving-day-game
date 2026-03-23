extends Node2D
## Scene controller for the Net/Rotation puzzle.
## Manages progressive tiers with escalating grid sizes and mechanics.

const SCREEN_SIZE := Vector2(320, 180)
const HUD_HEIGHT := 16.0  ## Space reserved at top for tier info + new button
var grid_offset := Vector2.ZERO  ## Computed per tier to center the grid
const NEW_BTN_RECT := Rect2(2, 2, 24, 12)

const TileScene := preload("res://scenes/net_puzzle/tile.tscn")
const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")

@onready var grid_manager = $GridManager

## Tier definitions: each tier adds a new mechanic on top of previous ones.
## { w, h, wrapping, fog, decay, decay_interval }
const TIERS := [
	{ "w": 3, "h": 3, "wrapping": false, "fog": false, "decay": false, "decay_interval": 0.0 },
	{ "w": 4, "h": 4, "wrapping": false, "fog": false, "decay": false, "decay_interval": 0.0 },
	{ "w": 5, "h": 5, "wrapping": false, "fog": false, "decay": false, "decay_interval": 0.0 },
	{ "w": 6, "h": 6, "wrapping": false, "fog": true,  "decay": false, "decay_interval": 0.0 },
	{ "w": 7, "h": 7, "wrapping": false, "fog": true,  "decay": false, "decay_interval": 0.0 },
	{ "w": 8, "h": 8, "wrapping": false, "fog": false, "decay": true,  "decay_interval": 5.0 },
	{ "w": 9, "h": 9, "wrapping": false, "fog": true,  "decay": true,  "decay_interval": 5.0 },
]

var current_tier: int = 0
var tile_nodes: Array = []
var cell_size: float = 20.0
var _win_tween: Tween = null
var _frame_texture: Texture2D = null
var _frame_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)
	_start_tier(0)


func _start_tier(tier: int) -> void:
	current_tier = clampi(tier, 0, TIERS.size() - 1)
	var t: Dictionary = TIERS[current_tier]

	cell_size = 16.0

	# Center the grid on screen relative to this node's position
	var grid_w_px: float = t["w"] * cell_size
	var grid_h_px: float = t["h"] * cell_size
	grid_offset = Vector2(
		floorf((SCREEN_SIZE.x - grid_w_px) / 2.0) - global_position.x,
		floorf((SCREEN_SIZE.y - grid_h_px) / 2.0) - global_position.y
	)

	# Clear old tiles
	for tile_node in tile_nodes:
		tile_node.queue_free()
	tile_nodes.clear()

	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
		_win_tween = null

	# Load frame for this grid size
	var frame_path := "res://assets/network/frame%dx%d.png" % [t["w"], t["h"]]
	if ResourceLoader.exists(frame_path):
		_frame_texture = load(frame_path)
		# Center the frame around the grid
		var frame_size := _frame_texture.get_size()
		_frame_pos = Vector2(
			floorf(grid_offset.x + grid_w_px / 2.0 - frame_size.x / 2.0),
			floorf(grid_offset.y + grid_h_px / 2.0 - frame_size.y / 2.0)
		)
	else:
		_frame_texture = null

	grid_manager.setup_and_generate(
		t["w"], t["h"],
		t["wrapping"],
		t["fog"], t["decay"], t["decay_interval"]
	)
	_create_tile_nodes()
	_refresh_all_tiles()
	queue_redraw()


func _create_tile_nodes() -> void:
	var gw: int = grid_manager.grid_width
	var gh: int = grid_manager.grid_height
	for y in range(gh):
		for x in range(gw):
			var tile_node = TileScene.instantiate()
			tile_node.setup(x, y, cell_size)
			tile_node.position = grid_offset + Vector2(x * cell_size, y * cell_size)
			tile_node.tile_clicked.connect(_on_tile_clicked)
			add_child(tile_node)
			tile_nodes.append(tile_node)


# =========================================================================
# Drawing — HUD
# =========================================================================

func _draw() -> void:
	# Frame behind the grid
	if _frame_texture:
		draw_texture(_frame_texture, _frame_pos)

	var font_size := 16

	# "New" button
	draw_rect(NEW_BTN_RECT, Color(0.25, 0.23, 0.2))
	draw_rect(NEW_BTN_RECT, Color(0.4, 0.38, 0.35), false)
	var txt := "New"
	var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := PIXEL_FONT.get_ascent(font_size)
	var descent := PIXEL_FONT.get_descent(font_size)
	var text_h := ascent + descent
	var tx := NEW_BTN_RECT.position.x + (NEW_BTN_RECT.size.x - ts.x) / 2.0
	var ty := NEW_BTN_RECT.position.y + (NEW_BTN_RECT.size.y - text_h) / 2.0 + ascent
	draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.8, 0.8, 0.7))

	# Tier indicator
	var tier_txt := "Tier " + str(current_tier + 1)
	var t: Dictionary = TIERS[current_tier]
	var size_txt := str(t["w"]) + "x" + str(t["h"])
	var info_parts := [size_txt]
	if t["fog"]:
		info_parts.append("fog")
	if t["wrapping"]:
		info_parts.append("wrap")
	if t["decay"]:
		info_parts.append("decay")
	var info_txt := " ".join(info_parts)

	draw_string(PIXEL_FONT, Vector2(32, ascent + 2), tier_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.85, 0.5))
	draw_string(PIXEL_FONT, Vector2(32, ascent + 2 + text_h), info_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.55, 0.55, 0.5))


# =========================================================================
# Input
# =========================================================================

func _on_tile_clicked(x: int, y: int) -> void:
	var gw: int = grid_manager.grid_width
	var idx := y * gw + x
	var td = grid_manager.tiles[idx]

	# Capture pre-rotation state for the clicked tile
	var old_conns: int = td.connections
	var old_active: bool = td.is_active

	# Rotate bitmask only — no BFS/fog/win yet
	grid_manager.rotate_tile_silent(x, y)

	# Refresh so the tile knows its new connections (for _draw after anim ends)
	_refresh_all_tiles()

	# Kick off visual rotation on the clicked tile
	tile_nodes[idx].start_rotate_anim(old_conns, old_active)

	# After animation, recompute everything
	var tween := create_tween()
	tween.tween_interval(tile_nodes[idx].ROTATE_TIME)
	tween.tween_callback(_finish_rotate_anim)


func _finish_rotate_anim() -> void:
	# Now recompute BFS, fog, win check, and refresh visuals
	grid_manager.recompute_and_check()
	_refresh_all_tiles()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = event.global_position - global_position
		if NEW_BTN_RECT.has_point(local):
			_start_tier(current_tier)
			get_viewport().set_input_as_handled()

	# Debug: N = next tier, P = previous tier
	if OS.is_debug_build() and event is InputEventKey and event.pressed:
		if event.keycode == KEY_N:
			_start_tier(current_tier + 1)
		elif event.keycode == KEY_P:
			_start_tier(current_tier - 1)


# =========================================================================
# Puzzle solved -> advance tier
# =========================================================================

func _on_puzzle_solved() -> void:
	_play_win_highlight(_advance_tier)


func _advance_tier() -> void:
	if current_tier < TIERS.size() - 1:
		_start_tier(current_tier + 1)
	else:
		# Already at max tier — restart it (infinite replay at hardest)
		_start_tier(current_tier)


func _on_grid_changed() -> void:
	# Called by grid_manager when decay rotates a tile (or during generate_puzzle).
	# Guard: tile_nodes may not exist yet during initial generation.
	if tile_nodes.is_empty():
		return
	_refresh_all_tiles()


# =========================================================================
# Win animation
# =========================================================================

func _play_win_highlight(next_callback: Callable) -> void:
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	_win_tween.set_parallel(true)
	var delay := 0.0
	var gw: int = grid_manager.grid_width
	var gh: int = grid_manager.grid_height
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			if (grid_manager.tiles[idx].connections & 0x0F) == 0:
				continue
			var node = tile_nodes[idx]
			node.highlight = 1.0
			_win_tween.tween_property(node, "highlight", 0.0, 0.6).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			delay += 0.03
	_win_tween.finished.connect(next_callback)


# =========================================================================
# Helpers
# =========================================================================

func _refresh_all_tiles() -> void:
	var gw: int = grid_manager.grid_width
	var gh: int = grid_manager.grid_height
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			tile_nodes[idx].refresh(grid_manager.tiles[idx])
