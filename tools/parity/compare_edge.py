"""Stage 5 side by side: one line per scripted edge swipe for each app.

    python3 compare_edge.py <dir> <native prefix> <ours prefix>

Reads <dir>/<prefix>_<Test>.csv for every test both apps have and prints
the held scale and left edge against the finger, the vertical follow
where the script moved down, the outcome, and the release timing.
"""
import csv
import subprocess
import sys
from pathlib import Path

TESTS = ["ZoomEdge20Rest", "ZoomEdge40Rest", "ZoomEdge44Rest", "ZoomEdge48Rest",
         "ZoomEdge52Rest", "ZoomEdge60Rest", "ZoomEdge20Fling", "ZoomEdge40Fling",
         "ZoomEdge60Fling", "ZoomEdge40Down", "ZoomEdge20DownUp", "ZoomEdge40Return"]


def summary(path):
    out = subprocess.run([sys.executable, str(Path(__file__).with_name("analyze_edge.py")), str(path)],
                         capture_output=True, text=True).stdout.splitlines()
    rows = [l.split() for l in out if l.startswith("  ") and len(l.split()) == 9 and l.split()[1].isdigit()]
    if not rows:
        return "-"
    # Held frame: the last finger row before release.
    held = rows[-1]
    fx, fy, s, l, t = float(held[0]), float(held[1]), float(held[3]), float(held[5]), float(held[7])
    rel = next((l for l in out if l.startswith("release")), "")
    settle = next((l.strip() for l in out if "98 %" in l), "")
    return f"held scale {s:.3f} l−finger {l - fx:+5.1f} top {t:5.1f} @({fx:.0f},{fy:.0f}) | {rel.replace('release at scale ', 'rel ')} | {settle}"


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
