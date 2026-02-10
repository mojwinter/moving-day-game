@warning_ignore("integer_division")
extends Node
## Manages the logical grid state for the Train Tracks puzzle.
## Handles generation, solver, DSF connectivity, completion check, and player moves.
## Port of core algorithms from Simon Tatham's tracks.c.

const SquareDataScript := preload("res://scripts/tracks_puzzle/square_data.gd")
const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")

signal puzzle_solved
signal grid_changed

const GRID_W := 5
const GRID_H := 4
const DIFF_EASY := 0

var squares: Array = []          # Array of SquareData, size W*H
var clue_numbers: Array = []     # size W+H: columns first, then rows
var num_errors: Array = []       # size W+H: 1 if clue violated
var row_station: int = -1        # entrance row (left edge)
var col_station: int = -1        # exit column (bottom edge)
var completed: bool = false
var impossible: bool = false

# DSF arrays (reused across solver calls)
var _dsf: Array = []
var _dsf_rank: Array = []


func _ready() -> void:
	randomize()


# ===========================================================================
# Public API
# ===========================================================================

func generate_puzzle() -> void:
	completed = false
	var max_attempts := 2000
	for _attempt in range(max_attempts):
		_init_blank()
		if not _lay_path():
			continue
		_mark_track_squares()
		_compute_clue_numbers()
		if not _validate_clue_numbers():
			continue
		var ret := _add_clues(DIFF_EASY)
		if ret != 1:
			continue
		# Strip solution from non-clue squares for the player
		_strip_for_player()
		check_completion(true)
		grid_changed.emit()
		return
	# Fallback: should rarely get here with 5x4
	push_warning("TracksPuzzle: failed to generate after %d attempts" % max_attempts)
	grid_changed.emit()


func apply_square_toggle(x: int, y: int, notrack: bool) -> void:
	if completed:
		return
	if not _can_flip_square(x, y, notrack):
		return
	var idx := y * GRID_W + x
	var f := TC.S_NOTRACK if notrack else TC.S_TRACK
	squares[idx].toggle_flag(f)
	check_completion(true)
	grid_changed.emit()
	if completed:
		puzzle_solved.emit()


func apply_edge_toggle(x: int, y: int, dir: int, notrack: bool) -> void:
	if completed:
		return
	if not _can_flip_edge(x, y, dir, notrack):
		return
	var ef := TC.E_NOTRACK if notrack else TC.E_TRACK
	var idx := y * GRID_W + x
	var current: int = squares[idx].e_flags(dir)
	if current & ef:
		_e_clear(x, y, dir, ef)
	else:
		_e_set(x, y, dir, ef)
	check_completion(true)
	grid_changed.emit()
	if completed:
		puzzle_solved.emit()


# ===========================================================================
# Grid initialization
# ===========================================================================

func _init_blank() -> void:
	squares.clear()
	for _i in range(GRID_W * GRID_H):
		squares.append(SquareDataScript.new())
	clue_numbers = []
	clue_numbers.resize(GRID_W + GRID_H)
	clue_numbers.fill(0)
	num_errors = []
	num_errors.resize(GRID_W + GRID_H)
	num_errors.fill(0)
	row_station = -1
	col_station = -1
	completed = false
	impossible = false


# ===========================================================================
# Path generation (port of lay_path, tracks.c:425-451)
# ===========================================================================

func _lay_path() -> bool:
	row_station = randi() % GRID_H
	var px := 0
	var py := row_station
	_e_set(px, py, TC.DIR_L, TC.E_TRACK)

	while _in_grid(px, py):
		var d := _find_direction(px, py)
		if d == 0:
			return false
		_e_set(px, py, d, TC.E_TRACK)
		px += TC.dx(d)
		py += TC.dy(d)

	# Must exit from the bottom edge
	if py != GRID_H or px < 0 or px >= GRID_W:
		return false
	col_station = px
	return true


func _find_direction(x: int, y: int) -> int:
	var dirs := TC.DIRECTIONS.duplicate()
	dirs.shuffle()
	for d in dirs:
		var nx := x + TC.dx(d)
		var ny := y + TC.dy(d)
		if nx >= 0 and nx < GRID_W and ny == GRID_H:
			return d  # exit off the bottom
		if not _in_grid(nx, ny):
			continue
		if squares[ny * GRID_W + nx].e_count(TC.E_TRACK) > 0:
			continue  # already has tracks
		return d
	return 0


