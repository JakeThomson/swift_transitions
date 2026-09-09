"""Stage 4 side by side: one line per scripted pan for each app.

    python3 compare_pan.py <dir> <native prefix> <ours prefix>

Reads <dir>/<prefix>_<Test>.csv for every test both apps have and prints
the held scale and the card's top-left against the pivot model, the
outcome, and the release timing.
"""
import csv
import subprocess
import sys
from pathlib import Path

TESTS = ["ZoomPan15Rest", "ZoomPan30Rest", "ZoomPan50Rest", "ZoomPan80Rest",
         "ZoomPanTop30Rest", "ZoomPanBottom20Rest", "ZoomPan30Right", "ZoomPan30Left",
         "ZoomPan30FarRight", "ZoomPanScrolled", "ZoomPan50UpFling",
         "ZoomPan20Slow", "ZoomPan20Medium", "ZoomPan20Fast",
         "ZoomPan40Slow", "ZoomPan40Medium", "ZoomPan40Fast",
         "ZoomPan60Slow", "ZoomPan60Medium", "ZoomPan60Fast"]


def summary(path):
    out = subprocess.run([sys.executable, str(Path(__file__).with_name("analyze_pan.py")), str(path)],
                         capture_output=True, text=True).stdout.splitlines()
    rows = [l.split() for l in out if l.startswith("  ") and len(l.split()) == 8 and l.split()[1].isdigit()]
    if not rows:
        return "-"
    held = rows[-1]
    fx, fy, s, l, pl, t, pt = (float(held[i]) for i in (0, 1, 3, 4, 5, 6, 7))
    rel = next((l for l in out if l.startswith("release")), "")
    settle = next((l.strip() for l in out if "98 %" in l), "")
    return (f"held scale {s:.3f} l {l:5.1f} ({l - pl:+5.1f}) t {t:5.1f} ({t - pt:+5.1f}) @({fx:.0f},{fy:.0f})"
            f" | {rel.replace('release at scale ', 'rel ')} | {settle}")


def main(d, native, ours):
    d = Path(d)
    for test in TESTS:
        pair = [(native, d / f"{native}_{test}.csv"), (ours, d / f"{ours}_{test}.csv")]
        if not all(p.exists() for _, p in pair):
            continue
        print(f"== {test}")
        for name, p in pair:
            print(f"  {name:9} {summary(p)}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
