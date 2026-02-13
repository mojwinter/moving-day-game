/*
 * loopy_bridge.h: C bridge exposing Simon Tatham's Loopy puzzle generator
 * to the GDExtension C++ wrapper.
 *
 * The bridge #includes all Tatham .c files into a single translation unit
 * so it can access their static functions. It exposes a single generate
 * function that returns all grid topology + clue data in flat arrays.
 */

#ifndef LOOPY_BRIDGE_H
#define LOOPY_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int num_dots, num_edges, num_faces;

    /* Dot positions in Tatham grid coordinates (integer).
     * Caller must scale to viewport. */
    int *dot_x, *dot_y;
    int lowest_x, lowest_y, highest_x, highest_y;

    /* Per-dot metadata */
    int *dot_order;            /* number of edges per dot */
    int *dot_edges_flat;       /* flattened: edges around dot i start at dot_edges_offsets[i] */
    int *dot_edges_offsets;    /* size num_dots+1 (sentinel at end) */
    int *dot_faces_flat;       /* cyclically ordered faces around dot (-1 = exterior) */
    int *dot_faces_offsets;    /* size num_dots+1 */

    /* Edge connectivity */
    int *edge_d1, *edge_d2;   /* dot indices for each edge's endpoints */
    int *edge_f1, *edge_f2;   /* face indices (-1 = boundary/exterior) */

    /* Per-face metadata */
    int *face_order;           /* number of edges/dots per face */
    int *face_dots_flat;       /* flattened vertex lists */
    int *face_dots_offsets;    /* size num_faces+1 */
    int *face_edges_flat;      /* flattened edge lists */
    int *face_edges_offsets;   /* size num_faces+1 */

    /* Face incentre (centre of largest inscribed circle) in grid coords.
     * Better label placement than vertex average for concave shapes. */
    int *face_ix, *face_iy;

    /* Clues: per-face, -1 means no clue shown */
    signed char *clues;
} LoopyPuzzleData;

/*
 * Generate a complete Loopy puzzle.
 * grid_type: index into Tatham's grid_type enum (11 = GRID_PENROSE_P2)
 * diff: difficulty (0 = DIFF_EASY)
 * Returns a heap-allocated struct. Caller must free with loopy_free_data().
 */
LoopyPuzzleData *loopy_generate(int w, int h, int grid_type, int diff);

void loopy_free_data(LoopyPuzzleData *data);

#ifdef __cplusplus
}
#endif

#endif /* LOOPY_BRIDGE_H */
