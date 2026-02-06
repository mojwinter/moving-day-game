extends Node2D
## Scene controller for the Night 3 Net/Rotation puzzle.
## Manages 3 sequential stages: Rotation -> Trace (Solder) -> Calibration.

const CELL_SIZE := 120
const GRID_OFFSET := Vector2(100, 100)
const GRID_W := 5
const GRID_H := 5

const TileScene := preload("res://scenes/net_puzzle/tile.tscn")

enum Stage { ROTATION, TRACE, CALIBRATION }

@onready var grid_manager = $GridManager

var tile_nodes := []
var current_stage: int = Stage.ROTATION

# --- Trace stage state ---
var is_dragging := false

# --- Calibration stage state ---
var pot_positions: Array = []       # Array of Vector2i — the 3 tiles with pots
var pot_targets: Array = []         # hidden target value per pot (not shown to player)
var active_pot_index: int = -1      # which pot is being dragged (-1 = none)
var pot_drag_start_y: float = 0.0   # mouse Y when drag started
var pot_drag_start_val: int = 0     # pot value when drag started

const POT_WIN_TOLERANCE := 5        # each dial must be within ±5 of its hidden target
const POT_LABELS := ["V", "R", "F"]


func _ready() -> void:
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.generate_puzzle()
	_create_tile_nodes()
	_refresh_all_tiles()
	_update_stage_label()


func _create_tile_nodes() -> void:
	for y in range(GRID_H):
		for x in range(GRID_W):
			var tile_node = TileScene.instantiate()
			tile_node.setup(x, y)
			tile_node.position = GRID_OFFSET + Vector2(x * CELL_SIZE, y * CELL_SIZE)
			tile_node.tile_clicked.connect(_on_tile_clicked)
			add_child(tile_node)
			tile_nodes.append(tile_node)


# =========================================================================
# Input routing
# =========================================================================

func _on_tile_clicked(x: int, y: int) -> void:
	if current_stage == Stage.ROTATION:
		grid_manager.rotate_tile(x, y)
		_refresh_all_tiles()


func _unhandled_input(event: InputEvent) -> void:
	if current_stage == Stage.TRACE:
		_handle_trace_input(event)
	elif current_stage == Stage.CALIBRATION:
		_handle_calibration_input(event)


# =========================================================================
# Stage transitions
# =========================================================================

func _on_puzzle_solved() -> void:
	# Rotation stage complete -> move to trace
	_enter_trace_stage()


func _enter_trace_stage() -> void:
	current_stage = Stage.TRACE
	# Mark source tile as soldered
	var src: Vector2i = grid_manager.source_pos
	grid_manager.tiles[src.y * GRID_W + src.x].is_soldered = true
	_set_all_draw_mode(1)  # TRACE
	_refresh_all_tiles()
	_update_stage_label()


func _enter_calibration_stage() -> void:
	current_stage = Stage.CALIBRATION
	_pick_pot_tiles()
	_generate_targets()
	_set_all_draw_mode(2)  # CALIBRATION
	_update_calibration_colors()
	_refresh_all_tiles()
	_update_stage_label()


func _on_all_stages_complete() -> void:
	$WinLabel.visible = true
	_update_stage_label()


# =========================================================================
# Trace stage — drag to solder
# =========================================================================

func _handle_trace_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var gpos := _mouse_to_grid(event.global_position)
			if gpos != Vector2i(-1, -1):
				var idx := gpos.y * GRID_W + gpos.x
				if grid_manager.tiles[idx].is_soldered:
					is_dragging = true
		else:
			is_dragging = false

	elif event is InputEventMouseMotion and is_dragging:
		var gpos := _mouse_to_grid(event.global_position)
		if gpos == Vector2i(-1, -1):
			return
		var idx := gpos.y * GRID_W + gpos.x
		var td = grid_manager.tiles[idx]
		if td.is_soldered:
			return  # already done
		if (td.connections & 0x0F) == 0:
			return  # no connections on this tile
		# Check adjacency to any soldered tile via mutual connection
		if _is_adjacent_to_soldered(gpos.x, gpos.y):
			td.is_soldered = true
			_refresh_all_tiles()
			_check_trace_win()


func _is_adjacent_to_soldered(x: int, y: int) -> bool:
	var neighbors: Array = grid_manager.get_connected_neighbors(x, y)
	for npos in neighbors:
		var nidx: int = npos.y * GRID_W + npos.x
		if grid_manager.tiles[nidx].is_soldered:
			return true
	return false


func _check_trace_win() -> void:
	for tile in grid_manager.tiles:
		if (tile.connections & 0x0F) != 0 and not tile.is_soldered:
			return
	# All connected tiles soldered
	_enter_calibration_stage()


# =========================================================================
# Calibration stage — potentiometer knobs on tiles
# =========================================================================

func _pick_pot_tiles() -> void:
	pot_positions.clear()
	# Gather candidate tiles: non-source, has connections
	var candidates := []
	for y in range(GRID_H):
		for x in range(GRID_W):
			var idx := y * GRID_W + x
			var td = grid_manager.tiles[idx]
			if not td.is_source and (td.connections & 0x0F) != 0:
				candidates.append(Vector2i(x, y))
	candidates.shuffle()
	for i in range(mini(3, candidates.size())):
		var pos: Vector2i = candidates[i]
		pot_positions.append(pos)
		var td = grid_manager.tiles[pos.y * GRID_W + pos.x]
		td.has_pot = true
		td.pot_value = 50
		td.pot_label = POT_LABELS[i]


func _generate_targets() -> void:
	pot_targets.clear()
	for i in range(pot_positions.size()):
		pot_targets.append(randi_range(10, 90))


