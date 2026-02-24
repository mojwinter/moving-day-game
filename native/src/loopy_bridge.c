/*
 * loopy_bridge.c: Bridge between Simon Tatham's Loopy puzzle C code
 * and the GDExtension C++ wrapper.
 *
 * This file #includes all of Tatham's .c files into a single translation
 * unit so that we can access static functions like new_game_desc(),
 * new_game(), etc. We provide stub implementations for framework
 * functions that Tatham's code expects but we don't need (drawing, UI).
 *
 * Build note: The include path must contain native/tatham/ so that
 * #include "puzzles.h" etc. resolve correctly.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include <assert.h>
#include <ctype.h>
#include <stdarg.h>
#include <time.h>

/* =====================================================================
 * Step 1: Include Tatham's headers so all types are declared.
 * The .c files will re-include these but the include guards prevent
 * any conflict.
 * ===================================================================== */

#include "puzzles.h"
#include "grid.h"
#include "tree234.h"
#include "penrose.h"
#include "loopgen.h"

/* =====================================================================
 * Step 2: Framework stubs
 * These match the exact signatures declared in puzzles.h.
 * They are defined before the .c includes so that when misc.c / loopy.c
 * reference these symbols they're already present.
 * ===================================================================== */

void fatal(char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fprintf(stderr, "\n");
    abort();
}

void frontend_default_colour(frontend *fe, float *output) {
    (void)fe;
    output[0] = output[1] = output[2] = 0.8f;
}

void activate_timer(frontend *fe) { (void)fe; }
void deactivate_timer(frontend *fe) { (void)fe; }

void get_random_seed(void **randseed, int *randseedsize) {
    static unsigned int seed;
    seed = (unsigned int)time(NULL);
    *randseed = &seed;
    *randseedsize = sizeof(seed);
}

/* version.c - required extern */
char ver[] = "loopy_bridge 1.0";

/* Drawing API stubs - never called during generation but must link. */
drawing *drawing_new(const drawing_api *api, midend *me, void *handle) {
    (void)api; (void)me; (void)handle; return NULL;
}
void drawing_free(drawing *dr) { (void)dr; }
void draw_text(drawing *dr, int x, int y, int ft, int fs, int a, int c, char *t) {
    (void)dr; (void)x; (void)y; (void)ft; (void)fs; (void)a; (void)c; (void)t;
}
void draw_rect(drawing *dr, int x, int y, int w, int h, int c) {
    (void)dr; (void)x; (void)y; (void)w; (void)h; (void)c;
}
void draw_line(drawing *dr, int x1, int y1, int x2, int y2, int c) {
    (void)dr; (void)x1; (void)y1; (void)x2; (void)y2; (void)c;
}
void draw_polygon(drawing *dr, int *co, int np, int fc, int oc) {
    (void)dr; (void)co; (void)np; (void)fc; (void)oc;
}
void draw_circle(drawing *dr, int cx, int cy, int r, int fc, int oc) {
    (void)dr; (void)cx; (void)cy; (void)r; (void)fc; (void)oc;
}
void draw_thick_line(drawing *dr, float th, float x1, float y1, float x2, float y2, int c) {
    (void)dr; (void)th; (void)x1; (void)y1; (void)x2; (void)y2; (void)c;
}
void clip(drawing *dr, int x, int y, int w, int h) {
    (void)dr; (void)x; (void)y; (void)w; (void)h;
}
void unclip(drawing *dr) { (void)dr; }
void start_draw(drawing *dr) { (void)dr; }
void draw_update(drawing *dr, int x, int y, int w, int h) {
    (void)dr; (void)x; (void)y; (void)w; (void)h;
}
void end_draw(drawing *dr) { (void)dr; }
char *text_fallback(drawing *dr, const char *const *strings, int nstrings) {
    (void)dr; (void)nstrings;
    return dupstr(strings[0]);
}
void status_bar(drawing *dr, char *text) { (void)dr; (void)text; }
blitter *blitter_new(drawing *dr, int w, int h) {
    (void)dr; (void)w; (void)h; return NULL;
}
void blitter_free(drawing *dr, blitter *bl) { (void)dr; (void)bl; }
void blitter_save(drawing *dr, blitter *bl, int x, int y) {
    (void)dr; (void)bl; (void)x; (void)y;
}
void blitter_load(drawing *dr, blitter *bl, int x, int y) {
    (void)dr; (void)bl; (void)x; (void)y;
}
int print_mono_colour(drawing *dr, int grey) { (void)dr; (void)grey; return 0; }
int print_grey_colour(drawing *dr, float grey) { (void)dr; (void)grey; return 0; }
int print_hatched_colour(drawing *dr, int hatch) { (void)dr; (void)hatch; return 0; }
int print_rgb_mono_colour(drawing *dr, float r, float g, float b, int mono) {
    (void)dr; (void)r; (void)g; (void)b; (void)mono; return 0;
}
int print_rgb_grey_colour(drawing *dr, float r, float g, float b, float grey) {
    (void)dr; (void)r; (void)g; (void)b; (void)grey; return 0;
}
int print_rgb_hatched_colour(drawing *dr, float r, float g, float b, int hatch) {
    (void)dr; (void)r; (void)g; (void)b; (void)hatch; return 0;
}
void print_line_width(drawing *dr, int width) { (void)dr; (void)width; }
void print_line_dotted(drawing *dr, int dotted) { (void)dr; (void)dotted; }
void print_begin_doc(drawing *dr, int pages) { (void)dr; (void)pages; }
void print_begin_page(drawing *dr, int number) { (void)dr; (void)number; }
void print_begin_puzzle(drawing *dr, float xm, float xc, float ym, float yc,
                        int pw, int ph, float wmm, float scale) {
    (void)dr; (void)xm; (void)xc; (void)ym; (void)yc;
    (void)pw; (void)ph; (void)wmm; (void)scale;
}
void print_end_puzzle(drawing *dr) { (void)dr; }
void print_end_page(drawing *dr, int number) { (void)dr; (void)number; }
void print_end_doc(drawing *dr) { (void)dr; }
void print_get_colour(drawing *dr, int colour, int pic,
                      int *hatch, float *r, float *g, float *b) {
    (void)dr; (void)colour; (void)pic;
    if (hatch) *hatch = 0;
    if (r) *r = 0; if (g) *g = 0; if (b) *b = 0;
}

