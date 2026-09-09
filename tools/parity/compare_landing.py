"""Stage 9: native and our landings side by side, one line per release.

    python3 compare_landing.py dir native ours ZoomPinch45Fast ...

For each script named, the settle time of the two apps' landings and the
difference, from [analyze_landing.py]'s fit of each.
"""
import csv
import os
import sys

from analyze_landing import fit, landing


def settle(path):
    if not os.path.exists(path):
        return None
    rows = [r for r in csv.DictReader(open(path)) if r["app"] == "1" and r["card_l"]]
    seg = landing(rows)
    result = fit(seg) if seg else None
    return None if result is None else result[4] * 1000


def main():
    directory, native, ours = sys.argv[1:4]
    print(f"{'script':24s} {'native':>8s} {'ours':>8s} {'diff':>8s}")
    for script in sys.argv[4:]:
        times = [settle(os.path.join(directory, f"{who}_{script}.csv")) for who in (native, ours)]
        cells = [f"{t:6.0f} ms" if t else "  no land" for t in times]
        diff = f"{times[1] - times[0]:+6.0f} ms" if all(times) else " " * 9
        print(f"{script:24s} {cells[0]} {cells[1]} {diff}")


if __name__ == "__main__":
    main()
