extends Node2D
## Scene controller for the Night 5 Shadow puzzle.
## Player drags polyomino pieces from a tray into a silhouette on the wall.

const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")

# --- Layout ---
const CELL := 10
const GRID_W := 12
const GRID_H := 12
const WALL_ORIGIN := Vector2(188, 14)
const TRAY_X := 12.0
const TRAY_Y := 14.0
const TRAY_W := 164.0
const TRAY_H := 152.0

const NEW_BTN_RECT := Rect2(2, 2, 24, 12)
const LIGHT_POS := Vector2(182, 90) # cosmetic glow at wall edge

# --- Colors ---
const BG_COLOR := Color(0.05, 0.04, 0.09)
const WALL_BG := Color(0.09, 0.07, 0.13)
const SILHOUETTE_COLOR := Color(0.16, 0.18, 0.28, 0.35)
const SHADOW_FILLED := Color(0.02, 0.02, 0.05, 0.92)
const OVERLAP_COLOR := Color(0.6, 0.15, 0.15, 0.45)
const WIN_GLOW := Color(1.0, 0.95, 0.7)
const LIGHT_GLOW := Color(1.0, 0.85, 0.5, 0.18)
const RAY_COLOR := Color(1.0, 0.9, 0.6, 0.025)
const DUST_COLOR := Color(1.0, 0.85, 0.5, 0.10)
const GRID_LINE := Color(0.14, 0.12, 0.20, 0.15)

@onready var grid_manager: Node = $GridManager

# --- Interaction ---
var _dragging_id: int = -1
var _drag_offset := Vector2.ZERO
var _drag_mouse := Vector2.ZERO # current mouse pos while dragging
var _solved := false
var _win_tween: Tween = null
var _win_progress: float = 0.0

# --- Dust motes ---
var _dust: Array[Dictionary] = []
const DUST_COUNT := 20


func _ready() -> void:
	grid_manager.generate_puzzle()
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)
	_init_dust()
	queue_redraw()


func _process(delta: float) -> void:
	_update_dust(delta)
	queue_redraw()


# ===========================================================================
# Drawing
# ===========================================================================

func _draw() -> void:
	_draw_background()
	_draw_light_glow()
	_draw_rays()
	_draw_wall()
	_draw_silhouette()
	_draw_placed_pieces()
	_draw_tray_pieces()
	_draw_drag_preview()
	_draw_dust()
	_draw_new_button()
	_draw_puzzle_name()


func _draw_background() -> void:
	draw_rect(Rect2(0, 0, 320, 180), BG_COLOR)
	# Tray area — subtle outline
	draw_rect(Rect2(TRAY_X, TRAY_Y, TRAY_W, TRAY_H), Color(0.08, 0.07, 0.12), false, 1.0)


func _draw_light_glow() -> void:
	for i in range(4, 0, -1):
		var r: float = 3.0 + float(i) * 3.0
		var a: float = LIGHT_GLOW.a * (1.0 - float(i) / 5.0)
		draw_circle(LIGHT_POS, r, Color(LIGHT_GLOW, a))
	draw_circle(LIGHT_POS, 2.0, Color(1.0, 0.95, 0.7, 0.4))


func _draw_rays() -> void:
	for y in range(0, 180, 14):
		draw_line(Vector2(LIGHT_POS.x - 2, float(y)), Vector2(WALL_ORIGIN.x, float(y)), RAY_COLOR, 1.0)


func _draw_wall() -> void:
	var w: float = float(GRID_W * CELL)
	var h: float = float(GRID_H * CELL)
	draw_rect(Rect2(WALL_ORIGIN, Vector2(w, h)), WALL_BG)
	# Subtle grid lines (only inside silhouette area, very faint)
	for x in range(GRID_W + 1):
		var px: float = WALL_ORIGIN.x + float(x * CELL)
		draw_line(Vector2(px, WALL_ORIGIN.y), Vector2(px, WALL_ORIGIN.y + h), GRID_LINE, 1.0)
	for y in range(GRID_H + 1):
		var py: float = WALL_ORIGIN.y + float(y * CELL)
		draw_line(Vector2(WALL_ORIGIN.x, py), Vector2(WALL_ORIGIN.x + w, py), GRID_LINE, 1.0)


func _draw_silhouette() -> void:
	# Draw the target shape as a faint shadow outline
	var pulse: float = sin(Time.get_ticks_msec() * 0.002) * 0.03
	var col := Color(SILHOUETTE_COLOR.r, SILHOUETTE_COLOR.g, SILHOUETTE_COLOR.b,
		SILHOUETTE_COLOR.a + pulse)
	for cell in grid_manager.silhouette:
		var rect := _cell_rect(cell)
		draw_rect(rect, col)


