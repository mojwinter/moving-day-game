extends Node2D
## Scene controller for the Night 4 Constellation (Loopy on Penrose P2) puzzle.
## Loads pre-generated puzzles from JSON, progressing linearly from easy to hard.

const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")
const STAR_TEX := preload("res://assets/loopy/star2.png")
const RING_SRC := preload("res://assets/loopy/ring11x12.png")
const LC := preload("res://scripts/loopy_puzzle/loopy_consts.gd")
const GridManagerScript := preload("res://scripts/loopy_puzzle/grid_manager.gd")

const EDGE_CLICK_DIST := 5.0
const DOT_RADIUS := 1.5
const LINE_WIDTH := 1.0
const NO_MARK_SIZE := 4.0
const RING_GAP := 0.4
const MAX_CLUE := 3

const VIEWPORT_W := 320.0
const VIEWPORT_H := 180.0

const MANIFEST_PATH := "res://data/loopy_puzzles/manifest.json"

# Constellation theme colours
const COL_DOT := Color(1.0, 0.95, 0.8)
const COL_EDGE_UNKNOWN := Color(0.35, 0.38, 0.5, 0.45)
const COL_EDGE_YES := Color(1.0, 0.9, 0.5)
const COL_EDGE_NO := Color(0.3, 0.25, 0.2, 0.5)
const COL_EDGE_ERROR := Color(1.0, 0.2, 0.2)
const COL_CLUE := Color(0.7, 0.75, 0.85)
const COL_CLUE_SAT := Color(0.4, 0.6, 0.4)
const COL_WIN_GLOW := Color(1.0, 0.95, 0.7)
const COL_RING_UNLIT := Color(0.3, 0.32, 0.4, 0.35)


const BG_STAR_COUNT := 120
const BG_STAR_DRIFT_X := 3.0   # px/sec base left-to-right drift
const BG_STAR_DRIFT_Y := 0.3   # px/sec slight downward drift
const COL_BG_STAR := Color(0.6, 0.65, 0.8, 0.4)

var _grid_manager: Node = null
var _manifest: Array = []
var _puzzle_index: int = 0
var _solved := false
var _win_tween: Tween = null
var _win_alpha := 0.0
var _win_fade := 0.0
var _win_shimmer := 0.0
var _time := 0.0

# Background drifting stars
var _bg_stars: Array[Dictionary] = []

func _ready() -> void:
	if _ring_seg_textures.is_empty():
		_build_ring_textures()
	_init_bg_stars()
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
# Background star particles
# ===========================================================================

func _init_bg_stars() -> void:
	_bg_stars.clear()
	for i in range(BG_STAR_COUNT):
		_bg_stars.append({
			"pos": Vector2(randf() * VIEWPORT_W, randf() * VIEWPORT_H),
			"speed": randf_range(0.5, 1.5),
			"drift_y": randf_range(-0.5, 1.0),
			"phase": randf() * TAU,
			"brightness": randf_range(0.2, 0.6),
		})


func _update_bg_stars(delta: float) -> void:
	for star in _bg_stars:
		star.pos.x += BG_STAR_DRIFT_X * star.speed * delta
		star.pos.y += BG_STAR_DRIFT_Y * star.drift_y * delta
		star.pos.x = fmod(star.pos.x + VIEWPORT_W, VIEWPORT_W)
		star.pos.y = fmod(star.pos.y + VIEWPORT_H, VIEWPORT_H)


func _draw_bg_stars() -> void:
	for star in _bg_stars:
		var twinkle := sin(_time * 1.5 + star.phase) * 0.5 + 0.5
		var alpha: float = star.brightness * (0.4 + twinkle * 0.6)
		var col := Color(COL_BG_STAR, COL_BG_STAR.a * alpha)
		var p := Vector2(floorf(star.pos.x), floorf(star.pos.y))
		draw_rect(Rect2(p, Vector2(1, 1)), col)


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
	_set_bloom_intensity(0.35)
	_grid_manager.load_from_json(_manifest[_puzzle_index])
	queue_redraw()


