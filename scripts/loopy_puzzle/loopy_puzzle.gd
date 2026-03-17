extends Node2D
## Scene controller for the Night 4 Constellation (Loopy on Penrose P2) puzzle.
## Loads pre-generated puzzles from JSON, progressing linearly from easy to hard.

const PIXEL_FONT := preload("res://assets/fonts/m3x6.ttf")
const STAR_TEX := preload("res://assets/loopy/star2.png")
const RING_SRC := preload("res://assets/loopy/ring11x12.png")
const EDGE_TEX := preload("res://assets/loopy/edge_line.png")
const LC := preload("res://scripts/loopy_puzzle/loopy_consts.gd")
const GridManagerScript := preload("res://scripts/loopy_puzzle/grid_manager.gd")

const EDGE_CLICK_DIST := 5.0
const DOT_CLICK_DIST := 8.0 # distance to snap to a dot when clicking
const DOT_SNAP_DIST := 6.0 # distance to auto-extend trail while drawing
const DOT_RADIUS := 1.5
const LINE_WIDTH := 1.0
const NO_MARK_SIZE := 4.0
const RING_GAP := 0.4
const MAX_CLUE := 3

# Beckon animation — continuous gentle glow pulse until player clicks a star
const BECKON_SPEED := 0.8 # pulse frequency (cycles/sec)
const BECKON_PHASE_SPREAD := 0.08 # phase offset between dots

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
const BG_STAR_DRIFT_X := 3.0 # px/sec base left-to-right drift
const BG_STAR_DRIFT_Y := 0.3 # px/sec slight downward drift
const COL_BG_STAR := Color(0.6, 0.65, 0.8, 0.4)

var _grid_manager: Node = null
var _manifest: Array = []
var _puzzle_index: int = 0
var _solved := false
var _win_tween: Tween = null
var _win_alpha := 0.0
var _win_fade := 0.0
var _win_shimmer := 0.0
var _loop_fade := 1.0 # 1=visible, 0=hidden — fades the solved loop outline
var _time := 0.0

# Trail drawing state
var _drawing := false # true while actively drawing a trail
var _current_dot := -1 # index of the dot the trail cursor is currently at
var _start_dot := -1 # index of the dot the trail started from
var _trail_edges: Array = [] # ordered list of edge indices in the current trail stroke
var _mouse_pos := Vector2.ZERO

# Background drifting stars
var _bg_stars: Array[Dictionary] = []

# Black hole hazard
const BH_SPAWN_DELAY := 10.0        # seconds before black hole appears
const BH_GROW_SPEED := 0.4          # px/sec radius growth
const BH_MAX_RADIUS := 28.0         # max consumption radius
const BH_MIN_RADIUS := 4.0          # starting / post-shrink minimum
const BH_CONSUME_INTERVAL := 2.5    # seconds between edge consumption ticks
const BH_TINT_RADIUS := 36.0        # dots/edges within this range get color-tinted
const BH_PARTICLE_COUNT := 24       # orbiting swirl particles
const BH_STREAM_COUNT := 16         # inward-streaming particles (Celeste-style)
const BH_MOVE_SPEED := 6.0          # px/sec drift toward target
const BH_FLEE_RADIUS := 30.0        # flee when mouse is within this distance
const BH_FLEE_SPEED := 12.0         # px/sec flee speed (much faster than drift)
const BH_GRACE_PERIOD := 3.0        # seconds before newly placed edges can be consumed
const COL_BH_CORE := Color(0.05, 0.0, 0.1, 0.9)
const COL_BH_RING := Color(0.3, 0.1, 0.5, 0.6)
const COL_BH_PARTICLE := Color(0.6, 0.3, 0.9, 0.5)
const COL_BH_TINT := Color(0.25, 0.1, 0.4)  # purple tint for nearby elements

var _bh_active := false
var _bh_pos := Vector2.ZERO
var _bh_radius := 0.0
var _bh_time := 0.0               # time accumulator for the black hole
var _bh_spawn_timer := 0.0        # countdown to spawn (only ticks after first line placed)
var _bh_waiting_for_line := true  # true until player places their first line
var _bh_consume_timer := 0.0      # countdown to next consume tick
var _bh_particles: Array[Dictionary] = []  # orbiting swirl particles
var _bh_streams: Array[Dictionary] = []   # inward-streaming particles
var _bh_edge_grace: Dictionary = {}  # edge_idx -> time remaining before it can be consumed
var _bh_fade := 1.0                  # 1=visible, 0=hidden — fades during win sequence
var _bh_spawn_fade := 1.0            # 0→1 fade-in when black hole first appears
var _bh_target := Vector2.ZERO       # cached drift target, re-picked periodically
var _bh_target_timer := 0.0          # countdown to pick a new drift target
const BH_SPAWN_FADE_DURATION := 3.0  # seconds to fade in
const BH_FIRST_PUZZLE := 1           # puzzle index where black hole starts (0 = skip first)

