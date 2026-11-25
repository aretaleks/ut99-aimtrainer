"""Generate the kill-streak chimes (AimTrainer/Sounds/Streak1..4.wav).

    python AimTrainer/Tools/make_sounds.py

Short metallic "tink" sounds that climb in pitch and get brighter with each
tier, in the spirit of the escalating kill sound in Valorant (made from
scratch here, nothing taken from it). Tier 1 is the 2nd kill of a streak,
tier 4 the 5th and every kill after it. The package imports them with
#exec AUDIO IMPORT (see ATGame.uc).
"""
import math
import os
import struct
import wave

RATE = 22050
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Sounds")

# base pitch per tier: rising major-ish steps (A5, C#6, E6, A6)
BASES = [880.0, 1108.7, 1318.5, 1760.0]
# bell-like inharmonic partials: (ratio, relative amplitude, decay rate 1/s)
PARTIALS = [(1.0, 1.0, 9.0), (2.0, 0.35, 14.0), (2.76, 0.30, 18.0), (5.40, 0.12, 30.0)]


def chime(tier):
    base = BASES[tier]
    length = 0.30 + 0.06 * tier
    n = int(RATE * length)
    out = []
    for i in range(n):
        t = i / RATE
        v = 0.0
        for ratio, amp, decay in PARTIALS:
            v += amp * math.sin(2 * math.pi * base * ratio * t) * math.exp(-decay * t)
        # higher tiers: a second, octave-up voice a few ms later (brighter, "more")
        if tier >= 2:
            t2 = t - 0.035
            if t2 > 0:
                v += 0.35 * (tier - 1) / 2 * math.sin(2 * math.pi * base * 2 * t2) * math.exp(-11.0 * t2)
        # top tier: a slow shimmer on the tail
        if tier == 3:
            v *= 1.0 + 0.25 * math.sin(2 * math.pi * 18 * t)
        # a crisp click at the start
        if t < 0.004:
            v += 0.6 * (1 - t / 0.004) * math.sin(2 * math.pi * 4200 * t)
        attack = min(1.0, t / 0.002)
        out.append(v * attack)
    peak = max(abs(x) for x in out)
    gain = (0.55 + 0.1 * tier) / peak
    return [x * gain for x in out]


def main():
    os.makedirs(OUT, exist_ok=True)
    for tier in range(4):
        path = os.path.join(OUT, "Streak%d.wav" % (tier + 1))
        samples = chime(tier)
        with wave.open(path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
        print(path, len(samples))


if __name__ == "__main__":
    main()