# ===========================================================================
# Drawing
# ===========================================================================

func _draw() -> void:
	# Background particles (behind everything)
	_draw_bg_stars()

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
				var mid := Vector2(floorf((d1.x + d2.x) * 0.5), floorf((d1.y + d2.y) * 0.5))
				var hs := NO_MARK_SIZE * 0.5
				var c := Color(COL_EDGE_NO, COL_EDGE_NO.a * fade_out)
				draw_line(mid + Vector2(-hs, -hs), mid + Vector2(hs, hs), c, 1.0)
				draw_line(mid + Vector2(hs, -hs), mid + Vector2(-hs, hs), c, 1.0)
		else:
			if fade_out > 0.01:
				draw_line(d1, d2, Color(COL_EDGE_UNKNOWN, COL_EDGE_UNKNOWN.a * fade_out), LINE_WIDTH)

	# Dots (stars) – shimmer during win
	var star_offset := Vector2(STAR_TEX.get_width() * 0.5, STAR_TEX.get_height() * 0.5)
	for di in range(grid.num_dots):
		var p: Vector2 = grid.dots[di]
		var draw_pos := Vector2(floorf(p.x - star_offset.x), floorf(p.y - star_offset.y))
		if _solved and _win_shimmer > 0.0:
			var twinkle := sin(_win_shimmer * 3.0 + p.x * 0.3 + p.y * 0.2) * 0.5 + 0.5
			var col := COL_DOT.lerp(COL_WIN_GLOW, twinkle * _win_alpha)
			draw_texture(STAR_TEX, draw_pos, col)
		else:
			draw_texture(STAR_TEX, draw_pos)

	# Face clues – fade out during win
	if fade_out > 0.01:
		var font_size := 16
		for fi in range(grid.num_faces):
			var c: int = gm.clues[fi]
			if c < 0:
				continue
			var center: Vector2 = grid.face_centroid(fi)
			var snapped := Vector2(floorf(center.x), floorf(center.y))

			var yes_count := 0
			for ei: int in grid.face_edges[fi]:
				if gm.lines[ei] == LC.LINE_YES:
					yes_count += 1
			var satisfied := (yes_count == c)

			# Progress ring (drawn first so text renders on top)
			_draw_clue_ring(snapped, c, yes_count, satisfied, fade_out)

			# Clue number text — center visually within ring
			var txt := str(c)
			var ts := PIXEL_FONT.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			var base_col := COL_CLUE
			var col := Color(base_col, base_col.a * fade_out)

			var tx := snapped.x - floorf(ts.x * 0.5) + 1.0
			var ty := snapped.y + 3.0
			draw_string(PIXEL_FONT, Vector2(tx, ty), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)


## Ring segment textures built from ring.png at startup.
## Walks ring pixels in clockwise order, splits into equal groups with 1px gaps.
## _ring_full_tex: the complete ring (for clue 0).
## _ring_seg_textures[n][i]: segment i of an n-segment ring (n = 1..MAX_CLUE).
static var _ring_full_tex: ImageTexture
static var _ring_full_glow: ImageTexture
static var _ring_seg_textures: Dictionary = {}  # { int -> Array[ImageTexture] }
static var _ring_seg_glow_textures: Dictionary = {}  # { int -> Array[ImageTexture] }
static var _ring_seg_phases: Dictionary = {}  # { int -> Array[float] } phase offset per segment

