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


## Face incentres (centre of largest inscribed circle), computed by Tatham's
## grid_find_incentre() and pre-scaled to viewport coords by the native plugin.
## Falls back to vertex average if not populated.
var face_incentres: Array = []  # Array of Vector2

func face_centroid(face_idx: int) -> Vector2:
	if face_idx < face_incentres.size():
		return face_incentres[face_idx]
	# Fallback: vertex average
	var verts: Array = face_dots[face_idx]
	var s := Vector2.ZERO
	for di in verts:
		s += Vector2(dots[di])
	return s / float(verts.size())
