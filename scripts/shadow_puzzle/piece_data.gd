@warning_ignore("integer_division")
extends RefCounted
class_name ShadowPieceData
## A polyomino piece in the Shadow puzzle.
## Lives either in the tray (not placed) or snapped to the wall grid.

const CELL := 10  # px per cell, must match shadow_consts.gd

var shape_name: String = ""
var base_cells: Array[Vector2i] = []   # rotation-0 cell offsets
var cells: Array[Vector2i] = []        # current rotated offsets
var rotation: int = 0                  # 0-3 (90° increments)

var grid_pos: Vector2i = Vector2i(-1, -1)  # top-left cell on wall grid, or (-1,-1) = in tray
var tray_pos: Vector2 = Vector2.ZERO       # pixel position when in tray

var piece_id: int = 0
var color: Color = Color.WHITE


func _init(p_name: String = "", p_cells: Array[Vector2i] = [],
		p_id: int = 0, p_color: Color = Color.WHITE) -> void:
	shape_name = p_name
	base_cells = p_cells.duplicate()
	cells = p_cells.duplicate()
	piece_id = p_id
	color = p_color


func is_placed() -> bool:
	return grid_pos.x >= 0


## Rotate 90° CW.
func rotate_cw() -> void:
	rotation = (rotation + 1) % 4
	cells = rotate_cells_static(base_cells, rotation)


## World-grid cells this piece occupies (only valid when placed).
func get_grid_cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for c in cells:
		result.append(grid_pos + c)
	return result


## Get pixel-space rects for drawing (either tray position or wall position).
func get_draw_rects(wall_origin: Vector2) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if is_placed():
		for c in cells:
			var px: float = wall_origin.x + float((grid_pos.x + c.x) * CELL)
			var py: float = wall_origin.y + float((grid_pos.y + c.y) * CELL)
			rects.append(Rect2(px, py, CELL, CELL))
	else:
		var bounds: Vector2i = bounds_of(cells)
		var half_x: float = float(bounds.x) * CELL * 0.5
		var half_y: float = float(bounds.y) * CELL * 0.5
		for c in cells:
			var px: float = tray_pos.x - half_x + float(c.x) * CELL
			var py: float = tray_pos.y - half_y + float(c.y) * CELL
			rects.append(Rect2(px, py, CELL, CELL))
	return rects


## Hit test against the piece's current draw position.
func point_inside(pt: Vector2, wall_origin: Vector2) -> bool:
	for r in get_draw_rects(wall_origin):
		if r.has_point(pt):
			return true
	return false


# --- Static helpers ---

static func rotate_cells_static(src: Array[Vector2i], times: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = src.duplicate()
	for _r in range(times % 4):
		var rotated: Array[Vector2i] = []
		for c in result:
			rotated.append(Vector2i(-c.y, c.x))
		result = rotated
	var mn := Vector2i(result[0])
	for c in result:
		mn.x = mini(mn.x, c.x)
		mn.y = mini(mn.y, c.y)
	for i in result.size():
		result[i] = result[i] - mn
	return result


static func bounds_of(src: Array[Vector2i]) -> Vector2i:
	var mx := Vector2i.ZERO
	for c in src:
		mx.x = maxi(mx.x, c.x)
		mx.y = maxi(mx.y, c.y)
	return mx + Vector2i.ONE
