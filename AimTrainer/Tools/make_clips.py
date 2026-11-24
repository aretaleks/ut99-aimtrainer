"""Turn recorded demo movement into clips for the aim trainer targets.

Reads AimTrainer/Recordings/*.txt (written by record_demos.py) and writes
System/AimTrainerMoves.ini, which ATMoves loads.

A clip is a few seconds of one enemy player moving while the demo's recorder
could see them. Movement is stored in the opponent frame: F = velocity towards
the recorder, R = velocity to the side. The trainer replays it relative to
the trainee, so the target strafes, dodges and jumps the way that player did
against the recorder. Clips are sorted from calm to hectic (direction changes
and dodges per second) and the trainer picks a slice of that order by
difficulty.

    python AimTrainer/Tools/make_clips.py
    python AimTrainer/Tools/make_clips.py --stats     # also print what was found
"""
import argparse
import glob
import math
import os
import random
from collections import defaultdict

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REC_DIR = os.path.join(ROOT, "AimTrainer", "Recordings")
OUT_INI = os.path.join(ROOT, "System", "AimTrainerMoves.ini")

ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz!#$%&()*+,-./:<>?@[]^_{|}~"
RATE = 20.0                 # samples per second in the clips
CLIP_MIN = 2.5
CLIP_TRY = (9.0, 7.0, 5.0, 3.5, 2.5)   # window lengths tried at each spot, longest first
CATEGORIES = ("long strafe", "ADAD", "mixed", "dodge-heavy")
MAX_CLIPS = 3000            # ATMoves.Clip array size
DODGE_ANIMS = ("dodgel", "dodger", "dodgeb", "dodgef", "flip")
JUMP_ANIMS = ("jumpsmfr", "jumplgfr")
AIR_ANIMS = DODGE_ANIMS + JUMP_ANIMS + ("duckwlks", "duckwlkl")


def enc(v):
    i = int(round(v / 25.0)) + 40
    return ALPHABET[max(0, min(80, i))]


def load(path):
    """Returns (viewer samples, {player id: samples}) for one recording."""
    viewer = []
    players = defaultdict(list)
    t = None
    vteam = 255
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            try:
                if p[0] == "F" and len(p) >= 12:
                    # demo time runs in real seconds; physics in game seconds (x1.1 in
                    # hardcore). Work in game time so velocities match the trainer's.
                    # udemo folds its playback speed into TimeDilation, so the game
                    # speed is TimeDilation / playback speed.
                    td = float(p[12]) if len(p) >= 13 else 1.0
                    if len(p) >= 14 and float(p[13]) > 0:
                        td /= float(p[13])
                    t = float(p[1]) * td
                    vteam = int(p[3])
                    viewer.append((t, float(p[4]), float(p[5]), float(p[6])))
                elif p[0] == "P" and len(p) >= 13 and t is not None:
                    players[int(p[1])].append(dict(
                        t=t, team=int(p[2]), x=float(p[3]), y=float(p[4]), z=float(p[5]),
                        los=int(p[11]), anim=p[12].lower(), vteam=vteam))
            except ValueError:
                continue
    return viewer, players


def split_tracks(samples):
    """Split a player's samples where they vanish, respawn or teleport."""
    tracks, cur = [], []
    for s in samples:
        if cur:
            prev = cur[-1]
            dt = s["t"] - prev["t"]
            d = math.hypot(s["x"] - prev["x"], s["y"] - prev["y"])
            if dt <= 0:
                continue
            if dt > 0.25 or d > 1300 * dt + 60 or abs(s["z"] - prev["z"]) > 900 * dt + 60:
                if len(cur) > 10:
                    tracks.append(cur)
                cur = []
        cur.append(s)
    if len(cur) > 10:
        tracks.append(cur)
    return tracks


def interp(arr, key_t, t, keys):
    """Linear interpolation of dict samples (sorted by key_t) at time t."""
    lo, hi = 0, len(arr) - 1
    if t <= arr[0][key_t]:
        return {k: arr[0][k] for k in keys}
    if t >= arr[-1][key_t]:
        return {k: arr[-1][k] for k in keys}
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if arr[mid][key_t] <= t:
            lo = mid
        else:
            hi = mid
    a, b = arr[lo], arr[hi]
    w = (t - a[key_t]) / max(1e-6, b[key_t] - a[key_t])
    out = {k: a[k] + (b[k] - a[k]) * w for k in keys if isinstance(a[k], float)}
    for k in keys:
        if k not in out:
            out[k] = a[k] if w < 0.5 else b[k]
    return out


