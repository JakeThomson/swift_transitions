"""Stage 6 side by side: one line per scripted pinch for each app.

    python3 compare_pinch.py <dir> <native prefix> <ours prefix>

Reads <dir>/<prefix>_<Test>.csv for every test both apps have and prints
the held scale and turn, the card's top-left against the focal model,
the outcome, and the release timing.
"""
import subprocess
import sys
from pathlib import Path

TESTS = ["ZoomPinch90Rest", "ZoomPinch80Rest", "ZoomPinch70Rest", "ZoomPinch60Rest",
         "ZoomPinch50Rest", "ZoomPinch48Rest", "ZoomPinch45Rest", "ZoomPinch40Rest",
         "ZoomPinch80Slow", "ZoomPinch80Fast", "ZoomPinch60Slow", "ZoomPinch60Fast",
         "ZoomPinch55Fast", "ZoomPinch45Fast", "ZoomPinch45Medium", "ZoomPinch40Fast",
         "ZoomRotate15", "ZoomRotate45", "ZoomRotateOnly", "ZoomPinchMove",
         "ZoomPinchOpen", "ZoomPinchReopen", "ZoomPinchScrolled"]


def summary(path):
    out = subprocess.run([sys.executable, str(Path(__file__).with_name("analyze_pinch.py")), str(path)],
                         capture_output=True, text=True).stdout.splitlines()
    rows = [l.replace("(", " ").replace(")", " ").split() for l in out if l.startswith("  ")]
    rows = [r for r in rows if len(r) == 10 and r[1].isdigit()]
    if not rows:
        return "-"
    held = rows[-1]
    ratio, s, turn, l, pl, t, pt = (float(held[i]) for i in (2, 4, 5, 6, 7, 8, 9))
    rel = next((l for l in out if l.startswith("release")), "")
    settle = next((l.strip() for l in out if "98 %" in l), "")
    return (f"held {s:.3f} @{ratio:.3f} turn {turn:4.1f} l {l:5.1f} ({l - pl:+5.1f}) t {t:5.1f} ({t - pt:+5.1f})"
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
