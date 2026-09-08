"""Stage 2 numbers from a tracked back-swipe recording.

    python3 analyze_swipe.py run.csv

Needs touch rings (PARITY_SHOW_TOUCHES) in the recording. Prints: the
page's edge against the finger's x while the finger is down (tracking
error), the outcome after release (popped or sprung back), and the
release curve's time constant and duration from the lift.
"""
import csv
import sys

import numpy as np

WIDTH = 402.0
RING = 12.0  # ring radius: ring_l + RING is the finger


def main():
    rows = [r for r in csv.DictReader(open(sys.argv[1])) if r["app"] == "1"]
    down = [r for r in rows if r["ring_l"] and r["push_pg_x600"]]
    if not down:
        print("no frames with both a touch ring and the page edge")
        return
    # The swipe: ring frames after the page is fully in (edge 0 seen before).
    seen_in = False
    swipe = []
    for r in rows:
        if r["push_pg_x600"] and float(r["push_pg_x600"]) <= 0.5:
            seen_in = True
        if seen_in and r["ring_l"] and r["push_pg_x600"]:
            swipe.append(r)
    if not swipe:
        print("no swipe frames")
        return
    err = []
    for r in swipe:
        finger = float(r["ring_l"]) + RING
        edge = float(r["push_pg_x600"])
        err.append(edge - finger)
    print(f"tracking over {len(swipe)} frames: edge − finger median {np.median(err):.1f} pt, range {min(err):.1f}..{max(err):.1f}")
    last = swipe[-1]
    t_lift = float(last["t"])
    after = [r for r in rows if float(r["t"]) > t_lift and r["push_pg_x600"]]
    if not after:
        print("nothing after the lift")
        return
    edges = np.array([float(r["push_pg_x600"]) for r in after])
    ts = np.array([float(r["t"]) for r in after]) - t_lift
    end = edges[-1]
    outcome = "popped" if end > WIDTH - 2 else "sprang back" if end < 2 else f"ended at {end:.0f}"
    settled = ts[np.nonzero(np.abs(edges - end) < 1)[0][0]] if np.any(np.abs(edges - end) < 1) else ts[-1]
    print(f"release at edge {float(last['push_pg_x600']):.0f} ({float(last['push_pg_x600']) / WIDTH:.0%}): {outcome}, settled {settled * 1000:.0f} ms after the lift")
    rem = np.abs(edges - end)
    m = (rem > 2) & (rem < abs(end - float(last['push_pg_x600'])) - 2)
    if m.sum() > 3:
        k, b = np.polyfit(ts[m], np.log(rem[m]), 1)
        print(f"  remaining distance decays with tau {-1000 / k:.0f} ms")


if __name__ == "__main__":
    main()
