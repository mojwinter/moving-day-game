extends Node
## Manages the logical grid state: generation, rotation, BFS connectivity, and win detection.
## Port of the core algorithms from Simon Tatham's net.c.

const TileDataScript := preload("res://scripts/net_puzzle/tile_data.gd")
const NC := preload("res://scripts/net_puzzle/net_consts.gd")

signal puzzle_solved
signal grid_changed  # emitted after any state change so visuals can refresh

const GRID_WIDTH := 5
const GRID_HEIGHT := 5

var tiles: Array = []
var source_pos: Vector2i = Vector2i(2, 2)
var _solved := false


func _ready() -> void:
	randomize()


## Generate a new puzzle: build spanning tree, mark source, shuffle.
func generate_puzzle() -> void:
	_solved = false
	tiles.clear()
	for i in range(GRID_WIDTH * GRID_HEIGHT):
		tiles.append(TileDataScript.new())

	source_pos = Vector2i(GRID_WIDTH / 2, GRID_HEIGHT / 2)
	tiles[source_pos.y * GRID_WIDTH + source_pos.x].is_source = true

	_build_spanning_tree()
	_shuffle_grid()
	_update_active()
	grid_changed.emit()


## Rotate a tile clockwise and recompute state.
func rotate_tile(x: int, y: int) -> void:
	if _solved:
		return
	var idx := y * GRID_WIDTH + x
	tiles[idx].rotate_cw()
	_update_active()
	_check_win()
	grid_changed.emit()


func get_tile(x: int, y: int):
	return tiles[y * GRID_WIDTH + x]


# ---------------------------------------------------------------------------
# Spanning tree generation (port of net.c new_game_desc, lines 1203-1326)
# ---------------------------------------------------------------------------

func _build_spanning_tree() -> void:
	var reached := []
	reached.resize(GRID_WIDTH * GRID_HEIGHT)
	reached.fill(false)
	reached[source_pos.y * GRID_WIDTH + source_pos.x] = true

	# Frontier: each entry is { "pos": Vector2i, "dir": int }
	var frontier := []

	# Seed frontier from source neighbors
	for dir in NC.DIRECTIONS:
		var neighbor: Vector2i = source_pos + NC.DIR_OFFSET[dir]
		if _in_bounds(neighbor):
			frontier.append({"pos": source_pos, "dir": dir})

	while frontier.size() > 0:
		# Pick a random frontier entry
		var pick_idx := randi() % frontier.size()
		var entry = frontier[pick_idx]
		frontier.remove_at(pick_idx)

		var x1: int = entry["pos"].x
		var y1: int = entry["pos"].y
		var d1: int = entry["dir"]
		var offset: Vector2i = NC.DIR_OFFSET[d1]
		var x2: int = x1 + offset.x
		var y2: int = y1 + offset.y
		var d2: int = NC.opposite(d1)

		# Skip if target already reached (would create a loop)
		if not _in_bounds(Vector2i(x2, y2)):
			continue
		if reached[y2 * GRID_WIDTH + x2]:
			continue

		# Make the connection
		tiles[y1 * GRID_WIDTH + x1].connections |= d1
		tiles[y2 * GRID_WIDTH + x2].connections |= d2
		reached[y2 * GRID_WIDTH + x2] = true

		# Cross prevention: if source tile now has 3 connections,
		# remove the frontier entry for its 4th direction
		if tiles[y1 * GRID_WIDTH + x1].connection_count() == 3:
			var missing_dir: int = 0x0F ^ (tiles[y1 * GRID_WIDTH + x1].connections & 0x0F)
			var new_frontier := []
			for e in frontier:
				if not (e["pos"].x == x1 and e["pos"].y == y1 and e["dir"] == missing_dir):
					new_frontier.append(e)
			frontier = new_frontier

		# Remove all frontier entries pointing INTO (x2, y2) from other cells
		var filtered_frontier := []
		for e in frontier:
			var eoffset: Vector2i = NC.DIR_OFFSET[e["dir"]]
			if not (e["pos"].x + eoffset.x == x2 and e["pos"].y + eoffset.y == y2):
				filtered_frontier.append(e)
		frontier = filtered_frontier

		# Add new frontier entries from the newly reached tile
		for dir in NC.DIRECTIONS:
			if dir == d2:
				continue  # don't go back the way we came
			var n: Vector2i = Vector2i(x2, y2) + NC.DIR_OFFSET[dir]
			if _in_bounds(n) and not reached[n.y * GRID_WIDTH + n.x]:
				frontier.append({"pos": Vector2i(x2, y2), "dir": dir})


# ---------------------------------------------------------------------------
# Shuffle (port of net.c shuffle, lines 1447-1510, simplified)
# ---------------------------------------------------------------------------

func _shuffle_grid() -> void:
	# Rotate each tile by a random amount
	for i in range(tiles.size()):
		var rotations := randi() % 4
		for _r in range(rotations):
			tiles[i].rotate_cw()

	# Verify the puzzle isn't accidentally already solved
	_update_active()
	var all_active := true
	for i in range(tiles.size()):
		if (tiles[i].connections & 0x0F) != 0 and not tiles[i].is_active:
			all_active = false
			break

	if all_active:
		# Rotate one non-source endpoint to break the solution
		for i in range(tiles.size()):
			if tiles[i].connection_count() >= 1 and not tiles[i].is_source:
				tiles[i].rotate_cw()
				break


# ---------------------------------------------------------------------------
# BFS active/powered computation (port of compute_active, net.c:1862-1910)
# ---------------------------------------------------------------------------

func _update_active() -> void:
	# Clear all active flags
	for i in range(tiles.size()):
		tiles[i].is_active = false

	# BFS from source
	var source_idx := source_pos.y * GRID_WIDTH + source_pos.x
	tiles[source_idx].is_active = true
	var queue := [source_pos]

	while queue.size() > 0:
		var pos: Vector2i = queue.pop_front()
		var idx := pos.y * GRID_WIDTH + pos.x

		for dir in NC.DIRECTIONS:
			if not tiles[idx].has_connection(dir):
				continue
			var neighbor_pos: Vector2i = pos + NC.DIR_OFFSET[dir]
			if not _in_bounds(neighbor_pos):
				continue
			var nidx := neighbor_pos.y * GRID_WIDTH + neighbor_pos.x
			var opp: int = NC.opposite(dir)
			if not tiles[nidx].has_connection(opp):
				continue  # connection not mutual
			if tiles[nidx].is_active:
				continue  # already visited
			tiles[nidx].is_active = true
			queue.append(neighbor_pos)


# ---------------------------------------------------------------------------
# Win check (port of net.c:2544-2568)
# ---------------------------------------------------------------------------

func _check_win() -> void:
	for i in range(tiles.size()):
		if (tiles[i].connections & 0x0F) != 0 and not tiles[i].is_active:
			return  # not all tiles powered yet
	_solved = true
	puzzle_solved.emit()


## Returns neighboring grid positions that share a mutual connection with tile (x, y).
func get_connected_neighbors(x: int, y: int) -> Array:
	var result := []
	var idx := y * GRID_WIDTH + x
	for dir in NC.DIRECTIONS:
		if not tiles[idx].has_connection(dir):
			continue
		var neighbor_pos: Vector2i = Vector2i(x, y) + NC.DIR_OFFSET[dir]
		if not _in_bounds(neighbor_pos):
			continue
		var nidx := neighbor_pos.y * GRID_WIDTH + neighbor_pos.x
		if tiles[nidx].has_connection(NC.opposite(dir)):
			result.append(neighbor_pos)
	return result


func _in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT
