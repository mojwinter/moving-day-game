extends Node2D
## Scene controller for the Net/Rotation puzzle.
## Manages progressive tiers with escalating grid sizes and mechanics.

const SCREEN_SIZE := Vector2(320, 180)
var grid_offset := Vector2.ZERO  ## Computed per tier to center the grid

const TileScene := preload("res://scenes/net_puzzle/tile.tscn")

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
var _flash_rect: ColorRect = null  ## Screen flash overlay


func _ready() -> void:
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)
	# Create flash overlay on a high z-index so it draws above tiles
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	_flash_rect.size = SCREEN_SIZE
	_flash_rect.position = -global_position
	_flash_rect.z_index = 100
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_flash_rect)
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
			# Set initial fog state instantly (no animation on tier start)
			var idx := y * gw + x
			tile_node.reset_fog(grid_manager.tiles[idx].is_revealed)


# =========================================================================
# Drawing — HUD
# =========================================================================

func _draw() -> void:
	# Frame behind the grid
	if _frame_texture:
		draw_texture(_frame_texture, _frame_pos)


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
# Win animation — soft BFS ripple
# =========================================================================

const WIN_FLASH_ALPHA := 0.03       ## Very subtle white flash
const WIN_FLASH_FADE := 0.6         ## Slow flash fade-out
const WIN_RIPPLE_DELAY := 0.06      ## Stagger per BFS hop (slower wave)
const WIN_RISE_TIME := 0.3          ## Time to ease highlight up to peak
const WIN_HOLD_TIME := 0.15         ## Brief hold at peak
const WIN_FADE_TIME := 0.5          ## Time to ease highlight back down
const WIN_PEAK := 0.7               ## Peak highlight intensity (not full)

func _play_win_highlight(next_callback: Callable) -> void:
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()

	var gw: int = grid_manager.grid_width
	var gh: int = grid_manager.grid_height

	# — Subtle screen flash —
	_flash_rect.color = Color(1.0, 1.0, 1.0, WIN_FLASH_ALPHA)

	_win_tween = create_tween()
	_win_tween.set_parallel(true)

	# Flash fade-out
	_win_tween.tween_property(_flash_rect, "color:a", 0.0, WIN_FLASH_FADE).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# — BFS-distance ripple: gentle rise → hold → fade per tile —
	var max_dist := 0
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			var d: int = grid_manager.tiles[idx].bfs_distance
			if d > max_dist:
				max_dist = d

	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			if (grid_manager.tiles[idx].connections & 0x0F) == 0:
				continue
			var node = tile_nodes[idx]
			var dist: int = grid_manager.tiles[idx].bfs_distance
			if dist < 0:
				dist = max_dist + 1
			var delay: float = dist * WIN_RIPPLE_DELAY

			# Rise gently to peak
			_win_tween.tween_property(node, "highlight", WIN_PEAK, WIN_RISE_TIME).set_delay(delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			# Hold briefly, then fade back down
			_win_tween.tween_property(node, "highlight", 0.0, WIN_FADE_TIME).set_delay(delay + WIN_RISE_TIME + WIN_HOLD_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	_win_tween.finished.connect(next_callback)



# =========================================================================
# Helpers
# =========================================================================

## Per-tile stagger delay for fog reveal based on BFS distance from source.
const FOG_STAGGER_DELAY := 0.04  ## Seconds per BFS hop

func _refresh_all_tiles() -> void:
	var gw: int = grid_manager.grid_width
	var gh: int = grid_manager.grid_height
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			var td = grid_manager.tiles[idx]
			var delay := 0.0
			if grid_manager.fog_enabled and td.bfs_distance >= 0:
				delay = td.bfs_distance * FOG_STAGGER_DELAY
			tile_nodes[idx].refresh(td, delay)