def resample(track, viewer):
    """20 Hz samples with position-derived velocity in the opponent frame."""
    t0, t1 = track[0]["t"], track[-1]["t"]
    n = int((t1 - t0) * RATE)
    if n < int(CLIP_MIN * RATE) + 2:
        return []
    vdicts = [dict(t=v[0], x=v[1], y=v[2], z=v[3]) for v in viewer]
    pos = [interp(track, "t", t0 + i / RATE, ("x", "y", "z", "los", "anim", "team", "vteam")) for i in range(n)]
    out = []
    for i in range(1, n - 1):
        a, b, c = pos[i - 1], pos[i], pos[i + 1]
        vx = (c["x"] - a["x"]) * RATE / 2
        vy = (c["y"] - a["y"]) * RATE / 2
        vz = (c["z"] - a["z"]) * RATE / 2
        v = interp(vdicts, "t", t0 + i / RATE, ("x", "y", "z"))
        fx, fy = v["x"] - b["x"], v["y"] - b["y"]
        dist = math.hypot(fx, fy)
        if dist < 1:
            fx, fy, dist = 1.0, 0.0, 1.0
        fx, fy = fx / dist, fy / dist
        rx, ry = fy, -fx            # F cross Z, as in ATTarget
        out.append(dict(
            f=vx * fx + vy * fy, r=vx * rx + vy * ry, vz=vz, dist=dist,
            los=b["los"], anim=b["anim"], enemy=(b["team"] != b["vteam"] or b["team"] == 255)))
    return out


def classify(samples):
    """Per sample state: w walk, c crouch (walking ducked), a air, j jump start,
    d dodge start; and launch Z."""
    st, lz = [], []
    air = False
    for i, s in enumerate(samples):
        anim = s["anim"]
        in_air_anim = anim.startswith(AIR_ANIMS)
        rising = s["vz"] > 90
        if not air and rising and (in_air_anim or s["vz"] > 140):
            air = True
            if anim.startswith(DODGE_ANIMS) or math.hypot(s["f"], s["r"]) > 520:
                st.append("d")
                lz.append(160.0)
            else:
                st.append("j")
                lz.append(max(200.0, min(400.0, s["vz"] + 60)))
            continue
        # landed: no vertical movement for two samples (the falling animation is
        # also DuckWlk, so the animation can't tell)
        if air and abs(s["vz"]) < 40 and i > 0 and abs(samples[i - 1]["vz"]) < 40:
            air = False
        if air:
            st.append("a")
        elif anim.startswith("duck") and math.hypot(s["f"], s["r"]) < 200:
            # crouch-walking (UT: 30 % speed); DuckWlk at running speed is the
            # in-air / landing animation instead
            st.append("c")
        else:
            st.append("w")
        lz.append(0.0)
    # a real crouch lasts a moment: drop 1-2 sample blips
    i = 0
    while i < len(st):
        if st[i] == "c":
            j = i
            while j < len(st) and st[j] == "c":
                j += 1
            if j - i < 3:
                for k in range(i, j):
                    st[k] = "w"
            i = j
        else:
            i += 1
    return st, lz


def score_clip(samples, st):
    """How hectic a clip is: lateral direction changes and dodges per second."""
    secs = len(samples) / RATE
    changes, side = 0, 0
    for s in samples:
        if s["r"] > 150 and side <= 0:
            changes += side < 0
            side = 1
        elif s["r"] < -150 and side >= 0:
            changes += side > 0
            side = -1
    dodges = sum(1 for c in st if c == "d")
    jumps = sum(1 for c in st if c == "j")
    lateral = sum(abs(s["r"]) for s in samples) / len(samples) / 400.0
    return (changes + 1.5 * dodges + 0.5 * jumps) / secs + 0.5 * lateral


