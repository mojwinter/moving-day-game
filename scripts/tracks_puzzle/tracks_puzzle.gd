extends Node2D
## Scene controller for the Night 2 Train Tracks puzzle.
## Creates square nodes, draws clue numbers and A/B markers, routes input.
## Supports chaining: after solving, new tiles drop in adjacent; camera pans to follow.

const CELL_SIZE := 28
const GRID_OFFSET := Vector2(62, 6)
const NEW_BTN_RECT := Rect2(2, 2, 24, 12)

const SquareScene := preload("res://scenes/tracks_puzzle/square.tscn")
const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")
const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")

# Tile drop animation constants
const TILE_DROP_HEIGHT := 40.0
const TILE_DROP_DURATION := 0.35
const TILE_DROP_STAGGER := 0.04
const CAMERA_PAN_DURATION := 0.6

# Progression: [grid_w, grid_h, difficulty] — cycles after last entry
const PROGRESSION := [
	[4, 4, 0],  # 4x4 Easy
	[5, 4, 0],  # 5x4 Easy
	[5, 4, 1],  # 5x4 Tricky
	[6, 5, 0],  # 6x5 Easy
	[6, 5, 1],  # 6x5 Tricky
]

@onready var grid_manager = $GridManager
@onready var _camera: Camera2D = $Camera2D

var square_nodes := []
var _solved := false
var _win_tween: Tween = null
var _deco_tween: Tween = null
var _transition_tween: Tween = null

# Chain state
var _chain_count: int = 0
var _transitioning := false

# Container for current grid's square nodes
var _current_container: Node2D = null
# World-space offset of the current active grid's container
var _current_grid_origin := Vector2.ZERO

# All past grid containers (kept visible as the growing map)
var _old_containers: Array[Node2D] = []

# Label snapshots for each grid (old + current) so we can draw all of them
# Each entry: { origin, w, h, clues, errors, ent_edge, ent_pos, ext_edge, ext_pos }
var _grid_labels: Array = []

# Drag state
var _drag_active := false
var _drag_notrack := false
var _drag_clearing := false
var _drag_sx: int = -1
var _drag_sy: int = -1
var _drag_ex: int = -1
var _drag_ey: int = -1
var _click_pos := Vector2.ZERO


func _ready() -> void:
	_apply_level(0)
	grid_manager.generate_puzzle()
	_current_container = Node2D.new()
	add_child(_current_container)
	_create_square_nodes(_current_container, square_nodes)
	_snapshot_current_labels(Vector2.ZERO)
	_refresh_all()
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)


func _apply_level(chain_idx: int) -> void:
	var level_idx := chain_idx % PROGRESSION.size()
	var level: Array = PROGRESSION[level_idx]
	grid_manager.GRID_W = level[0]
	grid_manager.GRID_H = level[1]


func _current_diff() -> int:
	var level_idx := _chain_count % PROGRESSION.size()
	return PROGRESSION[level_idx][2]


func _create_square_nodes(container: Node2D, nodes_array: Array) -> void:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	for y in range(gh):
		for x in range(gw):
			var sq_node = SquareScene.instantiate()
			sq_node.setup(x, y)
			sq_node.position = GRID_OFFSET + Vector2((x + 1) * CELL_SIZE, (y + 1) * CELL_SIZE)
			sq_node.square_clicked.connect(_on_square_clicked)
			sq_node.square_right_clicked.connect(_on_square_right_clicked)
			container.add_child(sq_node)
			nodes_array.append(sq_node)


func _snapshot_current_labels(origin: Vector2) -> void:
	_grid_labels.append({
		"origin": origin,
		"w": grid_manager.GRID_W,
		"h": grid_manager.GRID_H,
		"clues": grid_manager.clue_numbers.duplicate(),
		"errors": grid_manager.num_errors.duplicate(),
		"ent_edge": grid_manager.entrance_edge,
		"ent_pos": grid_manager.entrance_pos,
		"ext_edge": grid_manager.exit_edge,
		"ext_pos": grid_manager.exit_pos,
	})


# ===========================================================================
# Drawing clue numbers, border, A/B labels
# ===========================================================================

func _draw() -> void:
	# Draw labels for all grids (old + current)
	for label_data in _grid_labels:
		_draw_grid_labels(label_data)

	# "New" button drawn in camera-relative screen space
	_draw_new_button(16)


