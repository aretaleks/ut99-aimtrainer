"""Compile the AimTrainer packages with UCC.

Uses a copy of UnrealTournament.ini with the package added to EditPackages, so the
game's own ini is never changed.

    python AimTrainer/Tools/build.py              # System/AimTrainer.u (the game)
    python AimTrainer/Tools/build.py ATRecorder   # ATRecorder.u (demo recorder, needs udemo)
    python AimTrainer/Tools/build.py ATRecorder --runtime Rec469e
        # build it with another UT copy inside this folder (the 469e one used for
        # recording); the sources are copied next to that copy's System folder
"""
import argparse
import os
import re
import shutil
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
# package -> packages it needs loaded before it (besides the stock ones)
PACKAGES = {"AimTrainer": [], "ATRecorder": ["udemo"]}


def make_ini(system, build_dir, package):
    os.makedirs(build_dir, exist_ok=True)
    with open(os.path.join(system, "UnrealTournament.ini"), "r", encoding="latin-1") as f:
        lines = f.read().splitlines()
    names = PACKAGES[package] + [package]
    drop = re.compile(r"\s*EditPackages\s*=\s*(%s)\s*$" % "|".join(names), re.I)
    out, last_edit = [], -1
    for line in lines:
        if drop.match(line):
            continue
        out.append(line)
        if re.match(r"\s*EditPackages\s*=", line, re.I):
            last_edit = len(out) - 1
    if last_edit < 0:
        sys.exit("No EditPackages lines found in UnrealTournament.ini")
    for i, name in enumerate(names):
        out.insert(last_edit + 1 + i, "EditPackages=" + name)
    dst = os.path.join(build_dir, "Build-%s.ini" % package)
    with open(dst, "w", encoding="latin-1") as f:
        f.write("\n".join(out) + "\n")
    return dst


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("package", nargs="?", default="AimTrainer", choices=sorted(PACKAGES))
    ap.add_argument("--runtime", default="", help="UT copy inside this folder to build with")
    args = ap.parse_args()
    package = args.package

    ut_root = os.path.join(ROOT, args.runtime) if args.runtime else ROOT
    system = os.path.join(ut_root, "System")
    if ut_root != ROOT:
        src = os.path.join(ROOT, package, "Classes")
        dst = os.path.join(ut_root, package, "Classes")
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
    ini = make_ini(system, os.path.join(ut_root, "AimTrainer", "Build") if ut_root != ROOT
                   else os.path.join(ROOT, "AimTrainer", "Build"), package)
    pkg = os.path.join(system, package + ".u")
    if os.path.exists(pkg):
        os.remove(pkg)
    proc = subprocess.run(
        [os.path.join(system, "UCC.exe"), "make", "ini=" + ini, "-silent"],
        cwd=system, stdin=subprocess.DEVNULL, capture_output=True, text=True,
        encoding="latin-1", timeout=600)
    text = proc.stdout + proc.stderr
    keep = [l for l in text.splitlines()
            if package in l or "Error" in l or "Warning" in l or "Success" in l or "Failure" in l]
    print("\n".join(keep))
    ok = os.path.exists(pkg)
    print("BUILD", "OK" if ok else "FAILED", pkg)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
