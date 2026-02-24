extends Node
## Manages the logical state for the Night 4 Constellation (Loopy) puzzle.
## Supports both native GDExtension generation and loading from JSON files.
## Handles player moves and completion checking in GDScript.

const GridData := preload("res://scripts/loopy_puzzle/grid_data.gd")
const LC := preload("res://scripts/loopy_puzzle/loopy_consts.gd")

signal puzzle_solved
signal grid_changed

var grid: GridData = null
var clues: Array = [] # per face: -1 (no clue) or 0..N
var lines: Array = [] # per edge: LINE_YES / LINE_UNKNOWN / LINE_NO
var line_errors: Array = [] # per edge: true if violation
var solution: Array = [] # per edge: LINE_YES or LINE_NO (from generation/JSON)
var solved := false


func _ready() -> void:
	randomize()


# ===========================================================================
# Public API
# ===========================================================================

func generate_puzzle(w: int = 7, h: int = 5, diff: int = LC.DIFF_EASY) -> Dictionary:
	## Generate a puzzle using the native C extension. Returns the raw Dictionary
	## for serialization by the dev generator.
	var native := LoopyNative.new()
	var data: Dictionary = native.generate_puzzle(w, h, diff)
	load_from_dict(data)
	return data


func load_from_dict(data: Dictionary) -> void:
	## Unpack a puzzle Dictionary (from native or JSON) into GridData + player state.
	solved = false

	grid = GridData.new()
	grid.num_dots = data["num_dots"]
	grid.num_edges = data["num_edges"]
	grid.num_faces = data["num_faces"]

	# Dots: reconstruct Vector2 array from flat x/y arrays
	var dx: PackedFloat32Array = data["dots_x"]
	var dy: PackedFloat32Array = data["dots_y"]
	grid.dots.resize(grid.num_dots)
	for i in range(grid.num_dots):
		grid.dots[i] = Vector2(dx[i], dy[i])

	# Dot order
	var d_order: PackedInt32Array = data["dot_order"]
	grid.dot_order.resize(grid.num_dots)
	for i in range(grid.num_dots):
		grid.dot_order[i] = d_order[i]

	# Dot edges: unflatten using offsets
	var de_flat: PackedInt32Array = data["dot_edges_flat"]
	var de_off: PackedInt32Array = data["dot_edges_offsets"]
	grid.dot_edges.resize(grid.num_dots)
	for i in range(grid.num_dots):
		var arr: Array = []
		for j in range(de_off[i], de_off[i + 1]):
			arr.append(de_flat[j])
		grid.dot_edges[i] = arr

	# Dot faces: unflatten using offsets
	var df_flat: PackedInt32Array = data["dot_faces_flat"]
	var df_off: PackedInt32Array = data["dot_faces_offsets"]
	grid.dot_faces.resize(grid.num_dots)
	for i in range(grid.num_dots):
		var arr: Array = []
		for j in range(df_off[i], df_off[i + 1]):
			arr.append(df_flat[j])
		grid.dot_faces[i] = arr

	# Edges: reconstruct Vector2i arrays
	var ed1: PackedInt32Array = data["edge_d1"]
	var ed2: PackedInt32Array = data["edge_d2"]
	var ef1: PackedInt32Array = data["edge_f1"]
	var ef2: PackedInt32Array = data["edge_f2"]
	grid.edges.resize(grid.num_edges)
	grid.edge_faces.resize(grid.num_edges)
	for i in range(grid.num_edges):
		grid.edges[i] = Vector2i(ed1[i], ed2[i])
		grid.edge_faces[i] = Vector2i(ef1[i], ef2[i])

	# Face order
	var f_order: PackedInt32Array = data["face_order"]
	grid.face_order.resize(grid.num_faces)
	for i in range(grid.num_faces):
		grid.face_order[i] = f_order[i]

	# Face dots: unflatten
	var fd_flat: PackedInt32Array = data["face_dots_flat"]
	var fd_off: PackedInt32Array = data["face_dots_offsets"]
	grid.face_dots.resize(grid.num_faces)
	for i in range(grid.num_faces):
		var arr: Array = []
		for j in range(fd_off[i], fd_off[i + 1]):
			arr.append(fd_flat[j])
		grid.face_dots[i] = arr

	# Face edges: unflatten
	var fe_flat: PackedInt32Array = data["face_edges_flat"]
	var fe_off: PackedInt32Array = data["face_edges_offsets"]
	grid.face_edges.resize(grid.num_faces)
	for i in range(grid.num_faces):
		var arr: Array = []
		for j in range(fe_off[i], fe_off[i + 1]):
			arr.append(fe_flat[j])
		grid.face_edges[i] = arr

	# Face incentres (pre-scaled to viewport)
	if data.has("face_ix"):
		var fix: PackedFloat32Array = data["face_ix"]
		var fiy: PackedFloat32Array = data["face_iy"]
		grid.face_incentres.resize(grid.num_faces)
		for i in range(grid.num_faces):
			grid.face_incentres[i] = Vector2(fix[i], fiy[i])

	# Clues
	var c_arr: PackedInt32Array = data["clues"]
	clues.resize(grid.num_faces)
	for i in range(grid.num_faces):
		clues[i] = c_arr[i]

	# Solution (if available)
	if data.has("solution"):
		var sol_arr: PackedInt32Array = data["solution"]
		solution.resize(grid.num_edges)
		for i in range(grid.num_edges):
			solution[i] = sol_arr[i]
	else:
		solution.clear()

	# Initialise player state
	lines.resize(grid.num_edges)
	lines.fill(LC.LINE_UNKNOWN)
	line_errors.resize(grid.num_edges)
	line_errors.fill(false)

	grid_changed.emit()


