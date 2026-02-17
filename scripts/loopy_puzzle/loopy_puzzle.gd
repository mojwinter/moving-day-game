extends Node2D
## Scene controller for the Night 4 Constellation (Loopy on Penrose P2) puzzle.
## Presents 3 sequential puzzles with auto-scroll on solve.

const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")
const LC := preload("res://scripts/loopy_puzzle/loopy_consts.gd")
const GridManagerScript := preload("res://scripts/loopy_puzzle/grid_manager.gd")

const NEW_BTN_RECT := Rect2(2, 2, 24, 12)
const EDGE_CLICK_DIST := 5.0
const DOT_RADIUS := 1.5
const LINE_WIDTH := 1.0
const NO_MARK_SIZE := 4.0

const PUZZLE_COUNT := 3
const VIEWPORT_W := 320.0
const VIEWPORT_H := 180.0
const TOTAL_W := VIEWPORT_W * PUZZLE_COUNT

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


class PuzzleSlot:
	var grid_manager: Node = null
	var solved := false
	var win_tween: Tween = null
	var win_alpha := 0.0
	var win_fade := 0.0
	var win_shimmer := 0.0


var _slots: Array = []
var _scroll_x := 0.0
var _scroll_target := 0.0
var _current_puzzle := 0
var _scrolling := false

# Background star positions (random tiny dots for ambiance) spanning full width
var _bg_stars: Array = []


func _ready() -> void:
	_generate_bg_stars()
	for i in range(PUZZLE_COUNT):
		var slot := PuzzleSlot.new()
		var gm := Node.new()
		gm.set_script(GridManagerScript)
		gm.name = "GridManager%d" % i
		add_child(gm)
		slot.grid_manager = gm
		gm.puzzle_solved.connect(_on_puzzle_solved.bind(i))
		gm.grid_changed.connect(_on_grid_changed)
		_slots.append(slot)
	# Generate first puzzle immediately, stagger the rest so each gets a different time-based seed
	_slots[0].grid_manager.generate_puzzle()
	for i in range(1, PUZZLE_COUNT):
		get_tree().create_timer(i).timeout.connect(_slots[i].grid_manager.generate_puzzle)
	queue_redraw()


# ===========================================================================
# Drawing
# ===========================================================================

func _draw() -> void:
	# Background
	draw_rect(Rect2(0, 0, VIEWPORT_W, VIEWPORT_H), COL_BG)

	# Background stars (in world space, shifted by scroll)
	for s: Vector3 in _bg_stars:
		var sx := s.x - _scroll_x
		if sx >= -1.0 and sx <= VIEWPORT_W:
			draw_rect(Rect2(sx, s.y, 1, 1), Color(1.0, 1.0, 1.0, s.z))

	# Draw each puzzle with offset
	for i in range(PUZZLE_COUNT):
		var offset_x := i * VIEWPORT_W - _scroll_x
		# Frustum cull: skip puzzles entirely off-screen
		if offset_x < -VIEWPORT_W or offset_x > VIEWPORT_W:
			continue
		_draw_puzzle(_slots[i], offset_x)

	# Progress indicator dots
	_draw_page_indicators()

	# New button
	_draw_new_button()


func _draw_puzzle(slot: PuzzleSlot, offset_x: float) -> void:
	var gm := slot.grid_manager
	if gm.grid == null:
		return
	var grid = gm.grid
	var off := Vector2(offset_x, 0)
	var fade_out := 1.0 - slot.win_fade

	# Edges
	for ei in range(grid.num_edges):
		var d1: Vector2 = grid.dots[grid.edges[ei].x] + off
		var d2: Vector2 = grid.dots[grid.edges[ei].y] + off
		var state: int = gm.lines[ei]
		var err: bool = gm.line_errors[ei]

		if err:
			draw_line(d1, d2, COL_EDGE_ERROR, LINE_WIDTH)
		elif state == LC.LINE_YES:
			var base_col := COL_EDGE_YES.lerp(COL_WIN_GLOW, slot.win_alpha)
			draw_line(d1, d2, base_col, LINE_WIDTH)
		elif state == LC.LINE_NO:
			if fade_out > 0.01:
				var mid := Vector2(roundf((d1.x + d2.x) * 0.5), roundf((d1.y + d2.y) * 0.5))
				var hs := NO_MARK_SIZE * 0.5
				var c := Color(COL_EDGE_NO, COL_EDGE_NO.a * fade_out)
				draw_line(mid + Vector2(-hs, -hs), mid + Vector2(hs, hs), c, 1.0)
				draw_line(mid + Vector2(hs, -hs), mid + Vector2(-hs, hs), c, 1.0)
		else:
			if fade_out > 0.01:
				draw_line(d1, d2, Color(COL_EDGE_UNKNOWN, COL_EDGE_UNKNOWN.a * fade_out), LINE_WIDTH)

	# Dots (stars) – shimmer during win
	for di in range(grid.num_dots):
		var p: Vector2 = grid.dots[di] + off
		if slot.solved and slot.win_shimmer > 0.0:
			var twinkle := sin(slot.win_shimmer * 3.0 + grid.dots[di].x * 0.3 + grid.dots[di].y * 0.2) * 0.5 + 0.5
			var col := COL_DOT.lerp(COL_WIN_GLOW, twinkle * slot.win_alpha)
			draw_circle(p, DOT_RADIUS, col)
		else:
			draw_circle(p, DOT_RADIUS, COL_DOT)

	# Face clues – fade out during win
	if fade_out > 0.01:
		var font_size := 16
		for fi in range(grid.num_faces):
			var c: int = gm.clues[fi]
			if c < 0:
				continue
			var center: Vector2 = grid.face_centroid(fi) + off
			var txt := str(c)
			var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)

			var yes_count := 0
			for ei: int in grid.face_edges[fi]:
				if gm.lines[ei] == LC.LINE_YES:
					yes_count += 1
			var base_col := COL_CLUE_SAT if yes_count == c else COL_CLUE
			var col := Color(base_col, base_col.a * fade_out)

			var tx := roundf(center.x - ts.x * 0.5)
			var ty := roundf(center.y + 3.0)
			draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


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


