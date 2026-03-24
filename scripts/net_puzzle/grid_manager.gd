extends Node
## Manages the logical grid state: generation, rotation, BFS connectivity, and win detection.
## Supports configurable grid size, wrapping edges, fog of war, and decay.

const TileDataScript := preload("res://scripts/net_puzzle/tile_data.gd")
const NC := preload("res://scripts/net_puzzle/net_consts.gd")

signal puzzle_solved
signal grid_changed

var grid_width: int = 3
var grid_height: int = 3
var wrapping: bool = false
var fog_enabled: bool = false
var decay_enabled: bool = false
var decay_interval: float = 5.0  ## Seconds between random decay rotations

var tiles: Array = []
var source_pos: Vector2i = Vector2i.ZERO
var _solved := false

var _decay_timer: float = 0.0


func _ready() -> void:
	randomize()


func _process(delta: float) -> void:
	if not decay_enabled or _solved:
		return
	_decay_timer += delta
	if _decay_timer >= decay_interval:
		_decay_timer -= decay_interval
		_apply_decay()


## Configure and generate a new puzzle with the given parameters.
func setup_and_generate(w: int, h: int, p_wrapping: bool, p_fog: bool, p_decay: bool, p_decay_interval: float = 5.0) -> void:
	grid_width = w
	grid_height = h
	wrapping = p_wrapping
	fog_enabled = p_fog
	decay_enabled = p_decay
	decay_interval = p_decay_interval
	generate_puzzle()


func generate_puzzle() -> void:
	_solved = false
	_decay_timer = 0.0
	tiles.clear()
	for i in range(grid_width * grid_height):
		tiles.append(TileDataScript.new())

	source_pos = Vector2i(grid_width / 2, grid_height / 2)
	tiles[source_pos.y * grid_width + source_pos.x].is_source = true

	_build_spanning_tree()
	_shuffle_grid()
	_update_active()
	_update_fog()
	grid_changed.emit()


func rotate_tile(x: int, y: int) -> void:
	if _solved:
		return
	var idx := y * grid_width + x
	tiles[idx].rotate_cw()
	_update_active()
	_update_fog()
	_check_win()
	grid_changed.emit()


## Rotate the bitmask only — no BFS, no fog, no win check, no signal.
## Used by net_puzzle to defer visual updates until after animation.
func rotate_tile_silent(x: int, y: int) -> void:
	if _solved:
		return
	var idx := y * grid_width + x
	tiles[idx].rotate_cw()


## Re-run BFS, fog, win check, and emit signal. Called after animation finishes.
func recompute_and_check() -> void:
	_update_active()
	_update_fog()
	_check_win()
	grid_changed.emit()


func get_tile(x: int, y: int):
	return tiles[y * grid_width + x]


# ---------------------------------------------------------------------------
# Spanning tree generation
# ---------------------------------------------------------------------------

func _build_spanning_tree() -> void:
	var reached := []
	reached.resize(grid_width * grid_height)
	reached.fill(false)
	reached[source_pos.y * grid_width + source_pos.x] = true

	var frontier := []

	for dir in NC.DIRECTIONS:
		var neighbor: Vector2i = _neighbor_pos(source_pos, dir)
		if neighbor != Vector2i(-1, -1):
			frontier.append({"pos": source_pos, "dir": dir})

	while frontier.size() > 0:
		var pick_idx := randi() % frontier.size()
		var entry = frontier[pick_idx]
		frontier.remove_at(pick_idx)

		var p1: Vector2i = entry["pos"]
		var d1: int = entry["dir"]
		var p2: Vector2i = _neighbor_pos(p1, d1)
		var d2: int = NC.opposite(d1)

		if p2 == Vector2i(-1, -1):
			continue
		if reached[p2.y * grid_width + p2.x]:
			continue

		tiles[p1.y * grid_width + p1.x].connections |= d1
		tiles[p2.y * grid_width + p2.x].connections |= d2
		reached[p2.y * grid_width + p2.x] = true

		# Cross prevention
		if tiles[p1.y * grid_width + p1.x].connection_count() == 3:
			var missing_dir: int = 0x0F ^ (tiles[p1.y * grid_width + p1.x].connections & 0x0F)
			var new_frontier := []
			for e in frontier:
				if not (e["pos"] == p1 and e["dir"] == missing_dir):
					new_frontier.append(e)
			frontier = new_frontier

		# Remove frontier entries pointing into p2
		var filtered := []
		for e in frontier:
			var ep2: Vector2i = _neighbor_pos(e["pos"], e["dir"])
			if ep2 != p2:
				filtered.append(e)
		frontier = filtered

		# Add new frontier from p2
		for dir in NC.DIRECTIONS:
			if dir == d2:
				continue
			var n: Vector2i = _neighbor_pos(p2, dir)
			if n != Vector2i(-1, -1) and not reached[n.y * grid_width + n.x]:
				frontier.append({"pos": p2, "dir": dir})


