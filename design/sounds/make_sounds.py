#!/usr/bin/env python3
"""Slinky's sounds, synthesized: the real sound of a Slinky, and a lock that feels solid.

Two ingredients, both literal and quiet. The coil: a Slinky's coils settling against each other make a fast,
soft ripple of tiny metallic ticks, never a "boing". The latch: a damped mechanical click with a low body and
no ringing tone, like a well-made latch or a safe's bolt. No pitch glides, no wobble, nothing cartoon.

    python3 design/sounds/make_sounds.py   → Slinky/Sounds/*.caf (AAC, mono, a few KB each)
"""
import subprocess
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'Slinky' / 'Sounds'
rng = np.random.default_rng(11)


def decay_env(n, attack, decay):
    x = np.arange(n) / SR
    return np.clip(x / attack, 0, 1) * np.exp(-x / decay)


def lowpass(sig, width):
    return np.convolve(sig, np.ones(width) / width, mode='same')


def tick(f, gain, decay=0.004):
    """One coil touching the next: a very short metallic tick (inharmonic partials, a breath of noise)."""
    n = int(0.03 * SR)
    x = np.arange(n) / SR
    metal = (np.sin(2 * np.pi * f * x) + 0.6 * np.sin(2 * np.pi * f * 1.47 * x + 1.1)
             + 0.35 * np.sin(2 * np.pi * f * 2.09 * x + 2.3))
    out = metal * decay_env(n, 0.0003, decay) * 0.5
    out += lowpass(rng.standard_normal(n), 5) * decay_env(n, 0.0001, 0.0012) * 0.45
    return gain * out


def coil(count, length, accel=1.0, gain=1.0, f_lo=2300, f_hi=3700, swell=0.35):
    """A ripple of `count` ticks over `length` seconds. accel > 1 crowds them toward the end (the coil
    closing up), < 1 spreads them out (the coil opening). Loudness swells then eases off."""
    out = np.zeros(int((length + 0.05) * SR))
    u = np.linspace(0, 1, count) ** accel
    for k, p in enumerate(u):
        i = int(p * length * SR)
        level = np.sin(np.pi * min(1, (k + 0.5) / count) ** swell * 0.999) ** 0.8
        sig = tick(rng.uniform(f_lo, f_hi), (0.55 + 0.45 * rng.random()) * level)
        out[i:i + len(sig)] += sig[: len(out) - i]
    # A faint brush of the coils sliding, under the ticks.
    brush = lowpass(rng.standard_normal(len(out)), 9) * 0.05
    shape = np.sin(np.linspace(0, np.pi, len(out)))
    return gain * (out + brush * shape)


def latch(gain=1.0, body=190.0, brightness=7, firm=1.0):
    """A damped mechanical click: a dry transient, a short muffled knock, a low body. No ring."""
    n = int(0.09 * SR)
    noise = rng.standard_normal(n)
    transient = lowpass(noise, brightness) * decay_env(n, 0.0002, 0.003)
    knock = lowpass(noise, brightness * 4) * decay_env(n, 0.0005, 0.012) * 0.9
    x = np.arange(n) / SR
    thump = np.sin(2 * np.pi * body * x) * decay_env(n, 0.0015, 0.022) * 0.8 * firm
    return gain * (transient * 0.9 + knock + thump)


def mix(length, *parts):
    out = np.zeros(int(SR * length))
    for start, sig in parts:
        i = int(start * SR)
        j = min(len(out), i + len(sig))
        out[i:j] += sig[: j - i]
    return out


def finish(sig, peak=0.45):
    sig = sig - np.mean(sig)
    # Take the edge off the very top, so it reads as metal rather than hiss.
    sig = 0.6 * sig + 0.4 * lowpass(sig, 4)
    fade = int(0.015 * SR)
    sig[-fade:] *= np.linspace(1, 0, fade) ** 2
    return sig / (np.max(np.abs(sig)) or 1) * peak


SOUNDS = {
    # Saved: a short coil settle, then the latch closes.
    'saved': lambda: mix(0.32,
                         (0.0, coil(9, 0.11, accel=1.6, gain=0.55)),
                         (0.13, latch(1.0, body=200))),
    # Imported: a longer ripple, like a Slinky pouring from one hand to the other, then the latch.
    'imported': lambda: mix(0.62,
                            (0.0, coil(26, 0.4, accel=1.25, gain=0.6, swell=0.6)),
                            (0.44, latch(1.0, body=185))),
    # Locked: the coil closes up, then the bolt: two firm clicks, the second lower and heavier.
    'locked': lambda: mix(0.6,
                          (0.0, coil(14, 0.26, accel=1.8, gain=0.5, f_lo=2000, f_hi=3300)),
                          (0.36, latch(0.7, body=210, brightness=6)),
                          (0.42, latch(1.0, body=165, brightness=10, firm=1.3))),
    # Unlocked: the latch lets go, then the coil opens out and settles.
    'unlocked': lambda: mix(0.5,
                            (0.0, latch(0.85, body=220, brightness=5)),
                            (0.07, coil(14, 0.3, accel=0.6, gain=0.5, f_lo=2500, f_hi=3900, swell=0.25))),
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