# Dot transition between puzzles
var _transitioning := false
var _transition_t := 0.0
var _transition_dots: Array = [] # Array of {from: Vector2, to: Vector2, fade: String}
var _fade_in := 1.0 # 0→1 fade for edges/clues after dots settle

# Beckon animation state
var _beckon_active := false
var _beckon_time := 0.0

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
	_loop_fade = 1.0
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
		_win_tween = null
	_set_bloom_intensity(0.35)
	_grid_manager.load_from_json(_manifest[_puzzle_index])
	_init_black_hole()
	_start_beckon()
	queue_redraw()


# ===========================================================================
# Drawing
# ===========================================================================

func _draw() -> void:
	# Background particles (behind everything)
	_draw_bg_stars()

	if _transitioning:
		_draw_transition()
	else:
		# Draw the puzzle
		_draw_puzzle()

	# Progress indicator
	_draw_progress()


func _draw_puzzle() -> void:
	var gm := _grid_manager
	if gm.grid == null:
		return
	var grid = gm.grid
	var fade_out := (1.0 - _win_fade) * _fade_in

	# Guide layer: draw solution edges faintly so player knows the path
	if not _solved and fade_out > 0.01 and gm.solution.size() == grid.num_edges:
		for ei in range(grid.num_edges):
			if gm.solution[ei] == LC.LINE_YES:
				var d1: Vector2 = grid.dots[grid.edges[ei].x]
				var d2: Vector2 = grid.dots[grid.edges[ei].y]
				# Subtle pulsing guide
				var pulse := sin(_time * 2.0 + ei * 0.5) * 0.03 + 0.12
				var guide_col := Color(COL_EDGE_YES.r, COL_EDGE_YES.g, COL_EDGE_YES.b, pulse * fade_out)
				draw_line(d1, d2, guide_col, 1.0)

	# All edges (unknown shown dim, YES shown bright) — tint near black hole
	for ei in range(grid.num_edges):
		var d1: Vector2 = grid.dots[grid.edges[ei].x]
		var d2: Vector2 = grid.dots[grid.edges[ei].y]
		var mid := (d1 + d2) * 0.5
		var tint := _bh_get_tint(mid)
		var state: int = gm.lines[ei]
		var err: bool = gm.line_errors[ei]

		if err and fade_out > 0.01:
			var col := COL_EDGE_ERROR.lerp(COL_BH_TINT, tint)
			_draw_edge_glow(d1, d2, col, fade_out)
		elif state == LC.LINE_YES:
			var base_col := COL_EDGE_YES.lerp(COL_WIN_GLOW, _win_alpha)
			base_col = base_col.lerp(COL_BH_TINT, tint)
			var yes_alpha := _loop_fade if _solved else fade_out
			if yes_alpha > 0.01:
				_draw_edge_glow(d1, d2, base_col, yes_alpha)
		elif fade_out > 0.01:
			var col := COL_EDGE_UNKNOWN.lerp(COL_BH_TINT, tint * 0.5)
			_draw_edge_glow(d1, d2, col, COL_EDGE_UNKNOWN.a * fade_out)

	# Drawing-mode: show a line from current dot to mouse cursor
	if _drawing and _current_dot >= 0 and not _solved:
		var dot_pos: Vector2 = grid.dots[_current_dot]
		var trail_col := Color(COL_EDGE_YES.r, COL_EDGE_YES.g, COL_EDGE_YES.b, 0.4)
		draw_line(dot_pos, _mouse_pos, trail_col, 1.0)

	# Dots (stars) – shimmer during win, pulse during beckon, tint near black hole
	var star_offset := Vector2(STAR_TEX.get_width() * 0.5, STAR_TEX.get_height() * 0.5)
	for di in range(grid.num_dots):
		var p: Vector2 = grid.dots[di]
		var dot_tint := _bh_get_tint(p)
		var draw_pos := Vector2(floorf(p.x - star_offset.x), floorf(p.y - star_offset.y))
		if _solved and _win_shimmer > 0.0:
			var twinkle := sin(_win_shimmer * 3.0 + p.x * 0.3 + p.y * 0.2) * 0.5 + 0.5
			var col := COL_DOT.lerp(COL_WIN_GLOW, twinkle * _win_alpha)
			draw_texture(STAR_TEX, draw_pos, col)
		elif _beckon_active:
			var phase: float = _beckon_time * BECKON_SPEED * TAU + di * BECKON_PHASE_SPREAD
			var pulse: float = sin(phase) * 0.5 + 0.5
			var alpha: float = 0.5 + pulse * 0.5
			var col := Color(COL_DOT.lerp(COL_BH_TINT, dot_tint), alpha)
			draw_texture(STAR_TEX, draw_pos, col)
		elif _drawing and di == _current_dot:
			var col := COL_EDGE_YES.lerp(COL_BH_TINT, dot_tint)
			draw_texture(STAR_TEX, draw_pos, col)
		else:
			var col := COL_DOT.lerp(COL_BH_TINT, dot_tint)
			draw_texture(STAR_TEX, draw_pos, col)

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

	# Black hole (drawn on top of everything in the puzzle layer)
	_draw_black_hole()


