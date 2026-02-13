#include "loopy_native.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/array.hpp>

extern "C" {
#include "loopy_bridge.h"
}

using namespace godot;

/* GRID_PENROSE_P2 = 11 in Tatham's grid_type enum */
static const int GRID_TYPE_PENROSE_P2 = 11;
/* DIFF_EASY = 0 */
static const int DIFF_EASY = 0;

/* Viewport constants matching the game's 320x180 resolution */
static const float VIEWPORT_W = 320.0f;
static const float VIEWPORT_H = 180.0f;
static const float PADDING = 20.0f;

LoopyNative::LoopyNative() {}
LoopyNative::~LoopyNative() {}

void LoopyNative::_bind_methods() {
    ClassDB::bind_method(D_METHOD("generate_puzzle", "w", "h"), &LoopyNative::generate_puzzle);
}

Dictionary LoopyNative::generate_puzzle(int w, int h) {
    LoopyPuzzleData *data = loopy_generate(w, h, GRID_TYPE_PENROSE_P2, DIFF_EASY);

    Dictionary result;
    result["num_dots"] = data->num_dots;
    result["num_edges"] = data->num_edges;
    result["num_faces"] = data->num_faces;

    /* Scale dot positions from Tatham grid coordinates to viewport.
     * Tatham's grid uses large integer coordinates. We scale to fit
     * within the viewport with padding, centered. */
    float gw = (float)(data->highest_x - data->lowest_x);
    float gh = (float)(data->highest_y - data->lowest_y);
    float avail_w = VIEWPORT_W - 2.0f * PADDING;
    float avail_h = VIEWPORT_H - 2.0f * PADDING;
    float scale = (gw > 0 && gh > 0)
        ? fmin(avail_w / gw, avail_h / gh)
        : 1.0f;
    float off_x = (VIEWPORT_W - gw * scale) * 0.5f;
    float off_y = (VIEWPORT_H - gh * scale) * 0.5f;

    /* Dots: pack as two float arrays (x, y) already in viewport coords */
    PackedFloat32Array dots_x, dots_y;
    dots_x.resize(data->num_dots);
    dots_y.resize(data->num_dots);
    for (int i = 0; i < data->num_dots; i++) {
        dots_x[i] = (float)(data->dot_x[i] - data->lowest_x) * scale + off_x;
        dots_y[i] = (float)(data->dot_y[i] - data->lowest_y) * scale + off_y;
    }
    result["dots_x"] = dots_x;
    result["dots_y"] = dots_y;

    /* Dot metadata */
    PackedInt32Array dot_order;
    dot_order.resize(data->num_dots);
    for (int i = 0; i < data->num_dots; i++)
        dot_order[i] = data->dot_order[i];
    result["dot_order"] = dot_order;

    /* Dot edges: pack as flat array + offsets */
    int total_dot_edges = data->dot_edges_offsets[data->num_dots];
    PackedInt32Array dot_edges_flat, dot_edges_offsets;
    dot_edges_flat.resize(total_dot_edges);
    dot_edges_offsets.resize(data->num_dots + 1);
    for (int i = 0; i < total_dot_edges; i++)
        dot_edges_flat[i] = data->dot_edges_flat[i];
    for (int i = 0; i <= data->num_dots; i++)
        dot_edges_offsets[i] = data->dot_edges_offsets[i];
    result["dot_edges_flat"] = dot_edges_flat;
    result["dot_edges_offsets"] = dot_edges_offsets;

    /* Dot faces: pack as flat array + offsets */
    int total_dot_faces = data->dot_faces_offsets[data->num_dots];
    PackedInt32Array dot_faces_flat, dot_faces_offsets;
    dot_faces_flat.resize(total_dot_faces);
    dot_faces_offsets.resize(data->num_dots + 1);
    for (int i = 0; i < total_dot_faces; i++)
        dot_faces_flat[i] = data->dot_faces_flat[i];
    for (int i = 0; i <= data->num_dots; i++)
        dot_faces_offsets[i] = data->dot_faces_offsets[i];
    result["dot_faces_flat"] = dot_faces_flat;
    result["dot_faces_offsets"] = dot_faces_offsets;

    /* Edges: four parallel int arrays */
    PackedInt32Array edge_d1, edge_d2, edge_f1, edge_f2;
    edge_d1.resize(data->num_edges);
    edge_d2.resize(data->num_edges);
    edge_f1.resize(data->num_edges);
    edge_f2.resize(data->num_edges);
    for (int i = 0; i < data->num_edges; i++) {
        edge_d1[i] = data->edge_d1[i];
        edge_d2[i] = data->edge_d2[i];
        edge_f1[i] = data->edge_f1[i];
        edge_f2[i] = data->edge_f2[i];
    }
    result["edge_d1"] = edge_d1;
    result["edge_d2"] = edge_d2;
    result["edge_f1"] = edge_f1;
    result["edge_f2"] = edge_f2;

    /* Face order */
    PackedInt32Array face_order;
    face_order.resize(data->num_faces);
    for (int i = 0; i < data->num_faces; i++)
        face_order[i] = data->face_order[i];
    result["face_order"] = face_order;

    /* Face dots: flat + offsets */
    int total_face_dots = data->face_dots_offsets[data->num_faces];
    PackedInt32Array face_dots_flat, face_dots_offsets;
    face_dots_flat.resize(total_face_dots);
    face_dots_offsets.resize(data->num_faces + 1);
    for (int i = 0; i < total_face_dots; i++)
        face_dots_flat[i] = data->face_dots_flat[i];
    for (int i = 0; i <= data->num_faces; i++)
        face_dots_offsets[i] = data->face_dots_offsets[i];
    result["face_dots_flat"] = face_dots_flat;
    result["face_dots_offsets"] = face_dots_offsets;

    /* Face edges: flat + offsets */
    int total_face_edges = data->face_edges_offsets[data->num_faces];
    PackedInt32Array face_edges_flat, face_edges_offsets;
    face_edges_flat.resize(total_face_edges);
    face_edges_offsets.resize(data->num_faces + 1);
    for (int i = 0; i < total_face_edges; i++)
        face_edges_flat[i] = data->face_edges_flat[i];
    for (int i = 0; i <= data->num_faces; i++)
        face_edges_offsets[i] = data->face_edges_offsets[i];
    result["face_edges_flat"] = face_edges_flat;
    result["face_edges_offsets"] = face_edges_offsets;

    /* Clues: per-face, -1 = hidden */
    PackedInt32Array clues;
    clues.resize(data->num_faces);
    for (int i = 0; i < data->num_faces; i++)
        clues[i] = (int)data->clues[i];
    result["clues"] = clues;

    loopy_free_data(data);
    return result;
}
