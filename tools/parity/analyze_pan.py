"""Stage 4 numbers from a tracked zoom-page pan recording.

    python3 analyze_pan.py run.csv

Needs touch rings and the flat palette. While the finger is down: the
card's scale against the finger's travel, and where the card's top-left
sits against where a shrink about the grab point would put it (the pivot
and the sideways lag). After the lift: the outcome and the best spring
from the release, as analyze_zoom.py fits a flight.
"""
import csv
import sys

import numpy as np

from analyze_zoom import remaining

WIDTH = 402.0
HEIGHT = 874.0
SOURCE = (148.3, 250.0, 268.3, 430.0)
RING = 12.0


def card(r):
    return tuple(float(r[f"card_{k}"]) for k in ("l", "t", "r", "b"))


def finger(r):
    return float(r["ring_l"]) + RING, float(r["ring_t"]) + RING


def main():
    rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["app"] == "1" and r["card_l"]]
    # The page is open once the art spans the width, after the poster was
    # seen at home: the recording can start on whatever the app last showed.
    home = next((i for i, r in enumerate(rows) if card(r)[2] - card(r)[0] < 130), 0)
    open_at = next((i for i, r in enumerate(rows) if i > home and card(r)[2] - card(r)[0] > WIDTH - 1), None)
    if open_at is None:
        print("the page never opened")
        return
    rest = card(rows[open_at])
    t_open = float(rows[open_at]["t"])
    # The poster art on the open page: 585 pt tall natively, 599 in the
    # example, so scales are read against each app's own.
    art_w, art_h = rest[2] - rest[0], rest[3] - rest[1]
    # The drag is the last run of ring frames within the script's window:
    # the poster tap's ring can outlive the page opening, a scrolled run
    # scrolls first, and the simulator's wallpaper after the app closes is
    # poster orange.
    runs, run = [], []
    for r in rows[open_at:]:
        if r["ring_l"] and float(r["t"]) - t_open < 4.5:
            if float(r["t"]) - t_open > 0.3:
                run.append(r)
        elif run:
            runs.append(run)
            run = []
    if run:
        runs.append(run)
    # A drag starts on the open page, its art spanning the width.
    runs = [run for run in runs if card(run[0])[2] - card(run[0])[0] > WIDTH - 1]
    if not runs:
        print("no drag frames")
        return
    drag = runs[-1]
    if len(runs) > 1:
        first = runs[0]
        print(f"{len(runs)} touches; the first moved the art from top {card(first[0])[1]:.0f} to {card(first[-1])[1]:.0f}")
    start = finger(drag[0])
    # Where the drag's art sits at its start (the page may be scrolled).
    rest = card(drag[0])
    print(f"art at rest ({rest[0]:.0f},{rest[1]:.0f})–({rest[2]:.0f},{rest[3]:.0f}); grab ({start[0]:.0f},{start[1]:.0f}); {len(drag)} finger frames")
    # Scale from whichever art edge pair the screen has not clipped. The
    # pivot model: the grabbed point rides the finger, so the art's corner
    # is the finger less the grab offset scaled.
    print("  finger x    y   travel  scale   card l  l(pivot)   card t  t(pivot)")
    ys, scales = [], []
    for r in drag[::max(1, len(drag) // 20)]:
        fx, fy = finger(r)
        l, t, rr, b = card(r)
        s = max((rr - l) / art_w, (b - t) / art_h)
        travel = (fy - start[1]) / HEIGHT
        pl = fx - (start[0] - rest[0]) * s
        pt = fy - (start[1] - rest[1]) * s
        print(f"  {fx:7.1f} {fy:5.0f}   {travel:5.2f}  {s:5.3f}   {l:6.1f}  {pl:8.1f}   {t:6.1f}  {pt:8.1f}")
        ys.append(travel)
        scales.append(s)
    ys, scales = np.array(ys), np.array(scales)
    m = (ys > 0.03) & (ys < 0.3)
    if m.sum() > 3:
        g = np.polyfit(ys[m], 1 - scales[m], 1)
        print(f"  early scale ≈ 1 − {g[0]:.3f}·travel − {g[1]:.3f} (travel in screen heights)")
    last = drag[-1]
    t_lift = float(last["t"])
    after = [r for r in rows if float(r["t"]) > t_lift]
    if len(after) < 4:
        print("nothing after the lift")
        return
    t = np.array([float(r["t"]) for r in after]) - t_lift
    boxes = np.array([card(r) for r in after])
    within = t < 1.5
    t, boxes = t[within], boxes[within]
    h = boxes[:, 3] - boxes[:, 1]
    end = h[-1]
    landed = end < SOURCE[3] - SOURCE[1] + 3
    outcome = "landed" if landed else "back to full screen" if end > art_h - 3 else f"ended at height {end:.0f}"
    l0, t0, r0, b0 = card(last)
    print(f"release at scale {max((r0 - l0) / art_w, (b0 - t0) / art_h):.3f}: {outcome}")
    if landed:
        # A landing's art is confounded by the cross-fade, and so is its top
        # edge, where the copy fades in first; fit the left edge, or the
        # width when the card is against the left edge.
        if l0 < 5:
            w, w0, target = boxes[:, 2] - boxes[:, 0], r0 - l0, SOURCE[2] - SOURCE[0]
        else:
            w, w0, target = boxes[:, 0], l0, SOURCE[0]
    else:
        w, w0, target = h, b0 - t0, art_h
    if abs(w0 - target) < 5 or len(t) < 5:
        return
    moving = np.nonzero(np.abs(w - w0) > 1.5)[0]
    if not len(moving):
        print("  never moved")
        return
    start_t = t[max(moving[0] - 1, 0)]
    print(f"  motion starts {start_t * 1000:.0f} ms after the last finger frame")
    keep = (t >= start_t) & np.concatenate(([True], np.abs(np.diff(w)) > 0.05))
    t, w = t[keep] - start_t, w[keep]
    rem = (w - target) / (w0 - target)
    settled = t[np.nonzero(np.abs(rem) < 0.02)[0][0]] if np.any(np.abs(rem) < 0.02) else t[-1]
    print(f"  98 % settled {settled * 1000:.0f} ms after the motion starts")
    best = min(
        (np.sqrt(np.mean((remaining(t + dt, om, z, v) - rem) ** 2)), om, z, v, dt)
        for om in np.arange(8, 40, 0.5) for z in [1.0] + list(np.arange(0.6, 2.0, 0.1))
        for v in np.arange(-24, 6, 0.5) for dt in np.arange(0, 0.05, 0.008))
    print(f"  best spring: omega {best[1]:.1f}, zeta {best[2]:.2f}, v0 {best[3]:.1f}, lag {best[4] * 1000:.0f} ms, rms {best[0] * abs(w0 - target):.1f} pt")


if __name__ == "__main__":
    main()
