extends Node2D
## Visual representation of a single grid square for the Train Tracks puzzle.
## Draws track pieces, no-track marks, and error indicators via _draw().

const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")
var TRACKS_TEX: Texture2D = load("res://assets/tracks/tracks.png")
const FRAME_SIZE := 32
# Sprite-sheet frame index for each 2-direction track shape
const TRACK_FRAME := {
	5:  0,  # LR  – horizontal
	10: 1,  # UD  – vertical
	12: 2,  # LD  – west-south curve
	6:  3,  # LU  – west-north curve
	3:  4,  # RU  – north-east curve
	9:  5,  # RD  – south-east curve
}

signal square_clicked(grid_x: int, grid_y: int, local_pos: Vector2)
signal square_right_clicked(grid_x: int, grid_y: int, local_pos: Vector2)

const CELL_SIZE := 28.0
const CENTER := Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)

# Rail positions for stubs (scaled for 28px cell)
const RAIL_IN := 9.0
const RAIL_OUT := 19.0

# Colors
const BG_COLOR := Color(0.18, 0.16, 0.14)
const BG_TRACK := Color(0.25, 0.22, 0.18)
const TRACK_COLOR := Color(0.5, 0.5, 0.5)
const CLUE_TRACK_COLOR := Color(0.3, 0.3, 0.35)
const SLEEPER_COLOR := Color(0.5, 0.4, 0.1)
const ERROR_COLOR := Color(1.0, 0.2, 0.2)
const NOTRACK_COLOR := Color(0.45, 0.4, 0.35)
const GRID_LINE_COLOR := Color(0.35, 0.33, 0.3)
const HIGHLIGHT_COLOR := Color(0.95, 0.85, 0.3)  # warm gold for win highlight

# Decoration types
const DECO_NONE := 0
const DECO_TREE := 1
const DECO_HOUSE := 2
const DECO_WATER := 3

# Decoration colors
const TREE_GREEN := Color(0.2, 0.55, 0.2)
const TREE_TRUNK := Color(0.45, 0.3, 0.15)
const HOUSE_WALL := Color(0.6, 0.45, 0.3)
const HOUSE_ROOF := Color(0.55, 0.25, 0.2)
const HOUSE_WINDOW := Color(0.9, 0.85, 0.4)
const WATER_COLOR := Color(0.25, 0.45, 0.7)
const WATER_HIGHLIGHT := Color(0.4, 0.6, 0.85)

var grid_x: int = 0
var grid_y: int = 0
var square_data = null
var highlight: float = 0.0:  # 0.0 = normal, 1.0 = full highlight (win animation)
	set(v):
		highlight = v
		queue_redraw()
var decoration: int = DECO_NONE
var deco_alpha: float = 0.0:
	set(v):
		deco_alpha = v
		queue_redraw()


func setup(x: int, y: int) -> void:
	grid_x = x
	grid_y = y


func refresh(data) -> void:
	square_data = data
	queue_redraw()


func _draw() -> void:
	# Background
	var has_track: bool = false
	if square_data != null:
		has_track = square_data.has_flag(TC.S_TRACK) or square_data.e_count(TC.E_TRACK) > 0
	var bg: Color = BG_TRACK if has_track else BG_COLOR
	if highlight > 0.0 and has_track:
		bg = bg.lerp(HIGHLIGHT_COLOR, highlight * 0.4)
	draw_rect(Rect2(0, 0, CELL_SIZE, CELL_SIZE), bg)

	# Grid lines (all 4 edges so right/bottom border is visible)
	draw_line(Vector2(0, 0), Vector2(CELL_SIZE, 0), GRID_LINE_COLOR, 1.0)
	draw_line(Vector2(0, 0), Vector2(0, CELL_SIZE), GRID_LINE_COLOR, 1.0)
	draw_line(Vector2(CELL_SIZE, 0), Vector2(CELL_SIZE, CELL_SIZE), GRID_LINE_COLOR, 1.0)
	draw_line(Vector2(0, CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE), GRID_LINE_COLOR, 1.0)

	if square_data == null:
		return

	# Determine track tint (white = no tint, so sprite shows at full brightness)
	var is_error: bool = square_data.has_flag(TC.S_ERROR)
	var track_col := Color.WHITE
	if is_error:
		track_col = ERROR_COLOR
	if highlight > 0.0 and has_track:
		track_col = track_col.lerp(HIGHLIGHT_COLOR, highlight)

	# Draw track shapes based on edge flags
	var track_dirs: int = square_data.e_dirs(TC.E_TRACK)
	if track_dirs != 0:
		_draw_track_shape(track_dirs, track_col)

	# Draw square NOTRACK mark (X in center)
	if square_data.has_flag(TC.S_NOTRACK):
		var off := CELL_SIZE / 4.0
		draw_line(CENTER - Vector2(off, off), CENTER + Vector2(off, off), NOTRACK_COLOR, 1.0)
		draw_line(CENTER + Vector2(-off, off), CENTER + Vector2(off, -off), NOTRACK_COLOR, 1.0)

	# Draw edge NOTRACK marks (small X at edge midpoints)
	var notrack_dirs: int = square_data.e_dirs(TC.E_NOTRACK)
	for i in range(4):
		var d := 1 << i
		if notrack_dirs & d:
			_draw_edge_notrack(d)

	# Decorations (on non-track cells after win)
	if decoration != DECO_NONE and deco_alpha > 0.0:
		_draw_decoration()