## Create a glow version of a ring image: 2px padding, 5x5 soft spread.
static func _make_glow_image(src: Image) -> Image:
	var sw := src.get_width()
	var sh := src.get_height()
	var pad := 2
	var gw := sw + pad * 2
	var gh := sh + pad * 2
	var glow := Image.create(gw, gh, false, src.get_format())
	# Accumulate glow in a float buffer then write once
	var buf: Array[float] = []
	buf.resize(gw * gh)
	buf.fill(0.0)
	# Spread kernel: center=1.0, adjacent=0.5, diagonal=0.25, 2-away=0.15
	var offsets: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
		Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2),
	]
	var weights: Array[float] = [
		1.0, 0.5, 0.5, 0.5, 0.5,
		0.25, 0.25, 0.25, 0.25,
		0.15, 0.15, 0.15, 0.15,
	]
	for y in range(sh):
		for x in range(sw):
			if src.get_pixel(x, y).a > 0.0:
				for k in range(offsets.size()):
					var gx := x + pad + offsets[k].x
					var gy := y + pad + offsets[k].y
					if gx >= 0 and gx < gw and gy >= 0 and gy < gh:
						buf[gy * gw + gx] = maxf(buf[gy * gw + gx], weights[k])
	for y in range(gh):
		for x in range(gw):
			var v: float = buf[y * gw + x]
			if v > 0.0:
				glow.set_pixel(x, y, Color(1.0, 1.0, 1.0, v))
	return glow


static func _build_ring_textures() -> void:
	var src_img := RING_SRC.get_image()
	src_img.decompress()
	var w := src_img.get_width()
	var h := src_img.get_height()
	var cx := float(w) / 2.0
	var cy := float(h) / 2.0

	_ring_full_tex = ImageTexture.create_from_image(src_img)
	_ring_full_glow = ImageTexture.create_from_image(_make_glow_image(src_img))

	# Collect lit pixels sorted clockwise from top-center
	var pixels: Array[Vector2i] = []
	var angles: Array[float] = []
	for y in range(h):
		for x in range(w):
			if src_img.get_pixel(x, y).a > 0.0:
				var a := atan2(float(y) - cy, float(x) - cx) + PI / 2.0
				if a < 0.0:
					a += TAU
				pixels.append(Vector2i(x, y))
				angles.append(a)

	# Sort by angle
	var indices: Array[int] = []
	for idx in range(pixels.size()):
		indices.append(idx)
	indices.sort_custom(func(a_idx, b_idx): return angles[a_idx] < angles[b_idx])

	var sorted_pixels: Array[Vector2i] = []
	for idx in indices:
		sorted_pixels.append(pixels[idx])

	var total := sorted_pixels.size()

	# Hand-picked gap indices per segment count (on 30px 11x12 ring):
	# 1: no gaps → full 30px ring
	# 2: gaps at top + bottom center → 14+14
	# 3: gaps at mid-right + mid-bottom + mid-left → 7+7+13 (top seg is bigger)
	var gap_map: Dictionary = {
		1: [],
		2: [29, 14],
		3: [6, 14, 22],
	}

	for n in range(1, MAX_CLUE + 1):
		var gaps: Array = gap_map[n]
		var gap_set: Dictionary = {}
		for g in gaps:
			gap_set[g] = true

		var seg_pixels: Array[Array] = []
		for _i in range(n):
			seg_pixels.append([])

		if gaps.is_empty():
			# No gaps — entire ring is one segment
			for px_i in range(total):
				seg_pixels[0].append(sorted_pixels[px_i])
		else:
			# Walk pixels, splitting at gaps. Start from the first gap.
			var first_gap: int = gaps[0]
			var seg := 0
			for offset in range(total):
				var px_i := (first_gap + offset) % total
				if gap_set.has(px_i):
					if offset > 0:
						seg += 1
					continue
				if seg < n:
					seg_pixels[seg].append(sorted_pixels[px_i])

		# Compute phase offset for each segment based on its midpoint around the ring
		var phases: Array[float] = []
		if gaps.is_empty():
			phases.append(0.0)
		else:
			for i in range(n):
				var start: int = gaps[i]
				var end: int = gaps[(i + 1) % n]
				if end <= start:
					end += total
				var mid := float(start + end) / 2.0
				phases.append(mid / float(total) * TAU)

		# Create a texture + glow texture per segment
		var textures: Array[ImageTexture] = []
		var glow_textures: Array[ImageTexture] = []
		for i in range(n):
			var seg_img := Image.create(w, h, false, src_img.get_format())
			for px: Vector2i in seg_pixels[i]:
				seg_img.set_pixel(px.x, px.y, src_img.get_pixel(px.x, px.y))
			textures.append(ImageTexture.create_from_image(seg_img))
			glow_textures.append(ImageTexture.create_from_image(_make_glow_image(seg_img)))
		_ring_seg_textures[n] = textures
		_ring_seg_glow_textures[n] = glow_textures
		_ring_seg_phases[n] = phases


