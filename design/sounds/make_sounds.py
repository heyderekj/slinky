#!/usr/bin/env python3
"""Slinky's sounds, synthesized: a spring toy that locks things away.

Two ingredients. The spring: a stretched coil rings as a falling "sproing" chirp with a little wobble
(the sound a real Slinky makes, and where the classic laser "pew" came from). The latch: a short, dry,
solid click with a low body, so it feels secure rather than cute.

    python3 design/sounds/make_sounds.py   → Slinky/Sounds/*.caf (AAC, mono, a few KB each)
"""
import subprocess
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'Slinky' / 'Sounds'
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack=0.002, decay=0.08):
    x = np.arange(n) / SR
    a = np.clip(x / attack, 0, 1)
    return a * np.exp(-x / decay)


def sproing(dur=0.32, f_hi=2400.0, f_lo=520.0, wobble=7.0, decay=0.12, gain=1.0, rise=False):
    """A spring's chirp: exponential glide with a wobble, plus a quieter inharmonic coil partial."""
    x = t(dur)
    k = np.log(f_lo / f_hi) / dur
    glide = f_hi * np.exp(k * x)
    if rise:
        glide = glide[::-1]
    f = glide * (1 + 0.035 * np.sin(2 * np.pi * wobble * x) * np.exp(-x / 0.15))
    phase = 2 * np.pi * np.cumsum(f) / SR
    tone = np.sin(phase) + 0.28 * np.sin(2.76 * phase) + 0.12 * np.sin(5.4 * phase)
    # A faint echo, like the coil ringing back.
    out = tone * env(len(x), 0.003, decay)
    d = int(0.045 * SR)
    out[d:] += 0.25 * out[:-d]
    # Always fade to nothing, so a rising chirp never stops mid-tone.
    tail = int(0.04 * SR)
    out[-tail:] *= np.linspace(1, 0, tail) ** 2
    return gain * out


def latch(gain=1.0, body=140.0, bright=2600.0):
    """A dry, solid click: a tick of filtered noise, a short metal ping and a low thump (kept above ~180 Hz
    so laptop speakers carry it)."""
    n = int(0.12 * SR)
    noise = rng.standard_normal(n)
    noise = np.convolve(noise, np.ones(6) / 6, mode='same')  # soften the hiss
    tick = noise * env(n, 0.0004, 0.006)
    x = t(0.12)
    ping = np.sin(2 * np.pi * bright * x) * env(n, 0.0006, 0.018) * 0.35
    thump = np.sin(2 * np.pi * body * x) * env(n, 0.001, 0.035) * 0.9
    return gain * (tick * 0.8 + ping + thump)


def mix(length, *parts):
    out = np.zeros(int(SR * length))
    for start, sig in parts:
        i = int(start * SR)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[: j - i]
    return out


def finish(sig, peak=0.5):
    sig = sig - np.mean(sig)
    fade = int(0.012 * SR)
    sig[-fade:] *= np.linspace(1, 0, fade)
    return sig / (np.max(np.abs(sig)) or 1) * peak


SOUNDS = {
    # Saved: a small spring tucks it away, and the latch closes.
    'saved': lambda: mix(0.42,
                         (0.0, sproing(0.18, 2100, 700, decay=0.07, gain=0.55)),
                         (0.13, latch(0.9, body=230, bright=3000))),
    # Imported: a Slinky walking down the stairs, one step per few items, then the latch.
    'imported': lambda: mix(0.95,
                            *[(i * 0.12, sproing(0.16, 2300 - i * 260, 760 - i * 70, decay=0.06, gain=0.5 - i * 0.04))
                              for i in range(5)],
                            (0.66, latch(1.0, body=210, bright=2800))),
    # Locked: the coil draws in, then a firm double click of the bolt.
    'locked': lambda: mix(0.62,
                          (0.0, sproing(0.3, 1500, 420, wobble=9, decay=0.1, gain=0.45)),
                          (0.36, latch(0.75, body=200, bright=2200)),
                          (0.43, latch(1.0, body=180, bright=1900))),
    # Unlocked: the latch lets go, and the spring springs open, rising.
    'unlocked': lambda: mix(0.6,
                            (0.0, latch(0.8, body=240, bright=3200)),
                            (0.09, sproing(0.34, 2600, 480, wobble=6, decay=0.16, gain=0.6, rise=True))),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for name, make in SOUNDS.items():
        sig = finish(make())
        wav = OUT / f'{name}.wav'
        with wave.open(str(wav), 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((sig * 32767).astype('<i2').tobytes())
        caf = OUT / f'{name}.caf'
        subprocess.run(['afconvert', '-f', 'caff', '-d', 'aac', '-b', '64000', str(wav), str(caf)], check=True)
        wav.unlink()
        print(f'{name}: {caf.stat().st_size} bytes')


if __name__ == '__main__':
    main()
