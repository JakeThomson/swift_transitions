"""Stage 7 numbers from a tracked interruption recording.

    python3 analyze_catch.py run.csv [--frames]

Needs touch rings and the flat palette. The catching finger lands on
(208, 400) after the tap's or the pan's finger has gone, so its ring is
told by its top and the gap before it. Around the touch down: the art's
box frame by frame and whether the card flew on to its destination or
stopped under the finger. While the finger moves: the card's width
against its travel, as a scale of the full card. After the lift: the
outcome and the best spring from where the card was, as analyze_pan.py
reads a release. The bar's title and back button are read alongside.
`--frames` prints every frame of the release.
"""
import csv
import sys

import numpy as np

from analyze_pan import SOURCE, WIDTH, card
from analyze_zoom import remaining

CATCH_TOP = 400.0 - 12.0
SOURCE_W = SOURCE[2] - SOURCE[0]
# The catcher's script, by test: how long it holds, how long it moves and
# how long it rests before lifting.
SCRIPTS = {"PushDrag": (0.3, 200 / 300, 0.6), "PushDragNow": (0, 200 / 300, 0.6), "PushFlick": (0, 100 / 800, 0),
           "Landing": (0.5, 150 / 300, 0.6)}


def ring(r):
    return float(r["ring_l"]) + 12.0, float(r["ring_t"]) + 12.0


def is_catcher(rows, i):
    """The catcher's ring, landing after the tap's or the pan's has gone: a
    pan to 30 % passes the catch point on its way, and a catcher that drags
    at once has moved on by its first frame."""
    r = rows[i]
    return (r["ring_l"] and -6 < float(r["ring_t"]) - CATCH_TOP < 100 and float(r["ring_b"]) - float(r["ring_t"]) < 30
            and i > 0 and not rows[i - 1]["ring_l"])


def width(r):
    l, _, rr, _ = card(r)
    return rr - l


def bar(r):
    return f"title {float(r['title_lum']):5.1f} back {float(r['back_lum']):5.1f}"


def main():
    path = sys.argv[1]
    rows = [r for r in csv.DictReader(open(path)) if r["app"] == "1" and r["card_l"]]
    name = path.rsplit("Catch", 1)[-1].split(".")[0]
    down = next((i for i in range(len(rows)) if is_catcher(rows, i)), None)
    if down is None:
        print("the catcher never landed")
        return
    t0 = float(rows[down]["t"])
    hold, move, rest = SCRIPTS.get(name, (0.5, 0, 0))
    lift = t0 + hold + move + rest + 0.008
    w0 = width(rows[down])
    growing = w0 > width(rows[down - 2])
    print(f"catch at {t0:.3f} s, frame {rows[down]['index']}, art {w0:.0f} wide {'growing' if growing else 'shrinking'}; lift {lift - t0:.3f} s later")
    print("  before / at / after the touch: art box and its width's change per frame")
    for i in range(max(0, down - 3), min(len(rows), down + 7)):
        l, t, rr, b = card(rows[i])
        dw = (rr - l) - width(rows[i - 1])
        print(f"   {float(rows[i]['t']) - t0:+6.3f} s  ({l:6.1f},{t:6.1f})–({rr:6.1f},{b:6.1f})  dw {dw:+6.1f}  {bar(rows[i])}  {'<- down' if i == down else ''}")
    # Under the finger before it moves: flew on to the far end, or stopped.
    still_until = t0 + hold
    dest = WIDTH if growing else SOURCE_W
    reached = next((r for r in rows[down:] if float(r["t"]) <= still_until + 0.05 and abs(width(r) - dest) < 3), None)
    if reached is not None:
        print(f"  flew on: {'full screen' if growing else 'the source'} {(float(reached['t']) - t0) * 1000:.0f} ms after the touch; {bar(reached)}")
    else:
        stopped = next((i for i in range(down + 1, len(rows)) if float(rows[i]["t"]) <= still_until
                        and abs(width(rows[i]) - width(rows[i - 1])) < 0.5 and abs(card(rows[i])[1] - card(rows[i - 1])[1]) < 0.5), None)
        if stopped is None:
            print("  neither reached the far end nor stopped under the finger")
        else:
            held = card(rows[stopped])
            last = max((r for r in rows[stopped:] if float(r["t"]) <= still_until), key=lambda r: float(r["t"]))
            drift = max(abs(a - b) for a, b in zip(card(last), held))
            print(f"  stopped {(float(rows[stopped]['t']) - t0) * 1000:.0f} ms after the touch at ({held[0]:.1f},{held[1]:.1f})–({held[2]:.1f},{held[3]:.1f}); drifted {drift:.1f} pt while held; {bar(last)}")
    if move:
        # The card against the finger while it drags: the pan's scale is of
        # the full card once the flight is done underneath.
        print("  finger travel   art w   art t   of full   of touch")
        y0 = ring(rows[down])[1]
        for i in range(down, len(rows)):
            r = rows[i]
            if float(r["t"]) > lift:
                break
            if not r["ring_l"] or float(r["t"]) < still_until or (i - down) % 3:
                continue
            l, t, rr, b = card(r)
            print(f"   {ring(r)[1] - y0:+8.1f} {rr - l:7.1f} {t:7.1f}   {(rr - l) / WIDTH:.3f}    {(rr - l) / w0:.3f}")
    # After the lift: where the card goes and how.
    after = [r for r in rows if float(r["t"]) >= lift - 0.02]
    w1 = width(after[0])
    # Read a second on: the recording can run into the app's next state.
    final = width(min(after, key=lambda r: abs(float(r["t"]) - lift - 1.0)))
    landed = final < 183
    target = SOURCE_W if landed else WIDTH
    print(f"release from width {w1:.1f} ({w1 / WIDTH:.3f}): {'landed' if landed else 'back to full screen'}; {bar(after[-1])}")
    ws = np.array([width(r) for r in after])
    ts = np.array([float(r["t"]) for r in after])
    moving = np.nonzero(np.abs(ws - w1) > 1.0)[0]
    if not len(moving) or abs(w1 - target) < 3:
        print("  the card did not move")
        return
    start = max(0, moving[0] - 1)
    ts, ws = ts[start:] - ts[start], ws[start:]
    rem = (ws - target) / (w1 - target)
    settled = np.nonzero(rem < 0.02)[0]
    if len(settled):
        print(f"  motion starts {(ts[0] + float(after[0]['t']) - lift) * 1000:+.0f} ms after the lift; 98 % settled {ts[settled[0]] * 1000:.0f} ms after the motion starts")
    else:
        print("  never settled")
    if "--frames" in sys.argv:
        for t, w, r in zip(ts, ws, after[start:]):
            print(f"   {t:6.3f} {w:6.1f}  {bar(r)}")
    fit = ts < 0.6
    best = min(
        (np.sqrt(np.mean((remaining(ts[fit] + dt, om, z, v) - rem[fit]) ** 2)), om, z, v, dt)
        for om in np.arange(8, 40, 0.5) for z in [1.0] + list(np.arange(0.6, 1.6, 0.1))
        for v in np.arange(-2, 8, 0.5) for dt in np.arange(0, 0.02, 0.008))
    print(f"  best spring: omega {best[1]:.1f}, zeta {best[2]:.2f}, v0 {best[3]:.1f}, lag {best[4] * 1000:.0f} ms, rms {best[0] * abs(w1 - target):.1f} pt")


if __name__ == "__main__":
    main()