func _draw_clue_ring(center: Vector2, clue: int, yes_count: int, satisfied: bool, fade_out: float) -> void:
	@warning_ignore("integer_division")
	var ring_offset := Vector2i(RING_SRC.get_width() / 2, RING_SRC.get_height() / 2)
	var draw_pos := Vector2(center.x - ring_offset.x, center.y - ring_offset.y)
	# Glow textures are 2px larger on each side
	var glow_pos := Vector2(draw_pos.x - 2, draw_pos.y - 2)

	if clue == 0:
		var ring_col: Color
		var glow_col: Color
		if yes_count == 0:
			var wave := sin(_time * 2.5) * 0.5 + 0.5
			var bright := COL_CLUE_SAT.lerp(Color(0.7, 1.0, 0.7), wave)
			ring_col = Color(bright, fade_out)
			glow_col = Color(bright, 0.35 * fade_out)
		else:
			ring_col = Color(COL_EDGE_ERROR, COL_EDGE_ERROR.a * fade_out * 0.6)
			glow_col = Color(COL_EDGE_ERROR, 0.25 * fade_out)
		draw_texture(_ring_full_glow, glow_pos, glow_col)
		draw_texture(_ring_full_tex, draw_pos, ring_col)
		return

	var n := clue
	var seg_textures: Array = _ring_seg_textures[n]
	var seg_glows: Array = _ring_seg_glow_textures[n]
	var seg_phases: Array = _ring_seg_phases[n]

	for i in range(n):
		var seg_col: Color
		var glow_col: Color
		if yes_count > clue:
			seg_col = Color(COL_EDGE_ERROR, COL_EDGE_ERROR.a * fade_out * 0.7)
			glow_col = Color(COL_EDGE_ERROR, 0.25 * fade_out)
		elif satisfied:
			var wave := sin(_time * 4.0 - seg_phases[i]) * 0.5 + 0.5
			var dim := Color(0.15, 0.25, 0.15)
			var bright := Color(0.4, 0.75, 0.4)
			var col := dim.lerp(bright, wave)
			seg_col = Color(col, fade_out)
			glow_col = Color(col, (0.2 + wave * 0.5) * fade_out)
		elif i < yes_count:
			seg_col = Color(COL_EDGE_YES, fade_out)
			glow_col = Color(COL_EDGE_YES, 0.35 * fade_out)
		else:
			seg_col = Color(COL_RING_UNLIT, COL_RING_UNLIT.a * fade_out)
			glow_col = Color(0.0, 0.0, 0.0, 0.0)

		if glow_col.a > 0.0:
			draw_texture(seg_glows[i], glow_pos, glow_col)
		draw_texture(seg_textures[i], draw_pos, seg_col)


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


func _set_bloom_intensity(value: float) -> void:
	var overlay := get_node_or_null("BloomOverlay")
	if overlay and overlay.material:
		overlay.material.set_shader_parameter("bloom_intensity", value)


func _play_win_highlight() -> void:
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	# Phase 1: fade out non-loop elements
	_win_tween.tween_method(func(v): _win_fade = v; queue_redraw(), 0.0, 1.0, 0.8) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 2: glow the loop golden + bloom surge
	_win_tween.tween_method(func(v): _win_alpha = v; queue_redraw(), 0.0, 1.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_win_tween.parallel().tween_method(_set_bloom_intensity, 0.35, 1.2, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Phase 3: settle to sustained glow + bloom
	_win_tween.tween_method(func(v): _win_alpha = v; queue_redraw(), 1.0, 0.6, 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_win_tween.parallel().tween_method(_set_bloom_intensity, 1.2, 0.5, 0.4) \
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
	_time += delta
	_update_bg_stars(delta)
	if _solved:
		_win_shimmer += delta
	queue_redraw()