func _draw_page_indicators() -> void:
	var y := VIEWPORT_H - 6.0
	var spacing := 8.0
	var total_w := PUZZLE_COUNT * spacing
	var start_x := (VIEWPORT_W - total_w) * 0.5
	for i in range(PUZZLE_COUNT):
		var cx := start_x + i * spacing + spacing * 0.5
		var col: Color
		if _slots[i].solved:
			col = COL_WIN_GLOW
		elif i == _current_puzzle:
			col = COL_DOT
		else:
			col = Color(COL_DOT, 0.3)
		draw_circle(Vector2(cx, y), 1.5, col)


func _generate_bg_stars() -> void:
	_bg_stars.clear()
	for _i in range(120):
		_bg_stars.append(Vector3(randf() * TOTAL_W, randf() * VIEWPORT_H, randf_range(0.05, 0.25)))


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
	if _scrolling:
		return
	if _current_puzzle < 0 or _current_puzzle >= _slots.size():
		return
	var slot: PuzzleSlot = _slots[_current_puzzle]
	if slot.solved:
		return
	if slot.grid_manager.grid == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			var local: Vector2 = event.global_position - global_position
			# Offset click into the current puzzle's local space
			var puzzle_local := Vector2(local.x + _scroll_x - _current_puzzle * VIEWPORT_W, local.y)
			var ei := _find_nearest_edge(slot.grid_manager.grid, puzzle_local)
			if ei >= 0:
				var use_yes: bool = (event.button_index == MOUSE_BUTTON_LEFT)
				slot.grid_manager.toggle_edge(ei, use_yes)


func _find_nearest_edge(grid, local_pos: Vector2) -> int:
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


func _on_puzzle_solved(puzzle_idx: int) -> void:
	var slot: PuzzleSlot = _slots[puzzle_idx]
	slot.solved = true
	_play_win_highlight(slot, puzzle_idx)


func _play_win_highlight(slot: PuzzleSlot, puzzle_idx: int) -> void:
	if slot.win_tween and slot.win_tween.is_valid():
		slot.win_tween.kill()
	slot.win_tween = create_tween()
	# Phase 1: fade out non-loop elements
	slot.win_tween.tween_method(func(v): slot.win_fade = v; queue_redraw(), 0.0, 1.0, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 2: glow the loop golden
	slot.win_tween.tween_method(func(v): slot.win_alpha = v; queue_redraw(), 0.0, 1.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Phase 3: settle to sustained glow
	slot.win_tween.tween_method(func(v): slot.win_alpha = v; queue_redraw(), 1.0, 0.6, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Phase 4: auto-scroll to next puzzle (if not the last)
	if puzzle_idx < PUZZLE_COUNT - 1:
		slot.win_tween.tween_callback(_start_scroll_to_next.bind(puzzle_idx))


func _start_scroll_to_next(from_idx: int) -> void:
	_current_puzzle = from_idx + 1
	_scroll_target = _current_puzzle * VIEWPORT_W
	_scrolling = true


func _process(delta: float) -> void:
	# Smooth scroll toward target
	if _scrolling:
		_scroll_x = lerpf(_scroll_x, _scroll_target, 1.0 - exp(-3.0 * delta))
		if absf(_scroll_x - _scroll_target) < 0.5:
			_scroll_x = _scroll_target
			_scrolling = false
		queue_redraw()

	# Per-puzzle win animation updates
	var needs_redraw := false
	for slot in _slots:
		if slot.solved:
			slot.win_shimmer += delta
			needs_redraw = true
		elif slot.win_tween and slot.win_tween.is_valid():
			needs_redraw = true
	if needs_redraw:
		queue_redraw()


func _on_new_game_pressed() -> void:
	if _current_puzzle < 0 or _current_puzzle >= _slots.size():
		return
	var slot: PuzzleSlot = _slots[_current_puzzle]
	slot.solved = false
	slot.win_alpha = 0.0
	slot.win_fade = 0.0
	slot.win_shimmer = 0.0
	if slot.win_tween and slot.win_tween.is_valid():
		slot.win_tween.kill()
		slot.win_tween = null
	slot.grid_manager.generate_puzzle()
	queue_redraw()