func _draw_grid_labels(ld: Dictionary) -> void:
	var clues: Array = ld["clues"]
	if clues.size() == 0:
		return
	var gw: int = ld["w"]
	var gh: int = ld["h"]
	var errors: Array = ld["errors"]
	var font_size := 16
	var vy := 6
	var base: Vector2 = ld["origin"] + GRID_OFFSET

	# Column clues (above grid)
	for x in range(gw):
		var num: int = clues[x]
		var is_err: bool = errors[x] != 0
		var col := Color(1.0, 0.2, 0.2) if is_err else Color(0.8, 0.8, 0.7)
		var txt := str(num)
		var tw := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := base + Vector2((x + 1) * CELL_SIZE + CELL_SIZE / 2.0 - tw.x / 2.0, CELL_SIZE / 2.0 + vy)
		draw_string(PIXEL_FONT, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# Row clues (right of grid)
	for y in range(gh):
		var num: int = clues[gw + y]
		var is_err: bool = errors[gw + y] != 0
		var col := Color(1.0, 0.2, 0.2) if is_err else Color(0.8, 0.8, 0.7)
		var txt := str(num)
		var tw := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var pos := base + Vector2((gw + 1) * CELL_SIZE + CELL_SIZE / 2.0 - tw.x / 2.0, (y + 1) * CELL_SIZE + CELL_SIZE / 2.0 + vy)
		draw_string(PIXEL_FONT, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# "A" label at entrance edge
	_draw_edge_label("A", ld["ent_edge"], ld["ent_pos"], base, font_size, vy, gw, gh)

	# "B" label at exit edge
	_draw_edge_label("B", ld["ext_edge"], ld["ext_pos"], base, font_size, vy, gw, gh)


func _draw_edge_label(label: String, edge: int, pos_along: int, base: Vector2, font_size: int, vy: int, gw: int, gh: int) -> void:
	var txt_w := PIXEL_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var lbl_pos := Vector2.ZERO
	match edge:
		TC.EDGE_LEFT:
			lbl_pos = base + Vector2(CELL_SIZE / 2.0 - txt_w.x / 2.0, (pos_along + 1) * CELL_SIZE + CELL_SIZE / 2.0 + vy)
		TC.EDGE_RIGHT:
			lbl_pos = base + Vector2((gw + 2) * CELL_SIZE + CELL_SIZE / 2.0 - txt_w.x / 2.0, (pos_along + 1) * CELL_SIZE + CELL_SIZE / 2.0 + vy)
		TC.EDGE_TOP:
			lbl_pos = base + Vector2((pos_along + 1) * CELL_SIZE + CELL_SIZE / 2.0 - txt_w.x / 2.0, vy - 2)
		TC.EDGE_BOTTOM:
			lbl_pos = base + Vector2((pos_along + 1) * CELL_SIZE + CELL_SIZE / 2.0 - txt_w.x / 2.0, (gh + 1) * CELL_SIZE + CELL_SIZE / 2.0 + vy)
	draw_string(PIXEL_FONT, lbl_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.8, 0.3))


# ===========================================================================
# Input handling
# ===========================================================================

func _on_square_clicked(gx: int, gy: int, local_pos: Vector2) -> void:
	_handle_click(gx, gy, local_pos, false)


func _on_square_right_clicked(gx: int, gy: int, local_pos: Vector2) -> void:
	_handle_click(gx, gy, local_pos, true)


func _handle_click(gx: int, gy: int, local_pos: Vector2, is_right: bool) -> void:
	if _solved or _transitioning:
		return
	var cx := CELL_SIZE / 2.0
	var cy := CELL_SIZE / 2.0
	var dx := local_pos.x - cx
	var dy := local_pos.y - cy

	if max(abs(dx), abs(dy)) < CELL_SIZE / 4.0:
		grid_manager.apply_square_toggle(gx, gy, is_right)
	else:
		var dir: int
		if abs(dx) < abs(dy):
			dir = TC.DIR_U if dy < 0 else TC.DIR_D
		else:
			dir = TC.DIR_L if dx < 0 else TC.DIR_R
		grid_manager.apply_edge_toggle(gx, gy, dir, is_right)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = event.global_position - global_position
		var screen_origin := _camera.offset - Vector2(160, 90)
		var btn_world := Rect2(NEW_BTN_RECT.position + screen_origin, NEW_BTN_RECT.size)
		if btn_world.has_point(local):
			_on_new_game_pressed()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _solved or _transitioning:
		return
	var gw: int = grid_manager.GRID_W
	if event is InputEventMouseButton:
		if event.pressed and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
			var gpos := _mouse_to_grid(event.global_position)
			if gpos != Vector2i(-1, -1):
				_drag_notrack = (event.button_index == MOUSE_BUTTON_RIGHT)
				var idx := gpos.y * gw + gpos.x
				var f := TC.S_NOTRACK if _drag_notrack else TC.S_TRACK
				_drag_clearing = bool(grid_manager.squares[idx].sflags & f)
				_drag_sx = gpos.x
				_drag_sy = gpos.y
				_drag_ex = gpos.x
				_drag_ey = gpos.y
				_click_pos = event.global_position
				_drag_active = false
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
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	var dx: int = absi(_drag_sx - gx)
	var dy: int = absi(_drag_sy - gy)
	if dy == 0:
		_drag_ex = clampi(gx, 0, gw - 1)
		_drag_ey = _drag_sy
		_drag_active = true
	elif dx == 0:
		_drag_ex = _drag_sx
		_drag_ey = clampi(gy, 0, gh - 1)
		_drag_active = true


func _apply_drag() -> void:
	var gw: int = grid_manager.GRID_W
	var x1 := mini(_drag_sx, _drag_ex)
	var x2 := maxi(_drag_sx, _drag_ex)
	var y1 := mini(_drag_sy, _drag_ey)
	var y2 := maxi(_drag_sy, _drag_ey)
	var f := TC.S_NOTRACK if _drag_notrack else TC.S_TRACK

	for x in range(x1, x2 + 1):
		for y in range(y1, y2 + 1):
			var idx := y * gw + x
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
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			square_nodes[idx].refresh(grid_manager.squares[idx])
	# Update current grid's label errors in-place
	if _grid_labels.size() > 0:
		_grid_labels[-1]["errors"] = grid_manager.num_errors.duplicate()
	queue_redraw()


func _on_puzzle_solved() -> void:
	_solved = true
	_play_win_highlight()


func _play_win_highlight() -> void:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	var tween := _win_tween
	tween.set_parallel(true)
	var delay := 0.0
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
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
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	var empty_indices := []
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			var sq_data = grid_manager.squares[idx]
			var has_track: bool = sq_data.has_flag(TC.S_TRACK) or sq_data.e_count(TC.E_TRACK) > 0
			if not has_track:
				empty_indices.append(idx)

	if empty_indices.is_empty():
		_on_decorations_done()
		return

	empty_indices.shuffle()
	var deco_count := maxi(int(empty_indices.size() * randf_range(0.6, 0.8)), 1)
	var selected := empty_indices.slice(0, deco_count)
	selected.sort()

	var types := [square_nodes[0].DECO_TREE, square_nodes[0].DECO_HOUSE, square_nodes[0].DECO_WATER]
	for idx in selected:
		square_nodes[idx].decoration = types[randi() % types.size()]

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
	_deco_tween.finished.connect(_on_decorations_done)


func _on_decorations_done() -> void:
	var pause_tween := create_tween()
	pause_tween.tween_callback(_start_chain_transition).set_delay(1.0)


# ===========================================================================
# Chain transition: tile drop + camera pan
# ===========================================================================

func _start_chain_transition() -> void:
	_transitioning = true

	# Snapshot exit info and current grid size before generating next puzzle
	var old_exit_edge: int = grid_manager.exit_edge
	var old_exit_pos: int = grid_manager.exit_pos
	var old_gw: int = grid_manager.GRID_W
	var old_gh: int = grid_manager.GRID_H

	# Compute where the next grid sits in world space (adjacent to current grid)
	var exit_dir := TC.edge_slide_dir(old_exit_edge)
	var next_origin := _current_grid_origin + Vector2(
		exit_dir.x * old_gw * CELL_SIZE,
		exit_dir.y * old_gh * CELL_SIZE,
	)

	# Compute next puzzle entrance (opposite of current exit, same position)
	var next_ent_edge: int = TC.opposite_edge(old_exit_edge)
	var next_ent_pos := old_exit_pos

	# Disconnect signals so generating the next puzzle doesn't refresh old nodes
	grid_manager.grid_changed.disconnect(_on_grid_changed)
	grid_manager.puzzle_solved.disconnect(_on_puzzle_solved)

	# Retire the current container — disable input so old Area2Ds don't steal clicks
	for sq_node in square_nodes:
		sq_node.square_clicked.disconnect(_on_square_clicked)
		sq_node.square_right_clicked.disconnect(_on_square_right_clicked)
		var click_area: Area2D = sq_node.get_node("ClickArea")
		click_area.input_pickable = false
	_old_containers.append(_current_container)

	# Advance to next level in progression (sets grid_manager.GRID_W/H)
	_chain_count += 1
	_apply_level(_chain_count)
	var next_diff := _current_diff()

	# Generate next puzzle with new dimensions and difficulty
	grid_manager.generate_puzzle_from(next_ent_edge, next_ent_pos, next_diff)

	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H

	# Create new container at its real world position
	_current_container = Node2D.new()
	_current_container.position = next_origin
	add_child(_current_container)
	_current_grid_origin = next_origin

	square_nodes = []
	_create_square_nodes(_current_container, square_nodes)

	# Refresh visuals with new puzzle data
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			square_nodes[idx].refresh(grid_manager.squares[idx])

	# Snapshot labels for the new grid
	_snapshot_current_labels(next_origin)

	# --- Phase 1: Tile drop animation ---
	var ent_cell := TC.edge_to_cell(next_ent_edge, next_ent_pos, gw, gh)

	var tile_order := []
	for y in range(gh):
		for x in range(gw):
			var dist := absi(x - ent_cell.x) + absi(y - ent_cell.y)
			tile_order.append([dist, y * gw + x])
	tile_order.sort_custom(func(a, b): return a[0] < b[0])

	# Set initial state: tiles start above their target, invisible
	var target_positions := []
	target_positions.resize(gw * gh)
	for entry in tile_order:
		var idx: int = entry[1]
		var sq_node = square_nodes[idx]
		target_positions[idx] = sq_node.position
		sq_node.position.y -= TILE_DROP_HEIGHT
		sq_node.modulate.a = 0.0

	# Animate tiles dropping in
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.set_parallel(true)

	var delay := 0.0
	for entry in tile_order:
		var idx: int = entry[1]
		var sq_node = square_nodes[idx]
		var target_pos: Vector2 = target_positions[idx]

		_transition_tween.tween_property(sq_node, "position:y", target_pos.y, TILE_DROP_DURATION) \
			.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_transition_tween.tween_property(sq_node, "modulate:a", 1.0, TILE_DROP_DURATION * 0.6) \
			.set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

		delay += TILE_DROP_STAGGER

	_transition_tween.finished.connect(_on_tile_drop_finished)


func _on_tile_drop_finished() -> void:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	# Camera pan to center on new grid
	var grid_center := _current_grid_origin + GRID_OFFSET + Vector2(
		(gw + 2) * CELL_SIZE / 2.0,
		(gh + 2) * CELL_SIZE / 2.0,
	)
	var target_offset := grid_center

	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.tween_property(_camera, "offset", target_offset, CAMERA_PAN_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.finished.connect(_on_transition_finished)
	queue_redraw()


func _on_transition_finished() -> void:
	_transitioning = false
	_solved = false

	# Reconnect signals for the new puzzle
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)

	_refresh_all()


func _on_new_game_pressed() -> void:
	_solved = false
	_transitioning = false
	_drag_active = false
	_drag_sx = -1
	_chain_count = 0
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
		_win_tween = null
	if _deco_tween and _deco_tween.is_valid():
		_deco_tween.kill()
		_deco_tween = null
	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
		_transition_tween = null

	# Clean up all old containers
	for old_c in _old_containers:
		old_c.queue_free()
	_old_containers.clear()

	# Clean up current container
	for sq_node in square_nodes:
		sq_node.square_clicked.disconnect(_on_square_clicked)
		sq_node.square_right_clicked.disconnect(_on_square_right_clicked)
		sq_node.queue_free()
	square_nodes.clear()
	if _current_container:
		_current_container.queue_free()

	_grid_labels.clear()
	_current_grid_origin = Vector2.ZERO

	grid_manager.grid_changed.disconnect(_on_grid_changed)
	grid_manager.puzzle_solved.disconnect(_on_puzzle_solved)

	_apply_level(0)
	grid_manager.generate_puzzle(_current_diff())
	_current_container = Node2D.new()
	add_child(_current_container)
	_create_square_nodes(_current_container, square_nodes)
	_snapshot_current_labels(Vector2.ZERO)
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)

	# Reset camera
	_camera.offset = Vector2(160, 90)

	_refresh_all()