func _draw_transition() -> void:
	var star_offset := Vector2(STAR_TEX.get_width() * 0.5, STAR_TEX.get_height() * 0.5)
	var t := _transition_t
	for dot in _transition_dots:
		var p: Vector2
		var alpha: float
		match dot.fade:
			"morph":
				p = dot.from.lerp(dot.to, t)
				alpha = 1.0
			"out":
				p = dot.from
				alpha = 1.0 - t
			"in":
				p = dot.to
				alpha = t
		var draw_pos := Vector2(floorf(p.x - star_offset.x), floorf(p.y - star_offset.y))
		draw_texture(STAR_TEX, draw_pos, Color(COL_DOT, alpha))


## Ring segment textures built from ring.png at startup.
## Walks ring pixels in clockwise order, splits into equal groups with 1px gaps.
## _ring_full_tex: the complete ring (for clue 0).
## _ring_seg_textures[n][i]: segment i of an n-segment ring (n = 1..MAX_CLUE).
static var _ring_full_tex: ImageTexture
static var _ring_full_glow: ImageTexture
static var _ring_seg_textures: Dictionary = {} # { int -> Array[ImageTexture] }
static var _ring_seg_glow_textures: Dictionary = {} # { int -> Array[ImageTexture] }
static var _ring_seg_phases: Dictionary = {} # { int -> Array[float] } phase offset per segment

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


func _has_any_lines() -> bool:
	for ei in range(_grid_manager.grid.num_edges):
		if _grid_manager.lines[ei] == LC.LINE_YES:
			return true
	return false


func _start_beckon() -> void:
	var grid = _grid_manager.grid
	if grid == null or grid.num_dots == 0:
		return
	_beckon_active = true
	_beckon_time = 0.0


func _draw_edge_glow(d1: Vector2, d2: Vector2, col: Color, alpha: float) -> void:
	# Outer glow (wider, softer, antialiased for soft edges)
	draw_line(d1, d2, Color(col, alpha * 0.2), 5.0, true)
	# Inner glow
	draw_line(d1, d2, Color(col, alpha * 0.4), 3.0, true)
	# Core line
	draw_line(d1, d2, Color(col, alpha), LINE_WIDTH)


func _draw_clue_ring(center: Vector2, clue: int, yes_count: int, satisfied: bool, fade_out: float) -> void:
	@warning_ignore("integer_division")
	var ring_offset := Vector2i(RING_SRC.get_width() / 2, RING_SRC.get_height() / 2)
	var draw_pos := Vector2(center.x - ring_offset.x, center.y - ring_offset.y)
	# Glow textures are 2px larger on each side
	var glow_pos := Vector2(draw_pos.x - 2, draw_pos.y - 2)

	if clue == 0:
		if yes_count > 0:
			# Error: lines touching a 0-clue face
			var ring_col := Color(COL_EDGE_ERROR, COL_EDGE_ERROR.a * fade_out * 0.6)
			var glow_col := Color(COL_EDGE_ERROR, 0.25 * fade_out)
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
# Input handling — click-and-move trail drawing
# ===========================================================================

