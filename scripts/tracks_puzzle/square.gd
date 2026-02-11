extends Node2D
## Visual representation of a single grid square for the Train Tracks puzzle.
## Draws track pieces, no-track marks, and error indicators via _draw().

const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")

signal square_clicked(grid_x: int, grid_y: int, local_pos: Vector2)
signal square_right_clicked(grid_x: int, grid_y: int, local_pos: Vector2)

const CELL_SIZE := 20.0
const CENTER := Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)
const T3 := CELL_SIZE / 3.0     # one-third
const T6 := CELL_SIZE / 6.0     # one-sixth

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

	# Determine track color
	var is_error: bool = square_data.has_flag(TC.S_ERROR)
	var is_clue: bool = square_data.has_flag(TC.S_CLUE)
	var track_col: Color = ERROR_COLOR if is_error else (CLUE_TRACK_COLOR if is_clue else TRACK_COLOR)
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
	# Check for standard 2-direction shapes first
	if flags == TC.LR:
		_draw_straight_h(col)
		return
	if flags == TC.UD:
		_draw_straight_v(col)
		return
	if flags == TC.LU or flags == TC.LD or flags == TC.RU or flags == TC.RD:
		_draw_curve(flags, col)
		return
	# Fallback: draw individual edge stubs
	for i in range(4):
		var d := 1 << i
		if flags & d:
			_draw_stub(d, col)


func _draw_straight_h(col: Color) -> void:
	# Sleepers first (between rails)
	for i in range(5):
		var sx := 2.0 + i * 4.0
		draw_line(Vector2(sx, 6.0), Vector2(sx, 14.0), SLEEPER_COLOR, 1.0)
	# Two horizontal rails
	draw_line(Vector2(0, 6.0), Vector2(CELL_SIZE, 6.0), col, 1.0)
	draw_line(Vector2(0, 14.0), Vector2(CELL_SIZE, 14.0), col, 1.0)


func _draw_straight_v(col: Color) -> void:
	# Sleepers (between rails)
	for i in range(5):
		var sy := 2.0 + i * 4.0
		draw_line(Vector2(6.0, sy), Vector2(14.0, sy), SLEEPER_COLOR, 1.0)
	# Two vertical rails
	draw_line(Vector2(6.0, 0), Vector2(6.0, CELL_SIZE), col, 1.0)
	draw_line(Vector2(14.0, 0), Vector2(14.0, CELL_SIZE), col, 1.0)


func _draw_curve(flags: int, col: Color) -> void:
	# Arc center is at the corner toward both connected edges
	var cx := 0.0 if (flags & TC.DIR_L) else CELL_SIZE
	var cy := 0.0 if (flags & TC.DIR_U) else CELL_SIZE
	var arc_center := Vector2(cx, cy)

	# Determine arc angle range
	var start_angle := 0.0
	if flags == TC.RD:      # corner at bottom-right, arc from 180 to 270
		start_angle = PI
	elif flags == TC.LD:    # corner at bottom-left, arc from 270 to 360
		start_angle = PI * 1.5
	elif flags == TC.LU:    # corner at top-left, arc from 0 to 90
		start_angle = 0.0
	elif flags == TC.RU:    # corner at top-right, arc from 90 to 180
		start_angle = PI * 0.5

	var end_angle := start_angle + PI * 0.5

	# Draw sleepers (radial lines)
	var nsleepers := 4
	for i in range(nsleepers):
		var th := start_angle + (end_angle - start_angle) * (float(i) + 0.5) / float(nsleepers)
		var inner_pt := arc_center + Vector2(cos(th), sin(th)) * 6.0
		var outer_pt := arc_center + Vector2(cos(th), sin(th)) * 14.0
		draw_line(inner_pt, outer_pt, SLEEPER_COLOR, 1.0)

	# Draw inner and outer arcs (radii match rail positions 6 and 14)
	draw_arc(arc_center, 6.0, start_angle, end_angle, 12, col, 1.0)
	draw_arc(arc_center, 14.0, start_angle, end_angle, 12, col, 1.0)