# ===========================================================================
# Clue number computation
# ===========================================================================

func _mark_track_squares() -> void:
	for x in range(GRID_W):
		for y in range(GRID_H):
			var idx := y * GRID_W + x
			if squares[idx].e_count(TC.E_TRACK) > 0:
				squares[idx].set_flag(TC.S_TRACK)
			# Mark entrance and exit as clue squares
			if x == 0 and y == row_station:
				squares[idx].set_flag(TC.S_CLUE)
			if y == GRID_H - 1 and x == col_station:
				squares[idx].set_flag(TC.S_CLUE)


func _compute_clue_numbers() -> void:
	clue_numbers.fill(0)
	for x in range(GRID_W):
		for y in range(GRID_H):
			if squares[y * GRID_W + x].has_flag(TC.S_TRACK):
				clue_numbers[x] += 1
				clue_numbers[GRID_W + y] += 1


func _validate_clue_numbers() -> bool:
	# Reject if any clue is 0
	for i in range(GRID_W + GRID_H):
		if clue_numbers[i] == 0:
			return false
	# Reject consecutive 1-clues
	var last_was_one := true  # disallow 1 at entry point
	for i in range(GRID_W + GRID_H):
		var is_one: bool = (clue_numbers[i] == 1)
		if is_one and last_was_one:
			return false
		last_was_one = is_one
	if clue_numbers[GRID_W + GRID_H - 1] == 1:
		return false  # disallow 1 at exit point
	return true


# ===========================================================================
# Clue placement (port of add_clues, tracks.c:570-689)
# ===========================================================================

func _add_clues(diff: int) -> int:
	var positions := []
	for i in range(GRID_W * GRID_H):
		if squares[i].e_dirs(TC.E_TRACK) != 0:
			positions.append(i)

	# Check if already solvable without extra clues
	var scratch := _copy_sflags()
	var stripped := _strip_copy(scratch, -1)
	var sr := _solve_on(stripped, diff)
	if sr < 0:
		return -1  # impossible
	if sr > 0:
		return 1   # already soluble

	var progress := _solve_progress(stripped)
	var nedges_prev := []
	nedges_prev.resize(GRID_W * GRID_H)
	nedges_prev.fill(0)

	# Add clues until solvable
	positions.shuffle()
	for pi in range(positions.size()):
		var i: int = positions[pi]
		if squares[i].has_flag(TC.S_CLUE):
			continue
		if nedges_prev[i] == 2:
			continue

		stripped = _strip_copy(_copy_sflags(), i)
		if _check_phantom_moves(stripped):
			continue

		if diff > 0:
			if _solve_on(stripped, diff - 1) > 0:
				continue  # too easy

		stripped = _strip_copy(_copy_sflags(), i)
		if _solve_on(stripped, diff) > 0:
			squares[i].set_flag(TC.S_CLUE)
			# Go to strip phase
			return _strip_clues(positions, diff)

		var new_progress := _solve_progress(stripped)
		if new_progress > progress:
			progress = new_progress
			squares[i].set_flag(TC.S_CLUE)
			# Update edge counts from this solve
			for j in range(GRID_W * GRID_H):
				var sx := j % GRID_W
				var sy := j / GRID_W
				nedges_prev[j] = TC.NBITS[(stripped[j] >> TC.S_TRACK_SHIFT) & TC.ALLDIR]

	return -1  # couldn't make soluble


func _strip_clues(positions: Array, diff: int) -> int:
	positions.shuffle()
	for pi in range(positions.size()):
		var i: int = positions[pi]
		if not squares[i].has_flag(TC.S_CLUE):
			continue
		# Don't strip entrance/exit clues
		if i % GRID_W == 0 and i / GRID_W == row_station:
			continue
		if i / GRID_W == GRID_H - 1 and i % GRID_W == col_station:
			continue

		var stripped := _strip_copy(_copy_sflags(), i)  # remove this clue
		if _check_phantom_moves(stripped):
			continue
		if _solve_on(stripped, diff) > 0:
			squares[i].clear_flag(TC.S_CLUE)
	return 1


func _copy_sflags() -> Array:
	var result := []
	result.resize(GRID_W * GRID_H)
	for i in range(GRID_W * GRID_H):
		result[i] = squares[i].sflags
	return result


