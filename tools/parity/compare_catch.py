"""Stage 7 side by side: one line per scripted interruption for each app.

    python3 compare_catch.py <dir> <native prefix> <ours prefix>

Reads <dir>/<prefix>_<Test>.csv for every test both apps have and prints
where the card was when the finger landed, whether it flew on or stopped,
the pan's scale at the end of a drag, the outcome and the release timing.
"""
import subprocess
import sys
from pathlib import Path

TESTS = ["CatchPushHold", "CatchPushDrag", "CatchPushDragNow", "CatchPushFlick",
         "CatchLanding", "CatchLandingHold", "CatchReturn"]


def summary(path):
    out = subprocess.run([sys.executable, str(Path(__file__).with_name("analyze_catch.py")), str(path)],
                         capture_output=True, text=True).stdout.splitlines()
    if not out or out[0].startswith("the catcher"):
        return "-"
    at = out[0].split("art ")[1].split(";")[0]
    fate = next((l.strip().split(";")[0] for l in out if l.startswith("  flew on") or l.startswith("  stopped") or l.startswith("  neither")), "")
    drag = [l.split() for l in out if l.startswith("   ") and len(l.split()) == 5 and l.split()[0][0] in "+-"]
    pan = f"pan {drag[-1][3]} of full at {drag[-1][0]} pt" if drag else ""
    rel = next((l for l in out if l.startswith("release")), "").split(";")[0].replace("release from width ", "rel ")
    settle = next((l.strip().split(";")[-1].strip() for l in out if "98 %" in l), "")
    return " | ".join(x for x in (f"at {at}", fate, pan, rel, settle) if x)


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