func load_from_json(path: String) -> bool:
	## Load a puzzle from a JSON file. Returns true on success.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open puzzle: %s" % path)
		return false
	var json_text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var err := json.parse(json_text)
	if err != OK:
		push_error("JSON parse error in %s: %s" % [path, json.get_error_message()])
		return false
	var data: Dictionary = json.data
	_convert_json_arrays(data)
	load_from_dict(data)
	return true


func toggle_edge(edge_idx: int, use_yes: bool) -> void:
	## Toggle an edge. use_yes=true: UNKNOWN<->YES. use_yes=false: UNKNOWN<->NO.
	if solved or edge_idx < 0 or edge_idx >= grid.num_edges:
		return

	if use_yes:
		if lines[edge_idx] == LC.LINE_YES:
			lines[edge_idx] = LC.LINE_UNKNOWN
		elif lines[edge_idx] == LC.LINE_UNKNOWN:
			lines[edge_idx] = LC.LINE_YES
	else:
		if lines[edge_idx] == LC.LINE_NO:
			lines[edge_idx] = LC.LINE_UNKNOWN
		elif lines[edge_idx] == LC.LINE_UNKNOWN:
			lines[edge_idx] = LC.LINE_NO

	check_completion()
	grid_changed.emit()
	if solved:
		puzzle_solved.emit()


# ===========================================================================
# JSON array conversion
# ===========================================================================

func _convert_json_arrays(data: Dictionary) -> void:
	## Convert generic Arrays from JSON.parse to PackedFloat32Array / PackedInt32Array
	## to match the types expected by load_from_dict().
	for key in ["dots_x", "dots_y", "face_ix", "face_iy"]:
		if data.has(key) and data[key] is Array:
			var pf := PackedFloat32Array()
			var src: Array = data[key]
			pf.resize(src.size())
			for i in range(src.size()):
				pf[i] = float(src[i])
			data[key] = pf
	for key in ["dot_order", "dot_edges_flat", "dot_edges_offsets",
				"dot_faces_flat", "dot_faces_offsets",
				"edge_d1", "edge_d2", "edge_f1", "edge_f2",
				"face_order", "face_dots_flat", "face_dots_offsets",
				"face_edges_flat", "face_edges_offsets",
				"clues", "solution"]:
		if data.has(key) and data[key] is Array:
			var pi := PackedInt32Array()
			var src: Array = data[key]
			pi.resize(src.size())
			for i in range(src.size()):
				pi[i] = int(src[i])
			data[key] = pi


