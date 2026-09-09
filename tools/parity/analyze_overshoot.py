"""Stage 9: how far a landing goes past the source, and how it comes back.

    python3 analyze_overshoot.py run.csv [run2.csv ...]

[analyze_landing.py] fits a landing up to the frame it settles on and
stops there. This reads the rest: the card's width in flight progress
(1.0 is the screen, 0.0 the source, negative smaller than the source),
the deepest it goes past the source, how long it takes to get there and
how long it then takes to come back within a point of it. A landing
released at rest is 2 % of the flight deep and one released on a fast
pinch 8 %, all of them back within 150 to 250 ms.
"""
import csv
import os
import sys

import numpy as np

from analyze_landing import landing
from analyze_zoom import SCREEN_W, SOURCE_W


def progress(rows):
    t = np.array([float(r["t"]) for r in rows])
    w = np.array([float(r["card_r"]) - float(r["card_l"]) for r in rows])
    return t - t[0], (w - SOURCE_W) / (SCREEN_W - SOURCE_W)


def main():
    for path in sys.argv[1:]:
        name = os.path.basename(path)
        rows = [r for r in csv.DictReader(open(path)) if r["app"] == "1" and r["card_l"]]
        seg = landing(rows)
        if not seg:
            print(f"{name:34s} no landing")
            continue
        # The landing's own window ends 30 frames in; the return takes longer.
        t, p = progress(rows[rows.index(seg[0]):])
        if p[0] < 0.05:
            print(f"{name:34s} the landing is already over at the first frame")
            continue
        # Up to the next push, which grows the card again.
        deep = int(np.argmin(p))
        after = np.nonzero((np.arange(len(p)) > deep) & (p > 0.15))[0]
        if len(after):
            t, p = t[:after[0]], p[:after[0]]
            deep = int(np.argmin(p))
        back = np.nonzero((np.arange(len(p)) > deep) & (p > -0.01))[0]
        recovered = (t[back[0]] - t[deep]) * 1000 if len(back) else float("nan")
        print(f"{name:34s} from {p[0]:5.2f}  past the source by {-p[deep] * 100:4.1f} % of the flight "
              f"at {t[deep] * 1000:3.0f} ms, back within a point after {recovered:3.0f} ms")


if __name__ == "__main__":
    main()