func _draw_placed_pieces() -> void:
	var occupied: Dictionary = grid_manager.get_occupied_cells()
	for piece in grid_manager.pieces:
		if not piece.is_placed():
			continue
		var rects: Array[Rect2] = piece.get_draw_rects(WALL_ORIGIN)
		var col: Color = piece.color
		if _solved:
			col = Color(WIN_GLOW, lerpf(col.a, 1.0, _win_progress))
		for i in rects.size():
			var r: Rect2 = rects[i]
			var grid_cell: Vector2i = piece.get_grid_cells()[i]
			draw_rect(r, col)
			# Overlap highlight
			if occupied.has(grid_cell) and occupied[grid_cell] == -1:
				draw_rect(r, OVERLAP_COLOR)
			# Light edge on top + left
			var hi := Color(1.0, 1.0, 1.0, 0.15)
			draw_line(r.position, Vector2(r.end.x, r.position.y), hi, 1.0)
			draw_line(r.position, Vector2(r.position.x, r.end.y), hi, 1.0)
			# Dark edge on bottom + right
			var sh := Color(0.0, 0.0, 0.0, 0.2)
			draw_line(Vector2(r.position.x, r.end.y), r.end, sh, 1.0)
			draw_line(Vector2(r.end.x, r.position.y), r.end, sh, 1.0)


func _draw_tray_pieces() -> void:
	for piece in grid_manager.pieces:
		if piece.is_placed() or piece.piece_id == _dragging_id:
			continue
		var rects: Array[Rect2] = piece.get_draw_rects(WALL_ORIGIN)
		var col: Color = piece.color
		for r in rects:
			draw_rect(r, col)
			draw_rect(r, Color(1.0, 1.0, 1.0, 0.08), false, 1.0)


func _draw_drag_preview() -> void:
	if _dragging_id < 0:
		return
	var piece := _find_piece(_dragging_id)
	if piece == null:
		return

	# Draw the piece at the mouse position
	var bounds: Vector2i = ShadowPieceData.bounds_of(piece.cells)
	var half_x: float = float(bounds.x) * CELL * 0.5
	var half_y: float = float(bounds.y) * CELL * 0.5
	var base: Vector2 = _drag_mouse - _drag_offset

	for c in piece.cells:
		var px: float = base.x - half_x + float(c.x) * CELL
		var py: float = base.y - half_y + float(c.y) * CELL
		var r := Rect2(px, py, CELL, CELL)
		draw_rect(r, Color(piece.color, 0.55))
		draw_rect(r, Color(1.0, 1.0, 1.0, 0.3), false, 1.0)

	# Snap preview on wall
	var snap := _get_snap_cell(base, piece)
	if snap.x >= 0:
		var valid := _check_placement(piece, snap.x, snap.y)
		var preview_col := Color(0.3, 0.8, 0.4, 0.2) if valid else Color(0.8, 0.3, 0.3, 0.2)
		for c in piece.cells:
			var cell := Vector2i(snap.x + c.x, snap.y + c.y)
			var rect := _cell_rect(cell)
			draw_rect(rect, preview_col)


func _draw_dust() -> void:
	for d in _dust:
		var a: float = d["alpha"]
		var col := Color(DUST_COLOR, a)
		if _solved:
			col = Color(WIN_GLOW, a * minf(lerpf(1.0, 1.5, _win_progress), 1.0))
		draw_rect(Rect2(d["pos"], Vector2(1, 1)), col)


func _draw_new_button() -> void:
	draw_rect(NEW_BTN_RECT, Color(0.18, 0.16, 0.13))
	draw_rect(NEW_BTN_RECT, Color(0.32, 0.30, 0.26), false)
	var txt := "New"
	var fs := 16
	var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var asc := PIXEL_FONT.get_ascent(fs)
	var desc := PIXEL_FONT.get_descent(fs)
	var th := asc + desc
	var tx := NEW_BTN_RECT.position.x + (NEW_BTN_RECT.size.x - ts.x) / 2.0
	var ty := NEW_BTN_RECT.position.y + (NEW_BTN_RECT.size.y - th) / 2.0 + asc
	draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.8, 0.8, 0.7))


func _draw_puzzle_name() -> void:
	var txt: String = grid_manager.silhouette_name
	draw_string(PIXEL_FONT, Vector2(WALL_ORIGIN.x, WALL_ORIGIN.y - 2), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.4, 0.4, 0.5, 0.4))


# ===========================================================================
# Input — drag from tray to wall, scroll to rotate
# ===========================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = event.global_position - global_position
		if NEW_BTN_RECT.has_point(local):
			_on_new_pressed()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _solved:
		return
	var local: Vector2 = get_global_mouse_position() - global_position

	if event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_start_drag(local)
				MOUSE_BUTTON_WHEEL_UP:
					if _dragging_id >= 0:
						grid_manager.rotate_piece(_dragging_id)
				MOUSE_BUTTON_WHEEL_DOWN:
					if _dragging_id >= 0:
						# rotate 3x CW = 1x CCW
						grid_manager.rotate_piece(_dragging_id)
						grid_manager.rotate_piece(_dragging_id)
						grid_manager.rotate_piece(_dragging_id)
		elif not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_end_drag(local)

	elif event is InputEventMouseMotion:
		_drag_mouse = local


