"""Stage 8: the landing spring, from tracked recordings of any dismissal.

    python3 analyze_landing.py run.csv [run2.csv ...]

One line per recording: the art's left edge (its width, for a card against
the left edge) from the motion's start to where it settles, fitted with a
spring from rest or seeded — the seed is signed toward the target, so a
release still shrinking reads negative — and the best seed for the
package's landing spring (ω 15, ζ 0.75). The art's top edge is not used:
the copy fades in there first and pulls the box up mid-landing, which
misread native's long landings as a stiffer, overdamped spring.
"""
import csv
import os
import sys

import numpy as np

from analyze_pan import SOURCE
from analyze_zoom import remaining

LANDING = (15.0, 0.75)


def box(r):
    return tuple(float(r[k]) for k in ("card_l", "card_t", "card_r", "card_b"))


def same(a, b):
    return max(abs(x - y) for x, y in zip(a, b)) <= 1.5


def landing(rows):
    """The frames of the last landing: from the motion's start (the last
    ring frame before it, advanced over the frames the box then held still,
    since the ring leaves a hold early) to the source."""
    w = np.array([box(r)[2] - box(r)[0] for r in rows])
    end = None
    for i in range(len(rows) - 1, 0, -1):
        if 100 < w[i] <= 125 and w[i - 1] > 125:
            end = i
            break
    if end is None:
        return None
    rings = [i for i, r in enumerate(rows) if r["ring_l"] and i < end]
    if not rings:
        return None
    start = rings[-1]
    while start + 1 < end and same(box(rows[start + 1]), box(rows[rings[-1]])):
        start += 1
    return rows[start:end + 30]


def fit(seg):
    t = np.array([float(r["t"]) for r in seg])
    t -= t[0]
    l = np.array([box(r)[0] for r in seg])
    w = np.array([box(r)[2] - box(r)[0] for r in seg])
    use = w if l[0] < 5 else l
    if abs(use[0] - (SOURCE[2] - SOURCE[0] if l[0] < 5 else SOURCE[0])) < 25:
        return None
    target, k_set = use[-1], len(use) - 1
    for k in range(5, len(use) - 5):
        if np.all(np.abs(use[k:k + 5] - use[k]) <= 1.5):
            target, k_set = use[k], k
            break
    rem = (use - target) / (use[0] - target)
    t, rem = t[:k_set + 3], rem[:k_set + 3]
    keep = np.concatenate(([True], np.abs(np.diff(rem)) > 1e-6))
    t, rem = t[keep], rem[keep]
    best = min(
        (np.sqrt(np.mean((remaining(t + dt, om, z, v) - rem) ** 2)), om, z, v, dt)
        for om in np.arange(10, 42, 0.5) for z in np.arange(0.5, 1.6, 0.05)
        for v in np.arange(-40, 6, 0.5) for dt in (0, 0.008, 0.016))
    om, z = LANDING
    seeded = min(
        (np.sqrt(np.mean((remaining(t + dt, om, z, v) - rem) ** 2)), v, dt)
        for v in np.arange(-40, 6, 0.25) for dt in (0, 0.008, 0.016))
    settled = t[np.nonzero(np.abs(rem) < 0.02)[0][0]] if np.any(np.abs(rem) < 0.02) else t[-1]
    return use[0], target, best, seeded, settled


def main():
    for path in sys.argv[1:]:
        name = os.path.basename(path)
        rows = [r for r in csv.DictReader(open(path)) if r["app"] == "1" and r["card_l"]]
        seg = landing(rows)
        result = fit(seg) if seg else None
        if result is None:
            print(f"{name:34s} no landing")
            continue
        x0, target, best, seeded, settled = result
        travel = abs(x0 - target)
        print(f"{name:34s} {x0:5.1f}->{target:5.1f}  omega {best[1]:4.1f} zeta {best[2]:.2f} v0 {best[3]:5.1f} rms {best[0] * travel:4.1f} pt | "
              f"landing spring: v0 {seeded[1]:5.1f} rms {seeded[0] * travel:4.1f} pt | 98 % {settled * 1000:3.0f} ms")


if __name__ == "__main__":
    main()
