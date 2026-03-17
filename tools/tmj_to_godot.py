#!/usr/bin/env python3
"""Convert Tiled .tmj object layers into Godot Sprite2D nodes in a .tscn file."""

import json
import sys
import os

# Tiled flipping flags (top 3 bits of GID)
FLIPPED_HORIZONTALLY = 0x80000000
FLIPPED_VERTICALLY   = 0x40000000
FLIPPED_DIAGONALLY   = 0x20000000
GID_MASK = 0x1FFFFFFF

# Tileset info: firstgid -> (name, columns, tilewidth, tileheight, image_path)
TILESETS = [
    (1,     "beds",         120, 16, 16, "res://assets/interior full/furniture/beds.png"),
    (5881,  "global",       270, 16, 16, "res://assets/interior full/global.png"),
    (63931, "wallpapers",    40, 16, 16, "res://assets/interior full/basics/wallpapers.png"),
    (65971, "decorations",   60, 16, 16, "res://assets/interior full/furniture/decorations.png"),
    (68311, "couchtables",   20, 16, 16, "res://assets/interior full/furniture/couchtables.png"),
    (68451, "storage",       28, 16, 16, "res://assets/interior full/furniture/storage.png"),
    (69459, "tables",        28, 16, 16, "res://assets/interior full/furniture/tables.png"),
    (70075, "big-window",     1, 24, 24, "res://assets/interior full/big-window.png"),
]

# Sort by firstgid descending for lookup
TILESETS.sort(key=lambda t: t[0], reverse=True)


def resolve_gid(raw_gid):
    """Resolve a Tiled GID to tileset info and atlas coordinates."""
    flip_h = bool(raw_gid & FLIPPED_HORIZONTALLY)
    flip_v = bool(raw_gid & FLIPPED_VERTICALLY)
    gid = raw_gid & GID_MASK

    for firstgid, name, columns, tw, th, image_path in TILESETS:
        if gid >= firstgid:
            local_id = gid - firstgid
            col = local_id % columns
            row = local_id // columns
            region_x = col * tw
            region_y = row * th
            return {
                "tileset": name,
                "image": image_path,
                "region_x": region_x,
                "region_y": region_y,
                "region_w": tw,
                "region_h": th,
                "flip_h": flip_h,
                "flip_v": flip_v,
            }
    return None


def main():
    tmj_path = os.path.join(os.path.dirname(__file__), "..", "main_screen.tmj")
    with open(tmj_path, "r") as f:
        data = json.load(f)

    # Collect all unique images used
    ext_resources = {}  # image_path -> id string
    ext_id_counter = [1]

    def get_ext_id(image_path):
        if image_path not in ext_resources:
            ext_resources[image_path] = f"img_{ext_id_counter[0]}"
            ext_id_counter[0] += 1
        return ext_resources[image_path]

    # First pass: collect all objects and their resolved info
    object_layers = []
    for layer in data["layers"]:
        if layer["type"] != "objectgroup":
            continue
        if not layer.get("objects"):
            continue
        objects = []
        for obj in layer["objects"]:
            raw_gid = obj.get("gid", 0)
            if raw_gid == 0:
                continue
            info = resolve_gid(raw_gid)
            if info is None:
                continue
            get_ext_id(info["image"])

            # Tiled object positions: x,y is bottom-left of the tile
            # Godot Sprite2D position is the center by default, but we'll use
            # centered=false so position is top-left
            # Tiled y is bottom of tile, so subtract height to get top
            obj_w = obj.get("width", info["region_w"])
            obj_h = obj.get("height", info["region_h"])
            pos_x = obj["x"]
            pos_y = obj["y"] - obj_h  # convert from bottom-left to top-left

            objects.append({
                "name": obj.get("name", ""),
                "id": obj["id"],
                "pos_x": pos_x,
                "pos_y": pos_y,
                "info": info,
                "ext_id": get_ext_id(info["image"]),
            })
        if objects:
            object_layers.append({
                "name": layer["name"],
                "id": layer["id"],
                "objects": objects,
            })

    # Generate .tscn content for object layer nodes
    # This will be a standalone scene that can be instanced or merged
    lines = []
    lines.append('[gd_scene load_steps=%d format=3]' % (len(ext_resources) + 1))
    lines.append('')

    for image_path, ext_id in ext_resources.items():
        lines.append(f'[ext_resource type="Texture2D" path="{image_path}" id="{ext_id}"]')
    lines.append('')

    lines.append('[node name="ObjectLayers" type="Node2D"]')
    lines.append('')

    for layer in object_layers:
        layer_name = layer["name"].replace(" ", "_")
        # Deduplicate layer names
        lines.append(f'[node name="{layer_name}" type="Node2D" parent="."]')
        lines.append('')

        name_counts = {}
        for obj in layer["objects"]:
            info = obj["info"]
            # Generate a unique node name
            base_name = obj["name"] if obj["name"] else f'{info["tileset"]}_{obj["id"]}'
            base_name = base_name.replace(" ", "_").replace("-", "_")
            if base_name in name_counts:
                name_counts[base_name] += 1
                node_name = f"{base_name}_{name_counts[base_name]}"
            else:
                name_counts[base_name] = 0
                node_name = base_name

            lines.append(f'[node name="{node_name}" type="Sprite2D" parent="{layer_name}"]')
            lines.append(f'position = Vector2({obj["pos_x"]}, {obj["pos_y"]})')
            lines.append('centered = false')
            lines.append(f'texture = ExtResource("{obj["ext_id"]}")')
            lines.append('region_enabled = true')
            lines.append(f'region_rect = Rect2({info["region_x"]}, {info["region_y"]}, {info["region_w"]}, {info["region_h"]})')
            if info["flip_h"]:
                lines.append('flip_h = true')
            if info["flip_v"]:
                lines.append('flip_v = true')
            lines.append('')

    out_path = os.path.join(os.path.dirname(__file__), "..", "scenes", "object_layers.tscn")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", newline="\n") as f:
        f.write("\n".join(lines))

    print(f"Generated {out_path}")
    print(f"  {len(ext_resources)} textures, {sum(len(l['objects']) for l in object_layers)} sprites across {len(object_layers)} layers")


if __name__ == "__main__":
    main()
