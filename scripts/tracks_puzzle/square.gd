extends Node2D
## Visual representation of a single grid square for the Train Tracks puzzle.
## Draws track pieces, no-track marks, and error indicators via _draw().

const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")
var TRACKS_TEX: Texture2D = load("res://assets/tracks/tracks3.png")
var TILE_TEX: Texture2D = load("res://assets/tracks/dirt.png")
var TILE_GREY_TEX: Texture2D = load("res://assets/tracks/tile_grey.png")
var GREEN_TEX: Texture2D = load("res://assets/tracks/green3.png")
const FRAME_SIZE := 16
const TILE_FRAMES := 6
const GREY_FRAMES := 4
const GREEN_FRAMES := 4
# tracks3.png layout: frame 0 = UD straight, frame 1 = RD curve
# All variants derived via 90° rotation increments around cell center
# Each entry: [frame_index, rotation_count] (0=0°, 1=90°CW, 2=180°, 3=270°CW)
const TRACK_FRAME := {
	10: [0, 0],  # UD  – straight vertical (as-is)
	5:  [0, 1],  # LR  – straight horizontal (90° CW)
	9:  [1, 0],  # RD  – curve (as-is, arc at bottom-right)
	12: [1, 1],  # LD  – curve (90° CW, arc at bottom-left)
	6:  [1, 2],  # LU  – curve (180°, arc at top-left)
	3:  [1, 3],  # RU  – curve (270° CW, arc at top-right)
}

signal square_clicked(grid_x: int, grid_y: int, local_pos: Vector2)
signal square_right_clicked(grid_x: int, grid_y: int, local_pos: Vector2)

# Diagonal neighbor bits for autotile inner corners
const DIAG_NE := 16
const DIAG_NW := 32
const DIAG_SE := 64
const DIAG_SW := 128

const CELL_SIZE := 16.0
const CENTER := Vector2(CELL_SIZE / 2.0, CELL_SIZE / 2.0)

# Rail positions for stubs
const RAIL_IN := 5.0
const RAIL_OUT := 11.0

# Colors
const BG_COLOR := Color(0.18, 0.16, 0.14)
const BG_TRACK := Color(0.25, 0.22, 0.18)
const TRACK_COLOR := Color(0.5, 0.5, 0.5)
const CLUE_TRACK_COLOR := Color(0.3, 0.3, 0.35)
const SLEEPER_COLOR := Color(0.5, 0.4, 0.1)
const ERROR_COLOR := Color(1.0, 0.2, 0.2)
const NOTRACK_COLOR := Color(0.45, 0.4, 0.35)
const GRID_LINE_COLOR := Color(0.35, 0.33, 0.3)
const HIGHLIGHT_COLOR := Color(0.95, 0.85, 0.3)  # warm gold for win highlight

# Decoration types
const DECO_NONE := 0
const DECO_TREE := 1
const DECO_HOUSE := 2
const DECO_WATER := 3

# Decoration colors
const TREE_GREEN := Color(0.2, 0.55, 0.2)
const TREE_TRUNK := Color(0.45, 0.3, 0.15)
const HOUSE_WALL := Color(0.6, 0.45, 0.3)
const HOUSE_ROOF := Color(0.55, 0.25, 0.2)
const HOUSE_WINDOW := Color(0.9, 0.85, 0.4)
const WATER_COLOR := Color(0.25, 0.45, 0.7)
const WATER_HIGHLIGHT := Color(0.4, 0.6, 0.85)

var grid_x: int = 0
var grid_y: int = 0
var square_data = null
var highlight: float = 0.0:  # 0.0 = normal, 1.0 = full highlight (win animation)
	set(v):
		highlight = v
		queue_redraw()
var decoration: int = DECO_NONE
var _tile_frame: int = 0
var _tile_flip_h: bool = false
var _tile_flip_v: bool = false
var _grey_frame: int = 0
var _green_frame: int = 0
var tile_blend: float = 0.0:  # 0.0 = dirt, 1.0 = grey
	set(v):
		tile_blend = v
		queue_redraw()
var _green_mask: int = 0  # autotile bitmask: R=1 U=2 L=4 D=8, diagonals: NE=16 NW=32 SE=64 SW=128
var _neighbor_track: int = 0  # bitmask: which neighbors have track edges facing this cell (R=1 U=2 L=4 D=8)
var grid_bleed: float = 0.0:  # 0→1, fills the 1px grid gap around this cell
	set(v):
		grid_bleed = v
		queue_redraw()
var grid_bleed_right: float = 0.0:  # separate bleed for right edge
	set(v):
		grid_bleed_right = v
		queue_redraw()
var grid_bleed_bottom: float = 0.0:  # separate bleed for bottom edge
	set(v):
		grid_bleed_bottom = v
		queue_redraw()