# ---------------------------------------------------------------------------
# Shuffle
# ---------------------------------------------------------------------------

func _shuffle_grid() -> void:
	for i in range(tiles.size()):
		var rotations := randi() % 4
		for _r in range(rotations):
			tiles[i].rotate_cw()

	_update_active()
	var all_active := true
	for i in range(tiles.size()):
		if (tiles[i].connections & 0x0F) != 0 and not tiles[i].is_active:
			all_active = false
			break

	if all_active:
		for i in range(tiles.size()):
			if tiles[i].connection_count() >= 1 and not tiles[i].is_source:
				tiles[i].rotate_cw()
				break


# ---------------------------------------------------------------------------
# Fog of war
# ---------------------------------------------------------------------------

func _update_fog() -> void:
	if not fog_enabled:
		# All revealed
		for t in tiles:
			t.is_revealed = true
		return

	# Source is always revealed
	for t in tiles:
		t.is_revealed = false

	# Reveal active tiles and their immediate neighbors
	for y in range(grid_height):
		for x in range(grid_width):
			var idx := y * grid_width + x
			if tiles[idx].is_active:
				tiles[idx].is_revealed = true
				# Reveal neighbors (regardless of connection)
				for dir in NC.DIRECTIONS:
					var npos := _neighbor_pos(Vector2i(x, y), dir)
					if npos != Vector2i(-1, -1):
						tiles[npos.y * grid_width + npos.x].is_revealed = true

	# Source always revealed
	tiles[source_pos.y * grid_width + source_pos.x].is_revealed = true


# ---------------------------------------------------------------------------
# Decay — randomly rotate an unpowered tile
# ---------------------------------------------------------------------------

func _apply_decay() -> void:
	var candidates := []
	for i in range(tiles.size()):
		if not tiles[i].is_active and not tiles[i].is_source and tiles[i].connection_count() >= 1:
			candidates.append(i)
	if candidates.is_empty():
		return
	var idx: int = candidates[randi() % candidates.size()]
	tiles[idx].rotate_cw()
	_update_active()
	_update_fog()
	grid_changed.emit()


# ---------------------------------------------------------------------------
# BFS active/powered computation
# ---------------------------------------------------------------------------

func _update_active() -> void:
	for i in range(tiles.size()):
		tiles[i].is_active = false

	var source_idx := source_pos.y * grid_width + source_pos.x
	tiles[source_idx].is_active = true
	var queue := [source_pos]

	while queue.size() > 0:
		var pos: Vector2i = queue.pop_front()
		var idx := pos.y * grid_width + pos.x

		for dir in NC.DIRECTIONS:
			if not tiles[idx].has_connection(dir):
				continue
			var neighbor_pos: Vector2i = _neighbor_pos(pos, dir)
			if neighbor_pos == Vector2i(-1, -1):
				continue
			var nidx := neighbor_pos.y * grid_width + neighbor_pos.x
			var opp: int = NC.opposite(dir)
			if not tiles[nidx].has_connection(opp):
				continue
			if tiles[nidx].is_active:
				continue
			tiles[nidx].is_active = true
			queue.append(neighbor_pos)


# ---------------------------------------------------------------------------
# Win check
# ---------------------------------------------------------------------------

func _check_win() -> void:
	for i in range(tiles.size()):
		if (tiles[i].connections & 0x0F) != 0 and not tiles[i].is_active:
			return
	_solved = true
	puzzle_solved.emit()


## Returns neighboring grid positions that share a mutual connection with tile (x, y).
func get_connected_neighbors(x: int, y: int) -> Array:
	var result := []
	var idx := y * grid_width + x
	for dir in NC.DIRECTIONS:
		if not tiles[idx].has_connection(dir):
			continue
		var npos: Vector2i = _neighbor_pos(Vector2i(x, y), dir)
		if npos == Vector2i(-1, -1):
			continue
		var nidx := npos.y * grid_width + npos.x
		if tiles[nidx].has_connection(NC.opposite(dir)):
			result.append(npos)
	return result


# ---------------------------------------------------------------------------
# Neighbor helper — supports wrapping
# ---------------------------------------------------------------------------

func _neighbor_pos(pos: Vector2i, dir: int) -> Vector2i:
	var offset: Vector2i = NC.DIR_OFFSET[dir]
	var nx: int = pos.x + offset.x
	var ny: int = pos.y + offset.y

	if wrapping:
		nx = nx % grid_width
		if nx < 0:
			nx += grid_width
		ny = ny % grid_height
		if ny < 0:
			ny += grid_height
		return Vector2i(nx, ny)
	else:
		if nx < 0 or nx >= grid_width or ny < 0 or ny >= grid_height:
			return Vector2i(-1, -1)
		return Vector2i(nx, ny)