func _start_drag(mouse: Vector2) -> void:
	_drag_mouse = mouse
	# Check placed pieces first (to pick them up)
	for i in range(grid_manager.pieces.size() - 1, -1, -1):
		var piece: ShadowPieceData = grid_manager.pieces[i]
		if piece.is_placed() and piece.point_inside(mouse, WALL_ORIGIN):
			_dragging_id = piece.piece_id
			_drag_offset = Vector2.ZERO
			grid_manager.unplace_piece(piece.piece_id)
			return
	# Check tray pieces
	for i in range(grid_manager.pieces.size() - 1, -1, -1):
		var piece: ShadowPieceData = grid_manager.pieces[i]
		if not piece.is_placed() and piece.point_inside(mouse, WALL_ORIGIN):
			_dragging_id = piece.piece_id
			_drag_offset = Vector2.ZERO
			return
	_dragging_id = -1


func _end_drag(mouse: Vector2) -> void:
	if _dragging_id < 0:
		return
	var piece := _find_piece(_dragging_id)
	if piece == null:
		_dragging_id = -1
		return

	var base: Vector2 = mouse - _drag_offset
	var snap := _get_snap_cell(base, piece)
	if snap.x >= 0 and _check_placement(piece, snap.x, snap.y):
		grid_manager.place_piece(_dragging_id, snap.x, snap.y)
	# If placement failed, piece stays in tray (grid_pos remains -1,-1)

	_dragging_id = -1
	grid_manager.grid_changed.emit()


# ===========================================================================
# Helpers
# ===========================================================================

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		WALL_ORIGIN.x + float(cell.x * CELL),
		WALL_ORIGIN.y + float(cell.y * CELL),
		CELL, CELL)


## Compute which grid cell the piece would snap to given a screen position.
func _get_snap_cell(screen_pos: Vector2, piece: ShadowPieceData) -> Vector2i:
	var bounds: Vector2i = ShadowPieceData.bounds_of(piece.cells)
	var half_x: float = float(bounds.x) * CELL * 0.5
	var half_y: float = float(bounds.y) * CELL * 0.5
	# The piece's top-left cell in grid coords
	var gx := int((screen_pos.x - half_x - WALL_ORIGIN.x + CELL * 0.5) / CELL)
	var gy := int((screen_pos.y - half_y - WALL_ORIGIN.y + CELL * 0.5) / CELL)
	if gx < 0 or gy < 0 or gx + bounds.x > GRID_W or gy + bounds.y > GRID_H:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func _check_placement(piece: ShadowPieceData, gx: int, gy: int) -> bool:
	for c in piece.cells:
		var cell := Vector2i(gx + c.x, gy + c.y)
		if not grid_manager.silhouette.has(cell):
			return false
		if grid_manager._cell_occupied_by_other(cell, piece.piece_id):
			return false
	return true


func _find_piece(pid: int) -> ShadowPieceData:
	for p in grid_manager.pieces:
		if p.piece_id == pid:
			return p
	return null


# ===========================================================================
# State
# ===========================================================================

func _on_grid_changed() -> void:
	queue_redraw()


func _on_puzzle_solved() -> void:
	_solved = true
	_dragging_id = -1
	_play_win()


func _play_win() -> void:
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_progress = 0.0
	_win_tween = create_tween()
	_win_tween.tween_property(self , "_win_progress", 1.0, 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)


func _on_new_pressed() -> void:
	_solved = false
	_dragging_id = -1
	_win_progress = 0.0
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
		_win_tween = null
	grid_manager.generate_puzzle()
	queue_redraw()


# ===========================================================================
# Dust motes
# ===========================================================================

func _init_dust() -> void:
	_dust.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in DUST_COUNT:
		_dust.append(_new_mote(rng, true))


func _new_mote(rng: RandomNumberGenerator, scatter: bool) -> Dictionary:
	return {
		"pos": Vector2(
			rng.randf_range(LIGHT_POS.x - 30, WALL_ORIGIN.x + 30) if scatter else LIGHT_POS.x,
			rng.randf_range(5.0, 175.0)),
		"vel": Vector2(rng.randf_range(2.0, 6.0), rng.randf_range(-0.8, 0.8)),
		"alpha": rng.randf_range(0.0, DUST_COLOR.a) if scatter else 0.0,
		"life": rng.randf_range(0.0, 1.0) if scatter else 0.0,
		"max_life": rng.randf_range(3.0, 7.0),
	}


func _update_dust(delta: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in _dust.size():
		var d := _dust[i]
		d["pos"] += d["vel"] * delta
		d["life"] += delta
		var t: float = d["life"] / d["max_life"]
		if t < 0.2:
			d["alpha"] = lerpf(0.0, DUST_COLOR.a, t / 0.2)
		elif t > 0.8:
			d["alpha"] = lerpf(DUST_COLOR.a, 0.0, (t - 0.8) / 0.2)
		else:
			d["alpha"] = DUST_COLOR.a
		if t >= 1.0 or d["pos"].x > 320 or d["pos"].y < 0 or d["pos"].y > 180:
			_dust[i] = _new_mote(rng, false)
