"""Play demos in UT with the recording console and collect player movement.

Starts UnrealTournament.exe with copies of the ini files (the game's own ini files
are not changed), Console=ATRecorder.ATRecConsole, a small window and no sound.
The console plays every demo in the list and writes "ATRec:" lines to the log.
Each demo's samples are then split into AimTrainer/Recordings/<demo>.txt.

    python AimTrainer/Tools/record_demos.py                 # all demos not recorded yet
    python AimTrainer/Tools/record_demos.py --match Duku --limit 3
    python AimTrainer/Tools/record_demos.py --redo           # record again
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SYSTEM = os.path.join(ROOT, "System")
WORK = os.path.join(ROOT, "AimTrainer", "Build")
REC_DIR = os.path.join(ROOT, "AimTrainer", "Recordings")
# Demos are read (never written) from the main game install (atpaths.py).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atpaths  # noqa: E402
DEMO_ROOT = os.environ.get("AT_DEMO_ROOT") or os.path.join(atpaths.get("main_install"), "System")
LOG_NAME = "ATRec.log"
# UT 469 runs one copy per program name: starting UnrealTournament.exe again hands the
# command to a game that is already open. A renamed copy keeps the two apart.
REC_EXE = "atrec_ut.exe"


def set_key(lines, section, key, value):
    """Set key=value in [section] of an ini held as a list of lines."""
    sec_re = re.compile(r"^\[(.+)\]\s*$")
    start = None
    for i, l in enumerate(lines):
        m = sec_re.match(l)
        if m and m.group(1).lower() == section.lower():
            start = i
            break
    if start is None:
        lines += ["", "[%s]" % section, "%s=%s" % (key, value)]
        return
    end = len(lines)
    for j in range(start + 1, len(lines)):
        if sec_re.match(lines[j]):
            end = j
            break
    for j in range(start + 1, end):
        if lines[j].split("=", 1)[0].strip().lower() == key.lower():
            lines[j] = "%s=%s" % (key, value)
            return
    lines.insert(end, "%s=%s" % (key, value))


def read_lines(path):
    with open(path, "r", encoding="latin-1") as f:
        return f.read().splitlines()


def write_lines(path, lines):
    with open(path, "w", encoding="latin-1") as f:
        f.write("\n".join(lines) + "\n")


def find_demos():
    demos = []
    for path in glob.glob(os.path.join(DEMO_ROOT, "*.dem")) + glob.glob(os.path.join(DEMO_ROOT, "Demos", "*.dem")):
        demos.append(os.path.abspath(path))
    return sorted(demos)


def demo_key(rel):
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", os.path.splitext(os.path.basename(rel))[0])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--match", default="", help="only demos whose name contains this")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--redo", action="store_true")
    ap.add_argument("--speed", type=float, default=10, help="playback speed (udemo driver speed)")
    ap.add_argument("--timeout", type=float, default=6 * 3600)
    ap.add_argument("--runtime", default="Rec469e" if os.path.isdir(os.path.join(ROOT, "Rec469e")) else "",
                    help="UT copy inside this folder that plays the demos (default Rec469e: "
                         "469f RC crashes on demos from NPLoader servers, 469e doesn't)")
    args = ap.parse_args()
    global SYSTEM
    if args.runtime:
        SYSTEM = os.path.join(ROOT, args.runtime, "System")
        if not os.path.exists(os.path.join(SYSTEM, "ATRecorder.u")):
            sys.exit("Build the recorder for it first: build.py ATRecorder --runtime " + args.runtime)
    print("Playing demos with", SYSTEM)

    os.makedirs(WORK, exist_ok=True)
    os.makedirs(REC_DIR, exist_ok=True)
    demos = [d for d in find_demos() if args.match.lower() in d.lower()]
    if not args.redo:
        demos = [d for d in demos if not os.path.exists(os.path.join(REC_DIR, demo_key(d) + ".txt"))]
        failed_list = os.path.join(REC_DIR, "_failed.txt")
        if os.path.exists(failed_list):
            bad = set(open(failed_list, encoding="utf-8").read().splitlines())
            demos = [d for d in demos if d not in bad]
    if args.limit:
        demos = demos[:args.limit]
    if not demos:
        print("Nothing to record.")
        return
    if len(demos) > 512:
        demos = demos[:512]

    ini = read_lines(os.path.join(SYSTEM, "UnrealTournament.ini"))
    set_key(ini, "Engine.Engine", "Console", "ATRecorder.ATRecConsole")
    set_key(ini, "WinDrv.WindowsClient", "StartupFullscreen", "False")
    set_key(ini, "WinDrv.WindowsClient", "WindowedViewportX", "640")
    set_key(ini, "WinDrv.WindowsClient", "WindowedViewportY", "480")
    # no frame cap: more drawn frames per second allow a higher demo speed
    # at the same sample spacing
    for i, l in enumerate(ini):
        if re.match(r"\s*FrameRateLimit\s*=", l, re.I):
            ini[i] = "FrameRateLimit=0"
    ini_path = os.path.join(WORK, "ATRec.ini")
    write_lines(ini_path, ini)

    user = read_lines(os.path.join(SYSTEM, "User.ini"))
    user_path = os.path.join(WORK, "ATRecUser.ini")
    write_lines(user_path, user)

    if ut_running(REC_EXE):
        sys.exit(REC_EXE + " is already running.")
    exe = rec_exe()
    log_path = os.path.join(SYSTEM, LOG_NAME)
    print("Recording %d demo(s)..." % len(demos))
    t_start = time.time()
    pending = list(demos)
    failed = []
    # A demo that crashes the game (e.g. it needs a mod's native DLL) ends that run:
    # it's skipped and the game starts again with the demos that are left.
    while pending and time.time() - t_start < args.timeout:
        rec = ["[ATRecorder.ATRecConsole]", "DemoIndex=0", "bAutoPlay=True", "bQuitWhenDone=True",
               "PlaySpeed=%g" % args.speed]
        for i, d in enumerate(pending):
            rec.append("DemoList[%d]=%s" % (i, d))
        write_lines(os.path.join(SYSTEM, "AimTrainerRec.ini"), rec)
        clear_running_marker()
        if os.path.exists(log_path):
            os.remove(log_path)
        t0 = time.time()
        proc = subprocess.Popen(
            [exe, "ini=" + ini_path, "userini=" + user_path,
             "log=" + LOG_NAME, "-nosound", "-windowed"],
            cwd=SYSTEM, stdin=subprocess.DEVNULL)
        why = watch(proc, log_path, args.timeout - (time.time() - t_start))
        clear_running_marker()
        done, last, alldone = split_log(log_path)
        if why == "finished" and not alldone:
            why = "exited early"
        print("Game run ended (%s) after %.0fs" % (why, time.time() - t0), flush=True)
        pending = [d for d in pending if d not in done]
        if why != "finished" and last in pending:
            print("  skipping (crashed or stalled):", last, flush=True)
            failed.append(last)
            pending.remove(last)
            with open(os.path.join(REC_DIR, "_failed.txt"), "a", encoding="utf-8") as f:
                f.write(last + "\n")
        elif why == "finished":
            # everything requested was played or reported as not loadable
            pending = []
    print("Done in %.0f min. %d demo(s) could not be played." % ((time.time() - t_start) / 60, len(failed)))


def window_title(name):
    out = subprocess.run(["tasklist", "/V", "/FO", "CSV", "/NH", "/FI", "IMAGENAME eq " + name],
                         capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout
    for line in out.splitlines():
        cols = [c.strip('"') for c in line.split('","')]
        if cols and cols[0].lower() == name.lower():
            return cols[-1]
    return ""


def log_crash(log_path, size):
    """The crash message if the end of the log shows one."""
    if size <= 0:
        return ""
    with open(log_path, "rb") as f:
        f.seek(max(0, size - 16384))
        tail = f.read().decode("utf-8", "replace")
    for line in tail.splitlines():
        if line.startswith("Critical: ") and len(line) > 10:
            return line[10:].strip()[:120]
        if "General protection fault" in line:
            return "General protection fault"
    return ""


def watch(proc, log_path, timeout):
    """Wait for the game; kill it on a crash dialog or when the log stops growing."""
    t0 = time.time()
    last_size, last_change = -1, time.time()
    while True:
        try:
            proc.wait(timeout=3)
            return "finished"
        except subprocess.TimeoutExpired:
            pass
        # The crash handler writes "Critical:" lines to the log before showing its
        # dialog; close the game right away instead of leaving the dialog up.
        size = os.path.getsize(log_path) if os.path.exists(log_path) else 0
        crash = log_crash(log_path, size)
        title = window_title(REC_EXE)
        if crash or "critical" in title.lower() or "recovery" in title.lower():
            proc.kill()
            proc.wait()
            return "crash: " + (crash or title)
        if size != last_size:
            last_size, last_change = size, time.time()
        elif time.time() - last_change > 120:
            proc.kill()
            proc.wait()
            return "stalled"
        if time.time() - t0 > timeout:
            proc.kill()
            proc.wait()
            return "timeout"


def ut_running(name="UnrealTournament.exe"):
    out = subprocess.run(["tasklist", "/FI", "IMAGENAME eq " + name, "/NH"],
                         capture_output=True, text=True, stdin=subprocess.DEVNULL).stdout
    return name.lower() in out.lower()


def rec_exe():
    src = os.path.join(SYSTEM, "UnrealTournament.exe")
    dst = os.path.join(SYSTEM, REC_EXE)
    if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(src)             or os.path.getmtime(dst) < os.path.getmtime(src):
        shutil.copy2(src, dst)
    # window texts are looked up under the program name
    loc_src = os.path.join(SYSTEM, "UnrealTournament.int")
    loc_dst = os.path.join(SYSTEM, os.path.splitext(REC_EXE)[0] + ".int")
    if os.path.exists(loc_src) and not os.path.exists(loc_dst):
        shutil.copy2(loc_src, loc_dst)
    return dst


def clear_running_marker():
    """469f writes System/Running.ini while the game runs and shows a Recovery Mode
    prompt at the next start if it is left behind (after a crash or a kill)."""
    marker = os.path.join(SYSTEM, "Running.ini")
    # after a kill the file can stay locked for a moment
    for _ in range(10):
        if not os.path.exists(marker) or ut_running(REC_EXE):
            return
        try:
            os.remove(marker)
            return
        except OSError:
            time.sleep(0.5)


def split_log(log_path):
    if not os.path.exists(log_path):
        sys.exit("No log written: " + log_path)
    """Write each demo's samples to Recordings/<demo>.txt.
    Returns (demos finished or reported unloadable, the demo requested last)."""
    cur, out, counts, done, alldone = None, None, {}, set(), False
    with open(log_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.lstrip("﻿")
            if not line.startswith("ATRec: "):
                continue
            body = line[7:].rstrip("\n")
            if body.startswith("REQ "):
                cur = body[4:].strip()
            elif body.startswith("BEGIN "):
                if out:
                    out.close()
                out = open(os.path.join(REC_DIR, demo_key(cur or "unknown") + ".txt"), "w", encoding="utf-8")
                out.write(body + "\n")
                counts[cur] = 0
            elif body.startswith("END"):
                if out:
                    out.close()
                    out = None
                done.add(cur)
            elif out and (body.startswith("F ") or body.startswith("P ")):
                out.write(body + "\n")
                if body.startswith("P "):
                    counts[cur] += 1
            elif body.startswith("ALLDONE"):
                alldone = True
            elif body.startswith("FAILED"):
                print("  failed to load:", body[7:])
                done.add(body[7:].strip())
    if out:
        out.close()
    for d, n in counts.items():
        print("  %-70s %8d player samples" % (os.path.basename(d), n))
    return done, cur, alldone


if __name__ == "__main__":
    main()
