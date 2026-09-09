"""Stage 6 numbers from a tracked zoom-page pinch recording.

    python3 analyze_pinch.py run.csv

Needs touch rings and the flat palette. The two rings share one box, so
the fingers' distance is the box less a ring each way. While the fingers
are down: the card's scale and turn against the fingers' distance and
angle (the art's box is a scaled, turned rectangle — two unknowns from
its width and height), and the card's centre against where a scale about
the focal point would put it. After the lift: the outcome and the best
spring from the release, as analyze_pan.py reads a pan.
"""
import csv
import math
import sys

import numpy as np

from analyze_pan import HEIGHT, RING, SOURCE, WIDTH, card
from analyze_zoom import remaining


def fingers(r):
    l, t, rr, b = (float(r[f"ring_{k}"]) for k in ("l", "t", "r", "b"))
    dx, dy = max(0.0, rr - l - 2 * RING), max(0.0, b - t - 2 * RING)
    return (l + rr) / 2, (t + b) / 2, math.hypot(dx, dy), math.degrees(math.atan2(dx, dy))


def fit(box, art_w, art_h):
    """Scale and turn (degrees) of the art from its box; a box no taller
    than wide reads as the turn's mirror, so the turn is kept to a quadrant."""
    l, t, rr, b = box
    w, h = rr - l, b - t
    if abs(w / art_w - h / art_h) < 0.02:
        # An unturned card; a glitched frame that lost an edge reads as
        # turned, so the plainer reading wins whenever it fits.
        return max(w / art_w, h / art_h), 0.0
    # tan θ = (H'w − W'h) / (W'w − H'h) for a w × h card turned θ.
    theta = math.atan((h * art_w - w * art_h) / (w * art_w - h * art_h))
    theta = max(0.0, min(math.pi / 2, theta))
    s = w / (art_w * math.cos(theta) + art_h * math.sin(theta))
    return s, math.degrees(theta)


def main():
    rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["app"] == "1" and r["card_l"]]
    home = next((i for i, r in enumerate(rows) if card(r)[2] - card(r)[0] < 130), 0)
    open_at = next((i for i, r in enumerate(rows) if i > home and card(r)[2] - card(r)[0] > WIDTH - 1), None)
    if open_at is None:
        print("the page never opened")
        return
    t_open = float(rows[open_at]["t"])
    rest = card(rows[open_at])
    art_w, art_h = rest[2] - rest[0], rest[3] - rest[1]
    runs, run = [], []
    for r in rows[open_at:]:
        if r["ring_l"] and float(r["t"]) - t_open < 6:
            if float(r["t"]) - t_open > 0.3:
                run.append(r)
        elif run:
            runs.append(run)
            run = []
    if run:
        runs.append(run)
    # A pinch starts on the open page, its art near the width (a fast
    # pinch's first frame may already be shrinking; the wallpaper after
    # the app closes is poster orange, 280 pt wide).
    runs = [run for run in runs if card(run[0])[2] - card(run[0])[0] > WIDTH - 60]
    if not runs:
        print("no pinch frames")
        return
    pinch = runs[-1]
    rest = card(pinch[0])
    fx0, fy0, d0, a0 = fingers(pinch[0])
    print(f"art at rest ({rest[0]:.0f},{rest[1]:.0f})–({rest[2]:.0f},{rest[3]:.0f}); fingers {d0:.0f} apart about ({fx0:.0f},{fy0:.0f}); {len(pinch)} finger frames")
    # The art's left and top against a scale about the focal point carried
    # with it (its right may leave the screen); only right for no turn.
    print("      t  fingers  ratio  angle    scale   turn   card l (focal)   card t (focal)")
    ratios, scales = [], []
    for r in pinch[::max(1, len(pinch) // 24)]:
        fx, fy, d, a = fingers(r)
        box = card(r)
        s, turn = fit(box, art_w, art_h)
        pl, pt = fx + (rest[0] - fx0) * s, fy + (rest[1] - fy0) * s
        print(f"  {float(r['t']) - t_open:5.2f} {d:6.0f}   {d / d0:5.3f}  {a - a0:5.1f}    {s:5.3f}  {turn:5.1f}   {box[0]:6.1f} ({pl:6.1f})   {box[1]:6.1f} ({pt:6.1f})")
        ratios.append(d / d0)
        scales.append(s)
    ratios, scales = np.array(ratios), np.array(scales)
    m = (ratios < 0.97) & (ratios > 0.3)
    if m.sum() > 3:
        g = np.polyfit(ratios[m], scales[m], 1)
        print(f"  scale ≈ {g[0]:.3f}·ratio + {g[1]:.3f}")
    last = pinch[-1]
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
    s0, turn0 = fit(card(last), art_w, art_h)
    print(f"release at scale {s0:.3f} turn {turn0:.1f}: {outcome}")
    if turn0 > 1:
        # The un-rotate against the scale's own return, frame by frame.
        print("  after the lift:   t   scale   turn   (remaining)")
        for r in after:
            if float(r["t"]) - t_lift > 1.0:
                break
            s1, turn1 = fit(card(r), art_w, art_h)
            if s1 < s0 + 0.005 or s1 > 0.995:
                continue
            print(f"                 {float(r['t']) - t_lift:5.3f}  {s1:5.3f}  {turn1:5.1f}   {(1 - s1) / (1 - s0):5.3f}  {turn1 / turn0:5.3f}")
    if landed:
        l0, t0 = card(last)[0], card(last)[1]
        if abs(t0 - SOURCE[1]) >= abs(l0 - SOURCE[0]):
            w, w0, target = boxes[:, 1], t0, SOURCE[1]
        else:
            w, w0, target = boxes[:, 0], l0, SOURCE[0]
    else:
        w, w0, target = h, card(last)[3] - card(last)[1], art_h
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
    if "--curve" in sys.argv:
        print("  remaining: " + " ".join(f"{ti * 1000:.0f}:{ri:.2f}" for ti, ri in zip(t, rem) if ti < 0.4))
    best = min(
        (np.sqrt(np.mean((remaining(t + dt, om, z, v) - rem) ** 2)), om, z, v, dt)
        for om in np.arange(8, 40, 0.5) for z in [1.0] + list(np.arange(0.6, 2.0, 0.1))
        for v in np.arange(-2, 8, 0.5) for dt in np.arange(0, 0.05, 0.008))
    print(f"  best spring: omega {best[1]:.1f}, zeta {best[2]:.2f}, v0 {best[3]:.1f}, lag {best[4] * 1000:.0f} ms, rms {best[0] * abs(w0 - target):.1f} pt")


if __name__ == "__main__":
    main()
