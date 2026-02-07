extends Resource
## Pure data representation of a single grid square for the Train Tracks puzzle.
## State is stored in a single bit-packed integer (sflags) matching tracks.c conventions.

const TC := preload("res://scripts/tracks_puzzle/tracks_consts.gd")

var sflags: int = 0


## Extract the 4-bit direction mask of edges with a given flag (E_TRACK or E_NOTRACK).
func e_dirs(eflag: int) -> int:
	var shift := TC.S_TRACK_SHIFT if eflag == TC.E_TRACK else TC.S_NOTRACK_SHIFT
	return (sflags >> shift) & TC.ALLDIR


## Count edges with a given flag.
func e_count(eflag: int) -> int:
	return TC.NBITS[e_dirs(eflag)]


## Get the E_TRACK/E_NOTRACK flags on a specific edge direction.
func e_flags(d: int) -> int:
	var t := TC.E_TRACK if (sflags & (d << TC.S_TRACK_SHIFT)) else 0
	var nt := TC.E_NOTRACK if (sflags & (d << TC.S_NOTRACK_SHIFT)) else 0
	return t | nt


## Set an edge flag on direction d (local only; grid_manager propagates to neighbor).
func e_set(d: int, eflag: int) -> void:
	var shift := TC.S_TRACK_SHIFT if eflag == TC.E_TRACK else TC.S_NOTRACK_SHIFT
	sflags |= (d << shift)


## Clear an edge flag on direction d (local only).
func e_clear(d: int, eflag: int) -> void:
	var shift := TC.S_TRACK_SHIFT if eflag == TC.E_TRACK else TC.S_NOTRACK_SHIFT
	sflags &= ~(d << shift)


func has_flag(f: int) -> bool:
	return (sflags & f) != 0


func set_flag(f: int) -> void:
	sflags |= f


func clear_flag(f: int) -> void:
	sflags &= ~f


func toggle_flag(f: int) -> void:
	sflags ^= f