func _unhandled_input(event: InputEvent) -> void:
	if _solved or _transitioning or _fade_in < 1.0:
		return
	if _grid_manager.grid == null:
		return

	# Track mouse position for the trail cursor line
	if event is InputEventMouseMotion:
		_mouse_pos = event.global_position - global_position
		if _drawing:
			queue_redraw()
		return

	if event is InputEventMouseButton and event.pressed:
		var local: Vector2 = event.global_position - global_position
		_mouse_pos = local

		# Right-click: undo last trail edge while drawing, or remove a placed line
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if _drawing:
				_undo_last_trail_edge()
			else:
				var ei := _find_nearest_edge(_grid_manager.grid, local)
				if ei >= 0 and _grid_manager.lines[ei] == LC.LINE_YES:
					_grid_manager.lines[ei] = LC.LINE_UNKNOWN
					_grid_manager.check_completion()
				
					_grid_manager.grid_changed.emit()
					if not _has_any_lines():
						_start_beckon()
			return

		if event.button_index == MOUSE_BUTTON_LEFT:
			if not _drawing:
				# First click: try to start drawing from a dot
				var di := _find_nearest_dot(_grid_manager.grid, local)
				if di >= 0:
					_start_drawing(di)
			else:
				# Already drawing: click a nearby dot to extend or click away to stop
				var di := _find_nearest_dot(_grid_manager.grid, local)
				if di >= 0 and di != _current_dot:
					_try_click_extend(di)
				elif di == _current_dot:
					# Clicked the same dot — stop drawing
					_stop_drawing()
				else:
					# Clicked away from any dot — stop drawing
					_stop_drawing()


func _find_nearest_dot(grid, local_pos: Vector2) -> int:
	## Find the nearest dot within DOT_CLICK_DIST of local_pos.
	var best_dist := 999.0
	var best_dot := -1
	for i in range(grid.num_dots):
		var d := local_pos.distance_to(grid.dots[i])
		if d < best_dist:
			best_dist = d
			best_dot = i
	if best_dist < DOT_CLICK_DIST:
		return best_dot
	return -1


func _find_edge_between(grid, dot_a: int, dot_b: int) -> int:
	## Return the edge index connecting dot_a and dot_b, or -1 if none.
	for ei: int in grid.dot_edges[dot_a]:
		var e: Vector2i = grid.edges[ei]
		if (e.x == dot_b) or (e.y == dot_b):
			return ei
	return -1


func _start_drawing(dot_idx: int) -> void:
	_beckon_active = false
	_drawing = true
	_current_dot = dot_idx
	_start_dot = dot_idx
	_trail_edges.clear()
	queue_redraw()


func _stop_drawing() -> void:
	_drawing = false
	_current_dot = -1
	_trail_edges.clear()
	# Check completion after finishing a stroke
	_grid_manager.check_completion()

	_grid_manager.grid_changed.emit()
	if _grid_manager.solved:
		_grid_manager.puzzle_solved.emit()
	elif not _has_any_lines():
		_start_beckon()
	queue_redraw()


func _undo_last_trail_edge() -> void:
	## Undo the last edge in the current trail. If trail is empty, stop drawing.
	if _trail_edges.is_empty():
		_stop_drawing()
		return
	var edge_idx: int = _trail_edges.pop_back()
	# Revert edge to UNKNOWN (only if we placed it, not if it was pre-existing)
	_grid_manager.lines[edge_idx] = LC.LINE_UNKNOWN
	# Move cursor back to the other dot of this edge
	var e: Vector2i = _grid_manager.grid.edges[edge_idx]
	_current_dot = e.y if e.x == _current_dot else e.x
	_grid_manager.grid_changed.emit()
	queue_redraw()


