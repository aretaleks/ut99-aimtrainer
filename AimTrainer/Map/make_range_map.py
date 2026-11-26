"""Build DM-AimRange, the Aim Trainer's shooting range map, with the UnrealEd MCP
map generator from the mapping install (it builds with that install's 469e UCC).

    python AimTrainer/Map/make_range_map.py

Writes the map to the mapping install's Maps folder (the generator's output), then
copies it to this workspace's Maps folder. The project JSON is kept next to this
script.

The map has three halls side by side, one per course (ATGame.Course). Each has
its firing line at x = FIRE_X and runs downrange along +x:
  - Flat Range (y around 0): the open, flat hall;
  - High Ground (y around +HALL_DY): platforms of different heights over a pit,
    joined by ramps, laid out in the Close / Mid / Far distance bands; the
    firing deck is raised (DECK_Z), so there are targets below and above;
  - Airborne (y around -HALL_DY): kicker pads on both sides of the hall, four
    per distance band (the game sets each kick's arc).
ATGame tells the halls apart by y (ATGame.CourseOfY).
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
HALL_DY = 5120       # the other halls' centres are at y = +-HALL_DY
PIT = -256           # High Ground: the pit floor
DECK_Z = 224         # High Ground: the firing deck is raised, so some platforms are below the trainee
DECK_D = 256         # High Ground: the firing deck reaches this far downrange

# High Ground platforms per distance band: (d0, d1) downrange of the firing line,
# then a row across the hall: ("p", y0, y1, top) a platform, ("r", y0, y1, low, high,
# rises_toward) a ramp between its neighbours. y is relative to the hall's centre.
PLATFORM_BANDS = [
    ((380, 720), [            # Close (350-750)
        ("p", -620, -320, 0),
        ("r", -320, -120, 0, 96, "+y"),
        ("p", -120, 200, 96),
        ("r", 200, 400, 96, 192, "+y"),
        ("p", 400, 700, 192),
    ]),
    ((850, 1450), [           # Mid (800-1500): high on the left
        ("p", -1150, -400, 352),
        ("r", -400, -150, 224, 352, "-y"),
        ("p", -150, 400, 224),
        ("r", 400, 650, 96, 224, "-y"),
        ("p", 650, 1150, 96),
    ]),
    ((1700, 2700), [          # Far (1600-2800)
        ("p", -1600, -1000, 256),
        ("r", -1000, -720, 256, 416, "+y"),
        ("p", -720, -100, 416),
        ("r", -100, 180, 256, 416, "-y"),
        ("p", 180, 700, 256),
        ("r", 700, 1040, 256, 448, "+y"),
        ("p", 1040, 1600, 448),
    ]),
]

# Airborne kicker pads, four per distance band: two depths, both sides of the
# hall, (d, y) with d downrange of the firing line. Each one's distance from the
# firing spot is inside its band (Close 350-750, Mid 800-1500, Far 1600-2800).
# The map's KickVelocity is only a default: the game sets a new arc for every
# kick, towards a pad across the hall in the same band.
KICKER_PADS = [
    (420, 300), (620, 380),        # Close: 516, 727
    (900, 650), (1250, 700),       # Mid: 1110, 1433
    (1900, 1200), (2400, 1300),    # Far: 2247, 2729
]


def hall(cy, floor_z=0):
    """One hall centred on y = cy: room, side pillars, lights, zone, three starts."""
    print(S.add_room([X0, cy - Y, floor_z], [X1, cy + Y, H], corner="chamfer", corner_size=384,
                     floor_texture=FLOOR, wall_texture=WALL, ceiling_texture=CEIL))
    # pillars along the side walls every 1024 uu: depth cues down the range
    for x in range(-3072, 3073, 1024):
        for side in (-1, 1):
            y_in = cy + side * (Y - 64)
            y_out = cy + side * Y
            print(S.add_box([x - 64, min(y_in, y_out), floor_z], [x + 64, max(y_in, y_out), H], csg="add", texture=TRIM))


def lights(cy):
    for x in (-3840, -2304, -768, 768, 2304, 3712):
        for y in (-1152, 1152):
            print(S.add_light([x, cy + y, H - 160], brightness=150, radius=72))


def starts(cy, z=0):
    for y in (0, -192, 192):
        print(S.add_player_start(FIRE_X, cy + y, z, yaw=0))


def fire_line(cy, z=0):
    # a low line on the floor at the firing position (semisolid strip, 16 high)
    print(S.add_box([FIRE_X + 256, cy - 1024, z], [FIRE_X + 288, cy + 1024, z + 16], csg="semisolid", texture=TRIM))


def high_ground(cy):
    # firing deck over the pit
    print(S.add_box([X0, cy - Y, PIT], [FIRE_X + DECK_D, cy + Y, DECK_Z], csg="add",
                    floor_texture=FLOOR, wall_texture=TRIM))
    for (d0, d1), row in PLATFORM_BANDS:
        x0, x1 = FIRE_X + d0, FIRE_X + d1
        for part in row:
            if part[0] == "p":
                _, y0, y1, top = part
                print(S.add_box([x0, cy + y0, PIT], [x1, cy + y1, top], csg="add",
                                floor_texture=FLOOR, wall_texture=TRIM))
            else:
                _, y0, y1, low, high, rises = part
                # the ramp's support down to the pit, then the wedge on top
                print(S.add_box([x0, cy + y0, PIT], [x1, cy + y1, low], csg="add",
                                floor_texture=FLOOR, wall_texture=TRIM))
                print(S.add_ramp([x0, cy + y0, low], [x1, cy + y1, high], rises_toward=rises,
                                 texture=FLOOR))


def airborne(cy):
    for d, y in KICKER_PADS:
        for side in (-1, 1):
            # default arc: to the middle of the hall
            print(S.add_kicker(FIRE_X + d, cy + side * y, 0, [FIRE_X + d, cy, 0], apex=192, pad="inset", light=True))


def main():
    proj = os.path.join(GEN, "projects", NAME + ".json")
    if os.path.exists(proj):
        os.remove(proj)
    print(S.new_map(NAME, title="Aim Trainer Range", author="Aim Trainer", gametype="dm"))

    # Flat Range
    hall(0)
    fire_line(0)
    lights(0)
    print(S.add_zone([0, 0, H / 2], type="normal", name="Range", ambient_brightness=24))
    starts(0)

    # High Ground
    hall(HALL_DY, PIT)
    high_ground(HALL_DY)
    fire_line(HALL_DY, DECK_Z)
    lights(HALL_DY)
    print(S.add_zone([0, HALL_DY, H / 2], type="normal", name="HighGround", ambient_brightness=24))
    starts(HALL_DY, DECK_Z)

    # Airborne
    hall(-HALL_DY)
    airborne(-HALL_DY)
    fire_line(-HALL_DY)
    lights(-HALL_DY)
    print(S.add_zone([0, -HALL_DY, H / 2], type="normal", name="Airborne", ambient_brightness=24))
    starts(-HALL_DY)

    print(S.analyze_map())
    result = S.build_map(NAME + ".unr", lighting=True, paths="define", overwrite=True)
    print(result)
    if '"ok": true' not in result:
        sys.exit("Build failed: the map was not copied.")

    built = os.path.join(MAPPING, "Maps", NAME + ".unr")
    dst_dir = os.path.join(WORKSPACE, "Maps")
    os.makedirs(dst_dir, exist_ok=True)
    shutil.copy2(built, os.path.join(dst_dir, NAME + ".unr"))
    shutil.copy2(proj, os.path.join(HERE, NAME + ".json"))
    print("Copied to", dst_dir)


if __name__ == "__main__":
    main()
