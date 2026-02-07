extends RefCounted
## Shared constants for the Train Tracks puzzle.
## Direction constants match net_consts.gd (R=1, U=2, L=4, D=8).

# --- Direction constants ---
const DIR_R := 1
const DIR_U := 2
const DIR_L := 4
const DIR_D := 8
const ALLDIR := 15

const DIRECTIONS := [1, 2, 4, 8]  # R, U, L, D

const DIR_OFFSET := {
	1: Vector2i(1, 0),   # R
	2: Vector2i(0, -1),  # U
	4: Vector2i(-1, 0),  # L
	8: Vector2i(0, 1),   # D
}

# --- Named track shapes (2-direction combos) ---
const LR := 5   # L|R = 4|1
const UD := 10  # U|D = 2|8
const LU := 6   # L|U = 4|2
const LD := 12  # L|D = 4|8
const RU := 3   # R|U = 1|2
const RD := 9   # R|D = 1|8

# --- Square flags (bits 0-4 of sflags) ---
const S_TRACK := 1       # track passes through this square
const S_NOTRACK := 2     # no track in this square
const S_ERROR := 4       # constraint violation
const S_CLUE := 8        # pre-placed clue square (immutable)
const S_MARK := 16       # temporary solver marker

# --- Edge flag bit shifts within sflags ---
const S_TRACK_SHIFT := 16    # bits 16-19: per-edge E_TRACK flags
const S_NOTRACK_SHIFT := 20  # bits 20-23: per-edge E_NOTRACK flags

# --- Edge flag identifiers (passed to e_set/e_clear) ---
const E_TRACK := 1
const E_NOTRACK := 2

# --- Bit count lookup for 4-bit values (0..15) ---
const NBITS := [0, 1, 1, 2, 1, 2, 2, 3, 1, 2, 2, 3, 2, 3, 3, 4]


## Returns the opposite direction. Port of tracks.c F(d) macro.
static func opposite(dir: int) -> int:
	return ((dir << 2) | (dir >> 2)) & 0xF


## Returns x offset for a direction.
static func dx(dir: int) -> int:
	if dir == DIR_R: return 1
	if dir == DIR_L: return -1
	return 0


## Returns y offset for a direction.
static func dy(dir: int) -> int:
	if dir == DIR_D: return 1
	if dir == DIR_U: return -1
	return 0
