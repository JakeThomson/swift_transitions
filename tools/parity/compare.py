"""Compare one tracked quantity between two runs.

    python3 compare.py native.csv ours.csv card_w [--plot out.png]

Quantities: any box edge column (card_l, card_r, ...), or derived
card_w / card_h / card_cx / card_cy, or dim_y. Each run is split into
motion segments (runs of change ended by 0.35 s of stillness); segment
`--segment k` (default 1: the push; 2 is usually the pop) of each run is
aligned on its first moving frame, resampled to 120 Hz, and compared.
Prints RMS and max error in points and the 50 % and 90 % travel times.
"""
import csv
import sys

import numpy as np


def load(path, q):
    rows = list(csv.DictReader(open(path)))
    t = np.array([float(r["t"]) for r in rows])
    def col(name):
        return np.array([float(r[name]) if r[name] != "" else np.nan for r in rows])
    if q == "card_w":
        y = col("card_r") - col("card_l")
    elif q == "card_h":
        y = col("card_b") - col("card_t")
    elif q == "card_cx":
        y = (col("card_r") + col("card_l")) / 2
    elif q == "card_cy":
        y = (col("card_b") + col("card_t")) / 2
    else:
        y = col(q)
    ok = ~np.isnan(y)
    return t[ok], y[ok]


def segments(t, y, threshold=1.0, gap=0.35):
    """Motion segments: runs of samples where the quantity keeps changing,
    ended by `gap` seconds of stillness. Each is (t0, t1) with a little
    stillness kept on either side so the ends are visible."""
    moving = np.abs(np.diff(y)) > threshold
    out = []
    start = None
    last_move = None
    for i, m in enumerate(moving):
        if m:
            if start is None:
                start = i
            last_move = i
        elif start is not None and t[i] - t[last_move] > gap:
            out.append((start, last_move + 1))
            start = None
    if start is not None:
        out.append((start, last_move + 1))
    return out


def clip(t, y, seg, pad=0.05):
    a, b = seg
    t0, t1 = t[a] - pad, t[b] + pad
    keep = (t >= t0) & (t <= t1)
    return t[keep], y[keep], t[a]


def resample(t, y, t0, hz=120):
    grid = np.arange(0, t[-1] - t0, 1 / hz)
    return grid, np.interp(grid, t - t0, y)


def travel_times(grid, y):
    a, b = y[0], y[-1]
    if abs(b - a) < 1e-6:
        return None, None
    frac = (y - a) / (b - a)
    def first(p):
        idx = np.nonzero(frac >= p)[0]
        return grid[idx[0]] if len(idx) else None
    return first(0.5), first(0.9)


def main():
    a, b, q = sys.argv[1:4]
    k = int(sys.argv[sys.argv.index("--segment") + 1]) if "--segment" in sys.argv else 1
    ta, ya = load(a, q)
    tb, yb = load(b, q)
    sa, sb = segments(ta, ya), segments(tb, yb)
    for name, t, y, segs in (("A", ta, ya, sa), ("B", tb, yb, sb)):
        print(f"{name} {q}: {len(segs)} motion segment(s): " + ", ".join(
            f"[{i + 1}] {t[s0]:.2f}-{t[s1]:.2f}s {y[s0]:.0f}->{y[s1]:.0f}" for i, (s0, s1) in enumerate(segs)))
    if k > len(sa) or k > len(sb):
        print(f"segment {k} missing in one run")
        return
    ta, ya, t0a = clip(ta, ya, sa[k - 1])
    tb, yb, t0b = clip(tb, yb, sb[k - 1])
    ga, ra = resample(ta, ya, t0a)
    gb, rb = resample(tb, yb, t0b)
    n = min(len(ra), len(rb))
    err = ra[:n] - rb[:n]
    print(f"segment {k} {q}: RMS {np.sqrt(np.mean(err**2)):.2f} pt, max {np.abs(err).max():.2f} pt over {n / 120:.2f} s")
    for name, g, y in (("A", ga, ra), ("B", gb, rb)):
        t50, t90 = travel_times(g, y)
        f = lambda v: "-" if v is None else f"{v * 1000:.0f} ms"
        print(f"  {name}: {y[0]:.1f} -> {y[-1]:.1f} over {g[-1]:.2f} s, t50 {f(t50)}, t90 {f(t90)}")
    if "--plot" in sys.argv:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.plot(ga, ra, label=f"A {a}")
        plt.plot(gb, rb, label=f"B {b}")
        plt.xlabel("s from trigger"); plt.ylabel(q); plt.legend()
        plt.savefig(sys.argv[sys.argv.index("--plot") + 1], dpi=120)


if __name__ == "__main__":
    main()