def cut_clips(samples):
    """Windows where an enemy is visible, at fighting range, moving like a player."""
    clips = []
    i = 0
    n = len(samples)
    step = int(CLIP_MIN * RATE)
    while i + step <= n:
        # the longest window that qualifies, so strafe patterns can play out
        for secs in CLIP_TRY:
            win = samples[i:i + int(secs * RATE)]
            if len(win) >= int(secs * RATE) and window_ok(win):
                clips.append(win)
                i += len(win)
                break
        else:
            i += max(1, step // 3)
    return clips


def window_ok(win):
    return (
        all(s["enemy"] for s in win)
        and sum(s["los"] for s in win) >= 0.7 * len(win)
        and all(250 < s["dist"] < 3500 for s in win)
        and max(math.hypot(s["f"], s["r"]) for s in win) < 950      # no kickers / boots
        and max(abs(s["vz"]) for s in win) < 900
        and sum(math.hypot(s["f"], s["r"]) for s in win) / len(win) > 150   # not standing still
        and duel_like(win)
    )


def category(win, st):
    """0 long strafe (holds one side 1.3 s+), 1 ADAD (quick direction changes),
    2 mixed, 3 dodge-heavy."""
    secs = len(win) / RATE
    dodges = st.count("d") / secs
    best = run = side = 0
    changes, last = 0, 0
    for w in win:
        sd = 1 if w["r"] > 150 else -1 if w["r"] < -150 else 0
        if sd and sd == side:
            run += 1
        elif sd:
            side, run = sd, 1
        best = max(best, run)
        if sd and last and sd != last:
            changes += 1
        if sd:
            last = sd
    if dodges >= 0.55:
        return 3
    if best / RATE >= 1.3:
        return 0
    if changes / secs >= 1.0 and dodges < 0.4:
        return 1
    return 2


def duel_like(win):
    """CTF players often run at (or past) the recorder on their way to a flag. In a duel
    people mostly strafe: keep windows whose net approach/retreat is small and whose
    sideways movement is at least as strong as the toward/away movement."""
    n = len(win)
    mean_f = sum(s["f"] for s in win) / n
    abs_f = sum(abs(s["f"] - mean_f) for s in win) / n
    abs_r = sum(abs(s["r"]) for s in win) / n
    return abs(mean_f) < 180 and abs_r > 150 and abs_r >= 0.9 * abs_f


def encode(win):
    st, lz = classify(win)
    # remove what is left of the net drift towards / away from the opponent, keep the
    # back-and-forth (W/S taps mixed into the strafing)
    mean_f = sum(w["f"] for w in win) / len(win)
    s = "".join(st[i] + enc(w["f"] - mean_f) + enc(w["r"]) + enc(lz[i]) for i, w in enumerate(win))
    return s, category(win, st), st


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stats", action="store_true")
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    random.seed(args.seed)

    files = sorted(glob.glob(os.path.join(REC_DIR, "*.txt")))
    if not files:
        raise SystemExit("No recordings in " + REC_DIR + "; run record_demos.py first.")
    all_clips = []
    per_demo = {}
    for path in files:
        viewer, players = load(path)
        if not viewer:
            continue
        n_before = len(all_clips)
        for pid, samples in players.items():
            for track in split_tracks(samples):
                rs = resample(track, viewer)
                for win in cut_clips(rs):
                    s, cat, st = encode(win)
                    all_clips.append((cat, s, os.path.basename(path), st))
        per_demo[os.path.basename(path)] = len(all_clips) - n_before

    if len(all_clips) > MAX_CLIPS:
        random.shuffle(all_clips)
        all_clips = all_clips[:MAX_CLIPS]
    # grouped by pattern; ATMoves picks a pattern, then a random clip in it
    random.shuffle(all_clips)
    all_clips.sort(key=lambda c: c[0])

    lines = ["[AimTrainer.ATMoves]", "SampleRate=%g" % RATE,
             "Source=%d clips from %d recorded demos" % (len(all_clips), len(per_demo))]
    start = 0
    for k in range(len(CATEGORIES)):
        count = sum(1 for c in all_clips if c[0] == k)
        lines.append("CatStart[%d]=%d" % (k, start))
        lines.append("CatCount[%d]=%d" % (k, count))
        start += count
    for i, c in enumerate(all_clips):
        lines.append("Clip[%d]=%s" % (i, c[1]))
    with open(OUT_INI, "w", encoding="latin-1", newline="\r\n") as f:
        f.write("\n".join(lines) + "\n")

    secs = sum(len(c[1]) / 4 / RATE for c in all_clips)
    print("Wrote %d clips (%.0f s of movement) to %s" % (len(all_clips), secs, OUT_INI))
    if args.stats and all_clips:
        for d, n in sorted(per_demo.items()):
            print("  %4d  %s" % (n, d))
        for k, name in enumerate(CATEGORIES):
            sel = [c for c in all_clips if c[0] == k]
            secs_k = sum(len(c[3]) / RATE for c in sel)
            print("  %-12s %4d clips  %5.0f s  avg %.1f s  dodges %.2f/s" % (
                name, len(sel), secs_k, secs_k / max(1, len(sel)),
                sum(c[3].count("d") for c in sel) / max(1.0, secs_k)))
        d = sum(c[3].count("d") for c in all_clips)
        j = sum(c[3].count("j") for c in all_clips)
        c = sum(c[3].count("c") for c in all_clips)
        print("dodges %d (%.2f/s)  jumps %d (%.2f/s)  crouched %.1f s (%.1f%% of the time)" % (
            d, d / secs, j, j / secs, c / RATE, 100.0 * c / RATE / secs))


if __name__ == "__main__":
    main()