func _handle_calibration_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Check if clicking on a pot tile
			var gpos := _mouse_to_grid(event.global_position)
			if gpos != Vector2i(-1, -1):
				for i in range(pot_positions.size()):
					if pot_positions[i] == gpos:
						active_pot_index = i
						pot_drag_start_y = event.global_position.y
						pot_drag_start_val = grid_manager.tiles[gpos.y * GRID_W + gpos.x].pot_value
						break
		else:
			active_pot_index = -1

	elif event is InputEventMouseMotion and active_pot_index >= 0:
		# Drag up = increase, drag down = decrease
		var delta_y: float = pot_drag_start_y - event.global_position.y
		var delta_val: int = int(delta_y / 2.0)  # 2 pixels per unit
		var new_val: int = clampi(pot_drag_start_val + delta_val, 0, 100)
		var pos: Vector2i = pot_positions[active_pot_index]
		grid_manager.tiles[pos.y * GRID_W + pos.x].pot_value = new_val
		_update_calibration_colors()
		_refresh_all_tiles()
		_update_stage_label()
		_check_calibration_win()


func _pot_error(i: int) -> int:
	var pos: Vector2i = pot_positions[i]
	var val: int = grid_manager.tiles[pos.y * GRID_W + pos.x].pot_value
	return absi(val - pot_targets[i])


## Map error distance to a smooth color gradient:
## green (close) -> yellow -> orange -> red/dim (far)
func _error_to_color(error: int) -> Color:
	if error <= POT_WIN_TOLERANCE:
		return Color(0.2, 1.0, 0.3)           # bright green — locked in
	var t: float = clampf(float(error - POT_WIN_TOLERANCE) / 45.0, 0.0, 1.0)
	# green(0) -> yellow(0.33) -> orange(0.66) -> dim red(1.0)
	if t < 0.33:
		var s: float = t / 0.33
		return Color(0.2 + 0.5 * s, 1.0 - 0.1 * s, 0.3 - 0.1 * s)  # green -> yellow
	elif t < 0.66:
		var s: float = (t - 0.33) / 0.33
		return Color(0.7 + 0.2 * s, 0.9 - 0.5 * s, 0.2 - 0.1 * s)  # yellow -> orange
	else:
		var s: float = (t - 0.66) / 0.34
		return Color(0.9 - 0.55 * s, 0.4 - 0.25 * s, 0.1 + 0.2 * s)  # orange -> dim


func _update_calibration_colors() -> void:
	var per_pot_colors: Array = []

	for i in range(pot_positions.size()):
		per_pot_colors.append(_error_to_color(_pot_error(i)))

	# Board color reflects worst-performing dial so player can't ignore any
	var worst_error := 0
	for i in range(pot_positions.size()):
		worst_error = maxi(worst_error, _pot_error(i))
	var board_color: Color = _error_to_color(worst_error)

	# Apply per-pot color to pot tiles, board color to everything else
	for y in range(GRID_H):
		for x in range(GRID_W):
			var idx := y * GRID_W + x
			var node = tile_nodes[idx]
			var is_pot_tile := false
			for i in range(pot_positions.size()):
				if pot_positions[i] == Vector2i(x, y):
					node.calibration_color = per_pot_colors[i]
					is_pot_tile = true
					break
			if not is_pot_tile:
				node.calibration_color = board_color


func _check_calibration_win() -> void:
	for i in range(pot_positions.size()):
		if _pot_error(i) > POT_WIN_TOLERANCE:
			return
	_on_all_stages_complete()


# =========================================================================
# Helpers
# =========================================================================

func _mouse_to_grid(global_pos: Vector2) -> Vector2i:
	var local_pos: Vector2 = global_pos - global_position - GRID_OFFSET
	var gx: int = int(local_pos.x / CELL_SIZE)
	var gy: int = int(local_pos.y / CELL_SIZE)
	if gx < 0 or gx >= GRID_W or gy < 0 or gy >= GRID_H:
		return Vector2i(-1, -1)
	if local_pos.x < 0 or local_pos.y < 0:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func _set_all_draw_mode(mode: int) -> void:
	for node in tile_nodes:
		node.draw_mode = mode


func _refresh_all_tiles() -> void:
	for y in range(GRID_H):
		for x in range(GRID_W):
			var idx := y * GRID_W + x
			tile_nodes[idx].refresh(grid_manager.tiles[idx])


func _update_stage_label() -> void:
	if not has_node("StageLabel"):
		return
	match current_stage:
		Stage.ROTATION:
			$StageLabel.text = "Rotate tiles to connect all paths"
		Stage.TRACE:
			$StageLabel.text = "Drag along the traces to lay solder"
		Stage.CALIBRATION:
			var locked := 0
			for i in range(pot_positions.size()):
				if _pot_error(i) <= POT_WIN_TOLERANCE:
					locked += 1
			$StageLabel.text = "Tune each dial until it glows green  (%d / %d locked)" % [
				locked, pot_positions.size()]


func _on_new_game_pressed() -> void:
	$WinLabel.visible = false
	current_stage = Stage.ROTATION
	is_dragging = false
	active_pot_index = -1
	pot_positions.clear()
	# Remove old tile nodes
	for tile_node in tile_nodes:
		tile_node.queue_free()
	tile_nodes.clear()
	# Reset solder/pot state and generate new puzzle
	grid_manager.generate_puzzle()
	# Clear solder/pot flags (generate_puzzle creates fresh TileData instances)
	_set_all_draw_mode(0)  # ROTATION
	_create_tile_nodes()
	_refresh_all_tiles()
	_update_stage_label()
