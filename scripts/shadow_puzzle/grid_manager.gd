@warning_ignore("integer_division")
extends Node
## Logic for the Shadow puzzle.
## Manages the silhouette target, piece placement/removal, and win check.

signal puzzle_solved
signal grid_changed

const GRID_W := 12
const GRID_H := 12

# --- Silhouette data (imported from shadow_consts.gd at design time) ---
# Each puzzle: { "name": str, "silhouette": Array[Vector2i], "pieces": Array[String] }
var _puzzles: Array[Dictionary] = [
	{
		"name": "helicopter",
		"silhouette": [
			Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3),
			Vector2i(6, 3), Vector2i(7, 3),
			Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4),
			Vector2i(8, 4), Vector2i(9, 4),
		],
		"pieces": ["tet_i", "tet_l", "tet_t"],
	},
	{
		"name": "cat",
		"silhouette": [
			Vector2i(4, 2), Vector2i(6, 2),
			Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3),
			Vector2i(5, 4), Vector2i(5, 5),
			Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6),
			Vector2i(4, 7), Vector2i(6, 7),
		],
		"pieces": ["tet_t", "tet_s", "dom", "dom"],
	},
	{
		"name": "house",
		"silhouette": [
			Vector2i(5, 2),
			Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3),
			Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(7, 4),
			Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5),
			Vector2i(4, 6), Vector2i(6, 6),
		],
		"pieces": ["pent_t", "tet_l", "tri_l", "dom"],
	},
	{
		"name": "tree",
		"silhouette": [
			Vector2i(5, 1),
			Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
			Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3),
			Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6),
		],
		"pieces": ["pent_t", "tet_i", "tri_i"],
	},
	{
		"name": "bird",
		"silhouette": [
			Vector2i(3, 3), Vector2i(5, 3),
			Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4),
			Vector2i(4, 5),
			Vector2i(3, 6), Vector2i(4, 6), Vector2i(5, 6),
		],
		"pieces": ["tri_l", "tri_l", "tri_i"],
	},
	{
		"name": "star",
		"silhouette": [
			Vector2i(5, 1),
			Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2),
			Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3), Vector2i(7, 3),
			Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4),
		],
		"pieces": ["pent_t", "tet_i", "tri_i"],
	},
	{
		"name": "rocket",
		"silhouette": [
			Vector2i(5, 1), Vector2i(5, 2),
			Vector2i(4, 3), Vector2i(5, 3), Vector2i(6, 3),
			Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4),
			Vector2i(4, 5), Vector2i(6, 5),
			Vector2i(5, 6),
		],
		"pieces": ["tet_t", "tri_l", "dom", "dom"],
	},
	{
		"name": "key",
		"silhouette": [
			Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4),
			Vector2i(7, 4), Vector2i(8, 4),
			Vector2i(3, 5), Vector2i(8, 5),
		],
		"pieces": ["tet_i", "dom", "dom"],
	},
]

# --- Shape library ---
const SHAPES: Dictionary = {
	"dom": [Vector2i(0, 0), Vector2i(1, 0)],
	"tri_i": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	"tri_l": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)],
	"tet_i": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"tet_o": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"tet_t": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"tet_s": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"tet_z": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
	"tet_l": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1)],
	"tet_j": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1)],
	"pent_f": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)],
	"pent_p": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(0, 2)],
	"pent_u": [Vector2i(0, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"pent_t": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1), Vector2i(1, 2)],
	"pent_l": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 3)],
}

const PIECE_COLORS: Array[Color] = [
	Color(0.55, 0.35, 0.75, 0.88),
	Color(0.35, 0.65, 0.75, 0.88),
	Color(0.75, 0.45, 0.55, 0.88),
	Color(0.65, 0.60, 0.30, 0.88),
	Color(0.40, 0.68, 0.42, 0.88),
	Color(0.70, 0.50, 0.35, 0.88),
	Color(0.45, 0.45, 0.72, 0.88),
]

# --- Runtime state ---
var pieces: Array[ShadowPieceData] = []
var silhouette: Dictionary = {} # Vector2i → true (target cells)
var silhouette_name: String = ""
var _solved: bool = false
var _current_puzzle: int = -1


