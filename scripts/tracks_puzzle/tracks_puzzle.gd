extends Node2D
## Scene controller for the Night 2 Train Tracks puzzle.
## Creates square nodes, draws clue numbers and A/B markers, routes input.
## Supports chaining: after solving, new tiles drop in adjacent; camera pans to follow.

const CELL_SIZE := 16
const CELL_STRIDE := 17  # 16px cell + 1px shared border
const GRID_LINE_COLOR := Color(0.35, 0.33, 0.3)
const VIEWPORT_SIZE := Vector2(320, 180)
var GRID_OFFSET := Vector2.ZERO


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
var _tile_flip_tween: Tween = null
var _grid_line_alpha: float = 1.0:
	set(v):
		_grid_line_alpha = v
		if not _grid_labels.is_empty():
			_grid_labels[-1]["alpha"] = v
		queue_redraw()

# Chain state
var _chain_count: int = 0
var _transitioning := false

# Container for current grid's square nodes
var _current_container: Node2D = null
var _current_border: Node2D = null
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
	# Center the grid on screen
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	var grid_total_w := (gw + 2) * CELL_STRIDE + 1
	var grid_total_h := (gh + 2) * CELL_STRIDE + 1
	GRID_OFFSET = Vector2(
		floor((VIEWPORT_SIZE.x - grid_total_w) / 2.0),
		floor((VIEWPORT_SIZE.y - grid_total_h) / 2.0),
	)
	_current_container = Node2D.new()
	add_child(_current_container)
	_create_square_nodes(_current_container, square_nodes)
	_current_border = _create_border_node(_current_container)
	_snapshot_current_labels(Vector2.ZERO)
	_refresh_all()
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)


func _apply_level(chain_idx: int) -> void:
	var level_idx := mini(chain_idx, PROGRESSION.size() - 1)
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
			sq_node.position = GRID_OFFSET + Vector2((x + 1) * CELL_STRIDE + 1, (y + 1) * CELL_STRIDE + 1)
			sq_node.square_clicked.connect(_on_square_clicked)
			sq_node.square_right_clicked.connect(_on_square_right_clicked)
			container.add_child(sq_node)
			nodes_array.append(sq_node)


func _create_border_node(container: Node2D) -> Node2D:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	var x0 := GRID_OFFSET.x + CELL_STRIDE
	var y0 := GRID_OFFSET.y + CELL_STRIDE
	var total_w := gw * CELL_STRIDE + 1
	var total_h := gh * CELL_STRIDE + 1
	var border := Node2D.new()
	border.z_index = 1
	border.set_meta("x0", x0)
	border.set_meta("y0", y0)
	border.set_meta("total_w", total_w)
	border.set_meta("total_h", total_h)
	border.draw.connect(func() -> void:
		var bx: float = border.get_meta("x0")
		var by: float = border.get_meta("y0")
		var bw: float = border.get_meta("total_w")
		var bh: float = border.get_meta("total_h")
		# Top and bottom
		border.draw_rect(Rect2(bx, by, bw, 1), GRID_LINE_COLOR)
		border.draw_rect(Rect2(bx, by + bh - 1, bw, 1), GRID_LINE_COLOR)
		# Left and right
		border.draw_rect(Rect2(bx, by + 1, 1, bh - 2), GRID_LINE_COLOR)
		border.draw_rect(Rect2(bx + bw - 1, by + 1, 1, bh - 2), GRID_LINE_COLOR)
	)
	container.add_child(border)
	return border


