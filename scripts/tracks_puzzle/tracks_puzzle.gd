extends Node2D
## Scene controller for the Night 2 Train Tracks puzzle.
## Creates square nodes, draws clue numbers and A/B markers, routes input.

const CELL_SIZE := 28
const GRID_W := 5
const GRID_H := 4
const GRID_OFFSET := Vector2(62, 6)
const NEW_BTN_RECT := Rect2(2, 2, 24, 12)

const SquareScene := preload("res://scenes/tracks_puzzle/square.tscn")
const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")
const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")

@onready var grid_manager = $GridManager

var square_nodes := []
var _solved := false
var _win_tween: Tween = null
var _deco_tween: Tween = null

# Drag state
var _drag_active := false
var _drag_notrack := false
var _drag_clearing := false
var _drag_sx: int = -1
var _drag_sy: int = -1
var _drag_ex: int = -1
var _drag_ey: int = -1
var _click_pos := Vector2.ZERO  # mouse-down position for click-vs-drag


func _ready() -> void:
	grid_manager.generate_puzzle()
	_create_square_nodes()
	_refresh_all()
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)


func _create_square_nodes() -> void:
	for y in range(GRID_H):
		for x in range(GRID_W):
			var sq_node = SquareScene.instantiate()
			sq_node.setup(x, y)
			sq_node.position = GRID_OFFSET + Vector2((x + 1) * CELL_SIZE, (y + 1) * CELL_SIZE)
			sq_node.square_clicked.connect(_on_square_clicked)
			sq_node.square_right_clicked.connect(_on_square_right_clicked)
			add_child(sq_node)
			square_nodes.append(sq_node)


# ===========================================================================
# Drawing clue numbers, border, A/B labels
# ===========================================================================

