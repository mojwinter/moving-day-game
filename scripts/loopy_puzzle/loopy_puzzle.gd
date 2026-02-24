extends Node2D
## Scene controller for the Night 4 Constellation (Loopy on Penrose P2) puzzle.
## Loads pre-generated puzzles from JSON, progressing linearly from easy to hard.

const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")
const LC := preload("res://scripts/loopy_puzzle/loopy_consts.gd")
const GridManagerScript := preload("res://scripts/loopy_puzzle/grid_manager.gd")

const EDGE_CLICK_DIST := 5.0
const DOT_RADIUS := 1.5
const LINE_WIDTH := 1.0
const NO_MARK_SIZE := 4.0
const RING_RADIUS := 5.0
const RING_POINTS := 8
const RING_GAP := 0.25
const RING_WIDTH := 1.0

const VIEWPORT_W := 320.0
const VIEWPORT_H := 180.0

const MANIFEST_PATH := "res://data/loopy_puzzles/manifest.json"

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
const COL_RING_UNLIT := Color(0.3, 0.32, 0.4, 0.35)


var _grid_manager: Node = null
var _manifest: Array = []
var _puzzle_index: int = 0
var _solved := false
var _win_tween: Tween = null
var _win_alpha := 0.0
var _win_fade := 0.0
var _win_shimmer := 0.0

# Background star positions (random tiny dots for ambiance)
var _bg_stars: Array = []


func _ready() -> void:
	_generate_bg_stars()
	_grid_manager = Node.new()
	_grid_manager.set_script(GridManagerScript)
	_grid_manager.name = "GridManager"
	add_child(_grid_manager)
	_grid_manager.puzzle_solved.connect(_on_puzzle_solved)
	_grid_manager.grid_changed.connect(_on_grid_changed)
	_load_manifest()
	_load_current_puzzle()
	queue_redraw()


# ===========================================================================
# Manifest & puzzle loading
# ===========================================================================

func _load_manifest() -> void:
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open loopy puzzle manifest: %s" % MANIFEST_PATH)
		return
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	_manifest = json.data["puzzles"]


func _load_current_puzzle() -> void:
	if _puzzle_index >= _manifest.size():
		return
	_solved = false
	_win_alpha = 0.0
	_win_fade = 0.0
	_win_shimmer = 0.0
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
		_win_tween = null
	_grid_manager.load_from_json(_manifest[_puzzle_index])
	queue_redraw()


# ===========================================================================
# Drawing
# ===========================================================================

func _draw() -> void:
	# Background
	draw_rect(Rect2(0, 0, VIEWPORT_W, VIEWPORT_H), COL_BG)

	# Background stars
	for s: Vector3 in _bg_stars:
		draw_rect(Rect2(s.x, s.y, 1, 1), Color(1.0, 1.0, 1.0, s.z))

	# Draw the puzzle
	_draw_puzzle()

	# Progress indicator
	_draw_progress()


func _draw_puzzle() -> void:
	var gm := _grid_manager
	if gm.grid == null:
		return
	var grid = gm.grid
	var fade_out := 1.0 - _win_fade

	# Edges
	for ei in range(grid.num_edges):
		var d1: Vector2 = grid.dots[grid.edges[ei].x]
		var d2: Vector2 = grid.dots[grid.edges[ei].y]
		var state: int = gm.lines[ei]
		var err: bool = gm.line_errors[ei]

		if err:
			draw_line(d1, d2, COL_EDGE_ERROR, LINE_WIDTH)
		elif state == LC.LINE_YES:
			var base_col := COL_EDGE_YES.lerp(COL_WIN_GLOW, _win_alpha)
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
		var p: Vector2 = grid.dots[di]
		if _solved and _win_shimmer > 0.0:
			var twinkle := sin(_win_shimmer * 3.0 + grid.dots[di].x * 0.3 + grid.dots[di].y * 0.2) * 0.5 + 0.5
			var col := COL_DOT.lerp(COL_WIN_GLOW, twinkle * _win_alpha)
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
			var center: Vector2 = grid.face_centroid(fi)

			var yes_count := 0
			for ei: int in grid.face_edges[fi]:
				if gm.lines[ei] == LC.LINE_YES:
					yes_count += 1
			var satisfied := (yes_count == c)

			# Progress ring (drawn first so text renders on top)
			_draw_clue_ring(center, c, yes_count, satisfied, fade_out)

			# Clue number text
			var txt := str(c)
			var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var base_col := COL_CLUE_SAT if satisfied else COL_CLUE
			var col := Color(base_col, base_col.a * fade_out)

			var tx := roundf(center.x - ts.x * 0.5)
			var ty := roundf(center.y + 3.0)
			draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