func _draw_track_shape(flags: int, col: Color) -> void:
	if TRACK_FRAME.has(flags):
		_draw_track_sprite(TRACK_FRAME[flags], col)
		return
	# Fallback: draw individual edge stubs
	for i in range(4):
		var d := 1 << i
		if flags & d:
			_draw_stub(d, col)


func _draw_track_sprite(frame: int, col: Color) -> void:
	var src := Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
	draw_texture_rect_region(TRACKS_TEX, Rect2(0, 0, CELL_SIZE, CELL_SIZE), src, col)


func _draw_stub(d: int, col: Color) -> void:
	# Draw a short track stub from edge inward
	var stub_len := 7.0
	if d == TC.DIR_L:
		draw_line(Vector2(0, RAIL_IN), Vector2(stub_len, RAIL_IN), col, 1.0)
		draw_line(Vector2(0, RAIL_OUT), Vector2(stub_len, RAIL_OUT), col, 1.0)
	elif d == TC.DIR_R:
		draw_line(Vector2(CELL_SIZE - stub_len, RAIL_IN), Vector2(CELL_SIZE, RAIL_IN), col, 1.0)
		draw_line(Vector2(CELL_SIZE - stub_len, RAIL_OUT), Vector2(CELL_SIZE, RAIL_OUT), col, 1.0)
	elif d == TC.DIR_U:
		draw_line(Vector2(RAIL_IN, 0), Vector2(RAIL_IN, stub_len), col, 1.0)
		draw_line(Vector2(RAIL_OUT, 0), Vector2(RAIL_OUT, stub_len), col, 1.0)
	elif d == TC.DIR_D:
		draw_line(Vector2(RAIL_IN, CELL_SIZE - stub_len), Vector2(RAIL_IN, CELL_SIZE), col, 1.0)
		draw_line(Vector2(RAIL_OUT, CELL_SIZE - stub_len), Vector2(RAIL_OUT, CELL_SIZE), col, 1.0)


func _draw_edge_notrack(d: int) -> void:
	# Small X at the midpoint of edge d
	var ex := CELL_SIZE / 2.0
	var ey := CELL_SIZE / 2.0
	if d == TC.DIR_R:
		ex = CELL_SIZE
	elif d == TC.DIR_L:
		ex = 0.0
	elif d == TC.DIR_D:
		ey = CELL_SIZE
	elif d == TC.DIR_U:
		ey = 0.0
	var off := 3.0
	var center := Vector2(ex, ey)
	draw_line(center + Vector2(-off, -off), center + Vector2(off, off), NOTRACK_COLOR, 1.0)
	draw_line(center + Vector2(-off, off), center + Vector2(off, -off), NOTRACK_COLOR, 1.0)


func _draw_decoration() -> void:
	match decoration:
		DECO_TREE:
			_draw_tree()
		DECO_HOUSE:
			_draw_house()
		DECO_WATER:
			_draw_water()


func _draw_tree() -> void:
	var green := Color(TREE_GREEN, deco_alpha)
	var brown := Color(TREE_TRUNK, deco_alpha)
	var cx := CELL_SIZE / 2.0
	# Trunk: 2px wide, 6px tall
	draw_rect(Rect2(cx - 1, 18, 2, 6), brown)
	# Canopy: triangle
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, 4),
		Vector2(cx - 7, 18),
		Vector2(cx + 7, 18),
	]), green)


func _draw_house() -> void:
	var wall := Color(HOUSE_WALL, deco_alpha)
	var roof := Color(HOUSE_ROOF, deco_alpha)
	var window := Color(HOUSE_WINDOW, deco_alpha)
	var cx := CELL_SIZE / 2.0
	# Walls
	draw_rect(Rect2(cx - 7, 14, 14, 10), wall)
	# Roof triangle
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, 4),
		Vector2(cx - 8, 14),
		Vector2(cx + 8, 14),
	]), roof)
	# Window
	draw_rect(Rect2(cx - 1, 17, 3, 3), window)


func _draw_water() -> void:
	var col := Color(WATER_COLOR, deco_alpha)
	var hi := Color(WATER_HIGHLIGHT, deco_alpha)
	# Three wavy lines
	draw_line(Vector2(5, 10), Vector2(10, 8), hi, 1.0)
	draw_line(Vector2(10, 8), Vector2(17, 10), hi, 1.0)
	draw_line(Vector2(17, 10), Vector2(23, 8), hi, 1.0)
	draw_line(Vector2(4, 14), Vector2(10, 12), col, 1.0)
	draw_line(Vector2(10, 12), Vector2(16, 14), col, 1.0)
	draw_line(Vector2(16, 14), Vector2(22, 12), col, 1.0)
	draw_line(Vector2(6, 18), Vector2(12, 16), col, 1.0)
	draw_line(Vector2(12, 16), Vector2(18, 18), col, 1.0)
	draw_line(Vector2(18, 18), Vector2(24, 16), col, 1.0)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Use get_local_mouse_position() — event.global_position is in viewport
		# coords which breaks when Camera2D has panned
		var local := get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			square_clicked.emit(grid_x, grid_y, local)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			square_right_clicked.emit(grid_x, grid_y, local)
