"""Run the trainer in test mode as a fresh install would (UT's Default.ini settings,
no saved AimTrainer.ini), and report whether targets spawn and move.

Your System\\AimTrainer.ini (settings, highscores) is set aside for the run and
always put back.

    python AimTrainer/Tools/test_fresh.py [seconds]
"""
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SYSTEM = os.path.join(ROOT, "System")
BUILD = os.path.join(ROOT, "AimTrainer", "Build")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atpaths  # noqa: E402
# content (maps, textures, ...) read from the main install, as a path relative to System
MAIN = os.path.relpath(atpaths.get("main_install"), SYSTEM).replace(os.sep, "/")
EXE = os.path.join(SYSTEM, "AimTrainerUT.exe")


def fresh_ini():
    lines = open(os.path.join(SYSTEM, "Default.ini"), encoding="latin-1").read().splitlines()
    out = []
    for l in lines:
        m = re.match(r"Paths=\.\./(Maps|Textures|Sounds|Music)/(\*\.\w+)\s*$", l)
        if m:
            out += [l, "Paths=%s/%s/%s" % (MAIN, m.group(1), m.group(2))]
        elif l.startswith("CachePath="):
            out.append("CachePath=%s/Cache" % MAIN)
        elif l.startswith("StartupFullscreen="):
            out.append("StartupFullscreen=False")
        elif l.startswith("FirstRun="):
            out.append("FirstRun=469")       # no first-run setup wizard
        else:
            out.append(l)
    ini = os.path.join(BUILD, "Fresh.ini")
    open(ini, "w", encoding="latin-1").write("\n".join(out) + "\n")
    user = os.path.join(BUILD, "FreshUser.ini")
    shutil.copy2(os.path.join(SYSTEM, "DefUser.ini"), user)
    return ini, user


def main():
    secs = float(sys.argv[1]) if len(sys.argv) > 1 else 40
    ini, user = fresh_ini()
    mine = os.path.join(SYSTEM, "AimTrainer.ini")
    held = os.path.join(BUILD, "AimTrainer.ini.held")
    log = os.path.join(SYSTEM, "ATFresh.log")
    if os.path.exists(held):
        sys.exit("A held AimTrainer.ini already exists in " + held + "; put it back first.")
    had_mine = os.path.exists(mine)
    if had_mine:
        shutil.move(mine, held)
    try:
        marker = os.path.join(SYSTEM, "Running.ini")
        if os.path.exists(marker):
            os.remove(marker)
        p = subprocess.Popen([EXE, "DM-AimRange?game=AimTrainer.ATGame?ATTest=1?ATTargets=3",
                              "ini=" + ini, "userini=" + user, "log=ATFresh.log", "-nosound", "-forceflush"],
                             cwd=SYSTEM, stdin=subprocess.DEVNULL)
        try:
            p.wait(timeout=secs)
        except subprocess.TimeoutExpired:
            p.kill()
            p.wait()
        time.sleep(1)
        if os.path.exists(marker):
            os.remove(marker)
    finally:
        if os.path.exists(mine):
            os.remove(mine)          # the fresh run's own AimTrainer.ini
        if had_mine:
            shutil.move(held, mine)
    text = open(log, encoding="utf-8", errors="replace").read()
    errors = [l for l in text.splitlines() if re.search(r"Accessed None|ScriptWarning|Critical: [A-Z]", l)]
    targets = {}
    for l in text.splitlines():
        p = l.split()
        if len(p) > 12 and p[1] == "ATTEST" and p[3] == "2":
            targets.setdefault(p[4], []).append(float(p[8]))
    print("errors:", len(errors))
    for e in errors[:5]:
        print("  ", e)
    for slot, speeds in sorted(targets.items()):
        print("target %s: %d samples in session, avg speed %.0f" % (slot, len(speeds), sum(speeds) / len(speeds)))
    if not targets:
        print("NO TARGETS in the session")
    print("AimTrainer.ini restored:", os.path.exists(mine) == had_mine)


if __name__ == "__main__":
    main()
