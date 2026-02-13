extends Node2D
## Scene controller for the Night 4 Constellation (Loopy on Penrose P2) puzzle.
## Draws the grid, handles nearest-edge input, and plays win animation.

const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")
const LC := preload("res://scripts/loopy_puzzle/loopy_consts.gd")

const NEW_BTN_RECT := Rect2(2, 2, 24, 12)
const EDGE_CLICK_DIST := 5.0
const DOT_RADIUS := 1.5
const LINE_WIDTH := 1.0
const NO_MARK_SIZE := 4.0

# Constellation theme colours
const COL_BG := Color(0.05, 0.05, 0.15)
const COL_DOT := Color(1.0, 0.95, 0.8)
const COL_EDGE_UNKNOWN := Color(0.2, 0.2, 0.3, 0.3)
const COL_EDGE_YES := Color(1.0, 0.9, 0.5)
const COL_EDGE_NO := Color(0.3, 0.25, 0.2, 0.5)
const COL_EDGE_ERROR := Color(1.0, 0.2, 0.2)
const COL_CLUE := Color(0.7, 0.75, 0.85)
const COL_CLUE_SAT := Color(0.4, 0.6, 0.4)
const COL_WIN_GLOW := Color(1.0, 0.95, 0.7)

@onready var grid_manager = $GridManager

var _solved := false
var _win_tween: Tween = null
var _win_alpha := 0.0 # pulsing glow intensity during win

# Background star positions (random tiny dots for ambiance)
var _bg_stars: Array = []


func _ready() -> void:
	_generate_bg_stars()
	grid_manager.generate_puzzle()
	grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	grid_manager.grid_changed.connect(_on_grid_changed)
	queue_redraw()


# ===========================================================================
# Drawing
# ===========================================================================

func _draw() -> void:
	# Background
	draw_rect(Rect2(0, 0, 320, 180), COL_BG)

	# Background stars (ambient)
	for s in _bg_stars:
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(1.0, 1.0, 1.0, s.z))

	if grid_manager.grid == null:
		_draw_new_button()
		return

	var grid = grid_manager.grid

	# Edges
	for ei in range(grid.num_edges):
		var d1: Vector2 = grid.dots[grid.edges[ei].x]
		var d2: Vector2 = grid.dots[grid.edges[ei].y]
		var state: int = grid_manager.lines[ei]
		var err: bool = grid_manager.line_errors[ei]

		if err:
			draw_line(d1, d2, COL_EDGE_ERROR, LINE_WIDTH)
		elif state == LC.LINE_YES:
			var col := COL_WIN_GLOW.lerp(COL_EDGE_YES, 1.0 - _win_alpha) if _solved else COL_EDGE_YES
			draw_line(d1, d2, col, LINE_WIDTH)
		elif state == LC.LINE_NO:
			# X at midpoint
			var mid := Vector2(roundf((d1.x + d2.x) * 0.5), roundf((d1.y + d2.y) * 0.5))
			var hs := NO_MARK_SIZE * 0.5
			draw_line(mid + Vector2(-hs, -hs), mid + Vector2(hs, hs), COL_EDGE_NO, 1.0)
			draw_line(mid + Vector2(hs, -hs), mid + Vector2(-hs, hs), COL_EDGE_NO, 1.0)
		else:
			draw_line(d1, d2, COL_EDGE_UNKNOWN, LINE_WIDTH)

	# Dots (stars)
	for di in range(grid.num_dots):
		var p: Vector2 = grid.dots[di]
		var col := COL_WIN_GLOW.lerp(COL_DOT, 1.0 - _win_alpha * 0.5) if _solved else COL_DOT
		draw_circle(p, DOT_RADIUS, col)

	# Face clues
	var font_size := 16
	for fi in range(grid.num_faces):
		var c: int = grid_manager.clues[fi]
		if c < 0:
			continue
		var center: Vector2 = grid.face_centroid(fi)
		var txt := str(c)
		var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

		# Determine if clue is satisfied
		var yes_count := 0
		for ei: int in grid.face_edges[fi]:
			if grid_manager.lines[ei] == LC.LINE_YES:
				yes_count += 1
		var col := COL_CLUE_SAT if yes_count == c else COL_CLUE

		# draw_string y = baseline; ascent=11 descent=2 at size 16.
		# Visual glyph centre ≈ baseline - 4 (glyphs ~6px tall near bottom of ascent).
		var tx := roundf(center.x - ts.x * 0.5)
		var ty := roundf(center.y + 3.0)
		draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

	# New button
	_draw_new_button()


func _draw_new_button() -> void:
	var font_size := 16
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


func _generate_bg_stars() -> void:
	_bg_stars.clear()
	for _i in range(40):
		_bg_stars.append(Vector3(randf() * 320.0, randf() * 180.0, randf_range(0.05, 0.25)))


# ===========================================================================
# Input handling
# ===========================================================================

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local: Vector2 = event.global_position - global_position
		if NEW_BTN_RECT.has_point(local):
			_on_new_game_pressed()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if _solved:
		return
	if grid_manager.grid == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			var local: Vector2 = event.global_position - global_position
			var ei := _find_nearest_edge(local)
			if ei >= 0:
				var use_yes: bool = (event.button_index == MOUSE_BUTTON_LEFT)
				grid_manager.toggle_edge(ei, use_yes)


func _find_nearest_edge(local_pos: Vector2) -> int:
	var grid = grid_manager.grid
	var best_dist := 999.0
	var best_edge := -1
	for i in range(grid.num_edges):
		var d1: Vector2 = grid.dots[grid.edges[i].x]
		var d2: Vector2 = grid.dots[grid.edges[i].y]
		var dist := _point_to_segment_dist(local_pos, d1, d2)
		if dist < best_dist:
			best_dist = dist
			best_edge = i
	if best_dist < EDGE_CLICK_DIST:
		return best_edge
	return -1


static func _point_to_segment_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ap := p - a
	var t := ab.dot(ap) / ab.length_squared()
	t = clampf(t, 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)


# ===========================================================================
# State updates
# ===========================================================================

func _on_grid_changed() -> void:
	queue_redraw()


func _on_puzzle_solved() -> void:
	_solved = true
	_play_win_highlight()


func _play_win_highlight() -> void:
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	# Pulse the glow twice then settle
	_win_tween.tween_property(self, "_win_alpha", 1.0, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_win_tween.tween_property(self, "_win_alpha", 0.3, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_win_tween.tween_property(self, "_win_alpha", 0.8, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_win_tween.tween_property(self, "_win_alpha", 0.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_win_tween.tween_callback(queue_redraw)


func _process(_delta: float) -> void:
	if _win_tween and _win_tween.is_valid():
		queue_redraw()


func _on_new_game_pressed() -> void:
	_solved = false
	_win_alpha = 0.0
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
		_win_tween = null
	_generate_bg_stars()
	grid_manager.generate_puzzle()
	queue_redraw()
