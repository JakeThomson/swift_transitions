"""Stage 3 numbers from a tracked zoom recording.

    python3 analyze_zoom.py run.csv

For the push and the pop of the card: the best critically damped spring
from rest (ω) for the card's width, the best general spring, and the
timing of 50 % and 90 % travel.
"""
import csv
import math
import sys

import numpy as np

SOURCE_W, SCREEN_W = 120.0, 402.0


def width(r):
    return float(r["card_r"]) - float(r["card_l"])


def segments(rows):
    out = []
    i = 0
    while i < len(rows):
        w = width(rows[i])
        if SOURCE_W + 1 < w < SCREEN_W - 1:
            j = i
            while j + 1 < len(rows) and SOURCE_W + 0.5 < width(rows[j]) < SCREEN_W - 0.5:
                j += 1
            seg = rows[max(i - 1, 0):j + 1]
            span = float(seg[-1]["t"]) - float(seg[0]["t"])
            ends = (width(seg[0]), width(seg[-1]))
            # A flight runs from one end to the other within a second;
            # anything else is the launch or a poster scrolling.
            if span < 1.2 and min(ends) < SOURCE_W + 3 and max(ends) > SCREEN_W - 3:
                name = "push" if ends[1] > ends[0] else "pop"
                out.append((name, seg))
            i = j + 1
        else:
            i += 1
    return out


def remaining(t, omega, zeta, v0):
    """Fraction of the way still to go at t for a unit spring released from 1
    with velocity v0 — positive away from the target, negative toward it."""
    if abs(zeta - 1) < 1e-6:
        return (1 + (omega + v0) * t) * np.exp(-omega * t)
    if zeta > 1:
        s = omega * math.sqrt(zeta * zeta - 1)
        r1, r2 = -omega * zeta + s, -omega * zeta - s
        a = (v0 - r2) / (r1 - r2)
        return a * np.exp(r1 * t) + (1 - a) * np.exp(r2 * t)
    wd = omega * math.sqrt(1 - zeta * zeta)
    return np.exp(-zeta * omega * t) * (np.cos(wd * t) + (v0 + zeta * omega) / wd * np.sin(wd * t))


def analyze(name, seg):
    t = np.array([float(r["t"]) for r in seg])
    w = np.array([width(r) for r in seg])
    keep = np.concatenate(([True], np.abs(np.diff(w)) > 0.05))  # drop duplicated frames
    t, w = t[keep] - t[0], w[keep]
    a, b = (SOURCE_W, SCREEN_W) if name == "push" else (SCREEN_W, SOURCE_W)
    rem = (w - b) / (a - b)
    travel = abs(b - a)
    best_c = min(
        (np.sqrt(np.mean((remaining(t + dt, om, 1.0, 0.0) - rem) ** 2)), om, dt)
        for om in np.arange(8, 40, 0.25) for dt in np.arange(0, 0.02, 0.004))
    best = min(
        (np.sqrt(np.mean((remaining(t + dt, om, z, v) - rem) ** 2)), om, z, v, dt)
        for om in np.arange(8, 40, 0.5) for z in [1.0] + list(np.arange(0.6, 2.0, 0.1))
        for v in np.arange(-2, 8, 0.5) for dt in np.arange(0, 0.02, 0.008))
    def when(p):
        idx = np.nonzero(1 - rem >= p)[0]
        return f"{t[idx[0]] * 1000:.0f} ms" if len(idx) else "-"
    print(f"{name}: {len(t)} distinct frames over {t[-1] * 1000:.0f} ms; t50 {when(0.5)}, t90 {when(0.9)}")
    print(f"  critically damped from rest: omega {best_c[1]:.2f} rad/s (tau {1000 / best_c[1]:.0f} ms), rms {best_c[0] * travel:.1f} pt")
    print(f"  best spring: omega {best[1]:.1f}, zeta {best[2]:.2f}, v0 {best[3]:.1f}, rms {best[0] * travel:.1f} pt")


def main():
    rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["app"] == "1" and r["card_l"]]
    for name, seg in segments(rows):
        if len(seg) > 6:
            analyze(name, seg)


if __name__ == "__main__":
    main()
