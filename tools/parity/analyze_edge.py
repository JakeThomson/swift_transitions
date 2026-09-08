"""Stage 5 numbers from a tracked zoom-page edge-swipe recording.

    python3 analyze_edge.py run.csv

Needs touch rings and the flat palette. While the finger is down: the
card's scale against the finger's travel (the gain), and where the card
sits relative to the finger (the free follow). After the lift: the outcome
(landed on the source, or back to full screen) and the best spring from
the release, as analyze_zoom.py fits a flight.
"""
import csv
import sys

import numpy as np

from analyze_zoom import remaining

WIDTH = 402.0
ART_H = 585.0    # the poster art on the open page, 117–702
SOURCE_H = 180.0
SOURCE_L = 148.3  # the Dunes poster's left edge at home
RING = 12.0
START = (4.0, 437.0)  # where every scripted swipe touches down
DEAD = 12.0      # the edge recognizer's slop, measured in stage 2


def card(r):
    return tuple(float(r[f"card_{k}"]) for k in ("l", "t", "r", "b"))


def main():
    rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["app"] == "1" and r["card_l"]]
    # The page is open once the art spans the width; the swipe is the ring
    # frames from then until the ring goes.
    open_at = next((i for i, r in enumerate(rows) if card(r)[2] - card(r)[0] > WIDTH - 1), None)
    if open_at is None:
        print("the page never opened")
        return
    rest = card(rows[open_at])
    # The swipe is the first run of ring frames that starts at the edge;
    # the poster tap's ring can outlive the page opening.
    swipe = []
    for r in rows[open_at:]:
        if r["ring_l"]:
            if swipe or float(r["ring_l"]) + RING < 40:
                swipe.append(r)
        elif swipe:
            break
    if not swipe:
        print("no swipe frames")
        return
    # The card runs off the right of the screen, so its scale is the art's
    # height; its left edge is the art's. The model checked against: scale
    # 1 − 0.644 × (travel − dead zone) / width, left edge at the finger less
    # the dead zone, vertical pivot at the finger.
    print(f"art at rest ({rest[0]:.0f},{rest[1]:.0f})–({rest[2]:.0f},{rest[3]:.0f}); {len(swipe)} finger frames")
    print("  finger x    y   travel  scale  model   card l  l−finger   card t  t(pivot)")
    xs, scales = [], []
    for r in swipe[::max(1, len(swipe) // 16)]:
        fx, fy = float(r["ring_l"]) + RING, float(r["ring_t"]) + RING
        l, t, rr, b = card(r)
        s = (b - t) / ART_H
        travel = max(0.0, fx - START[0] - DEAD) / WIDTH
        model = 1 - 0.644 * travel
        pivot_t = fy + (rest[1] - START[1]) * s
        print(f"  {fx:7.1f} {fy:5.0f}   {travel:5.2f}  {s:5.3f}  {model:5.3f}   {l:6.1f}  {l - fx:+7.1f}   {t:6.1f}  {pivot_t:6.1f}")
        xs.append(travel)
        scales.append(s)
    xs, scales = np.array(xs), np.array(scales)
    m = xs > 0.02
    if m.sum() > 3:
        g = np.polyfit(xs[m], 1 - scales[m], 1)
        print(f"  scale ≈ 1 − {g[0]:.3f}·travel − {g[1]:.3f} (travel in widths past the dead zone)")
    last = swipe[-1]
    t_lift = float(last["t"])
    after = [r for r in rows if float(r["t"]) > t_lift]
    if len(after) < 4:
        print("nothing after the lift")
        return
    t = np.array([float(r["t"]) for r in after]) - t_lift
    h = np.array([card(r)[3] - card(r)[1] for r in after])
    within = t < 1.5
    t, h = t[within], h[within]
    end = h[-1]
    landed = end < SOURCE_H + 3
    outcome = "landed" if landed else "back to full screen" if end > ART_H - 3 else f"ended at height {end:.0f}"
    print(f"release at scale {(card(last)[3] - card(last)[1]) / ART_H:.3f}: {outcome}")
    if landed:
        # A landing's art is confounded by the cross-fade; its left edge is not.
        w = np.array([card(r)[0] for r in after])[within]
        w0, target = card(last)[0], SOURCE_L
    else:
        w, w0, target = h, card(last)[3] - card(last)[1], ART_H
    if abs(w0 - target) < 5 or len(t) < 5:
        return
    # The motion starts when the height first leaves its held value.
    moving = np.nonzero(np.abs(w - w0) > 1.5)[0]
    if not len(moving):
        print("  never moved")
        return
    start = t[max(moving[0] - 1, 0)]
    print(f"  motion starts {start * 1000:.0f} ms after the last finger frame")
    keep = (t >= start) & np.concatenate(([True], np.abs(np.diff(w)) > 0.05))
    t, w = t[keep] - start, w[keep]
    rem = (w - target) / (w0 - target)
    settled = t[np.nonzero(np.abs(rem) < 0.02)[0][0]] if np.any(np.abs(rem) < 0.02) else t[-1]
    print(f"  98 % settled {settled * 1000:.0f} ms after the motion starts")
    best = min(
        (np.sqrt(np.mean((remaining(t + dt, om, z, v) - rem) ** 2)), om, z, v, dt)
        for om in np.arange(8, 40, 0.5) for z in [1.0] + list(np.arange(0.6, 2.0, 0.1))
        for v in np.arange(-2, 8, 0.5) for dt in np.arange(0, 0.05, 0.008))
    print(f"  best spring: omega {best[1]:.1f}, zeta {best[2]:.2f}, v0 {best[3]:.1f}, lag {best[4] * 1000:.0f} ms, rms {best[0] * abs(w0 - target):.1f} pt")


if __name__ == "__main__":
    main()
