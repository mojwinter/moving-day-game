#!/usr/bin/env python3
"""Generate a clean player.tscn with Body and Clothes AnimatedSprite2D layers."""

# char1_walk.png: 256x128 = 8 cols x 4 rows @ 32x32
# basic_walk.png: 2560x128 = 80 cols x 4 rows @ 32x32 (first 8 cols = first outfit)

FRAME_SIZE = 32
BODY_COLS = 8
CLOTHES_COLS = 80  # but we only use first 8

# Row 2 = right, Row 3 = left (verified in-game)
ROWS = {
    "down": 0,
    "up": 1,
    "right": 2,
    "left": 3,
}

def gen_atlas_textures(ext_id, cols, directions, frame_size=32):
    """Generate atlas texture sub-resources and return (sub_resources_text, animation_map)."""
    subs = []
    # animation_map: direction -> list of sub_resource IDs
    anim_map = {}
    counter = [1]

    def next_id():
        val = f"atlas_{ext_id}_{counter[0]}"
        counter[0] += 1
        return val

    for dir_name, row in directions.items():
        frames = []
        for col in range(8):  # always 8 frames per direction
            sub_id = next_id()
            x = col * frame_size
            y = row * frame_size
            subs.append(f'[sub_resource type="AtlasTexture" id="{sub_id}"]')
            subs.append(f'atlas = ExtResource("{ext_id}")')
            subs.append(f'region = Rect2({x}, {y}, {frame_size}, {frame_size})')
            subs.append('')
            frames.append(sub_id)
        anim_map[dir_name] = frames

    return '\n'.join(subs), anim_map


def gen_sprite_frames(anim_map, sf_id):
    """Generate SpriteFrames resource text."""
    anims = []

    for dir_name, frames in anim_map.items():
        # idle = first frame only
        idle_frames = '{\n"duration": 1.0,\n"texture": SubResource("%s")\n}' % frames[0]
        anims.append('{{\n"frames": [{idle}],\n"loop": true,\n"name": &"idle_{dir}",\n"speed": 8.0\n}}'.format(
            idle=idle_frames, dir=dir_name))

        # walk = all 8 frames
        walk_frames = ', '.join(
            '{{\n"duration": 1.0,\n"texture": SubResource("{id}")\n}}'.format(id=f)
            for f in frames
        )
        anims.append('{{\n"frames": [{walk}],\n"loop": true,\n"name": &"walk_{dir}",\n"speed": 8.0\n}}'.format(
            walk=walk_frames, dir=dir_name))

    return '[sub_resource type="SpriteFrames" id="{id}"]\nanimations = [{anims}]'.format(
        id=sf_id, anims=', '.join(anims))


def main():
    lines = []

    # (ext_id, sf_id, node_name, uid, path, visible)
    LAYERS = [
        ("body_tex",    "body_sf",    "Body",    "uid://cxguekbr31i14", "res://assets/character/char1_walk.png",    True),
        ("clothes_tex", "clothes_sf", "Clothes", "uid://c15bff2fcrali", "res://assets/character/basic_walk.png",   True),
        ("eyes_tex",    "eyes_sf",    "Eyes",    "uid://qiymjjhkv842",  "res://assets/character/eyes_walk.png",    True),
        ("hair_tex",    "hair_sf",    "Hair",    "",                     "res://assets/character/ponytail_walk.png", False),
    ]

    all_subs = []
    all_sf = []
    for ext_id, sf_id, _, _, _, _ in LAYERS:
        subs, amap = gen_atlas_textures(ext_id, 8, ROWS)
        sf = gen_sprite_frames(amap, sf_id)
        all_subs.append(subs)
        all_sf.append(sf)

    num_atlas = 8 * 4 * len(LAYERS)  # 32 per layer
    load_steps = num_atlas + len(LAYERS) + 1  # +sprite frames +script

    lines.append(f'[gd_scene load_steps={load_steps} format=3 uid="uid://dkxc74amhredq"]')
    lines.append('')
    lines.append('[ext_resource type="Script" uid="uid://dwvknuqlabnh1" path="res://scripts/player/player.gd" id="1_script"]')
    for ext_id, _, _, uid, path, _ in LAYERS:
        uid_str = f' uid="{uid}"' if uid else ''
        lines.append(f'[ext_resource type="Texture2D"{uid_str} path="{path}" id="{ext_id}"]')
    lines.append('')

    for subs in all_subs:
        lines.append(subs)
    for sf in all_sf:
        lines.append(sf)
        lines.append('')

    lines.append('[node name="Player" type="CharacterBody2D"]')
    lines.append('script = ExtResource("1_script")')
    lines.append('')
    for _, sf_id, name, _, _, visible in LAYERS:
        lines.append(f'[node name="{name}" type="AnimatedSprite2D" parent="."]')
        if not visible:
            lines.append('visible = false')
        lines.append(f'sprite_frames = SubResource("{sf_id}")')
        lines.append('animation = &"idle_down"')
        lines.append('')

    import os
    out_path = os.path.join(os.path.dirname(__file__), "..", "scenes", "player.tscn")
    with open(out_path, "w", newline="\n") as f:
        f.write('\n'.join(lines) + '\n')

    print(f"Generated {out_path}")
    for _, _, name, _, path, _ in LAYERS:
        print(f"  {name}: 4 directions x 8 frames + 4 idles")


if __name__ == "__main__":
    main()