# ===========================================================================
# Completion check (port of check_completion from loopy.c)
# ===========================================================================

func check_completion() -> void:
	## Check if the current line state is a valid solution.
	## Marks errors on violating edges.
	for i in range(grid.num_edges):
		line_errors[i] = false

	var nf := grid.num_faces
	var inf_face := nf # index for the infinite exterior face

	# DSF: merge faces connected by non-YES edges
	var dsf := PackedInt32Array()
	dsf.resize(nf + 1)
	for i in range(nf + 1):
		dsf[i] = (1 << 2) | 2 # root, size 1

	for ei in range(grid.num_edges):
		if lines[ei] != LC.LINE_YES:
			var f1: int = grid.edge_faces[ei].x
			var f2: int = grid.edge_faces[ei].y
			if f1 < 0: f1 = inf_face
			if f2 < 0: f2 = inf_face
			_dsf_merge(dsf, f1, f2)

	# Check YES edges: each should separate two non-equivalent face groups
	var infinite_area := _dsf_canonify(dsf, inf_face)
	var finite_area := -1
	var loops_found := 0
	var found_edge_not_in_loop := false

	for ei in range(grid.num_edges):
		if lines[ei] != LC.LINE_YES:
			continue
		var f1: int = grid.edge_faces[ei].x
		var f2: int = grid.edge_faces[ei].y
		if f1 < 0: f1 = inf_face
		if f2 < 0: f2 = inf_face
		var can1 := _dsf_canonify(dsf, f1)
		var can2 := _dsf_canonify(dsf, f2)

		if can1 == can2:
			found_edge_not_in_loop = true
			continue

		line_errors[ei] = true
		if loops_found == 0:
			loops_found = 1
		if loops_found == 2:
			continue
		if finite_area == -1:
			finite_area = can2 if can1 == infinite_area else can1
		if finite_area != -1:
			if can1 != infinite_area and can1 != finite_area:
				loops_found = 2
			elif can2 != infinite_area and can2 != finite_area:
				loops_found = 2

	# Check for valid single loop
	if loops_found == 1 and not found_edge_not_in_loop:
		var clue_violation := false
		for fi in range(nf):
			var c: int = clues[fi]
			if c >= 0:
				var yes_count := 0
				for ei: int in grid.face_edges[fi]:
					if lines[ei] == LC.LINE_YES:
						yes_count += 1
				if yes_count != c:
					clue_violation = true
					break
		if not clue_violation:
			# Valid solution!
			for i in range(grid.num_edges):
				line_errors[i] = false
			solved = true
			return

	# Mark dot violations (dead-ends and branches)
	for di in range(grid.num_dots):
		var yes := 0
		var unknown := 0
		for ei: int in grid.dot_edges[di]:
			if lines[ei] == LC.LINE_YES:
				yes += 1
			elif lines[ei] == LC.LINE_UNKNOWN:
				unknown += 1
		if (yes == 1 and unknown == 0) or yes >= 3:
			for ei: int in grid.dot_edges[di]:
				if lines[ei] == LC.LINE_YES:
					line_errors[ei] = true


# ---------- DSF helpers ----------

func _dsf_canonify(dsf: PackedInt32Array, idx: int) -> int:
	var i := idx
	while (dsf[i] & 2) == 0:
		i = dsf[i] >> 2
	var root := i
	i = idx
	while i != root:
		var next_i := dsf[i] >> 2
		dsf[i] = (root << 2)
		i = next_i
	return root


func _dsf_merge(dsf: PackedInt32Array, a: int, b: int) -> void:
	var ra := _dsf_canonify(dsf, a)
	var rb := _dsf_canonify(dsf, b)
	if ra == rb:
		return
	if ra > rb:
		var tmp := ra
		ra = rb
		rb = tmp
	dsf[ra] = ((dsf[ra] >> 2) + (dsf[rb] >> 2)) << 2 | 2
	dsf[rb] = (ra << 2)