func _snapshot_current_labels(origin: Vector2) -> void:
	var ent: int = grid_manager.entrance_edge
	# Place clues on sides where no old puzzle overlaps.
	# Check each candidate side against all existing grid rects.
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	var col_edge := _pick_free_edge(origin, gw, gh, [TC.EDGE_TOP, TC.EDGE_BOTTOM])
	var row_edge := _pick_free_edge(origin, gw, gh, [TC.EDGE_RIGHT, TC.EDGE_LEFT])

	_grid_labels.append({
		"origin": origin,
		"w": grid_manager.GRID_W,
		"h": grid_manager.GRID_H,
		"clues": grid_manager.clue_numbers.duplicate(),
		"errors": grid_manager.num_errors.duplicate(),
		"ent_edge": ent,
		"ent_pos": grid_manager.entrance_pos,
		"ext_edge": grid_manager.exit_edge,
		"ext_pos": grid_manager.exit_pos,
		"clue_col_edge": col_edge,
		"clue_row_edge": row_edge,
		"alpha": 1.0,
	})


# ===========================================================================
# Drawing clue numbers, border, A/B labels
# ===========================================================================

func _draw() -> void:
	# Draw labels for all grids (old + current)
	for label_data in _grid_labels:
		_draw_grid_labels(label_data)



func _draw_grid_lines(origin: Vector2, gw: int, gh: int, alpha: float) -> void:
	var base := origin + GRID_OFFSET
	var x0 := base.x + CELL_STRIDE
	var y0 := base.y + CELL_STRIDE
	var total_w := gw * CELL_STRIDE + 1
	var total_h := gh * CELL_STRIDE + 1
	var col := Color(GRID_LINE_COLOR, alpha)
	# Inner horizontal lines only (skip first and last = outer border)
	for row in range(1, gh):
		var y := y0 + row * CELL_STRIDE
		draw_rect(Rect2(x0, y, total_w, 1), col)
	# Inner vertical lines only
	for column in range(1, gw):
		var x := x0 + column * CELL_STRIDE
		draw_rect(Rect2(x, y0, 1, total_h), col)


