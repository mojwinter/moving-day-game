extends RefCounted
## Stores the topology and geometry of a Penrose (kite/dart) grid.
## Port of the grid struct from Simon Tatham's grid.h / grid.c.
## All references are index-based (no pointers).

## Dot (vertex) positions in viewport-scaled coordinates.
var dots: Array = [] # Array of Vector2
var dot_edges: Array = [] # dot_edges[i] = Array of edge indices incident on dot i (clockwise)
var dot_faces: Array = [] # dot_faces[i] = Array of face indices around dot i (clockwise, -1 = exterior)
var dot_order: Array = [] # number of edges per dot
var num_dots: int = 0

## Edges: each connects two dots and borders up to two faces.
var edges: Array = [] # Array of Vector2i(dot1_idx, dot2_idx)
var edge_faces: Array = [] # Array of Vector2i(face1_idx, face2_idx); -1 if boundary
var num_edges: int = 0

## Faces (kites or darts): each bounded by edges/dots.
var face_edges: Array = [] # face_edges[i] = Array of edge indices bounding face i
var face_dots: Array = [] # face_dots[i] = Array of dot indices (vertices, in order)
var face_order: Array = [] # number of edges per face
var num_faces: int = 0


## Compute the centroid of face i (average of its vertex positions).
func face_centroid(face_idx: int) -> Vector2:
	var verts: Array = face_dots[face_idx]
	var cx := 0.0
	var cy := 0.0
	for di in verts:
		cx += dots[di].x
		cy += dots[di].y
	var n := float(verts.size())
	return Vector2(cx / n, cy / n)