func _draw_clue_ring(center: Vector2, clue: int, yes_count: int, satisfied: bool, fade_out: float) -> void:
	if clue == 0:
		var ring_col: Color
		if yes_count == 0:
			ring_col = Color(COL_CLUE_SAT, COL_CLUE_SAT.a * fade_out)
		else:
			ring_col = Color(COL_EDGE_ERROR, COL_EDGE_ERROR.a * fade_out * 0.6)
		draw_arc(center, RING_RADIUS, 0.0, TAU, 24, ring_col, RING_WIDTH)
		return

	var n := clue
	var total_arc := TAU - n * RING_GAP
	var seg_arc := total_arc / float(n)
	var start := -PI / 2.0
	var step := seg_arc + RING_GAP

	for i in range(n):
		var seg_start := start + i * step
		var seg_end := seg_start + seg_arc

		var seg_col: Color
		if yes_count > clue:
			seg_col = Color(COL_EDGE_ERROR, COL_EDGE_ERROR.a * fade_out * 0.7)
		elif satisfied:
			seg_col = Color(COL_CLUE_SAT, COL_CLUE_SAT.a * fade_out)
		elif i < yes_count:
			seg_col = Color(COL_EDGE_YES, fade_out)
		else:
			seg_col = Color(COL_RING_UNLIT, COL_RING_UNLIT.a * fade_out)

		draw_arc(center, RING_RADIUS, seg_start, seg_end, RING_POINTS, seg_col, RING_WIDTH)


func _draw_progress() -> void:
	if _manifest.is_empty():
		return
	var font_size := 16
	var txt := "%d/%d" % [_puzzle_index + 1, _manifest.size()]
	var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var tx := VIEWPORT_W - ts.x - 4.0
	var ty := 12.0
	draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT,
				-1, font_size, Color(0.5, 0.5, 0.5, 0.6))


func _generate_bg_stars() -> void:
	_bg_stars.clear()
	for _i in range(120):
		_bg_stars.append(Vector3(randf() * VIEWPORT_W, randf() * VIEWPORT_H, randf_range(0.05, 0.25)))


# ===========================================================================
# Input handling
# ===========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _solved:
		return
	if _grid_manager.grid == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			var local: Vector2 = event.global_position - global_position
			var ei := _find_nearest_edge(_grid_manager.grid, local)
			if ei >= 0:
				var use_yes: bool = (event.button_index == MOUSE_BUTTON_LEFT)
				_grid_manager.toggle_edge(ei, use_yes)


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


func _on_puzzle_solved() -> void:
	_solved = true
	_play_win_highlight()


func _play_win_highlight() -> void:
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	# Phase 1: fade out non-loop elements
	_win_tween.tween_method(func(v): _win_fade = v; queue_redraw(), 0.0, 1.0, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 2: glow the loop golden
	_win_tween.tween_method(func(v): _win_alpha = v; queue_redraw(), 0.0, 1.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Phase 3: settle to sustained glow
	_win_tween.tween_method(func(v): _win_alpha = v; queue_redraw(), 1.0, 0.6, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Phase 4: hold, then advance
	_win_tween.tween_interval(0.5)
	_win_tween.tween_callback(_advance_to_next_puzzle)


func _advance_to_next_puzzle() -> void:
	_puzzle_index += 1
	if _puzzle_index >= _manifest.size():
		# All puzzles complete
		return
	_load_current_puzzle()


func _process(delta: float) -> void:
	if _solved:
		_win_shimmer += delta
		queue_redraw()