func _try_click_extend(target_dot: int) -> void:
	## Called when the player clicks a dot while drawing.
	## If the target dot is adjacent to the current dot, extend or backtrack.
	var grid = _grid_manager.grid
	if _current_dot < 0:
		return

	# Find the edge connecting _current_dot and target_dot
	var edge_idx := _find_edge_between(grid, _current_dot, target_dot)
	if edge_idx < 0:
		# Not adjacent — stop drawing
		_stop_drawing()
		return

	# Check if this edge is the last one in our trail (undo / backtrack)
	if _trail_edges.size() > 0 and _trail_edges[-1] == edge_idx:
		# Backtracking: undo the last edge
		_trail_edges.pop_back()
		_grid_manager.lines[edge_idx] = LC.LINE_UNKNOWN
		_current_dot = target_dot
		_grid_manager.grid_changed.emit()
		return

	# Extend trail: set edge to YES and move cursor to target dot
	if _grid_manager.lines[edge_idx] == LC.LINE_YES:
		# Edge already drawn — traverse over it without changing state
		_trail_edges.append(edge_idx)
		_current_dot = target_dot
	else:
		_grid_manager.lines[edge_idx] = LC.LINE_YES
		_bh_edge_grace[edge_idx] = BH_GRACE_PERIOD
	
		_trail_edges.append(edge_idx)
		_current_dot = target_dot
		_grid_manager.grid_changed.emit()

	# Auto-stop if we've closed a loop: target dot now has 2 YES edges
	var yes_count := 0
	for ei: int in grid.dot_edges[target_dot]:
		if _grid_manager.lines[ei] == LC.LINE_YES:
			yes_count += 1
	if yes_count >= 2:
		_stop_drawing()
		return
	queue_redraw()


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
	_loop_fade = 1.0
	_win_tween = create_tween()
	# Phase 1 (1s): fade out non-loop elements + black hole
	_win_tween.tween_method(func(v): _win_fade = v; queue_redraw(), 0.0, 1.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_win_tween.parallel().tween_method(func(v): _bh_fade = v; queue_redraw(), 1.0, 0.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 2 (0.5s): glow the loop golden + bloom surge
	_win_tween.tween_method(func(v): _win_alpha = v; queue_redraw(), 0.0, 1.0, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_win_tween.parallel().tween_method(_set_bloom_intensity, 0.35, 1.2, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	# Phase 3 (0.5s): settle to sustained glow + bloom
	_win_tween.tween_method(func(v): _win_alpha = v; queue_redraw(), 1.0, 0.6, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_win_tween.parallel().tween_method(_set_bloom_intensity, 1.2, 0.5, 0.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	# Phase 4 (0.5s): hold the completed loop outline
	_win_tween.tween_interval(0.5)
	# Phase 5 (1s): fade out the loop edges
	_win_tween.tween_method(func(v): _loop_fade = v; queue_redraw(), 1.0, 0.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_win_tween.parallel().tween_method(_set_bloom_intensity, 0.5, 0.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	# Phase 6: advance to next puzzle (dot transition 1.5s, then fade-in 1s)
	_win_tween.tween_callback(_advance_to_next_puzzle)


func _advance_to_next_puzzle() -> void:
	_puzzle_index += 1
	if _puzzle_index >= _manifest.size():
		return
	# Snapshot old dot positions
	var old_dots: Array[Vector2] = []
	if _grid_manager.grid != null:
		for di in range(_grid_manager.grid.num_dots):
			old_dots.append(_grid_manager.grid.dots[di])
	# Pre-read next puzzle JSON to get new dot positions
	var new_dots := _read_dots_from_json(_manifest[_puzzle_index])
	# Build transition array
	_transition_dots = _match_dots(old_dots, new_dots)
	_transitioning = true
	_transition_t = 0.0
	# Tween the transition
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	_win_tween.tween_method(func(v): _transition_t = v; queue_redraw(), 0.0, 1.0, 1.5) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_win_tween.tween_callback(_finish_transition)


func _read_dots_from_json(path: String) -> Array[Vector2]:
	var dots: Array[Vector2] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return dots
	var json := JSON.new()
	json.parse(file.get_as_text())
	file.close()
	var data: Dictionary = json.data
	var dx = data["dots_x"]
	var dy = data["dots_y"]
	for i in range(dx.size()):
		dots.append(Vector2(dx[i], dy[i]))
	return dots


func _match_dots(old_dots: Array[Vector2], new_dots: Array[Vector2]) -> Array:
	var result: Array = []
	var old_used: Array[bool] = []
	old_used.resize(old_dots.size())
	old_used.fill(false)
	var new_used: Array[bool] = []
	new_used.resize(new_dots.size())
	new_used.fill(false)
	var match_count := mini(old_dots.size(), new_dots.size())
	# Greedy nearest-neighbour matching
	for _m in range(match_count):
		var best_dist := 9999.0
		var best_old := -1
		var best_new := -1
		for oi in range(old_dots.size()):
			if old_used[oi]:
				continue
			for ni in range(new_dots.size()):
				if new_used[ni]:
					continue
				var d := old_dots[oi].distance_to(new_dots[ni])
				if d < best_dist:
					best_dist = d
					best_old = oi
					best_new = ni
		if best_old < 0 or best_dist > 120.0:
			break
		old_used[best_old] = true
		new_used[best_new] = true
		result.append({"from": old_dots[best_old], "to": new_dots[best_new], "fade": "morph"})
	# Remaining old dots fade out
	for oi in range(old_dots.size()):
		if not old_used[oi]:
			result.append({"from": old_dots[oi], "to": old_dots[oi], "fade": "out"})
	# Remaining new dots fade in
	for ni in range(new_dots.size()):
		if not new_used[ni]:
			result.append({"from": new_dots[ni], "to": new_dots[ni], "fade": "in"})
	return result


func _finish_transition() -> void:
	_transitioning = false
	_transition_dots.clear()
	_load_current_puzzle()
	# Fade in edges and clues
	_fade_in = 0.0
	if _win_tween and _win_tween.is_valid():
		_win_tween.kill()
	_win_tween = create_tween()
	_win_tween.tween_method(func(v): _fade_in = v; queue_redraw(), 0.0, 1.0, 1.0) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ===========================================================================
# Black hole hazard
# ===========================================================================

func _init_black_hole() -> void:
	_bh_active = false
	_bh_radius = 0.0
	_bh_time = 0.0
	_bh_spawn_timer = BH_SPAWN_DELAY
	_bh_consume_timer = BH_CONSUME_INTERVAL
	_bh_particles.clear()
	_bh_streams.clear()
	_bh_edge_grace.clear()
	_bh_fade = 1.0
	_bh_spawn_fade = 1.0
	_bh_target = Vector2.ZERO
	_bh_target_timer = 0.0


func _spawn_black_hole() -> void:
	var target := _find_spawn_near_progress()
	if target == Vector2.ZERO:
		return
	_bh_active = true
	_bh_pos = target
	_bh_radius = BH_MIN_RADIUS
	_bh_spawn_fade = 0.0
	_bh_consume_timer = BH_CONSUME_INTERVAL
	# Initialize swirl particles
	_bh_particles.clear()
	for i in range(BH_PARTICLE_COUNT):
		_bh_particles.append({
			"angle": randf() * TAU,
			"dist": randf_range(0.5, 1.0),
			"speed": randf_range(1.5, 3.0),
			"size": randf_range(0.5, 1.5),
			"phase": randf() * TAU,
		})
	# Initialize inward-streaming particles (Celeste BlackholeBG style)
	_bh_streams.clear()
	for i in range(BH_STREAM_COUNT):
		_bh_streams.append(_make_stream_particle())


func _make_stream_particle() -> Dictionary:
	## Create a single inward-streaming particle at a random position around the black hole.
	var angle := randf() * TAU
	var dist := randf_range(1.2, 2.0)  # starts outside the visual radius
	return {
		"angle": angle,
		"dist": dist,           # fraction of radius (starts far, accelerates in)
		"speed": randf_range(0.4, 0.8),  # inward speed (fraction/sec)
		"accel": randf_range(1.5, 3.0),  # acceleration factor (Celeste CubeIn style)
		"alpha": randf_range(0.3, 0.7),
	}


func _find_spawn_near_progress() -> Vector2:
	## Pick a random face that has at least one YES edge (player progress),
	## and return its centroid as the spawn point.
	var gm := _grid_manager
	if gm.grid == null:
		return Vector2.ZERO
	var grid = gm.grid
	var candidates: Array[int] = []
	for fi in range(grid.num_faces):
		for ei: int in grid.face_edges[fi]:
			if gm.lines[ei] == LC.LINE_YES:
				candidates.append(fi)
				break
	if candidates.is_empty():
		return Vector2.ZERO
	var pick: int = candidates[randi() % candidates.size()]
	return grid.face_centroid(pick)


func _find_unsolved_cluster_center() -> Vector2:
	## Find the centroid of the largest cluster of unsolved clue faces.
	var gm := _grid_manager
	if gm.grid == null:
		return Vector2.ZERO
	var grid = gm.grid
	# Gather unsolved faces that have clues
	var unsolved_centers: Array[Vector2] = []
	for fi in range(grid.num_faces):
		var c: int = gm.clues[fi]
		if c < 0:
			continue
		var yes_count := 0
		for ei: int in grid.face_edges[fi]:
			if gm.lines[ei] == LC.LINE_YES:
				yes_count += 1
		if yes_count != c:
			unsolved_centers.append(grid.face_centroid(fi))
	if unsolved_centers.is_empty():
		return Vector2.ZERO
	# Return average position of unsolved faces
	var sum := Vector2.ZERO
	for p in unsolved_centers:
		sum += p
	return sum / float(unsolved_centers.size())


func _update_black_hole(delta: float) -> void:
	# Tick down edge grace timers
	var expired: Array = []
	for ei in _bh_edge_grace:
		_bh_edge_grace[ei] -= delta
		if _bh_edge_grace[ei] <= 0.0:
			expired.append(ei)
	for ei in expired:
		_bh_edge_grace.erase(ei)

	if not _bh_active:
		_bh_spawn_timer -= delta
		if _bh_spawn_timer <= 0.0 and _has_any_lines():
			_spawn_black_hole()
		return

	_bh_time += delta

	# Fade in gradually
	if _bh_spawn_fade < 1.0:
		_bh_spawn_fade = minf(_bh_spawn_fade + delta / BH_SPAWN_FADE_DURATION, 1.0)

	# Grow radius
	_bh_radius = minf(_bh_radius + BH_GROW_SPEED * delta, BH_MAX_RADIUS)

	# Update stream particles — accelerate inward, respawn when they reach center
	for i in range(_bh_streams.size()):
		var sp: Dictionary = _bh_streams[i]
		# Accelerate inward (CubeIn easing: faster as it gets closer)
		var inward: float = sp.speed * (1.0 + sp.accel * (1.0 - sp.dist)) * delta
		sp.dist -= inward
		if sp.dist <= 0.1:
			_bh_streams[i] = _make_stream_particle()

	# Pick a new drift target every few seconds
	_bh_target_timer -= delta
	if _bh_target_timer <= 0.0 or _bh_target == Vector2.ZERO:
		_bh_target_timer = randf_range(3.0, 6.0)
		var candidate := _find_spawn_near_progress()
		if candidate != Vector2.ZERO:
			# Offset the target randomly so it doesn't beeline to the same spot
			candidate += Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0))
			candidate.x = clampf(candidate.x, 20.0, VIEWPORT_W - 20.0)
			candidate.y = clampf(candidate.y, 20.0, VIEWPORT_H - 20.0)
			_bh_target = candidate

	# Movement: orbit around target + drift toward it + flee from cursor
	var move := Vector2.ZERO

	if _bh_target != Vector2.ZERO:
		var to_target := _bh_target - _bh_pos
		var dist_to_target := to_target.length()

		if dist_to_target > 3.0:
			# Drift toward target
			move += to_target.normalized() * BH_MOVE_SPEED * delta
			# Perpendicular orbit component — keeps it circling instead of sitting
			var perp := Vector2(-to_target.y, to_target.x).normalized()
			move += perp * BH_MOVE_SPEED * 0.7 * delta

	# Flee from mouse cursor when player is nearby
	var mouse_dist := _mouse_pos.distance_to(_bh_pos)
	if mouse_dist < BH_FLEE_RADIUS and mouse_dist > 0.1:
		var flee_dir := (_bh_pos - _mouse_pos).normalized()
		var flee_strength := (1.0 - mouse_dist / BH_FLEE_RADIUS) * BH_FLEE_SPEED * delta
		move += flee_dir * flee_strength

	_bh_pos += move
	# Clamp to viewport bounds with padding
	_bh_pos.x = clampf(_bh_pos.x, 20.0, VIEWPORT_W - 20.0)
	_bh_pos.y = clampf(_bh_pos.y, 20.0, VIEWPORT_H - 20.0)

	# Consume edges periodically (only after fully faded in)
	if _bh_spawn_fade >= 1.0:
		_bh_consume_timer -= delta
		if _bh_consume_timer <= 0.0:
			_bh_consume_timer = BH_CONSUME_INTERVAL
			_bh_consume_edges()


func _bh_consume_edges() -> void:
	## Reset YES edges within the black hole radius to UNKNOWN.
	var gm := _grid_manager
	var grid = gm.grid
	if grid == null:
		return
	var consumed := false
	for ei in range(grid.num_edges):
		if gm.lines[ei] != LC.LINE_YES:
			continue
		# Skip edges still under grace protection
		if _bh_edge_grace.has(ei):
			continue
		# Check if edge midpoint is within black hole radius
		var d1: Vector2 = grid.dots[grid.edges[ei].x]
		var d2: Vector2 = grid.dots[grid.edges[ei].y]
		var mid := (d1 + d2) * 0.5
		if mid.distance_to(_bh_pos) < _bh_radius:
			gm.lines[ei] = LC.LINE_UNKNOWN
			consumed = true
	if consumed:
		# Truncate active trail if any consumed edge was part of it
		if _drawing:
			_truncate_trail_at_consumed()
		gm.check_completion()
		gm.grid_changed.emit()
		if not _has_any_lines():
			_start_beckon()


func _truncate_trail_at_consumed() -> void:
	## Remove any consumed edges from the trail but keep the player's
	## current dot unchanged so they can continue drawing from where they are.
	var gm := _grid_manager
	var new_trail: Array = []
	for ei in _trail_edges:
		if gm.lines[ei] == LC.LINE_YES:
			new_trail.append(ei)
	_trail_edges = new_trail
	queue_redraw()


func _draw_black_hole() -> void:
	if not _bh_active or _bh_fade < 0.01:
		return
	var r := _bh_radius
	var center := _bh_pos
	var f := _bh_fade * _bh_spawn_fade  # combined spawn fade-in + win fade-out

	# Outer distortion ring — pulsing
	var pulse := sin(_bh_time * 2.0) * 0.15 + 0.85
	var outer_r := r * 1.4 * pulse
	draw_circle(center, outer_r, Color(COL_BH_RING.r, COL_BH_RING.g, COL_BH_RING.b, COL_BH_RING.a * 0.3 * f))

	# Mid ring
	draw_circle(center, r * 1.1, Color(COL_BH_RING, COL_BH_RING.a * 0.5 * f))

	# Core — dark void
	draw_circle(center, r * 0.7, Color(COL_BH_CORE, COL_BH_CORE.a * f))

	# Swirl particles orbiting the center
	for p in _bh_particles:
		var angle: float = p.angle + _bh_time * p.speed
		var dist: float = r * p.dist * pulse
		var px := center.x + cos(angle) * dist
		var py := center.y + sin(angle) * dist
		var twinkle := sin(_bh_time * 4.0 + p.phase) * 0.3 + 0.7
		var col := Color(COL_BH_PARTICLE, COL_BH_PARTICLE.a * twinkle * f)
		var sz: float = p.size
		draw_rect(Rect2(floorf(px), floorf(py), sz, sz), col)

	# Inward-streaming particles (Celeste BlackholeBG style)
	for sp in _bh_streams:
		var sp_angle: float = sp.angle
		var sp_dist: float = sp.dist * r * 1.5
		var sp_pos := center + Vector2(cos(sp_angle), sin(sp_angle)) * sp_dist
		# Fade in as they approach, brighter near center
		var sp_alpha: float = sp.alpha * (1.0 - sp.dist) * f
		if sp_alpha > 0.01:
			var sp_col := Color(COL_BH_PARTICLE.r, COL_BH_PARTICLE.g, COL_BH_PARTICLE.b, sp_alpha)
			draw_rect(Rect2(floorf(sp_pos.x), floorf(sp_pos.y), 1, 1), sp_col)

	# Inner bright accretion dot
	var acc_pulse := sin(_bh_time * 5.0) * 0.3 + 0.7
	draw_circle(center, 1.5, Color(0.8, 0.5, 1.0, acc_pulse * 0.6 * f))


func _bh_get_tint(pos: Vector2) -> float:
	## Returns 0.0-1.0 tint strength for elements near the black hole.
	## Used to lerp colors toward COL_BH_TINT (purple) near the vortex.
	if not _bh_active:
		return 0.0
	var dist := pos.distance_to(_bh_pos)
	if dist > BH_TINT_RADIUS:
		return 0.0
	return (1.0 - dist / BH_TINT_RADIUS) * _bh_fade * _bh_spawn_fade * 0.6


func _process(delta: float) -> void:
	_time += delta
	_update_bg_stars(delta)
	if _solved:
		_win_shimmer += delta
	if _beckon_active:
		_beckon_time += delta
	if not _solved and not _transitioning and _fade_in >= 1.0 and _puzzle_index >= BH_FIRST_PUZZLE:
		_update_black_hole(delta)
	queue_redraw()
