extends Resource
## Pure data representation of a single grid tile.
## Connections are stored as a 4-bit bitmask matching net.c conventions.

var connections: int = 0
var is_source: bool = false
var is_active: bool = false
var is_revealed: bool = false  ## Fog of war: tile content visible to player
var bfs_distance: int = -1     ## BFS hops from source (-1 = unreached)


## Clockwise rotation: R->D->L->U->R
## Port of net.c macro C(x) = ((x & 0x0E) >> 1) | ((x & 0x01) << 3)
func rotate_cw() -> void:
	connections = ((connections & 0x0E) >> 1) | ((connections & 0x01) << 3)


## Counter-clockwise rotation: R->U->L->D->R
## Port of net.c macro A(x) = ((x & 0x07) << 1) | ((x & 0x08) >> 3)
func rotate_ccw() -> void:
	connections = ((connections & 0x07) << 1) | ((connections & 0x08) >> 3)


func has_connection(dir: int) -> bool:
	return (connections & dir) != 0


## Port of net.c COUNT macro
func connection_count() -> int:
	var c := connections & 0x0F
	return ((c >> 3) & 1) + ((c >> 2) & 1) + ((c >> 1) & 1) + (c & 1)
