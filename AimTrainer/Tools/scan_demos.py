"""List which packages each demo needs, to skip demos that crash playback.

Demos recorded on servers running some anti-cheat/loader mods (NPLoader) crash the game
when played back: the mod's native functions aren't available during demo playback.
A demo's header names the packages it needs, so they can be found without playing it.

    python AimTrainer/Tools/scan_demos.py            # summary
    python AimTrainer/Tools/scan_demos.py --verbose  # per demo
"""
import argparse
import glob
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import atpaths  # noqa: E402

DEMO_ROOT = os.environ.get("AT_DEMO_ROOT") or os.path.join(atpaths.get("main_install"), "System")
# substrings of package names whose demos crash playback
BAD = ("NPLoader",)


def bit_shifts(data):
    """The demo stream is bit packed: names start at any bit. Yield the data shifted by 0-7 bits."""
    import numpy as np
    a = np.frombuffer(data, dtype=np.uint8).astype(np.uint16)
    for s in range(8):
        yield (((a[:-1] >> s) | (a[1:] << (8 - s))) & 0xFF).astype(np.uint8).tobytes()


def bad_reason(path, head=3 * 1024 * 1024):
    with open(path, "rb") as f:
        data = f.read(head)
    for x in bit_shifts(data):
        for b in BAD:
            if b.encode() in x:
                return b
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()
    demos = sorted(glob.glob(os.path.join(DEMO_ROOT, "*.dem")) + glob.glob(os.path.join(DEMO_ROOT, "Demos", "*.dem")))
    reasons = Counter()
    for d in demos:
        r = bad_reason(d)
        reasons[r] += 1
        if args.verbose or r:
            print("%-10s %s" % (r or "ok", os.path.basename(d)))
    print(dict(reasons))


if __name__ == "__main__":
    main()
