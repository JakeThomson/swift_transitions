"""Stage 1 numbers from a tracked push recording.

    python3 analyze_push.py run.csv frames/

Prints, for the push and the pop: the exponential fit of the arriving
page's remaining distance (time constant), the covered page's travel per
point of the arriving page's, the dim per unit of progress, and the
luminance profile beside the arriving edge at mid-flight (the shadow).
"""
import csv
import sys

import numpy as np
from PIL import Image

WIDTH = 402.0
AURORA_RIGHT = 136.0
WHITE = 253.0


def load(path):
    return [r for r in csv.DictReader(open(path)) if r["app"] == "1" and r["push_pg_x600"]]


def runs(rows):
    """(name, rows) for the push (edge falling from the right) and the pop."""
    es = [float(r["push_pg_x600"]) for r in rows]
    out = []
    i = 0
    while i < len(rows):
        if es[i] < WIDTH - 5 and (i == 0 or es[i - 1] >= WIDTH - 5 or rows[i - 1]["push_pg_x600"] == ""):
            j = i
            while j + 1 < len(rows) and es[j] > 0.5:
                j += 1
            out.append(("push", rows[i:j + 1]))
            i = j + 1
        elif es[i] > 0.5 and i > 0 and es[i - 1] <= 0.5:
            j = i
            while j + 1 < len(rows) and es[j] < WIDTH - 0.5:
                j += 1
            out.append(("pop", rows[i:j + 1]))
            i = j + 1
        else:
            i += 1
    return out


def analyze(name, seg, frames):
    t = np.array([float(r["t"]) for r in seg])
    e = np.array([float(r["push_pg_x600"]) for r in seg])
    rem = e if name == "push" else WIDTH - e
    t = t - t[0]
    m = (rem > 3) & (rem < 340)
    k, b = np.polyfit(t[m], np.log(rem[m]), 1)
    resid = np.sqrt(np.mean((k * t[m] + b - np.log(rem[m])) ** 2))
    print(f"{name}: {len(seg)} frames over {t[-1] * 1000:.0f} ms; remaining distance decays with tau {-1000 / k:.1f} ms (log rms {resid:.3f})")
    # covered page: aurora right edge vs arriving travel
    ratios = []
    dims = []
    for r in seg:
        edge = float(r["push_pg_x600"])
        travel = WIDTH - edge
        if r["aurora_r"] and 20 < travel < WIDTH - 5:
            ratios.append((AURORA_RIGHT - float(r["aurora_r"])) / travel)
        if edge > 30 and travel > 20:
            dims.append((1 - float(r["dim_y"]) / WHITE) / (travel / WIDTH))
    if ratios:
        print(f"  covered page travel / arriving travel: {np.median(ratios):.3f} (range {min(ratios):.3f}–{max(ratios):.3f})")
    if dims:
        print(f"  dim per unit progress: {np.median(dims):.3f} (range {min(dims):.3f}–{max(dims):.3f})")
    # shadow: luminance profile left of the edge at the frame nearest mid-flight
    mid = min(seg, key=lambda r: abs(float(r["push_pg_x600"]) - WIDTH / 2))
    edge = float(mid["push_pg_x600"])
    a = np.asarray(Image.open(f"{frames}/{int(mid['index']):06d}.png").convert("RGB")).astype(float)
    y = int(600 * 3)
    lum = lambda px: 0.2126 * px[0] + 0.7152 * px[1] + 0.0722 * px[2]
    prof = [(d, lum(a[y, int((edge + d) * 3)])) for d in range(-30, 0, 2)]
    base = prof[0][1]
    print(f"  shadow at edge {edge:.0f}: " + " ".join(f"{d:+d}:{(base - l) / base * 100:.1f}%" for d, l in prof if d >= -20))


def main():
    rows = load(sys.argv[1])
    for name, seg in runs(rows):
        if len(seg) > 5:
            analyze(name, seg, sys.argv[2])


if __name__ == "__main__":
    main()