func _draw_stub(d: int, col: Color) -> void:
	# Draw a short track stub from edge inward (~5px)
	var stub_len := 5.0
	if d == TC.DIR_L:
		draw_line(Vector2(0, 6.0), Vector2(stub_len, 6.0), col, 1.0)
		draw_line(Vector2(0, 14.0), Vector2(stub_len, 14.0), col, 1.0)
	elif d == TC.DIR_R:
		draw_line(Vector2(CELL_SIZE - stub_len, 6.0), Vector2(CELL_SIZE, 6.0), col, 1.0)
		draw_line(Vector2(CELL_SIZE - stub_len, 14.0), Vector2(CELL_SIZE, 14.0), col, 1.0)
	elif d == TC.DIR_U:
		draw_line(Vector2(6.0, 0), Vector2(6.0, stub_len), col, 1.0)
		draw_line(Vector2(14.0, 0), Vector2(14.0, stub_len), col, 1.0)
	elif d == TC.DIR_D:
		draw_line(Vector2(6.0, CELL_SIZE - stub_len), Vector2(6.0, CELL_SIZE), col, 1.0)
		draw_line(Vector2(14.0, CELL_SIZE - stub_len), Vector2(14.0, CELL_SIZE), col, 1.0)


func _draw_edge_notrack(d: int) -> void:
	# Small X at the midpoint of edge d
	var cx := CELL_SIZE / 2.0
	var cy := CELL_SIZE / 2.0
	if d == TC.DIR_R:
		cx = CELL_SIZE
	elif d == TC.DIR_L:
		cx = 0.0
	elif d == TC.DIR_D:
		cy = CELL_SIZE
	elif d == TC.DIR_U:
		cy = 0.0
	var off := 2.0
	var center := Vector2(cx, cy)
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
	# Trunk: 2px wide, 4px tall
	draw_rect(Rect2(cx - 1, 13, 2, 4), brown)
	# Canopy: triangle
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, 3),
		Vector2(cx - 5, 13),
		Vector2(cx + 5, 13),
	]), green)


func _draw_house() -> void:
	var wall := Color(HOUSE_WALL, deco_alpha)
	var roof := Color(HOUSE_ROOF, deco_alpha)
	var window := Color(HOUSE_WINDOW, deco_alpha)
	var cx := CELL_SIZE / 2.0
	# Walls
	draw_rect(Rect2(cx - 5, 10, 10, 7), wall)
	# Roof triangle
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, 3),
		Vector2(cx - 6, 10),
		Vector2(cx + 6, 10),
	]), roof)
	# Window
	draw_rect(Rect2(cx - 1, 12, 2, 2), window)


func _draw_water() -> void:
	var col := Color(WATER_COLOR, deco_alpha)
	var hi := Color(WATER_HIGHLIGHT, deco_alpha)
	# Three wavy lines
	draw_line(Vector2(4, 7), Vector2(8, 6), hi, 1.0)
	draw_line(Vector2(8, 6), Vector2(12, 7), hi, 1.0)
	draw_line(Vector2(12, 7), Vector2(16, 6), hi, 1.0)
	draw_line(Vector2(3, 10), Vector2(7, 9), col, 1.0)
	draw_line(Vector2(7, 9), Vector2(11, 10), col, 1.0)
	draw_line(Vector2(11, 10), Vector2(15, 9), col, 1.0)
	draw_line(Vector2(5, 13), Vector2(9, 12), col, 1.0)
	draw_line(Vector2(9, 12), Vector2(13, 13), col, 1.0)
	draw_line(Vector2(13, 13), Vector2(17, 12), col, 1.0)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		# local_pos relative to this node's origin
		var local := to_local(event.global_position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			square_clicked.emit(grid_x, grid_y, local)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			square_right_clicked.emit(grid_x, grid_y, local)
