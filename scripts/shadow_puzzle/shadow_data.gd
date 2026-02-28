extends RefCounted
## Puzzle definitions for the Wire Bridge puzzle.
## Each puzzle defines a grid, two nodes, and available pieces.

const SC := preload("res://scripts/shadow_puzzle/shadow_consts.gd")


## First bridge puzzle: horizontal bridge, 6×4 grid.
## Node A on left edge, Node B on right edge.
static func bridge_1() -> Dictionary:
	var pieces: Array[int] = [
		SC.PIECE_I, SC.PIECE_O, SC.PIECE_T,
		SC.PIECE_L, SC.PIECE_J, SC.PIECE_S, SC.PIECE_Z,
	]
	return {
		"grid_w": 6,
		"grid_h": 4,
		# Node A: left edge, middle row, terminal faces right into the grid
		"node_a": { "pos": Vector2i(0, 1), "side": 1 },  # DIR_R
		# Node B: right edge, middle row, terminal faces left into the grid
		"node_b": { "pos": Vector2i(5, 2), "side": 4 },  # DIR_L
		"pieces": pieces,
	}