func _draw() -> void:
	if grid_manager.clue_numbers.size() == 0:
		return

	var font_size := 16
	var vy := 6  # vertical centering offset for m3x6 at size 16

	# Column clues (above grid)
	for x in range(GRID_W):
		var num: int = grid_manager.clue_numbers[x]
		var is_err: bool = grid_manager.num_errors[x] != 0
		var col := Color(1.0, 0.2, 0.2) if is_err else Color(0.8, 0.8, 0.7)
		var txt := str(num)
		var tw := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := GRID_OFFSET + Vector2((x + 1) * CELL_SIZE + CELL_SIZE / 2.0 - tw.x / 2.0, CELL_SIZE / 2.0 + vy)
		draw_string(PIXEL_FONT, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# Row clues (right of grid)
	for y in range(GRID_H):
		var num: int = grid_manager.clue_numbers[GRID_W + y]
		var is_err: bool = grid_manager.num_errors[GRID_W + y] != 0
		var col := Color(1.0, 0.2, 0.2) if is_err else Color(0.8, 0.8, 0.7)
		var txt := str(num)
		var tw := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := GRID_OFFSET + Vector2((GRID_W + 1) * CELL_SIZE + CELL_SIZE / 2.0 - tw.x / 2.0, (y + 1) * CELL_SIZE + CELL_SIZE / 2.0 + vy)
		draw_string(PIXEL_FONT, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# "A" label (left of entrance row)
	var a_txt := "A"
	var a_tw := PIXEL_FONT.get_string_size(a_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var a_pos := GRID_OFFSET + Vector2(CELL_SIZE / 2.0 - a_tw.x / 2.0, (grid_manager.row_station + 1) * CELL_SIZE + CELL_SIZE / 2.0 + vy)
	draw_string(PIXEL_FONT, a_pos, a_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.8, 0.3))

	# "B" label (below exit column)
	var b_txt := "B"
	var b_tw := PIXEL_FONT.get_string_size(b_txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var b_pos := GRID_OFFSET + Vector2((grid_manager.col_station + 1) * CELL_SIZE + CELL_SIZE / 2.0 - b_tw.x / 2.0, (GRID_H + 1) * CELL_SIZE + CELL_SIZE / 2.0 + vy)
	draw_string(PIXEL_FONT, b_pos, b_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.8, 0.3))

	# "New" button
	_draw_new_button(font_size)


# ===========================================================================
# Input handling
# ===========================================================================

func _on_square_clicked(gx: int, gy: int, local_pos: Vector2) -> void:
	_handle_click(gx, gy, local_pos, false)


func _on_square_right_clicked(gx: int, gy: int, local_pos: Vector2) -> void:
	_handle_click(gx, gy, local_pos, true)


func _handle_click(gx: int, gy: int, local_pos: Vector2, is_right: bool) -> void:
	if _solved:
		return
	var cx := CELL_SIZE / 2.0
	var cy := CELL_SIZE / 2.0
	var dx := local_pos.x - cx
	var dy := local_pos.y - cy

	if max(abs(dx), abs(dy)) < CELL_SIZE / 4.0:
		# Center click -> square toggle
		grid_manager.apply_square_toggle(gx, gy, is_right)
	else:
		# Edge click -> determine closest edge
		var dir: int
		if abs(dx) < abs(dy):
			dir = TC.DIR_U if dy < 0 else TC.DIR_D
		else:
			dir = TC.DIR_L if dx < 0 else TC.DIR_R
		grid_manager.apply_edge_toggle(gx, gy, dir, is_right)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = event.global_position - global_position
		if NEW_BTN_RECT.has_point(local):
			_on_new_game_pressed()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _solved:
		return
	if event is InputEventMouseButton:
		if event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			var gpos := _mouse_to_grid(event.global_position)
			if gpos != Vector2i(-1, -1):
				_drag_notrack = (event.button_index == MOUSE_BUTTON_RIGHT)
				var idx := gpos.y * GRID_W + gpos.x
				var f := TC.S_NOTRACK if _drag_notrack else TC.S_TRACK
				_drag_clearing = bool(grid_manager.squares[idx].sflags & f)
				_drag_sx = gpos.x
				_drag_sy = gpos.y
				_drag_ex = gpos.x
				_drag_ey = gpos.y
				_click_pos = event.global_position
				_drag_active = false  # only becomes a drag if we move to a different cell
		elif not event.pressed:
			if _drag_active and (_drag_sx != _drag_ex or _drag_sy != _drag_ey):
				_apply_drag()
			_drag_active = false
			_drag_sx = -1

	elif event is InputEventMouseMotion and _drag_sx >= 0:
		var gpos := _mouse_to_grid(event.global_position)
		if gpos != Vector2i(-1, -1):
			_update_drag(gpos.x, gpos.y)


func _update_drag(gx: int, gy: int) -> void:
	var dx: int = absi(_drag_sx - gx)
	var dy: int = absi(_drag_sy - gy)
	if dy == 0:
		_drag_ex = clampi(gx, 0, GRID_W - 1)
		_drag_ey = _drag_sy
		_drag_active = true
	elif dx == 0:
		_drag_ex = _drag_sx
		_drag_ey = clampi(gy, 0, GRID_H - 1)
		_drag_active = true


func _apply_drag() -> void:
	var x1 := mini(_drag_sx, _drag_ex)
	var x2 := maxi(_drag_sx, _drag_ex)
	var y1 := mini(_drag_sy, _drag_ey)
	var y2 := maxi(_drag_sy, _drag_ey)
	var f := TC.S_NOTRACK if _drag_notrack else TC.S_TRACK

	for x in range(x1, x2 + 1):
		for y in range(y1, y2 + 1):
			var idx := y * GRID_W + x
			var has_f: bool = bool(grid_manager.squares[idx].sflags & f)
			if _drag_clearing and not has_f:
				continue
			if not _drag_clearing and has_f:
				continue
			if grid_manager._can_flip_square(x, y, _drag_notrack):
				grid_manager.squares[idx].toggle_flag(f)

	grid_manager.check_completion(true)
	grid_manager.grid_changed.emit()
	if grid_manager.completed:
		grid_manager.puzzle_solved.emit()


# ===========================================================================
# State updates
# ===========================================================================

func _on_grid_changed() -> void:
	_refresh_all()


func _refresh_all() -> void:
	for y in range(GRID_H):
		for x in range(GRID_W):
			var idx := y * GRID_W + x
			square_nodes[idx].refresh(grid_manager.squares[idx])
	queue_redraw()


func _on_puzzle_solved() -> void:
	_solved = true
	_play_win_highlight()


func _play_win_highlight() -> void:
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	var tween := _win_tween
	tween.set_parallel(true)
	var delay := 0.0
	for y in range(GRID_H):
		for x in range(GRID_W):
			var idx := y * GRID_W + x
			var sq_data = grid_manager.squares[idx]
			var has_track: bool = sq_data.has_flag(TC.S_TRACK) or sq_data.e_count(TC.E_TRACK) > 0
			if not has_track:
				continue
			var sq_node = square_nodes[idx]
			sq_node.highlight = 1.0
			tween.tween_property(sq_node, "highlight", 0.0, 0.8).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			delay += 0.04
	tween.finished.connect(_spawn_decorations)


func _spawn_decorations() -> void:
	# Collect empty (non-track) cell indices
	var empty_indices := []
	for y in range(GRID_H):
		for x in range(GRID_W):
			var idx := y * GRID_W + x
			var sq_data = grid_manager.squares[idx]
			var has_track: bool = sq_data.has_flag(TC.S_TRACK) or sq_data.e_count(TC.E_TRACK) > 0
			if not has_track:
				empty_indices.append(idx)

	if empty_indices.is_empty():
		return

	# Pick random 60-80% subset
	empty_indices.shuffle()
	var deco_count := maxi(int(empty_indices.size() * randf_range(0.6, 0.8)), 1)
	var selected := empty_indices.slice(0, deco_count)
	selected.sort()

	# Assign random decoration types
	var types := [square_nodes[0].DECO_TREE, square_nodes[0].DECO_HOUSE, square_nodes[0].DECO_WATER]
	for idx in selected:
		square_nodes[idx].decoration = types[randi() % types.size()]

	# Staggered fade-in
	if _deco_tween and _deco_tween.is_valid():
		_deco_tween.kill()
	_deco_tween = create_tween()
	_deco_tween.set_parallel(true)
	var delay := 0.0
	for idx in selected:
		var sq_node = square_nodes[idx]
		sq_node.deco_alpha = 0.0
		_deco_tween.tween_property(sq_node, "deco_alpha", 1.0, 0.3).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		delay += 0.06


func _on_new_game_pressed() -> void:
	_solved = false
	_drag_active = false
	_drag_sx = -1
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
		_win_tween = null
	if _deco_tween and _deco_tween.is_valid():
		_deco_tween.kill()
		_deco_tween = null
	for sq_node in square_nodes:
		sq_node.queue_free()
	square_nodes.clear()
	grid_manager.grid_changed.disconnect(_on_grid_changed)
	grid_manager.puzzle_solved.disconnect(_on_puzzle_solved)
	grid_manager.generate_puzzle()
	_create_square_nodes()
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)
	_refresh_all()


# ===========================================================================
# Helpers
# ===========================================================================

func _draw_new_button(font_size: int) -> void:
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


func _mouse_to_grid(global_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = global_pos - global_position - GRID_OFFSET
	# Account for the +1 cell offset (clue labels take column 0 / row 0)
	var gx: int = int(local_pos.x / CELL_SIZE) - 1
	var gy: int = int(local_pos.y / CELL_SIZE) - 1
	if local_pos.x < CELL_SIZE or local_pos.y < CELL_SIZE:
		return Vector2i(-1, -1)
	if gx < 0 or gx >= GRID_W or gy < 0 or gy >= GRID_H:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)