var deco_alpha: float = 0.0:
	set(v):
		deco_alpha = v
		queue_redraw()


func setup(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	# Deterministic per-cell tile variant from position hash
	var h := hash(x * 1000 + y)
	_tile_frame = absi(h) % TILE_FRAMES
	_tile_flip_h = (h >> 16) & 1 == 1
	_tile_flip_v = (h >> 17) & 1 == 1
	_grey_frame = absi(hash(y * 1000 + x)) % GREY_FRAMES
	_green_frame = absi(hash(x * 31 + y * 97)) % GREEN_FRAMES


func refresh(data) -> void:
	square_data = data
	queue_redraw()


func _draw() -> void:
	# Background
	var has_track: bool = false
	if square_data != null:
		has_track = square_data.has_flag(TC.S_TRACK) or square_data.e_count(TC.E_TRACK) > 0
	# Draw tile background from atlas (randomized per cell)
	var src := Rect2(_tile_frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
	var dst := Rect2(0, 0, CELL_SIZE, CELL_SIZE)
	if _tile_flip_h or _tile_flip_v:
		var sx := -1.0 if _tile_flip_h else 1.0
		var sy := -1.0 if _tile_flip_v else 1.0
		var ox := CELL_SIZE if _tile_flip_h else 0.0
		var oy := CELL_SIZE if _tile_flip_v else 0.0
		draw_set_transform(Vector2(ox, oy), 0.0, Vector2(sx, sy))
		draw_texture_rect_region(TILE_TEX, dst, src)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		draw_texture_rect_region(TILE_TEX, dst, src)
	# Crossfade to grey tile variant
	if tile_blend > 0.0:
		var grey_src := Rect2(_grey_frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		draw_texture_rect_region(TILE_GREY_TEX, dst, grey_src, Color(1, 1, 1, tile_blend))
	# Tint overlay for track vs highlight
	if has_track and highlight > 0.0:
		draw_rect(Rect2(0, 0, CELL_SIZE, CELL_SIZE), Color(HIGHLIGHT_COLOR, highlight * 0.4))

	if square_data == null:
		return

	# Determine track tint (white = no tint, so sprite shows at full brightness)
	var is_error: bool = square_data.has_flag(TC.S_ERROR)
	var track_col := Color.WHITE
	if is_error:
		track_col = ERROR_COLOR
	if highlight > 0.0 and has_track:
		track_col = track_col.lerp(HIGHLIGHT_COLOR, highlight)

	# Draw track shapes based on edge flags
	var track_dirs: int = square_data.e_dirs(TC.E_TRACK)
	if track_dirs != 0:
		_draw_track_shape(track_dirs, track_col)

	# Draw square NOTRACK mark (X in center)
	if square_data.has_flag(TC.S_NOTRACK):
		var off := CELL_SIZE / 4.0
		draw_line(CENTER - Vector2(off, off), CENTER + Vector2(off, off), NOTRACK_COLOR, 1.0)
		draw_line(CENTER + Vector2(-off, off), CENTER + Vector2(off, -off), NOTRACK_COLOR, 1.0)

	# Draw edge NOTRACK marks (small X at edge midpoints)
	var notrack_dirs: int = square_data.e_dirs(TC.E_NOTRACK)
	for i in range(4):
		var d := 1 << i
		if notrack_dirs & d:
			_draw_edge_notrack(d)

	# Decorations (on non-track cells after win)
	if decoration != DECO_NONE and deco_alpha > 0.0:
		_draw_decoration()

	# Bleed: fill the 1px grid gaps by extending cell edges
	if grid_bleed > 0.0 or grid_bleed_right > 0.0 or grid_bleed_bottom > 0.0:
		_draw_grid_bleed()

	# Rail detail on grid lines between connected track heads (drawn last)
	_draw_rail_detail()


func _draw_track_shape(flags: int, col: Color) -> void:
	if TRACK_FRAME.has(flags):
		var info: Array = TRACK_FRAME[flags]
		_draw_track_sprite(info[0], info[1], col)
		return
	# Fallback: draw individual edge stubs
	for i in range(4):
		var d := 1 << i
		if flags & d:
			_draw_stub(d, col)


func _draw_track_sprite(frame: int, rot: int, col: Color) -> void:
	var src := Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
	if rot == 0:
		draw_texture_rect_region(TRACKS_TEX, Rect2(0, 0, CELL_SIZE, CELL_SIZE), src, col)
	else:
		# Rotate around the cell center
		var half := CELL_SIZE / 2.0
		var angle := rot * PI / 2.0
		draw_set_transform(Vector2(half, half), angle, Vector2.ONE)
		draw_texture_rect_region(TRACKS_TEX, Rect2(-half, -half, CELL_SIZE, CELL_SIZE), src, col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_stub(d: int, col: Color) -> void:
	# Track head sprite is frame 2, facing down by default
	var rot: int = 0
	if d == TC.DIR_D:
		rot = 0
	elif d == TC.DIR_L:
		rot = 1
	elif d == TC.DIR_U:
		rot = 2
	elif d == TC.DIR_R:
		rot = 3
	_draw_track_sprite(2, rot, col)


func _draw_edge_notrack(d: int) -> void:
	# Small X at the midpoint of edge d
	var ex := CELL_SIZE / 2.0
	var ey := CELL_SIZE / 2.0
	if d == TC.DIR_R:
		ex = CELL_SIZE
	elif d == TC.DIR_L:
		ex = 0.0
	elif d == TC.DIR_D:
		ey = CELL_SIZE
	elif d == TC.DIR_U:
		ey = 0.0
	var off := 3.0
	var center := Vector2(ex, ey)
	draw_line(center + Vector2(-off, -off), center + Vector2(off, off), NOTRACK_COLOR, 1.0)
	draw_line(center + Vector2(-off, off), center + Vector2(off, -off), NOTRACK_COLOR, 1.0)


func _draw_rail_detail() -> void:
	if square_data == null:
		return
	var my_tracks: int = square_data.e_dirs(TC.E_TRACK)
	if my_tracks == 0 or _neighbor_track == 0:
		return
	var hi := Color("9c9c9c")
	var lo := Color("686868")
	# Left grid line: this cell has track-left AND neighbor-left has track-right
	if (my_tracks & TC.DIR_L) and (_neighbor_track & TC.DIR_L):
		draw_rect(Rect2(-1, 2, 1, 1), hi)
		draw_rect(Rect2(-1, 3, 1, 1), lo)
		draw_rect(Rect2(-1, 12, 1, 1), lo)
		draw_rect(Rect2(-1, 13, 1, 1), hi)
	# Top grid line: this cell has track-up AND neighbor-above has track-down
	if (my_tracks & TC.DIR_U) and (_neighbor_track & TC.DIR_U):
		draw_rect(Rect2(2, -1, 1, 1), hi)
		draw_rect(Rect2(3, -1, 1, 1), lo)
		draw_rect(Rect2(12, -1, 1, 1), lo)
		draw_rect(Rect2(13, -1, 1, 1), hi)


func _get_bleed_color() -> Color:
	if decoration == DECO_TREE and deco_alpha >= 1.0:
		return Color("996b49")
	elif tile_blend > 0.5:
		return Color("766f6b")
	else:
		return Color("766f6b")


func _draw_grid_bleed() -> void:
	var is_green := decoration == DECO_TREE and deco_alpha >= 1.0
	var base := _get_bleed_color()
	var frame := _green_mask & 0xF
	var frame_x := frame * FRAME_SIZE
	# Left + top (owned by this cell)
	if grid_bleed > 0.0:
		var a := grid_bleed
		if is_green:
			var tint := Color(1, 1, 1, a)
			# Left: leftmost pixel column of green frame
			draw_texture_rect_region(GREEN_TEX, Rect2(-1, 0, 1, CELL_SIZE),
				Rect2(frame_x, 0, 1, FRAME_SIZE), tint)
			# Top: topmost pixel row of green frame
			draw_texture_rect_region(GREEN_TEX, Rect2(0, -1, CELL_SIZE, 1),
				Rect2(frame_x, 0, FRAME_SIZE, 1), tint)
			# Corner: top-left pixel
			draw_texture_rect_region(GREEN_TEX, Rect2(-1, -1, 1, 1),
				Rect2(frame_x, 0, 1, 1), tint)
		else:
			var col := Color(base, a)
			draw_rect(Rect2(-1, 0, 1, CELL_SIZE), col)
			draw_rect(Rect2(0, -1, CELL_SIZE, 1), col)
			draw_rect(Rect2(-1, -1, 1, 1), col)
		# Right edge
	if grid_bleed_right > 0.0:
		if is_green:
			var tint := Color(1, 1, 1, grid_bleed_right)
			# Rightmost pixel column of green frame
			draw_texture_rect_region(GREEN_TEX, Rect2(CELL_SIZE, 0, 1, CELL_SIZE),
				Rect2(frame_x + FRAME_SIZE - 1, 0, 1, FRAME_SIZE), tint)
			draw_texture_rect_region(GREEN_TEX, Rect2(CELL_SIZE, -1, 1, 1),
				Rect2(frame_x + FRAME_SIZE - 1, 0, 1, 1), tint)
		else:
			var col := Color(base, grid_bleed_right)
			draw_rect(Rect2(CELL_SIZE, 0, 1, CELL_SIZE), col)
			draw_rect(Rect2(CELL_SIZE, -1, 1, 1), col)
	# Bottom edge
	if grid_bleed_bottom > 0.0:
		if is_green:
			var tint := Color(1, 1, 1, grid_bleed_bottom)
			# Bottom pixel row of green frame
			draw_texture_rect_region(GREEN_TEX, Rect2(0, CELL_SIZE, CELL_SIZE, 1),
				Rect2(frame_x, FRAME_SIZE - 1, FRAME_SIZE, 1), tint)
			draw_texture_rect_region(GREEN_TEX, Rect2(-1, CELL_SIZE, 1, 1),
				Rect2(frame_x, FRAME_SIZE - 1, 1, 1), tint)
		else:
			var col := Color(base, grid_bleed_bottom)
			draw_rect(Rect2(0, CELL_SIZE, CELL_SIZE, 1), col)
			draw_rect(Rect2(-1, CELL_SIZE, 1, 1), col)
	# Bottom-right corner
	if grid_bleed_right > 0.0 and grid_bleed_bottom > 0.0:
		if is_green:
			var tint := Color(1, 1, 1, maxf(grid_bleed_right, grid_bleed_bottom))
			draw_texture_rect_region(GREEN_TEX, Rect2(CELL_SIZE, CELL_SIZE, 1, 1),
				Rect2(frame_x + FRAME_SIZE - 1, FRAME_SIZE - 1, 1, 1), tint)
		else:
			var col := Color(base, maxf(grid_bleed_right, grid_bleed_bottom))
			draw_rect(Rect2(CELL_SIZE, CELL_SIZE, 1, 1), col)


func _draw_decoration() -> void:
	match decoration:
		DECO_TREE:
			_draw_tree()
		DECO_HOUSE:
			_draw_house()
		DECO_WATER:
			_draw_water()


func _draw_tree() -> void:
	# Draw autotiled green from atlas — mask (cardinal bits only) indexes the frame
	var frame := _green_mask & 0xF  # lower 4 bits = R U L D
	var src := Rect2(frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
	draw_texture_rect_region(GREEN_TEX, Rect2(0, 0, CELL_SIZE, CELL_SIZE), src, Color(1, 1, 1, deco_alpha))
	# Inner corners: both cardinal neighbors are green but diagonal is not
	var border_col := Color(TREE_TRUNK, deco_alpha)
	var bw := 2.0
	if (_green_mask & TC.DIR_R) and (_green_mask & TC.DIR_U) and not (_green_mask & DIAG_NE):
		draw_rect(Rect2(CELL_SIZE - bw, 0, bw, bw), border_col)
	if (_green_mask & TC.DIR_L) and (_green_mask & TC.DIR_U) and not (_green_mask & DIAG_NW):
		draw_rect(Rect2(0, 0, bw, bw), border_col)
	if (_green_mask & TC.DIR_R) and (_green_mask & TC.DIR_D) and not (_green_mask & DIAG_SE):
		draw_rect(Rect2(CELL_SIZE - bw, CELL_SIZE - bw, bw, bw), border_col)
	if (_green_mask & TC.DIR_L) and (_green_mask & TC.DIR_D) and not (_green_mask & DIAG_SW):
		draw_rect(Rect2(0, CELL_SIZE - bw, bw, bw), border_col)


func _draw_house() -> void:
	var wall := Color(HOUSE_WALL, deco_alpha)
	var roof := Color(HOUSE_ROOF, deco_alpha)
	var window := Color(HOUSE_WINDOW, deco_alpha)
	var cx := CELL_SIZE / 2.0
	# Walls
	draw_rect(Rect2(cx - 7, 14, 14, 10), wall)
	# Roof triangle
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, 4),
		Vector2(cx - 8, 14),
		Vector2(cx + 8, 14),
	]), roof)
	# Window
	draw_rect(Rect2(cx - 1, 17, 3, 3), window)


func _draw_water() -> void:
	var col := Color(WATER_COLOR, deco_alpha)
	var hi := Color(WATER_HIGHLIGHT, deco_alpha)
	# Three wavy lines
	draw_line(Vector2(5, 10), Vector2(10, 8), hi, 1.0)
	draw_line(Vector2(10, 8), Vector2(17, 10), hi, 1.0)
	draw_line(Vector2(17, 10), Vector2(23, 8), hi, 1.0)
	draw_line(Vector2(4, 14), Vector2(10, 12), col, 1.0)
	draw_line(Vector2(10, 12), Vector2(16, 14), col, 1.0)
	draw_line(Vector2(16, 14), Vector2(22, 12), col, 1.0)
	draw_line(Vector2(6, 18), Vector2(12, 16), col, 1.0)
	draw_line(Vector2(12, 16), Vector2(18, 18), col, 1.0)
	draw_line(Vector2(18, 18), Vector2(24, 16), col, 1.0)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Use get_local_mouse_position() — event.global_position is in viewport
		# coords which breaks when Camera2D has panned
		var local := get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			square_clicked.emit(grid_x, grid_y, local)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			square_right_clicked.emit(grid_x, grid_y, local)