# ===========================================================================
# Helpers
# ===========================================================================

func _draw_new_button(font_size: int) -> void:
	var screen_origin := _camera.offset - Vector2(160, 90)
	var btn_rect := Rect2(NEW_BTN_RECT.position + screen_origin, NEW_BTN_RECT.size)
	draw_rect(btn_rect, Color(0.25, 0.23, 0.2))
	draw_rect(btn_rect, Color(0.4, 0.38, 0.35), false)
	var txt := "New"
	var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var ascent := PIXEL_FONT.get_ascent(font_size)
	var descent := PIXEL_FONT.get_descent(font_size)
	var text_h := ascent + descent
	var tx := btn_rect.position.x + (btn_rect.size.x - ts.x) / 2.0
	var ty := btn_rect.position.y + (btn_rect.size.y - text_h) / 2.0 + ascent
	draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.8, 0.8, 0.7))


func _mouse_to_grid(global_pos: Vector2) -> Vector2i:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	var local_pos: Vector2 = global_pos - global_position - _current_grid_origin - GRID_OFFSET
	var gx: int = int(local_pos.x / CELL_SIZE) - 1
	var gy: int = int(local_pos.y / CELL_SIZE) - 1
	if local_pos.x < CELL_SIZE or local_pos.y < CELL_SIZE:
		return Vector2i(-1, -1)
	if gx < 0 or gx >= gw or gy < 0 or gy >= gh:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)