func generate_puzzle(index: int = -1) -> void:
	_solved = false
	if index < 0:
		_current_puzzle = (_current_puzzle + 1) % _puzzles.size()
	else:
		_current_puzzle = index % _puzzles.size()

	var pdef: Dictionary = _puzzles[_current_puzzle]
	silhouette_name = pdef["name"]

	# Build silhouette lookup
	silhouette.clear()
	var sil_cells: Array = pdef["silhouette"]
	for c in sil_cells:
		silhouette[c as Vector2i] = true

	# Create pieces
	pieces.clear()
	var shape_names: Array = pdef["pieces"]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in shape_names.size():
		var raw: Array = SHAPES[shape_names[i]]
		var typed: Array[Vector2i] = []
		for c in raw:
			typed.append(c as Vector2i)
		var piece := ShadowPieceData.new(shape_names[i], typed, i,
			PIECE_COLORS[i % PIECE_COLORS.size()])
		# Random rotation
		var rand_rot: int = rng.randi_range(0, 3)
		for _r in rand_rot:
			piece.rotate_cw()
		# Position in tray (spread out vertically)
		piece.tray_pos = Vector2(
			rng.randf_range(40.0, 140.0),
			20.0 + float(i) * 36.0
		)
		pieces.append(piece)

	grid_changed.emit()


## Try to place a piece at a grid position. Returns true on success.
func place_piece(piece_id: int, gx: int, gy: int) -> bool:
	if _solved:
		return false
	var piece := _get_piece(piece_id)
	if piece == null:
		return false

	# Check all cells are within the silhouette
	for c in piece.cells:
		var cell := Vector2i(gx + c.x, gy + c.y)
		if not silhouette.has(cell):
			return false
		# Check no overlap with other placed pieces
		if _cell_occupied_by_other(cell, piece_id):
			return false

	piece.grid_pos = Vector2i(gx, gy)
	grid_changed.emit()
	check_completion()
	return true


## Remove a piece from the grid back to the tray.
func unplace_piece(piece_id: int) -> void:
	if _solved:
		return
	var piece := _get_piece(piece_id)
	if piece == null:
		return
	piece.grid_pos = Vector2i(-1, -1)
	grid_changed.emit()


## Rotate a piece (only if not placed, or remove first).
func rotate_piece(piece_id: int) -> void:
	if _solved:
		return
	var piece := _get_piece(piece_id)
	if piece == null:
		return
	piece.rotate_cw()
	grid_changed.emit()


func check_completion() -> bool:
	if _solved:
		return true
	# Every silhouette cell must be covered by exactly one piece
	var covered := {}
	for piece in pieces:
		if not piece.is_placed():
			return false # all pieces must be placed
		for cell in piece.get_grid_cells():
			if covered.has(cell):
				return false # overlap
			covered[cell] = true
	# Check coverage matches silhouette exactly
	for cell in silhouette:
		if not covered.has(cell):
			return false
	for cell in covered:
		if not silhouette.has(cell):
			return false
	_solved = true
	puzzle_solved.emit()
	return true


func is_solved() -> bool:
	return _solved


## Get a dictionary of all occupied cells → piece_id (for rendering overlap checks).
func get_occupied_cells() -> Dictionary:
	var result := {}
	for piece in pieces:
		if not piece.is_placed():
			continue
		for cell in piece.get_grid_cells():
			if result.has(cell):
				result[cell] = -1 # overlap marker
			else:
				result[cell] = piece.piece_id
	return result


func _get_piece(piece_id: int) -> ShadowPieceData:
	for p in pieces:
		if p.piece_id == piece_id:
			return p
	return null


func _cell_occupied_by_other(cell: Vector2i, exclude_id: int) -> bool:
	for piece in pieces:
		if piece.piece_id == exclude_id or not piece.is_placed():
			continue
		for c in piece.cells:
			if piece.grid_pos + c == cell:
				return true
	return false