/* =====================================================================
 * Step 3: Include Tatham .c files
 * Order matters — dependencies must come first.
 * Since we already included all headers above (puzzles.h, grid.h, etc.)
 * the re-includes inside each .c are harmless (guards).
 * ===================================================================== */

#include "tree234.c"
#include "dsf.c"
#include "malloc.c"
#include "random.c"
#include "misc.c"
#include "penrose.c"
#include "grid.c"
#include "loopgen.c"
#include "loopy.c"

/* =====================================================================
 * Step 4: Bridge implementation
 * All static functions from the included .c files are now visible.
 * ===================================================================== */

#include "loopy_bridge.h"

/* Helper: convert Tatham pointer-based references to flat integer indices */
static int bridge_edge_index(grid *g, grid_edge *e) {
    return (int)(e - g->edges);
}
static int bridge_face_index(grid *g, grid_face *f) {
    return f ? (int)(f - g->faces) : -1;
}
static int bridge_dot_index(grid *g, grid_dot *d) {
    return (int)(d - g->dots);
}

LoopyPuzzleData *loopy_generate(int w, int h, int grid_type, int diff) {
    int i, j, offset;

    /* 1. Set up params */
    game_params params;
    params.w = w;
    params.h = h;
    params.type = grid_type;
    params.diff = diff;

    /* 2. Create random state from a time-based seed */
    random_state *rs;
    {
        void *seed_ptr;
        int seedsize;
        get_random_seed(&seed_ptr, &seedsize);
        char buf[64];
        int len = sprintf(buf, "%u", *(unsigned int *)seed_ptr);
        rs = random_new(buf, len);
    }

    /* 3. Generate puzzle description (solver + loop gen + clue removal) */
    char *aux = NULL;
    char *desc = new_game_desc(&params, rs, &aux, FALSE);

    /* 4. Reconstruct game state from description (parses clues + grid) */
    game_state *state = new_game(NULL, &params, desc);
    grid *g = state->game_grid;

    /* 5. Allocate and fill LoopyPuzzleData */
    LoopyPuzzleData *data = (LoopyPuzzleData *)calloc(1, sizeof(LoopyPuzzleData));
    data->num_dots = g->num_dots;
    data->num_edges = g->num_edges;
    data->num_faces = g->num_faces;
    data->lowest_x = g->lowest_x;
    data->lowest_y = g->lowest_y;
    data->highest_x = g->highest_x;
    data->highest_y = g->highest_y;

    /* --- Dots --- */
    data->dot_x = (int *)malloc(g->num_dots * sizeof(int));
    data->dot_y = (int *)malloc(g->num_dots * sizeof(int));
    data->dot_order = (int *)malloc(g->num_dots * sizeof(int));
    data->dot_edges_offsets = (int *)malloc((g->num_dots + 1) * sizeof(int));
    data->dot_faces_offsets = (int *)malloc((g->num_dots + 1) * sizeof(int));

    int total_dot_edges = 0, total_dot_faces = 0;
    for (i = 0; i < g->num_dots; i++) {
        data->dot_x[i] = g->dots[i].x;
        data->dot_y[i] = g->dots[i].y;
        data->dot_order[i] = g->dots[i].order;
        total_dot_edges += g->dots[i].order;
        total_dot_faces += g->dots[i].order;
    }

    data->dot_edges_flat = (int *)malloc(total_dot_edges * sizeof(int));
    data->dot_faces_flat = (int *)malloc(total_dot_faces * sizeof(int));

    offset = 0;
    for (i = 0; i < g->num_dots; i++) {
        data->dot_edges_offsets[i] = offset;
        for (j = 0; j < g->dots[i].order; j++) {
            data->dot_edges_flat[offset++] = bridge_edge_index(g, g->dots[i].edges[j]);
        }
    }
    data->dot_edges_offsets[g->num_dots] = offset;

    offset = 0;
    for (i = 0; i < g->num_dots; i++) {
        data->dot_faces_offsets[i] = offset;
        for (j = 0; j < g->dots[i].order; j++) {
            data->dot_faces_flat[offset++] = bridge_face_index(g, g->dots[i].faces[j]);
        }
    }
    data->dot_faces_offsets[g->num_dots] = offset;

    /* --- Edges --- */
    data->edge_d1 = (int *)malloc(g->num_edges * sizeof(int));
    data->edge_d2 = (int *)malloc(g->num_edges * sizeof(int));
    data->edge_f1 = (int *)malloc(g->num_edges * sizeof(int));
    data->edge_f2 = (int *)malloc(g->num_edges * sizeof(int));

    for (i = 0; i < g->num_edges; i++) {
        data->edge_d1[i] = bridge_dot_index(g, g->edges[i].dot1);
        data->edge_d2[i] = bridge_dot_index(g, g->edges[i].dot2);
        data->edge_f1[i] = bridge_face_index(g, g->edges[i].face1);
        data->edge_f2[i] = bridge_face_index(g, g->edges[i].face2);
    }

    /* --- Faces --- */
    data->face_order = (int *)malloc(g->num_faces * sizeof(int));
    data->face_dots_offsets = (int *)malloc((g->num_faces + 1) * sizeof(int));
    data->face_edges_offsets = (int *)malloc((g->num_faces + 1) * sizeof(int));

    int total_face_dots = 0, total_face_edges = 0;
    for (i = 0; i < g->num_faces; i++) {
        data->face_order[i] = g->faces[i].order;
        total_face_dots += g->faces[i].order;
        total_face_edges += g->faces[i].order;
    }

    data->face_dots_flat = (int *)malloc(total_face_dots * sizeof(int));
    data->face_edges_flat = (int *)malloc(total_face_edges * sizeof(int));

    offset = 0;
    for (i = 0; i < g->num_faces; i++) {
        data->face_dots_offsets[i] = offset;
        for (j = 0; j < g->faces[i].order; j++) {
            data->face_dots_flat[offset++] = bridge_dot_index(g, g->faces[i].dots[j]);
        }
    }
    data->face_dots_offsets[g->num_faces] = offset;

    offset = 0;
    for (i = 0; i < g->num_faces; i++) {
        data->face_edges_offsets[i] = offset;
        for (j = 0; j < g->faces[i].order; j++) {
            data->face_edges_flat[offset++] = bridge_edge_index(g, g->faces[i].edges[j]);
        }
    }
    data->face_edges_offsets[g->num_faces] = offset;

    /* --- Face incentres --- */
    data->face_ix = (int *)malloc(g->num_faces * sizeof(int));
    data->face_iy = (int *)malloc(g->num_faces * sizeof(int));
    for (i = 0; i < g->num_faces; i++) {
        grid_find_incentre(&g->faces[i]);
        data->face_ix[i] = g->faces[i].ix;
        data->face_iy[i] = g->faces[i].iy;
    }

    /* --- Clues --- */
    data->clues = (signed char *)malloc(g->num_faces * sizeof(signed char));
    memcpy(data->clues, state->clues, g->num_faces * sizeof(signed char));

    /* --- Solution: solve at max difficulty to get edge states --- */
    {
        solver_state *sstate = new_solver_state(state, DIFF_MAX);
        solver_state *sstate_solved = solve_game_rec(sstate);
        data->solution = (char *)malloc(g->num_edges * sizeof(char));
        if (sstate_solved->solver_status == SOLVER_SOLVED) {
            memcpy(data->solution, sstate_solved->state->lines, g->num_edges);
        } else {
            memset(data->solution, LINE_UNKNOWN, g->num_edges);
        }
        free_solver_state(sstate_solved);
        free_solver_state(sstate);
    }

    /* 6. Cleanup Tatham objects */
    free_game(state);
    sfree(desc);
    if (aux) sfree(aux);
    random_free(rs);

    return data;
}

void loopy_free_data(LoopyPuzzleData *data) {
    if (!data) return;
    free(data->dot_x);
    free(data->dot_y);
    free(data->dot_order);
    free(data->dot_edges_flat);
    free(data->dot_edges_offsets);
    free(data->dot_faces_flat);
    free(data->dot_faces_offsets);
    free(data->edge_d1);
    free(data->edge_d2);
    free(data->edge_f1);
    free(data->edge_f2);
    free(data->face_order);
    free(data->face_dots_flat);
    free(data->face_dots_offsets);
    free(data->face_edges_flat);
    free(data->face_edges_offsets);
    free(data->face_ix);
    free(data->face_iy);
    free(data->clues);
    free(data->solution);
    free(data);
}
