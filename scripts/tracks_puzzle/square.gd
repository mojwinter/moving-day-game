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

var grid_x: int = 0
var grid_y: int = 0
var square_data = null


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
	draw_rect(Rect2(0, 0, CELL_SIZE, CELL_SIZE), bg)

	# Grid lines
	draw_line(Vector2(0, 0), Vector2(CELL_SIZE, 0), GRID_LINE_COLOR, 1.0)
	draw_line(Vector2(0, 0), Vector2(0, CELL_SIZE), GRID_LINE_COLOR, 1.0)

	if square_data == null:
		return

	# Determine track color
	var is_error: bool = square_data.has_flag(TC.S_ERROR)
	var is_clue: bool = square_data.has_flag(TC.S_CLUE)
	var track_col: Color = ERROR_COLOR if is_error else (CLUE_TRACK_COLOR if is_clue else TRACK_COLOR)

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
	# Sleepers first (behind rails)
	for i in range(1, 8, 2):
		var sx := CELL_SIZE / 8.0 * i
		draw_line(Vector2(sx, T6), Vector2(sx, T6 + 2 * T3), SLEEPER_COLOR, 1.0)
	# Two horizontal rails
	draw_line(Vector2(0, T3), Vector2(CELL_SIZE, T3), col, 1.0)
	draw_line(Vector2(0, 2 * T3), Vector2(CELL_SIZE, 2 * T3), col, 1.0)


func _draw_straight_v(col: Color) -> void:
	# Sleepers
	for i in range(1, 8, 2):
		var sy := CELL_SIZE / 8.0 * i
		draw_line(Vector2(T6, sy), Vector2(T6 + 2 * T3, sy), SLEEPER_COLOR, 1.0)
	# Two vertical rails
	draw_line(Vector2(T3, 0), Vector2(T3, CELL_SIZE), col, 1.0)
	draw_line(Vector2(2 * T3, 0), Vector2(2 * T3, CELL_SIZE), col, 1.0)


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
		var inner_pt := arc_center + Vector2(cos(th), sin(th)) * T3
		var outer_pt := arc_center + Vector2(cos(th), sin(th)) * (2 * T3)
		draw_line(inner_pt, outer_pt, SLEEPER_COLOR, 1.0)

	# Draw inner and outer arcs
	draw_arc(arc_center, T3, start_angle, end_angle, 12, col, 1.0)
	draw_arc(arc_center, 2 * T3, start_angle, end_angle, 12, col, 1.0)


func _draw_stub(d: int, col: Color) -> void:
	# Draw a short track stub from center toward edge d
	var half := CELL_SIZE / 2.0
	if d == TC.DIR_L:
		draw_line(Vector2(0, T3), Vector2(half, T3), col, 1.0)
		draw_line(Vector2(0, 2 * T3), Vector2(half, 2 * T3), col, 1.0)
	elif d == TC.DIR_R:
		draw_line(Vector2(half, T3), Vector2(CELL_SIZE, T3), col, 1.0)
		draw_line(Vector2(half, 2 * T3), Vector2(CELL_SIZE, 2 * T3), col, 1.0)
	elif d == TC.DIR_U:
		draw_line(Vector2(T3, 0), Vector2(T3, half), col, 1.0)
		draw_line(Vector2(2 * T3, 0), Vector2(2 * T3, half), col, 1.0)
	elif d == TC.DIR_D:
		draw_line(Vector2(T3, half), Vector2(T3, CELL_SIZE), col, 1.0)
		draw_line(Vector2(2 * T3, half), Vector2(2 * T3, CELL_SIZE), col, 1.0)


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


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		# local_pos relative to this node's origin
		var local := to_local(event.global_position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			square_clicked.emit(grid_x, grid_y, local)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			square_right_clicked.emit(grid_x, grid_y, local)
