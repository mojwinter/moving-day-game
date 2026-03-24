extends Node2D
## Visual representation of a single grid tile.
## Renders pipe sprites from a sprite sheet and handles click input via Area2D.

const NC := preload("res://scripts/net_puzzle/net_consts.gd")

signal tile_clicked(grid_x: int, grid_y: int)

const PIPE_SHEET := preload("res://assets/network/pipes16x16.png")
const SPRITE_SIZE := 16

## Maps a connection bitmask to { "col": sprite column, "rot": CW 90° rotations }.
## CW visual rotation = CW bitmask rotation: U(2)->R(1)->D(8)->L(4)
const PIPE_LOOKUP := {
	# Dead ends (1 connection) — base: UP (2)
	2:  { "col": 0, "rot": 0 },   # UP
	1:  { "col": 0, "rot": 1 },   # RIGHT
	8:  { "col": 0, "rot": 2 },   # DOWN
	4:  { "col": 0, "rot": 3 },   # LEFT
	# Straights (2 opposite) — base: UP+DOWN (10)
	10: { "col": 1, "rot": 0 },   # UP+DOWN
	5:  { "col": 1, "rot": 1 },   # RIGHT+LEFT
	# L-bends (2 adjacent) — base: DOWN+RIGHT (9)
	9:  { "col": 2, "rot": 0 },   # DOWN+RIGHT
	12: { "col": 2, "rot": 1 },   # DOWN+LEFT
	6:  { "col": 2, "rot": 2 },   # UP+LEFT
	3:  { "col": 2, "rot": 3 },   # UP+RIGHT
	# T-junctions (3 connections) — base: UP+DOWN+RIGHT (11)
	11: { "col": 3, "rot": 0 },   # UP+DOWN+RIGHT
	13: { "col": 3, "rot": 1 },   # DOWN+LEFT+RIGHT
	14: { "col": 3, "rot": 2 },   # UP+DOWN+LEFT
	7:  { "col": 3, "rot": 3 },   # UP+LEFT+RIGHT
	# Cross (4 connections)
	15: { "col": 4, "rot": 0 },
}

var cell_size: float = 16.0
var center: Vector2 = Vector2(8.0, 8.0)

const BG_COLOR := Color(0.15, 0.15, 0.2)
const FOG_COLOR := Color(0.012, 0.02, 0.078)  # #030514
const HIGHLIGHT_COLOR := Color(0.95, 0.85, 0.3)
const SOURCE_COLOR := Color(1.0, 1.0, 1.0)

const ROTATE_TIME := 0.15  ## Seconds for rotation animation
const FOG_REVEAL_TIME := 0.35  ## Seconds for fog fade-in/out
const FOG_HIDE_TIME := 0.25    ## Slightly faster re-fog

var highlight: float = 0.0:
	set(v):
		highlight = v
		queue_redraw()

## Fog alpha: 1.0 = fully fogged, 0.0 = fully revealed
var fog_alpha: float = 1.0:
	set(v):
		fog_alpha = v
		queue_redraw()

var grid_x: int = 0
var grid_y: int = 0
var tile_data = null
var _was_revealed: bool = false  ## Track previous reveal state for transitions
var _fog_tween: Tween = null

## Rotation animation state
var _anim_angle: float = 0.0      ## Current extra rotation in degrees (0 to 90)
var _anim_active: bool = false
var _anim_conns: int = 0           ## Connection bitmask BEFORE rotation (used during anim)
var _anim_was_active: bool = false  ## Active state BEFORE rotation


func setup(x: int, y: int, p_cell_size: float = 16.0) -> void:
	grid_x = x
	grid_y = y
	cell_size = p_cell_size
	center = Vector2(cell_size / 2.0, cell_size / 2.0)
	var area := get_node_or_null("ClickArea")
	if area:
		var shape_owner := area.get_node_or_null("CollisionShape")
		if shape_owner and shape_owner.shape is RectangleShape2D:
			shape_owner.shape.size = Vector2(cell_size, cell_size)
			shape_owner.position = center


func refresh(data, reveal_delay: float = 0.0) -> void:
	tile_data = data
	_update_fog_visual(reveal_delay)
	queue_redraw()


