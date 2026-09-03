#!/usr/bin/env python3
"""Generate chiptune WAV samples for omarchy-neonbubble."""
import math
import os
import random
import struct
import wave

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sfx")
SR = 22050


def write_wav(name, samples):
    path = os.path.join(OUT, name + ".wav")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = b"".join(struct.pack("<h", max(-32767, min(32767, int(s)))) for s in samples)
        w.writeframes(frames)
    print(path)


def tone(freq, ms, vol=0.35, decay=True):
    n = int(SR * ms / 1000)
    out = []
    for i in range(n):
        t = i / SR
        env = (1 - i / n) if decay else 1
        out.append(math.sin(2 * math.pi * freq * t) * vol * env * 32767)
    return out


def chirp(f0, f1, ms, vol=0.3):
    n = int(SR * ms / 1000)
    out = []
    for i in range(n):
        t = i / max(1, n - 1)
        f = f0 + (f1 - f0) * t
        env = 1 - i / n
        out.append(math.sin(2 * math.pi * f * (i / SR)) * vol * env * 32767)
    return out


def noise(ms, vol=0.15):
    random.seed(7)
    n = int(SR * ms / 1000)
    return [(random.random() * 2 - 1) * vol * (1 - i / n) * 32767 for i in range(n)]


if __name__ == "__main__":
    # A bubble sticking: a short, soft knock.
    write_wav("stick", tone(240, 45, 0.24) + noise(14, 0.07))
    # A cluster popping: the sound the whole game is built around, so it is the
    # one with a rising tail rather than a flat blip.
    write_wav("pop", chirp(520, 1180, 90, 0.36) + tone(1180, 45, 0.2))
    # Bubbles cut loose and falling.
    write_wav("drop", chirp(880, 220, 200, 0.3) + tone(220, 90, 0.18))
    # The shot leaving the gun.
    write_wav("fire", chirp(300, 720, 60, 0.26))
    # Bouncing off a side wall — very quiet, it happens constantly.
    write_wav("wall", tone(420, 22, 0.12))
    # The ceiling coming down: the pressure sound, so it descends.
    write_wav("descend", chirp(400, 130, 260, 0.3) + tone(130, 120, 0.2))
    # The meter filling: a short rising two-note, so you know without looking.
    write_wav("charged", tone(660, 60, 0.26) + tone(990, 90, 0.28))
    # A bomb going off is the loudest thing on the board.
    write_wav("bomb", noise(60, 0.28) + chirp(300, 90, 260, 0.34) + tone(90, 120, 0.22))
    # A wildcard deciding what it is.
    write_wav("wild", chirp(520, 1560, 150, 0.3) + tone(1560, 70, 0.22))
    # A star arriving, and a star collected — the second is the reward.
    write_wav("star_in", tone(1320, 70, 0.18) + tone(1760, 60, 0.16))
    write_wav("star", chirp(880, 2640, 220, 0.36) + tone(2200, 110, 0.28))
    write_wav("start", chirp(220, 880, 180, 0.3))
    write_wav("gameover", chirp(660, 165, 220, 0.26) + tone(165, 140, 0.2))
    # Clearing the board is the best thing that can happen here.
    write_wav("cleared", chirp(440, 1760, 300, 0.38) + tone(1320, 120, 0.3)
              + tone(1760, 180, 0.28))
