#!/usr/bin/env python3
"""
Remap main_screen.tscn to use wallpapers.png instead of global.png
for the Walls, Base, and Trim TileMapLayers.

Tile coordinate mapping (global.png atlas coords -> wallpapers.png atlas coords):
  Walls:  (17,32)->(17,0)  (17,33)->(17,1)  (16,66)->(16,34)  (16,67)->(16,35)
  Base:   (14,70)->(14,38)
  Trim:   (2,68)->(2,36)  (2,69)->(2,37)  (3,68)->(3,36)  (4,68)->(4,36)  (4,69)->(4,37)
"""

import base64
import struct
import re
from pathlib import Path

SCENE_PATH = Path(__file__).parent.parent / "main_screen.tscn"

# global atlas coord -> wallpapers atlas coord
REMAP = {
    (17, 32): (17, 0),
    (17, 33): (17, 1),
    (16, 66): (16, 34),
    (16, 67): (16, 35),
    (14, 70): (14, 38),
    (2, 68):  (2, 36),
    (2, 69):  (2, 37),
    (3, 68):  (3, 36),
    (4, 68):  (4, 36),
    (4, 69):  (4, 37),
}

NEW_SOURCE_ID = 1


def decode_tile_map_data(b64: str):
    data = base64.b64decode(b64)
    header = struct.unpack_from("<H", data, 0)[0]
    entries = []
    for i in range(2, len(data), 12):
        if i + 12 > len(data):
            break
        entry = list(struct.unpack("<hhhhhh", data[i:i + 12]))
        entries.append(entry)
    return header, entries


def encode_tile_map_data(header: int, entries: list) -> str:
    parts = [struct.pack("<H", header)]
    for e in entries:
        parts.append(struct.pack("<hhhhhh", *e))
    return base64.b64encode(b"".join(parts)).decode("ascii")


def remap_entries(entries: list, old_source: int = 1) -> int:
    count = 0
    for e in entries:
        if e[2] == old_source:
            old_atlas = (e[3], e[4])
            if old_atlas in REMAP:
                new_atlas = REMAP[old_atlas]
                e[2] = NEW_SOURCE_ID
                e[3] = new_atlas[0]
                e[4] = new_atlas[1]
                count += 1
            else:
                print(f"  WARNING: unmapped atlas coord {old_atlas} at cell ({e[0]},{e[1]})")
    return count


def main():
    text = SCENE_PATH.read_text(encoding="utf-8")

    # Step 1: Replace global.png ext_resource with wallpapers.png
    text = text.replace(
        '[ext_resource type="Texture2D" uid="uid://djoitp5vy0fa8" path="res://assets/interior full/global.png" id="global"]',
        '[ext_resource type="Texture2D" path="res://assets/interior full/basics/wallpapers.png" id="wallpapers"]'
    )

    # Step 2: Replace texture reference in atlas source
    text = text.replace(
        'texture = ExtResource("global")',
        'texture = ExtResource("wallpapers")'
    )

    # Step 3: Rebuild TileSetAtlasSource_1 with only the wallpapers tiles we use
    wallpapers_tiles = sorted(set(REMAP.values()))

    pattern = r'(\[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_1"\]\ntexture = ExtResource\("wallpapers"\)\n)((?:\d+:\d+/\d+[^\n]*\n)*)'
    new_tile_defs = ""
    for ax, ay in wallpapers_tiles:
        new_tile_defs += f"{ax}:{ay}/0 = 0\n"

    text = re.sub(pattern, r'\g<1>' + new_tile_defs, text)

    # Step 4: Remap tile_map_data for each layer
    total_remapped = 0
    for layer_name in ["Walls", "Base", "Trim", "Furniture", "Bed"]:
        layer_pattern = rf'\[node name="{layer_name}" type="TileMapLayer"[^\]]*\]'
        layer_match = re.search(layer_pattern, text)
        if not layer_match:
            continue
        after = text[layer_match.end():]
        data_match = re.search(r'tile_map_data = PackedByteArray\("([^"]+)"\)', after)
        if not data_match:
            continue

        print(f"Processing {layer_name}:")
        full_start = layer_match.end() + data_match.start()
        full_end = layer_match.end() + data_match.end()

        b64 = data_match.group(1)
        header, entries = decode_tile_map_data(b64)
        count = remap_entries(entries)
        new_b64 = encode_tile_map_data(header, entries)
        new_text = f'tile_map_data = PackedByteArray("{new_b64}")'

        text = text[:full_start] + new_text + text[full_end:]
        print(f"  Remapped {count} tiles")
        total_remapped += count

    SCENE_PATH.write_text(text, encoding="utf-8")
    print(f"\nDone! Updated {SCENE_PATH.name}")
    print(f"  - Replaced global.png with wallpapers.png")
    print(f"  - Trimmed atlas from ~26k tile defs to {len(wallpapers_tiles)}")
    print(f"  - Remapped {total_remapped} tile placements")
    print(f"\nNote: object_layers.tscn still uses global.png for Sprite2D objects.")


if __name__ == "__main__":
    main()
