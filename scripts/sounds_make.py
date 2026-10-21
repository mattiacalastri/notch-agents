#!/usr/bin/env python3
"""Synthesize the «Sine» kit: Sounds/sine/<cue>.wav, 16-bit mono 44.1 kHz.

Only the standard library, so anyone can rebuild or retune the kit. Each cue is a
few sine notes with a soft second harmonic, a 5 ms attack and an exponential decay.
The question is the loudest cue, opening and closing the quietest: you hear the
notch every few seconds, a question once. Nothing is sampled from anyone: the files
are under the repo's license.

Usage: python3 scripts/sounds_make.py
"""
import math
import struct
import wave
from pathlib import Path

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "Sounds" / "sine"

# cue: (peak amplitude 0..1, [(start s, frequency Hz, glide-to Hz, length s), ...])
CUES = {
    "asking":   (0.30, [(0.00, 659.3, 659.3, 0.22), (0.16, 880.0, 880.0, 0.45)]),
    "finished": (0.20, [(0.00, 1046.5, 1046.5, 0.30), (0.12, 784.0, 784.0, 0.55)]),
    "arrived":  (0.10, [(0.00, 880.0, 1318.5, 0.14)]),
    "left":     (0.08, [(0.00, 1318.5, 880.0, 0.14)]),
    "open":     (0.05, [(0.00, 1568.0, 1760.0, 0.09)]),
    "close":    (0.04, [(0.00, 1760.0, 1568.0, 0.09)]),
    "tap":      (0.08, [(0.00, 2093.0, 2093.0, 0.05)]),
}


def render(peak, notes):
    length = max(s + d for s, _, _, d in notes) + 0.02
    buf = [0.0] * int(length * SR)
    for start, f0, f1, dur in notes:
        n = int(dur * SR)
        phase = 0.0
        for i in range(n):
            t = i / SR
            f = f0 + (f1 - f0) * (i / n)
            phase += 2 * math.pi * f / SR
            env = min(1.0, t / 0.005) * math.exp(-5.0 * t / dur)
            fade = min(1.0, (n - i) / (0.01 * SR))   # no click at the end
            buf[int(start * SR) + i] += env * fade * (math.sin(phase) + 0.18 * math.sin(2 * phase))
    top = max(abs(x) for x in buf) or 1.0
    return [x / top * peak for x in buf]


def write(path, samples):
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x)) * 32767)) for x in samples))


if __name__ == "__main__":
    for cue, (peak, notes) in CUES.items():
        write(OUT / f"{cue}.wav", render(peak, notes))
        print(f"Sounds/sine/{cue}.wav")