func _strip_copy(source: Array, flip_clue_i: int) -> Array:
	var result := source.duplicate()
	if flip_clue_i != -1:
		result[flip_clue_i] ^= TC.S_CLUE

	for i in range(GRID_W * GRID_H):
		if not (result[i] & TC.S_CLUE):
			result[i] &= ~(TC.S_TRACK | TC.S_NOTRACK | TC.S_ERROR | TC.S_MARK)
			for j in range(4):
				var f := 1 << j
				var xx := i % GRID_W + TC.dx(f)
				var yy := i / GRID_W + TC.dy(f)
				if not (xx >= 0 and xx < GRID_W and yy >= 0 and yy < GRID_H) or not (result[yy * GRID_W + xx] & TC.S_CLUE):
					result[i] &= ~(f << TC.S_TRACK_SHIFT)
					result[i] &= ~(f << TC.S_NOTRACK_SHIFT)
					# Also clear on neighbor side
					if xx >= 0 and xx < GRID_W and yy >= 0 and yy < GRID_H:
						var opp := TC.opposite(f)
						result[yy * GRID_W + xx] &= ~(opp << TC.S_TRACK_SHIFT)
						result[yy * GRID_W + xx] &= ~(opp << TC.S_NOTRACK_SHIFT)
	return result


func _check_phantom_moves(sflags_arr: Array) -> bool:
	for x in range(GRID_W):
		for y in range(GRID_H):
			var i := y * GRID_W + x
			if sflags_arr[i] & TC.S_CLUE:
				continue
			var track_dirs: int = (sflags_arr[i] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
			if TC.NBITS[track_dirs] > 1:
				return true
	return false


func _solve_progress(sflags_arr: Array) -> int:
	var progress := 0
	for i in range(GRID_W * GRID_H):
		if sflags_arr[i] & TC.S_TRACK:
			progress += 1
		if sflags_arr[i] & TC.S_NOTRACK:
			progress += 1
		progress += TC.NBITS[(sflags_arr[i] >> TC.S_TRACK_SHIFT) & TC.ALLDIR]
		progress += TC.NBITS[(sflags_arr[i] >> TC.S_NOTRACK_SHIFT) & TC.ALLDIR]
	return progress


func _strip_for_player() -> void:
	for i in range(GRID_W * GRID_H):
		if not squares[i].has_flag(TC.S_CLUE):
			squares[i].sflags &= ~(TC.S_TRACK | TC.S_NOTRACK | TC.S_ERROR | TC.S_MARK)
			for j in range(4):
				var f := 1 << j
				var xx := i % GRID_W + TC.dx(f)
				var yy := i / GRID_W + TC.dy(f)
				if not _in_grid(xx, yy) or not squares[yy * GRID_W + xx].has_flag(TC.S_CLUE):
					squares[i].e_clear(f, TC.E_TRACK)
					squares[i].e_clear(f, TC.E_NOTRACK)


# ===========================================================================
# Solver operating on sflags array (port of tracks_solve, tracks.c:1287-1320)
# ===========================================================================

func _solve_on(sf: Array, diff: int) -> int:
	# Set outer border edges as no-track
	for x in range(GRID_W):
		_sf_discount_edge(sf, x, 0, TC.DIR_U)
		_sf_discount_edge(sf, x, GRID_H - 1, TC.DIR_D)
	for y in range(GRID_H):
		_sf_discount_edge(sf, 0, y, TC.DIR_L)
		_sf_discount_edge(sf, GRID_W - 1, y, TC.DIR_R)

	var imp := false
	while true:
		var did := 0
		var result := _sf_update_flags(sf)
		did += result[0]
		imp = imp or result[1]
		result = _sf_count_clues(sf)
		did += result[0]
		imp = imp or result[1]
		did += _sf_check_loop(sf)
		if did == 0 or imp:
			break

	if imp:
		return -1
	return 1 if _sf_check_completion(sf) else 0


func _sf_discount_edge(sf: Array, x: int, y: int, d: int) -> void:
	var track_dirs: int = (sf[y * GRID_W + x] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
	if track_dirs & d:
		return  # clue square has this outer edge set as track
	_sf_e_set(sf, x, y, d, TC.E_NOTRACK)


func _sf_e_set(sf: Array, x: int, y: int, d: int, eflag: int) -> void:
	var shift := TC.S_TRACK_SHIFT if eflag == TC.E_TRACK else TC.S_NOTRACK_SHIFT
	sf[y * GRID_W + x] |= (d << shift)
	var ax := x + TC.dx(d)
	var ay := y + TC.dy(d)
	if ax >= 0 and ax < GRID_W and ay >= 0 and ay < GRID_H:
		sf[ay * GRID_W + ax] |= (TC.opposite(d) << shift)


func _sf_e_clear(sf: Array, x: int, y: int, d: int, eflag: int) -> void:
	var shift := TC.S_TRACK_SHIFT if eflag == TC.E_TRACK else TC.S_NOTRACK_SHIFT
	sf[y * GRID_W + x] &= ~(d << shift)
	var ax := x + TC.dx(d)
	var ay := y + TC.dy(d)
	if ax >= 0 and ax < GRID_W and ay >= 0 and ay < GRID_H:
		sf[ay * GRID_W + ax] &= ~(TC.opposite(d) << shift)


func _sf_set_sflag(sf: Array, x: int, y: int, f: int) -> int:
	var idx := y * GRID_W + x
	if sf[idx] & f:
		return 0
	sf[idx] |= f
	return 1


func _sf_set_eflag(sf: Array, x: int, y: int, d: int, eflag: int) -> Array:
	# Returns [did, impossible]
	var shift := TC.S_TRACK_SHIFT if eflag == TC.E_TRACK else TC.S_NOTRACK_SHIFT
	if sf[y * GRID_W + x] & (d << shift):
		return [0, false]
	# Check for contradiction
	var opp_shift := TC.S_NOTRACK_SHIFT if eflag == TC.E_TRACK else TC.S_TRACK_SHIFT
	var imp := false
	if sf[y * GRID_W + x] & (d << opp_shift):
		imp = true
	_sf_e_set(sf, x, y, d, eflag)
	return [1, imp]


# Port of solve_update_flags (tracks.c:918-972)
func _sf_update_flags(sf: Array) -> Array:
	var did := 0
	var imp := false
	for x in range(GRID_W):
		for y in range(GRID_H):
			var idx := y * GRID_W + x
			var track_dirs: int = (sf[idx] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
			var notrack_dirs: int = (sf[idx] >> TC.S_NOTRACK_SHIFT) & TC.ALLDIR
			var ntrack: int = TC.NBITS[track_dirs]
			var nnotrack: int = TC.NBITS[notrack_dirs]

			# If NOTRACK square, all edges must be NOTRACK
			if sf[idx] & TC.S_NOTRACK:
				for i in range(4):
					var d := 1 << i
					var r := _sf_set_eflag(sf, x, y, d, TC.E_NOTRACK)
					did += r[0]; imp = imp or r[1]

			# If 3+ edges are NOTRACK, square is NOTRACK
			if nnotrack >= 3:
				if not (sf[idx] & TC.S_NOTRACK):
					if sf[idx] & TC.S_TRACK:
						imp = true
					sf[idx] |= TC.S_NOTRACK
					did += 1

			# If any edge is TRACK, square is TRACK
			if ntrack > 0:
				if not (sf[idx] & TC.S_TRACK):
					if sf[idx] & TC.S_NOTRACK:
						imp = true
					sf[idx] |= TC.S_TRACK
					did += 1

			# If TRACK square with 2 NOTRACK edges, other 2 must be TRACK
			if (sf[idx] & TC.S_TRACK) and nnotrack == 2 and ntrack < 2:
				for i in range(4):
					var d := 1 << i
					if not ((track_dirs | notrack_dirs) & d):
						var r := _sf_set_eflag(sf, x, y, d, TC.E_TRACK)
						did += r[0]; imp = imp or r[1]

			# If TRACK square with 2 TRACK edges, other 2 must be NOTRACK
			if (sf[idx] & TC.S_TRACK) and ntrack == 2 and nnotrack < 2:
				for i in range(4):
					var d := 1 << i
					if not ((track_dirs | notrack_dirs) & d):
						var r := _sf_set_eflag(sf, x, y, d, TC.E_NOTRACK)
						did += r[0]; imp = imp or r[1]

	return [did, imp]


# Port of solve_count_clues (tracks.c:1020-1033)
func _sf_count_clues(sf: Array) -> Array:
	var did := 0
	var imp := false
	for x in range(GRID_W):
		var target: int = clue_numbers[x]
		var r := _sf_count_clues_sub(sf, x, GRID_W, GRID_H, target)
		did += r[0]; imp = imp or r[1]
	for y in range(GRID_H):
		var target: int = clue_numbers[GRID_W + y]
		var r := _sf_count_clues_sub(sf, y * GRID_W, 1, GRID_W, target)
		did += r[0]; imp = imp or r[1]
	return [did, imp]


func _sf_count_clues_sub(sf: Array, si: int, id: int, n: int, target: int) -> Array:
	var ctrack := 0
	var cnotrack := 0
	var did := 0
	var imp := false
	var i := si
	for _j in range(n):
		if sf[i] & TC.S_TRACK:
			ctrack += 1
		if sf[i] & TC.S_NOTRACK:
			cnotrack += 1
		i += id

	if ctrack == target:
		# Everything that's not S_TRACK must be S_NOTRACK
		i = si
		for _j in range(n):
			if not (sf[i] & TC.S_TRACK):
				did += _sf_set_sflag(sf, i % GRID_W, i / GRID_W, TC.S_NOTRACK)
			i += id

	if cnotrack == (n - target):
		# Everything that's not S_NOTRACK must be S_TRACK
		i = si
		for _j in range(n):
			if not (sf[i] & TC.S_NOTRACK):
				did += _sf_set_sflag(sf, i % GRID_W, i / GRID_W, TC.S_TRACK)
			i += id

	return [did, imp]


# Port of solve_check_loop (tracks.c:1226-1276)
func _sf_check_loop(sf: Array) -> int:
	var size := GRID_W * GRID_H
	_dsf_init(size)
	var did := 0

	# Build connectivity from current E_TRACK edges
	for x in range(GRID_W):
		for y in range(GRID_H):
			var idx := y * GRID_W + x
			var track_dirs: int = (sf[idx] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
			if (track_dirs & TC.DIR_R) and x < GRID_W - 1:
				_dsf_merge(idx, y * GRID_W + (x + 1))
			if (track_dirs & TC.DIR_D) and y < GRID_H - 1:
				_dsf_merge(idx, (y + 1) * GRID_W + x)

	var startc := _dsf_find(row_station * GRID_W)
	var endc := _dsf_find((GRID_H - 1) * GRID_W + col_station)

	# Check each potential edge between adjacent TRACK squares
	for x in range(GRID_W):
		for y in range(GRID_H):
			var idx := y * GRID_W + x
			if not (sf[idx] & TC.S_TRACK):
				continue
			for dir_info in [[TC.DIR_R, 1, 0], [TC.DIR_D, 0, 1]]:
				var d: int = dir_info[0]
				var ddx: int = dir_info[1]
				var ddy: int = dir_info[2]
				var nx := x + ddx
				var ny := y + ddy
				if nx >= GRID_W or ny >= GRID_H:
					continue
				var nidx := ny * GRID_W + nx
				if not (sf[nidx] & TC.S_TRACK):
					continue
				var track_dirs: int = (sf[idx] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
				var notrack_dirs: int = (sf[idx] >> TC.S_NOTRACK_SHIFT) & TC.ALLDIR
				if (track_dirs & d) or (notrack_dirs & d):
					continue  # already decided

				var ic := _dsf_find(idx)
				var jc := _dsf_find(nidx)
				if ic == jc:
					# Would create a loop
					_sf_e_set(sf, x, y, d, TC.E_NOTRACK)
					did += 1
					continue

				if (ic == startc and jc == endc) or (ic == endc and jc == startc):
					# Would join start to end; check if that's premature
					var has_detached := false
					for k in range(size):
						if (sf[k] & TC.S_TRACK) and _dsf_find(k) != startc and _dsf_find(k) != endc:
							has_detached = true
							break
					if has_detached:
						_sf_e_set(sf, x, y, d, TC.E_NOTRACK)
						did += 1
						continue

					# Check if clues are satisfied
					var satisfied := true
					for cx in range(GRID_W):
						var cnt := 0
						for cy in range(GRID_H):
							if sf[cy * GRID_W + cx] & TC.S_TRACK:
								cnt += 1
						if cnt < clue_numbers[cx]:
							satisfied = false
							break
					if satisfied:
						for ry in range(GRID_H):
							var cnt := 0
							for rx in range(GRID_W):
								if sf[ry * GRID_W + rx] & TC.S_TRACK:
									cnt += 1
							if cnt < clue_numbers[GRID_W + ry]:
								satisfied = false
								break
					if not satisfied:
						_sf_e_set(sf, x, y, d, TC.E_NOTRACK)
						did += 1

	return did


func _sf_check_completion(sf: Array) -> bool:
	# Check column clues
	for x in range(GRID_W):
		var target: int = clue_numbers[x]
		var ntrack := 0
		for y in range(GRID_H):
			var track_dirs: int = (sf[y * GRID_W + x] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
			if TC.NBITS[track_dirs] > 0:
				ntrack += 1
		if ntrack != target:
			return false

	# Check row clues
	for y in range(GRID_H):
		var target: int = clue_numbers[GRID_W + y]
		var ntrack := 0
		for x in range(GRID_W):
			var track_dirs: int = (sf[y * GRID_W + x] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
			if TC.NBITS[track_dirs] == 2:
				ntrack += 1
		if ntrack != target:
			return false

	# Check for loops and connectivity via DSF
	var size := GRID_W * GRID_H
	_dsf_init(size)
	var loopclass := -1

	for x in range(GRID_W):
		for y in range(GRID_H):
			var idx := y * GRID_W + x
			var track_dirs: int = (sf[idx] >> TC.S_TRACK_SHIFT) & TC.ALLDIR
			if (track_dirs & TC.DIR_R) and x < GRID_W - 1:
				var j := y * GRID_W + (x + 1)
				var ic := _dsf_find(idx)
				var jc := _dsf_find(j)
				if ic == jc:
					loopclass = ic
				else:
					_dsf_merge(idx, j)
			if (track_dirs & TC.DIR_D) and y < GRID_H - 1:
				var j := (y + 1) * GRID_W + x
				var ic := _dsf_find(idx)
				var jc := _dsf_find(j)
				if ic == jc:
					loopclass = ic
				else:
					_dsf_merge(idx, j)

	if loopclass != -1:
		return false

	return true


# ===========================================================================
# Completion check on live game state (port of check_completion, tracks.c:1517-1618)
# ===========================================================================

func check_completion(mark: bool) -> bool:
	var ret := true

	if mark:
		num_errors.fill(0)
		for i in range(GRID_W * GRID_H):
			squares[i].clear_flag(TC.S_ERROR)
			if squares[i].e_count(TC.E_TRACK) > 2:
				squares[i].set_flag(TC.S_ERROR)

	# Check column clues
	for x in range(GRID_W):
		var target: int = clue_numbers[x]
		var ntrack := 0
		var nnotrack := 0
		for y in range(GRID_H):
			if squares[y * GRID_W + x].e_count(TC.E_TRACK) > 0:
				ntrack += 1
			if squares[y * GRID_W + x].has_flag(TC.S_NOTRACK):
				nnotrack += 1
		if mark:
			if ntrack > target or nnotrack > (GRID_H - target):
				num_errors[x] = 1
		if ntrack != target:
			ret = false

	# Check row clues
	for y in range(GRID_H):
		var target: int = clue_numbers[GRID_W + y]
		var ntrack := 0
		var nnotrack := 0
		for x in range(GRID_W):
			if squares[y * GRID_W + x].e_count(TC.E_TRACK) == 2:
				ntrack += 1
			if squares[y * GRID_W + x].has_flag(TC.S_NOTRACK):
				nnotrack += 1
		if mark:
			if ntrack > target or nnotrack > (GRID_W - target):
				num_errors[GRID_W + y] = 1
		if ntrack != target:
			ret = false

	# DSF for loop/path detection
	var size := GRID_W * GRID_H
	_dsf_init(size)
	var loopclass := -1

	for x in range(GRID_W):
		for y in range(GRID_H):
			var idx := y * GRID_W + x
			if (squares[idx].e_dirs(TC.E_TRACK) & TC.DIR_R) and x < GRID_W - 1:
				var j := y * GRID_W + (x + 1)
				var ic := _dsf_find(idx)
				var jc := _dsf_find(j)
				if ic == jc:
					loopclass = ic
				else:
					_dsf_merge(idx, j)
			if (squares[idx].e_dirs(TC.E_TRACK) & TC.DIR_D) and y < GRID_H - 1:
				var j := (y + 1) * GRID_W + x
				var ic := _dsf_find(idx)
				var jc := _dsf_find(j)
				if ic == jc:
					loopclass = ic
				else:
					_dsf_merge(idx, j)

	if loopclass != -1:
		ret = false
		if mark:
			for x in range(GRID_W):
				for y in range(GRID_H):
					if _dsf_find(y * GRID_W + x) == loopclass:
						squares[y * GRID_W + x].set_flag(TC.S_ERROR)

	if mark:
		var pathclass := _dsf_find(row_station * GRID_W)
		if pathclass == _dsf_find((GRID_H - 1) * GRID_W + col_station):
			for i in range(size):
				if _dsf_find(i) != pathclass:
					if squares[i].has_flag(TC.S_TRACK) or squares[i].e_count(TC.E_TRACK) > 0:
						squares[i].set_flag(TC.S_ERROR)

	if mark:
		completed = ret
	return ret


# ===========================================================================
# Edge propagation helpers (operate on live squares array)
# ===========================================================================

func _e_set(x: int, y: int, d: int, eflag: int) -> void:
	squares[y * GRID_W + x].e_set(d, eflag)
	var ax := x + TC.dx(d)
	var ay := y + TC.dy(d)
	if _in_grid(ax, ay):
		squares[ay * GRID_W + ax].e_set(TC.opposite(d), eflag)


func _e_clear(x: int, y: int, d: int, eflag: int) -> void:
	squares[y * GRID_W + x].e_clear(d, eflag)
	var ax := x + TC.dx(d)
	var ay := y + TC.dy(d)
	if _in_grid(ax, ay):
		squares[ay * GRID_W + ax].e_clear(TC.opposite(d), eflag)


# ===========================================================================
# Input validation (port of ui_can_flip_edge/square, tracks.c:1716-1778)
# ===========================================================================

func _can_flip_edge(x: int, y: int, dir: int, notrack: bool) -> bool:
	var x2 := x + TC.dx(dir)
	var y2 := y + TC.dy(dir)
	if not _in_grid(x, y) or not _in_grid(x2, y2):
		return false

	var sf1: int = squares[y * GRID_W + x].sflags
	var sf2: int = squares[y2 * GRID_W + x2].sflags
	var ef: int = squares[y * GRID_W + x].e_flags(dir)

	if not notrack and ((sf1 & TC.S_CLUE) or (sf2 & TC.S_CLUE)):
		return false

	if notrack:
		if not (ef & TC.E_NOTRACK) and (ef & TC.E_TRACK):
			return false
	else:
		if not (ef & TC.E_TRACK):
			if (sf1 & TC.S_NOTRACK) or (sf2 & TC.S_NOTRACK) or (ef & TC.E_NOTRACK):
				return false
			if squares[y * GRID_W + x].e_count(TC.E_TRACK) >= 2:
				return false
			if squares[y2 * GRID_W + x2].e_count(TC.E_TRACK) >= 2:
				return false
	return true


func _can_flip_square(x: int, y: int, notrack: bool) -> bool:
	if not _in_grid(x, y):
		return false
	var idx := y * GRID_W + x
	var sf: int = squares[idx].sflags
	var trackc: int = squares[idx].e_count(TC.E_TRACK)

	if sf & TC.S_CLUE:
		return false

	if notrack:
		if not (sf & TC.S_NOTRACK) and ((sf & TC.S_TRACK) or trackc > 0):
			return false
	else:
		if not (sf & TC.S_TRACK) and (sf & TC.S_NOTRACK):
			return false
	return true


# ===========================================================================
# DSF (Disjoint Set Forest / Union-Find)
# ===========================================================================

func _dsf_init(size: int) -> void:
	_dsf.resize(size)
	_dsf_rank.resize(size)
	for i in range(size):
		_dsf[i] = i
		_dsf_rank[i] = 0


func _dsf_find(i: int) -> int:
	while _dsf[i] != i:
		_dsf[i] = _dsf[_dsf[i]]  # path compression
		i = _dsf[i]
	return i


func _dsf_merge(i: int, j: int) -> void:
	i = _dsf_find(i)
	j = _dsf_find(j)
	if i == j:
		return
	if _dsf_rank[i] < _dsf_rank[j]:
		_dsf[i] = j
	elif _dsf_rank[i] > _dsf_rank[j]:
		_dsf[j] = i
	else:
		_dsf[j] = i
		_dsf_rank[i] += 1


# ===========================================================================
# Utility
# ===========================================================================

func _in_grid(x: int, y: int) -> bool:
	return x >= 0 and x < GRID_W and y >= 0 and y < GRID_H
