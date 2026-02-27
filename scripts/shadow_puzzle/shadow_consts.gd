extends RefCounted
## Constants and data for the Shadow puzzle.
## The player fills recognisable silhouettes with polyomino blocks.

# --- Wall grid (silhouette surface) ---
const CELL := 10            # pixels per cell
const GRID_W := 12          # silhouette grid width
const GRID_H := 12          # silhouette grid height
const WALL_ORIGIN := Vector2(188, 14)  # top-left of wall grid on screen

# --- Tray (unplaced pieces sit here) ---
const TRAY_ORIGIN := Vector2(12, 14)
const TRAY_W := 164         # pixels wide
const TRAY_H := 152         # pixels tall

# --- Colors ---
const BG_COLOR := Color(0.05, 0.04, 0.09)
const WALL_BG := Color(0.09, 0.07, 0.13)
const SILHOUETTE_COLOR := Color(0.16, 0.18, 0.28, 0.35)
const SHADOW_FILLED := Color(0.02, 0.02, 0.05, 0.92)
const OVERLAP_COLOR := Color(0.6, 0.15, 0.15, 0.45)
const WIN_GLOW := Color(1.0, 0.95, 0.7)
const LIGHT_GLOW := Color(1.0, 0.85, 0.5, 0.18)
const RAY_COLOR := Color(1.0, 0.9, 0.6, 0.025)
const DUST_COLOR := Color(1.0, 0.85, 0.5, 0.10)
const GRID_LINE := Color(0.14, 0.12, 0.20, 0.15)

const PIECE_COLORS: Array[Color] = [
	Color(0.55, 0.35, 0.75, 0.88),  # lavender
	Color(0.35, 0.65, 0.75, 0.88),  # teal
	Color(0.75, 0.45, 0.55, 0.88),  # rose
	Color(0.65, 0.60, 0.30, 0.88),  # gold
	Color(0.40, 0.68, 0.42, 0.88),  # mint
	Color(0.70, 0.50, 0.35, 0.88),  # amber
	Color(0.45, 0.45, 0.72, 0.88),  # indigo
]

# --- Piece shapes (polyomino cell offsets) ---
const SHAPES: Dictionary = {
	"dom":   [Vector2i(0,0), Vector2i(1,0)],
	"tri_i": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0)],
	"tri_l": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1)],
	"tet_i": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(3,0)],
	"tet_o": [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)],
	"tet_t": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(1,1)],
	"tet_s": [Vector2i(1,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1)],
	"tet_z": [Vector2i(0,0), Vector2i(1,0), Vector2i(1,1), Vector2i(2,1)],
	"tet_l": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(0,1)],
	"tet_j": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(2,1)],
	"pent_f": [Vector2i(1,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1), Vector2i(1,2)],
	"pent_p": [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1), Vector2i(0,2)],
	"pent_u": [Vector2i(0,0), Vector2i(2,0), Vector2i(0,1), Vector2i(1,1), Vector2i(2,1)],
	"pent_t": [Vector2i(0,0), Vector2i(1,0), Vector2i(2,0), Vector2i(1,1), Vector2i(1,2)],
	"pent_l": [Vector2i(0,0), Vector2i(0,1), Vector2i(0,2), Vector2i(0,3), Vector2i(1,3)],
}

# --- Silhouette library ---
# Each silhouette is an Array[Vector2i] of occupied cells on the wall grid.
# Also stores which pieces to give the player and their solution rotations.

# Helicopter (12 cells)
const SIL_HELICOPTER: Array[Vector2i] = [
	Vector2i(2,3), Vector2i(3,3), Vector2i(4,3), Vector2i(5,3), Vector2i(6,3), Vector2i(7,3),
	Vector2i(3,4), Vector2i(4,4), Vector2i(5,4), Vector2i(6,4),
	Vector2i(8,4), Vector2i(9,4),
]

# Cat sitting (12 cells)
const SIL_CAT: Array[Vector2i] = [
	Vector2i(4,2), Vector2i(6,2),
	Vector2i(4,3), Vector2i(5,3), Vector2i(6,3),
	Vector2i(5,4), Vector2i(5,5),
	Vector2i(4,6), Vector2i(5,6), Vector2i(6,6),
	Vector2i(4,7), Vector2i(6,7),
]

# House (14 cells)
const SIL_HOUSE: Array[Vector2i] = [
	Vector2i(5,2),
	Vector2i(4,3), Vector2i(5,3), Vector2i(6,3),
	Vector2i(3,4), Vector2i(4,4), Vector2i(5,4), Vector2i(6,4), Vector2i(7,4),
	Vector2i(4,5), Vector2i(5,5), Vector2i(6,5),
	Vector2i(4,6), Vector2i(6,6),
]

# Tree (10 cells)
const SIL_TREE: Array[Vector2i] = [
	Vector2i(5,1),
	Vector2i(4,2), Vector2i(5,2), Vector2i(6,2),
	Vector2i(3,3), Vector2i(4,3), Vector2i(5,3), Vector2i(6,3), Vector2i(7,3),
	Vector2i(5,4),
	Vector2i(5,5),
	Vector2i(5,6),
]

# Bird (9 cells)
const SIL_BIRD: Array[Vector2i] = [
	Vector2i(3,3), Vector2i(5,3),
	Vector2i(3,4), Vector2i(4,4), Vector2i(5,4),
	Vector2i(4,5),
	Vector2i(3,6), Vector2i(4,6), Vector2i(5,6),
]

# Star (12 cells)
const SIL_STAR: Array[Vector2i] = [
	Vector2i(5,1),
	Vector2i(4,2), Vector2i(5,2), Vector2i(6,2),
	Vector2i(3,3), Vector2i(4,3), Vector2i(5,3), Vector2i(6,3), Vector2i(7,3),
	Vector2i(4,4), Vector2i(5,4), Vector2i(6,4),
]

# Rocket (11 cells)
const SIL_ROCKET: Array[Vector2i] = [
	Vector2i(5,1),
	Vector2i(5,2),
	Vector2i(4,3), Vector2i(5,3), Vector2i(6,3),
	Vector2i(4,4), Vector2i(5,4), Vector2i(6,4),
	Vector2i(4,5), Vector2i(6,5),
	Vector2i(5,6),
]

# Key (8 cells)
const SIL_KEY: Array[Vector2i] = [
	Vector2i(3,4), Vector2i(4,4), Vector2i(5,4), Vector2i(6,4), Vector2i(7,4), Vector2i(8,4),
	Vector2i(3,5), Vector2i(8,5),
]