func _draw_grid_labels(ld: Dictionary) -> void:
	var clues: Array = ld["clues"]
	if clues.size() == 0:
		return
	var gw: int = ld["w"]
	var gh: int = ld["h"]
	var alpha: float = ld.get("alpha", 1.0)
	if alpha > 0.0:
		_draw_grid_lines(ld["origin"], gw, gh, alpha)

	if alpha <= 0.0:
		return

	var errors: Array = ld["errors"]
	var font_size := 16
	var vy := 6
	var base: Vector2 = ld["origin"] + GRID_OFFSET
	var col_edge: int = ld.get("clue_col_edge", TC.EDGE_TOP)
	var row_edge: int = ld.get("clue_row_edge", TC.EDGE_RIGHT)

	# Column clues (top or bottom of grid)
	for x in range(gw):
		var num: int = clues[x]
		var is_err: bool = errors[x] != 0
		var col := Color(1.0, 0.2, 0.2, alpha) if is_err else Color(0.8, 0.8, 0.7, alpha)
		var txt := str(num)
		var tw := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var cx := (x + 1) * CELL_STRIDE + 1 + CELL_SIZE / 2.0 - tw.x / 2.0
		var cy: float
		if col_edge == TC.EDGE_TOP:
			cy = CELL_STRIDE / 2.0 + vy
		else:
			cy = (gh + 1) * CELL_STRIDE + 1 + CELL_SIZE / 2.0 + vy
		draw_string(PIXEL_FONT, base + Vector2(cx, cy), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# Row clues (left or right of grid)
	for y in range(gh):
		var num: int = clues[gw + y]
		var is_err: bool = errors[gw + y] != 0
		var col := Color(1.0, 0.2, 0.2, alpha) if is_err else Color(0.8, 0.8, 0.7, alpha)
		var txt := str(num)
		var tw := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var rx: float
		if row_edge == TC.EDGE_RIGHT:
			rx = (gw + 1) * CELL_STRIDE + 1 + CELL_SIZE / 2.0 - tw.x / 2.0
		else:
			rx = CELL_STRIDE / 2.0 - tw.x / 2.0
		var ry := (y + 1) * CELL_STRIDE + 1 + CELL_SIZE / 2.0 + vy
		draw_string(PIXEL_FONT, base + Vector2(rx, ry), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)




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
			# Compute neighbor track edges facing this cell
			var nt := 0
			if x > 0 and (grid_manager.squares[idx - 1].e_dirs(TC.E_TRACK) & TC.DIR_R):
				nt |= TC.DIR_L
			if y > 0 and (grid_manager.squares[idx - gw].e_dirs(TC.E_TRACK) & TC.DIR_D):
				nt |= TC.DIR_U
			if x < gw - 1 and (grid_manager.squares[idx + 1].e_dirs(TC.E_TRACK) & TC.DIR_L):
				nt |= TC.DIR_R
			if y < gh - 1 and (grid_manager.squares[idx + gw].e_dirs(TC.E_TRACK) & TC.DIR_U):
				nt |= TC.DIR_D
			square_nodes[idx]._neighbor_track = nt
			square_nodes[idx].refresh(grid_manager.squares[idx])
	# Update current grid's label errors in-place
	if _grid_labels.size() > 0:
		_grid_labels[-1]["errors"] = grid_manager.num_errors.duplicate()
	queue_redraw()


func _on_puzzle_solved() -> void:
	_solved = true
	print("[TRACKS] puzzle_solved chain=%d  grid=%dx%d  origin=%s" % [_chain_count, grid_manager.GRID_W, grid_manager.GRID_H, _current_grid_origin])
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
	print("[TRACKS] win_highlight started  total_delay=%.2fs" % delay)
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

	print("[TRACKS] spawn_decorations  empty_count=%d" % empty_indices.size())
	if empty_indices.is_empty():
		print("[TRACKS]   no empties, skipping to transition")
		_on_decorations_done()
		return

	# Build a set of empty cell indices for fast neighbor lookup
	var empty_set := {}
	for idx in empty_indices:
		empty_set[idx] = true

	# Compute autotile neighbor mask for each empty cell
	for idx in empty_indices:
		var x: int = idx % gw
		var y: int = idx / gw
		var mask := 0
		if x < gw - 1 and empty_set.has(idx + 1):
			mask |= TC.DIR_R
		if y > 0 and empty_set.has(idx - gw):
			mask |= TC.DIR_U
		if x > 0 and empty_set.has(idx - 1):
			mask |= TC.DIR_L
		if y < gh - 1 and empty_set.has(idx + gw):
			mask |= TC.DIR_D
		# Diagonal neighbors for inner corners (NE=16, NW=32, SE=64, SW=128)
		if x < gw - 1 and y > 0 and empty_set.has(idx - gw + 1):
			mask |= 16  # NE
		if x > 0 and y > 0 and empty_set.has(idx - gw - 1):
			mask |= 32  # NW
		if x < gw - 1 and y < gh - 1 and empty_set.has(idx + gw + 1):
			mask |= 64  # SE
		if x > 0 and y < gh - 1 and empty_set.has(idx + gw - 1):
			mask |= 128  # SW
		square_nodes[idx]._green_mask = mask

	# All empty cells get DECO_TREE (green autotile); pick some for house/water instead
	var selected := empty_indices.duplicate()
	selected.sort()
	print("[TRACKS]   placing %d decorations" % selected.size())

	for idx in selected:
		square_nodes[idx].decoration = square_nodes[0].DECO_TREE

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
	_deco_tween.finished.connect(_flip_tiles_to_grey)


func _flip_tiles_to_grey() -> void:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	if _tile_flip_tween and _tile_flip_tween.is_valid():
		_tile_flip_tween.kill()
	_tile_flip_tween = create_tween()
	_tile_flip_tween.set_parallel(true)
	var delay := 0.0
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			var sq_node = square_nodes[idx]
			sq_node.tile_blend = 0.0
			_tile_flip_tween.tween_property(sq_node, "tile_blend", 1.0, 0.3).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			delay += 0.04
	_tile_flip_tween.finished.connect(_on_decorations_done)


func _on_decorations_done() -> void:
	print("[TRACKS] decorations_done -> fading grid lines")
	_grid_line_alpha = 1.0
	var fade_tween := create_tween()
	fade_tween.set_parallel(true)
	fade_tween.tween_property(self, "_grid_line_alpha", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Bleed cell edges into the grid gaps as lines fade
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	for y in range(gh):
		for x in range(gw):
			var sq_node = square_nodes[y * gw + x]
			sq_node.grid_bleed = 0.0
			fade_tween.tween_property(sq_node, "grid_bleed", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			# Right column owns the right outer border
			if x == gw - 1:
				sq_node.grid_bleed_right = 0.0
				fade_tween.tween_property(sq_node, "grid_bleed_right", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			# Bottom row owns the bottom outer border
			if y == gh - 1:
				sq_node.grid_bleed_bottom = 0.0
				fade_tween.tween_property(sq_node, "grid_bleed_bottom", 1.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fade_tween.set_parallel(false)
	fade_tween.tween_callback(_start_chain_transition).set_delay(0.5)


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

	# Compute next puzzle entrance (opposite of current exit, same position)
	var next_ent_edge: int = TC.opposite_edge(old_exit_edge)
	var next_ent_pos := old_exit_pos

	var _edge_names := {TC.EDGE_LEFT: "LEFT", TC.EDGE_RIGHT: "RIGHT", TC.EDGE_TOP: "TOP", TC.EDGE_BOTTOM: "BOTTOM"}
	print("=== CHAIN TRANSITION #%d ===" % _chain_count)
	print("  old grid: %dx%d  origin=%s" % [old_gw, old_gh, _current_grid_origin])
	print("  old exit: edge=%s pos=%d" % [_edge_names.get(old_exit_edge, "?"), old_exit_pos])
	print("  new entrance: edge=%s pos=%d" % [_edge_names.get(next_ent_edge, "?"), next_ent_pos])

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
	var level_idx := mini(_chain_count, PROGRESSION.size() - 1)
	print("  progression: chain_count=%d  level_idx=%d  target=%dx%d  diff=%d" % [_chain_count, level_idx, grid_manager.GRID_W, grid_manager.GRID_H, next_diff])

	# Generate next puzzle, aligning entrance cell with exit cell for continuity
	var next_origin: Vector2
	var gw: int
	var gh: int
	var old_exit_cell := TC.edge_to_cell(old_exit_edge, old_exit_pos, old_gw, old_gh)
	var exit_dir := TC.edge_slide_dir(old_exit_edge)
	var max_attempts := 10
	var placed := false
	for _attempt in range(max_attempts):
		grid_manager.generate_puzzle_from(next_ent_edge, next_ent_pos, next_diff)
		gw = grid_manager.GRID_W
		gh = grid_manager.GRID_H

		var new_ent_cell := TC.edge_to_cell(next_ent_edge, next_ent_pos, gw, gh)

		# Place grid adjacent along exit direction
		var off_w: int = old_gw if exit_dir.x > 0 else gw
		var off_h: int = old_gh if exit_dir.y > 0 else gh
		var base_origin := _current_grid_origin + Vector2(
			exit_dir.x * off_w * CELL_STRIDE,
			exit_dir.y * off_h * CELL_STRIDE,
		)
		# Align the entrance cell with the exit cell on the perpendicular axis
		# For vertical exits (TOP/BOTTOM): align columns (x)
		# For horizontal exits (LEFT/RIGHT): align rows (y)
		if exit_dir.x != 0:
			base_origin.y += (old_exit_cell.y - new_ent_cell.y) * CELL_STRIDE
		else:
			base_origin.x += (old_exit_cell.x - new_ent_cell.x) * CELL_STRIDE

		# Try aligned position first, then shift perpendicular if it overlaps
		var perp := Vector2(-exit_dir.y, exit_dir.x)
		for shift in range(0, 6):
			var sign_mult: int = -1 if shift % 2 == 1 else 1
			@warning_ignore("INTEGER_DIVISION")
			var shift_amount: int = (shift + 1) / 2 * sign_mult
			next_origin = base_origin + perp * (shift_amount * CELL_STRIDE)
			if not _grid_overlaps(next_origin, gw, gh):
				placed = true
				break
		if placed:
			break

	print("  generated: %dx%d  entrance=%s@%d  exit=%s@%d" % [gw, gh, _edge_names.get(grid_manager.entrance_edge, "?"), grid_manager.entrance_pos, _edge_names.get(grid_manager.exit_edge, "?"), grid_manager.exit_pos])
	print("  next_origin=%s  (delta=%s)" % [next_origin, next_origin - _current_grid_origin])

	# Create new container at its real world position
	_current_container = Node2D.new()
	_current_container.position = next_origin
	add_child(_current_container)
	_current_grid_origin = next_origin

	square_nodes = []
	_create_square_nodes(_current_container, square_nodes)
	_current_border = _create_border_node(_current_container)

	# Refresh visuals with new puzzle data
	for y in range(gh):
		for x in range(gw):
			var idx := y * gw + x
			square_nodes[idx].refresh(grid_manager.squares[idx])

	# Snapshot labels for the new grid
	_grid_line_alpha = 1.0
	_snapshot_current_labels(next_origin)

	# Fade out old grid's clue labels (second-to-last entry, since we just appended the new one)
	var old_label_idx := _grid_labels.size() - 2
	if old_label_idx >= 0:
		var old_ld: Dictionary = _grid_labels[old_label_idx]
		var fade_tween := create_tween()
		var fade_dur := TILE_DROP_DURATION + TILE_DROP_STAGGER * gw * gh
		fade_tween.set_parallel(true)
		fade_tween.tween_method(func(v: float) -> void:
			old_ld["alpha"] = v
			queue_redraw()
		, old_ld["alpha"], 0.0, fade_dur)

	# --- Phase 1: Tile drop animation ---
	print("  tile_drop: %d tiles  drop_height=%.0f  duration=%.2f  stagger=%.2f" % [gw * gh, TILE_DROP_HEIGHT, TILE_DROP_DURATION, TILE_DROP_STAGGER])
	var ent_cell := TC.edge_to_cell(next_ent_edge, next_ent_pos, gw, gh)
	print("  entrance_cell=(%d,%d)  tiles ripple from here" % [ent_cell.x, ent_cell.y])

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

	print("  tile_drop: total_anim_time=%.2fs" % (delay + TILE_DROP_DURATION))
	_transition_tween.finished.connect(_on_tile_drop_finished)


func _on_tile_drop_finished() -> void:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	# Camera pan to center on new grid
	var grid_center := _current_grid_origin + GRID_OFFSET + Vector2(
		floor(((gw + 2) * CELL_STRIDE + 1) / 2.0),
		floor(((gh + 2) * CELL_STRIDE + 1) / 2.0),
	)
	var target_offset := grid_center
	print("[TRACKS] tile_drop_finished -> camera pan  from=%s  to=%s  duration=%.2f" % [_camera.offset, target_offset, CAMERA_PAN_DURATION])

	if _transition_tween and _transition_tween.is_valid():
		_transition_tween.kill()
	_transition_tween = create_tween()
	_transition_tween.tween_property(_camera, "offset", target_offset, CAMERA_PAN_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	_transition_tween.finished.connect(_on_transition_finished)
	queue_redraw()


func _on_transition_finished() -> void:
	# Snap camera to integer position to avoid sub-pixel rendering
	_camera.offset = Vector2(round(_camera.offset.x), round(_camera.offset.y))
	_transitioning = false
	_solved = false
	print("[TRACKS] transition_finished  chain=%d  grid=%dx%d  origin=%s  camera=%s" % [_chain_count, grid_manager.GRID_W, grid_manager.GRID_H, _current_grid_origin, _camera.offset])
	print("[TRACKS]   ready for player input")

	# Reconnect signals for the new puzzle
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)

	_refresh_all()



# ===========================================================================
# Helpers
# ===========================================================================

## Check if placing clues on a given edge of the current grid would overlap
## with any existing old grid's tile area. Returns true if the clue zone on
## that edge intersects an old grid's tile rect.
func _edge_blocked(origin: Vector2, gw: int, gh: int, edge: int) -> bool:
	# The clue zone is a 1-cell-wide strip on the given edge.
	# Compute the world-space rect of that strip.
	var base := origin + GRID_OFFSET
	var clue_rect: Rect2
	match edge:
		TC.EDGE_TOP:
			clue_rect = Rect2(base.x + CELL_STRIDE, base.y, gw * CELL_STRIDE, CELL_STRIDE)
		TC.EDGE_BOTTOM:
			clue_rect = Rect2(base.x + CELL_STRIDE, base.y + (gh + 1) * CELL_STRIDE, gw * CELL_STRIDE, CELL_STRIDE)
		TC.EDGE_LEFT:
			clue_rect = Rect2(base.x, base.y + CELL_STRIDE, CELL_STRIDE, gh * CELL_STRIDE)
		TC.EDGE_RIGHT:
			clue_rect = Rect2(base.x + (gw + 1) * CELL_STRIDE, base.y + CELL_STRIDE, CELL_STRIDE, gh * CELL_STRIDE)
		_:
			return false

	# Check against all existing grids' tile areas
	for ld in _grid_labels:
		var old_origin: Vector2 = ld["origin"]
		var old_gw: int = ld["w"]
		var old_gh: int = ld["h"]
		var old_base := old_origin + GRID_OFFSET
		# Tile area: starts at (1,1) stride offset, spans gw x gh strides
		var tile_rect := Rect2(
			old_base.x + CELL_STRIDE, old_base.y + CELL_STRIDE,
			old_gw * CELL_STRIDE, old_gh * CELL_STRIDE
		)
		if clue_rect.intersects(tile_rect):
			return true
	return false


## Check if a new grid's tile area at the given origin would overlap any existing grid.
func _grid_overlaps(origin: Vector2, gw: int, gh: int) -> bool:
	var base := origin + GRID_OFFSET
	var new_rect := Rect2(
		base.x + CELL_STRIDE, base.y + CELL_STRIDE,
		gw * CELL_STRIDE, gh * CELL_STRIDE
	)
	for ld in _grid_labels:
		var old_base: Vector2 = ld["origin"] + GRID_OFFSET
		var old_rect := Rect2(
			old_base.x + CELL_STRIDE, old_base.y + CELL_STRIDE,
			ld["w"] * CELL_STRIDE, ld["h"] * CELL_STRIDE
		)
		if new_rect.intersects(old_rect):
			return true
	return false


## Pick the first unblocked edge from candidates. Falls back to first candidate.
func _pick_free_edge(origin: Vector2, gw: int, gh: int, candidates: Array) -> int:
	for edge in candidates:
		if not _edge_blocked(origin, gw, gh, edge):
			return edge
	return candidates[0]


func _mouse_to_grid(global_pos: Vector2) -> Vector2i:
	var gw: int = grid_manager.GRID_W
	var gh: int = grid_manager.GRID_H
	var local_pos: Vector2 = global_pos - global_position - _current_grid_origin - GRID_OFFSET
	var gx: int = int(local_pos.x / CELL_STRIDE) - 1
	var gy: int = int(local_pos.y / CELL_STRIDE) - 1
	if local_pos.x < CELL_STRIDE or local_pos.y < CELL_STRIDE:
		return Vector2i(-1, -1)
	if gx < 0 or gx >= gw or gy < 0 or gy >= gh:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)