## Animate fog transitions when reveal state changes.
func _update_fog_visual(reveal_delay: float) -> void:
	if tile_data == null:
		return

	var is_now_revealed: bool = tile_data.is_revealed

	if is_now_revealed == _was_revealed:
		return  # No change

	_was_revealed = is_now_revealed

	# Kill any existing fog tween
	if _fog_tween and _fog_tween.is_valid():
		_fog_tween.kill()

	_fog_tween = create_tween()

	if is_now_revealed:
		# Revealing: fade fog out with optional stagger delay
		if reveal_delay > 0.0:
			_fog_tween.tween_interval(reveal_delay)
		_fog_tween.tween_property(self, "fog_alpha", 0.0, FOG_REVEAL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		# Hiding: fade fog back in
		_fog_tween.tween_property(self, "fog_alpha", 1.0, FOG_HIDE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## Reset fog state instantly (used when starting a new tier).
func reset_fog(revealed: bool) -> void:
	_was_revealed = revealed
	fog_alpha = 0.0 if revealed else 1.0
	if _fog_tween and _fog_tween.is_valid():
		_fog_tween.kill()
		_fog_tween = null


## Call this BEFORE rotating the bitmask to kick off the animation.
## Captures the pre-rotation visual state so we can animate from it.
func start_rotate_anim(old_connections: int, old_active: bool) -> void:
	_anim_conns = old_connections
	_anim_was_active = old_active
	_anim_angle = 0.0
	_anim_active = true


func _process(delta: float) -> void:
	if not _anim_active:
		return
	_anim_angle += delta / ROTATE_TIME * 90.0
	if _anim_angle >= 90.0:
		_anim_angle = 0.0
		_anim_active = false
	queue_redraw()


func _draw() -> void:
	if tile_data == null:
		draw_rect(Rect2(0, 0, cell_size, cell_size), BG_COLOR)
		return

	# Fully fogged — just draw fog rectangle
	if fog_alpha >= 1.0:
		draw_rect(Rect2(0, 0, cell_size, cell_size), FOG_COLOR)
		return

	# Background tile sprite (row 2, col 0) — drawn 1:1 at origin
	var bg_src := Rect2(0, 2 * SPRITE_SIZE, SPRITE_SIZE, SPRITE_SIZE)
	var bg_tint := Color.WHITE.lerp(HIGHLIGHT_COLOR, highlight * 0.4) if highlight > 0.0 else Color.WHITE
	draw_texture_rect_region(PIPE_SHEET, Rect2(0, 0, SPRITE_SIZE, SPRITE_SIZE), bg_src, bg_tint)

	# During animation: use pre-rotation bitmask + interpolated angle
	# After animation: use current bitmask at its natural angle
	var conns: int
	var is_active: bool
	var extra_angle: float

	if _anim_active:
		conns = _anim_conns & 0x0F
		is_active = _anim_was_active
		extra_angle = _anim_angle
	else:
		conns = tile_data.connections & 0x0F
		is_active = tile_data.is_active
		extra_angle = 0.0

	if conns == 0:
		# Overlay fog on top if partially fogged
		if fog_alpha > 0.0:
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_rect(Rect2(0, 0, cell_size, cell_size), Color(FOG_COLOR, fog_alpha))
		return

	var half := SPRITE_SIZE / 2.0

	if conns in PIPE_LOOKUP:
		var info: Dictionary = PIPE_LOOKUP[conns]
		var row: int = 0 if is_active else 1
		var src_rect := Rect2(info["col"] * SPRITE_SIZE, row * SPRITE_SIZE, SPRITE_SIZE, SPRITE_SIZE)

		var base_angle: float = info["rot"] * 90.0
		var total_angle: float = base_angle + extra_angle
		var tint := Color.WHITE.lerp(HIGHLIGHT_COLOR, highlight) if highlight > 0.0 else Color.WHITE

		# Rotate around center, no scaling (1:1 at 16px)
		draw_set_transform(center, deg_to_rad(total_angle), Vector2.ONE)
		draw_texture_rect_region(PIPE_SHEET, Rect2(-half, -half, SPRITE_SIZE, SPRITE_SIZE), src_rect, tint)

	# Source overlay sprite (row 2, cols 1-4 match pipe cols 1-4)
	if tile_data.is_source and conns in PIPE_LOOKUP:
		var info: Dictionary = PIPE_LOOKUP[conns]
		if info["col"] >= 1:
			var src_src := Rect2(info["col"] * SPRITE_SIZE, 2 * SPRITE_SIZE, SPRITE_SIZE, SPRITE_SIZE)
			var base_angle: float = info["rot"] * 90.0
			var src_angle: float = base_angle + extra_angle
			var src_tint := Color.WHITE.lerp(HIGHLIGHT_COLOR, highlight) if highlight > 0.0 else Color.WHITE
			draw_set_transform(center, deg_to_rad(src_angle), Vector2.ONE)
			draw_texture_rect_region(PIPE_SHEET, Rect2(-half, -half, SPRITE_SIZE, SPRITE_SIZE), src_src, src_tint)

	# Overlay fog on top if partially fogged (smooth transition)
	if fog_alpha > 0.0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_rect(Rect2(0, 0, cell_size, cell_size), Color(FOG_COLOR, fog_alpha))


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tile_clicked.emit(grid_x, grid_y)
