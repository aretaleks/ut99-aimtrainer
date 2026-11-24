"""Build DM-AimRange, the Aim Trainer's shooting range map, with the UnrealEd MCP
map generator from the mapping install (it builds with that install's 469e UCC).

    python AimTrainer/Map/make_range_map.py

Writes the map to the mapping install's Maps folder (the generator's output), then
copies it to this workspace's Maps folder. The project JSON is kept next to this
script.
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Tools"))
import atpaths  # noqa: E402
MAPPING = atpaths.get("mapping_install")
GEN = os.path.join(MAPPING, "UnrealEdMCP")
HERE = os.path.dirname(os.path.abspath(__file__))
WORKSPACE = os.path.abspath(os.path.join(HERE, "..", ".."))
NAME = "DM-AimRange"

sys.path.insert(0, GEN)
os.chdir(GEN)
import server as S  # noqa: E402

FLOOR = "UTtech2.Floor.rClfFlr1x"
WALL = "UTtech1.Base.panelbase"
CEIL = "UTtech1.Ceiling.bmCeiling"
TRIM = "UTtech1.Base.metals5"

# hall: x is downrange, the firing position is at the -x end
X0, X1, Y, H = -4608, 4096, 2048, 1280
FIRE_X = -4096


def main():
    proj = os.path.join(GEN, "projects", NAME + ".json")
    if os.path.exists(proj):
        os.remove(proj)
    print(S.new_map(NAME, title="Aim Trainer Range", author="Aim Trainer", gametype="dm"))
    print(S.add_room([X0, -Y, 0], [X1, Y, H], corner="chamfer", corner_size=384,
                     floor_texture=FLOOR, wall_texture=WALL, ceiling_texture=CEIL))
    # pillars along the side walls every 1024 uu: depth cues down the range
    for x in range(-3072, 3073, 1024):
        for side in (-1, 1):
            y_in = side * (Y - 64)
            y_out = side * Y
            print(S.add_box([x - 64, min(y_in, y_out), 0], [x + 64, max(y_in, y_out), H], csg="add", texture=TRIM))
    # a low line on the floor at the firing position (semisolid strip, 16 high)
    print(S.add_box([FIRE_X + 256, -1024, 0], [FIRE_X + 288, 1024, 16], csg="semisolid", texture=TRIM))
    # even light over the whole range
    for x in (-3840, -2304, -768, 768, 2304, 3712):
        for y in (-1152, 1152):
            print(S.add_light([x, y, H - 160], brightness=150, radius=72))
    print(S.add_zone([0, 0, H / 2], type="normal", name="Range", ambient_brightness=24))
    for y in (0, -192, 192):
        print(S.add_player_start(FIRE_X, y, 0, yaw=0))
    print(S.analyze_map())
    print(S.build_map(NAME + ".unr", lighting=True, paths="define", overwrite=True))

    built = os.path.join(MAPPING, "Maps", NAME + ".unr")
    dst_dir = os.path.join(WORKSPACE, "Maps")
    os.makedirs(dst_dir, exist_ok=True)
    shutil.copy2(built, os.path.join(dst_dir, NAME + ".unr"))
    shutil.copy2(proj, os.path.join(HERE, NAME + ".json"))
    print("Copied to", dst_dir)


if __name__ == "__main__":
    main()
