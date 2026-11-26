"""Make the shareable release: Release/AimTrainer.zip with AimTrainer.exe and README.txt.

AimTrainer.exe carries the four game files inside (AimTrainer.u, AimTrainer.int,
AimTrainerMoves.ini, DM-AimRange.unr). It's compiled with the .NET Framework's
own C# compiler, so nothing needs installing.

    python AimTrainer/Tools/make_release.py
"""
import os
import shutil
import subprocess
import sys
import zipfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SYSTEM = os.path.join(ROOT, "System")
LAUNCHER = os.path.join(ROOT, "AimTrainer", "Launcher")
REL = os.path.join(ROOT, "Release")
WORK = os.path.join(REL, "build")
CSC = r"C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
FILES = [
    (os.path.join(SYSTEM, "AimTrainer.u"), "AimTrainer.u"),
    (os.path.join(SYSTEM, "AimTrainer.int"), "AimTrainer.int"),
    (os.path.join(SYSTEM, "AimTrainerMoves.ini"), "AimTrainerMoves.ini"),
    (os.path.join(ROOT, "Maps", "DM-AimRange.unr"), "DM-AimRange.unr"),
]

README = """AIM TRAINER for Unreal Tournament (UT99, OldUnreal 469 patches)
=====================================================

Targets are player models that move like real players: their movement is
replayed from about 3 hours of recorded movement of real players in iCTF
matches (strafes, circle strafes, ADAD, dodges, the odd crouch). Shoot them
for a timed session, with your accuracy, kills, headshots and best scores.
Three courses: Flat Range, High Ground (platforms above and below you) and
Airborne (targets fly off kicker pads; only targets in the air count).


INSTALL AND PLAY
----------------
1. Unzip anywhere.
2. Double-click AimTrainer.exe.
   It finds your Unreal Tournament folder (or asks for it), copies the Aim
   Trainer's four files into it and starts the game on the shooting range.
   It only adds these files, nothing of yours is changed:
     System\\AimTrainer.u
     System\\AimTrainer.int
     System\\AimTrainerMoves.ini
     Maps\\DM-AimRange.unr
3. Next time, AimTrainer.exe again (it updates the files if the exe is newer).

Made and tested on Unreal Tournament with the OldUnreal 469f patch
(oldunreal.com); players report 469b works too. Older versions (436,
451) are untested.

Windows may warn that the exe is from an unknown publisher (it isn't signed):
choose "More info" > "Run anyway". Or put the four files in place yourself:
"AimTrainer.exe install" does only the copying.

You can also start it from the game: Practice Session, game type
"Aim Trainer", any DM or CTF map.


IN THE GAME
-----------
Esc            the Aim Trainer window (instead of UT's menu):
                 map, course, weapon (Enhanced Shock Rifle / Sniper / ...),
                 mode, range, position, movement, session length, number
                 of targets, mouse sensitivity, target model (random or a
                 fixed model with skin and face), team colour, hit sound,
                 headshot announcer, kill streak sound.
                 Buttons: Start, UT Menu (UT's own menu), Main Menu,
                 Exit UT, Resume.
Fire           start a session (3-2-1), and again after the results.

Course    (DM-AimRange) Flat Range: the flat hall.
          High Ground: platforms above and below you, joined by ramps.
          Airborne: targets dodge onto kicker pads and fly across
          the field; only targets flying from a pad can be hit.
          Close / Mid / Far mean the same distances in every course
          (on Airborne: where you stand in front of the pad field).
Mode      Duel: targets die and come back elsewhere.
          Tracking: they never die; score damage over time.
Position  Fixed: you stand at the firing line and the targets move
          downrange (default).
          Free roam: move around as in a normal game (on DM-AimRange
          the targets still stay down the range).

Headshot announcer  "Head Shot!!" as in UT, with the weapons that can
                    headshot (Sniper Rifle, Ripper).
Kill streak sound   a chime that climbs with each kill in a row. Kills
                    must be less than 1.5 s apart (time with no target up
                    doesn't count); the first kill plays nothing.

Hitboxes match IG+ servers: a crouching target's hitbox shrinks to about
65% of its height, and Sniper headshots start at 0.66 of the height.
Movement  Recorded: real players (default). Synthetic: made up. Mixed.

Score is the damage you deal (a kill = 100). Accuracy is hits / shots.
Your best 10 results for each combination of settings are kept in
System\\AimTrainer.ini.

Console commands, if you like binding keys: mutate at help


UNINSTALL
---------
AimTrainer.exe uninstall   (removes the four files; settings and
highscores in System\\AimTrainer.ini are kept)
"""


def run(cmd):
    p = subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=True, encoding="latin-1")
    if p.returncode != 0:
        print(p.stdout + p.stderr)
        sys.exit("Failed: " + " ".join(cmd[:2]))
    return p.stdout


def make_icon(path):
    from PIL import Image, ImageDraw
    size = 256
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c, w = size // 2, 18
    d.ellipse([20, 20, size - 20, size - 20], outline=(230, 40, 40, 255), width=w)
    d.ellipse([c - 14, c - 14, c + 14, c + 14], fill=(230, 40, 40, 255))
    for a, b in (((c, 0), (c, 70)), ((c, size - 70), (c, size)), ((0, c), (70, c)), ((size - 70, c), (size, c))):
        d.line([a, b], fill=(240, 240, 240, 255), width=w)
    img.save(path, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])


def main():
    # 1. the package, compiled with this workspace's 469f UCC
    run([sys.executable, os.path.join(ROOT, "AimTrainer", "Tools", "build.py")])
    for src, _ in FILES:
        if not os.path.exists(src):
            sys.exit("Missing " + src)

    if os.path.exists(WORK):
        shutil.rmtree(WORK)
    os.makedirs(WORK)
    for src, name in FILES:
        shutil.copy2(src, os.path.join(WORK, name))
    icon = os.path.join(WORK, "AimTrainer.ico")
    make_icon(icon)

    # 2. the exe with the files inside
    exe = os.path.join(REL, "AimTrainer.exe")
    cmd = [CSC, "/nologo", "/target:winexe", "/optimize+", "/out:" + exe, "/win32icon:" + icon,
           "/reference:System.Windows.Forms.dll"]
    for _, name in FILES:
        cmd.append("/resource:%s,AT.%s" % (os.path.join(WORK, name), name))
    cmd.append(os.path.join(LAUNCHER, "AimTrainerLauncher.cs"))
    run(cmd)

    # 3. readme and zip
    readme = os.path.join(REL, "README.txt")
    with open(readme, "w", encoding="utf-8", newline="\r\n") as f:
        f.write(README)
    zpath = os.path.join(REL, "AimTrainer.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        z.write(exe, "AimTrainer.exe")
        z.write(readme, "README.txt")
    shutil.rmtree(WORK)
    for p in (exe, readme, zpath):
        print("%8.0f KB  %s" % (os.path.getsize(p) / 1024, p))


if __name__ == "__main__":
    main()
