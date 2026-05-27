extends Node2D
## Visual representation of a single grid square for the Train Tracks puzzle.
## Draws track pieces, no-track marks, and error indicators via _draw().

const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")
var TRACKS_TEX: Texture2D = load("res://assets/tracks/tracks3.png")
var TILE_TEX: Texture2D = load("res://assets/tracks/dirt.png")
var TILE_GREY_TEX: Texture2D = load("res://assets/tracks/tile_grey.png")
var ROCKS_TEX: Texture2D = load("res://assets/tracks/rocks.png")
var TREE_TEX: Texture2D = load("res://assets/tracks/tree.png")
const FRAME_SIZE := 16
const TILE_FRAMES := 6
const GREY_FRAMES := 4
const ROCK_FRAMES := 4
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

var grid_x: int = 0
var grid_y: int = 0
var square_data = null
var highlight: float = 0.0:  # 0.0 = normal, 1.0 = full highlight (win animation)
	set(v):
		highlight = v
		queue_redraw()
var _tile_frame: int = 0
var _tile_flip_h: bool = false
var _tile_flip_v: bool = false
var _grey_frame: int = 0
var tile_blend: float = 0.0:  # 0.0 = dirt, 1.0 = grey
	set(v):
		tile_blend = v
		queue_redraw()
var _neighbor_track: int = 0  # bitmask: which neighbors have track edges facing this cell (R=1 U=2 L=4 D=8)
var _neighbor_has_track: int = 0  # bitmask: which neighbors are track cells (R=1 U=2 L=4 D=8), for bleed blending
# Decoration: 0=none, 1=rocks, 2=tree (bottom-left cell owns the 32x32 tree)
var decoration: int = 0
var _rock_frame: int = 0
var deco_alpha: float = 0.0:
	set(v):
		deco_alpha = v
		queue_redraw()
var grid_bleed: float = 0.0:  # 0→1, fills the 1px grid gap around this cell
	set(v):
		grid_bleed = v
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
	_rock_frame = absi(hash(x * 31 + y * 97)) % ROCK_FRAMES


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

	# Bleed: fill the 1px grid gaps by extending cell edges
	if grid_bleed > 0.0:
		_draw_grid_bleed()

	# Decorations (rocks/trees on empty cells after win)
	if decoration != 0 and deco_alpha > 0.0:
		_draw_decoration()

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


const GRAVEL_COLOR := Color("766f6b")
const DIRT_COLOR := Color("996b49")

func _my_track() -> bool:
	if square_data == null:
		return false
	return square_data.has_flag(TC.S_TRACK) or square_data.e_count(TC.E_TRACK) > 0

func _bleed_color_for_edge(dir: int) -> Color:
	# Blend between this cell's color and the neighbor's across the gap
	var me := GRAVEL_COLOR if _my_track() else DIRT_COLOR
	var neighbor_is_track := (_neighbor_has_track & dir) != 0
	var them := GRAVEL_COLOR if neighbor_is_track else DIRT_COLOR
	return me.lerp(them, 0.5)


func _draw_grid_bleed() -> void:
	# Fill interior grid gaps only (skip outer grid edges)
	if grid_bleed > 0.0:
		if grid_x > 0:
			var left_col := Color(_bleed_color_for_edge(TC.DIR_L), grid_bleed)
			draw_rect(Rect2(-1, 0, 1, CELL_SIZE), left_col)
		if grid_y > 0:
			var top_col := Color(_bleed_color_for_edge(TC.DIR_U), grid_bleed)
			draw_rect(Rect2(0, -1, CELL_SIZE, 1), top_col)
		if grid_x > 0 and grid_y > 0:
			var left_col := _bleed_color_for_edge(TC.DIR_L)
			var top_col := _bleed_color_for_edge(TC.DIR_U)
			var corner_col := Color(left_col.lerp(top_col, 0.5), grid_bleed)
			draw_rect(Rect2(-1, -1, 1, 1), corner_col)


const DECO_ROCKS := 1
const DECO_TREE := 2

func _draw_decoration() -> void:
	var tint := Color(1, 1, 1, deco_alpha)
	if decoration == DECO_ROCKS:
		var src := Rect2(_rock_frame * FRAME_SIZE, 0, FRAME_SIZE, FRAME_SIZE)
		draw_texture_rect_region(ROCKS_TEX, Rect2(0, 0, CELL_SIZE, CELL_SIZE), src, tint)
	elif decoration == DECO_TREE:
		# Tree is 32x32: this cell is bottom-left, draws upward 16px into the row above
		draw_texture_rect_region(TREE_TEX, Rect2(0, -CELL_SIZE, CELL_SIZE * 2, CELL_SIZE * 2),
			Rect2(0, 0, 32, 32), tint)


func _on_click_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed:
		# Use get_local_mouse_position() — event.global_position is in viewport
		# coords which breaks when Camera2D has panned
		var local := get_local_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			square_clicked.emit(grid_x, grid_y, local)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			square_right_clicked.emit(grid_x, grid_y, local)
