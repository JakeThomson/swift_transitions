"""The film pop: the card's box and how solid the poster is over the page.

    python3 analyze_film.py frames/

Frames from extract.py of a flat-palette run of the film row. The poster
is D58B3A, the page E0F0FF and the backdrop lerp(D58B3A, white, .35), read
again from the recording itself (the codec shifts the saturated colours);
a pixel on the line between the page, or the backdrop, and the poster
gives the poster's opacity there. The pop measured is the last run of
frames that starts on the page and ends on the home. Prints one line per
frame: the card's box, the poster's opacity over the page under it and
over the backdrop band across its top.
"""
import csv
import sys
from pathlib import Path

import numpy as np
from PIL import Image

POSTER = np.array([0xD5, 0x8B, 0x3A], float)
PAGE = np.array([0xE0, 0xF0, 0xFF], float)
BACKDROP = np.array([228, 180, 127], float)
# The other two Dunes posters at rest (poster row, still row), in points.
OTHERS = [(148, 250, 268, 430), (188, 507, 348, 597)]
SCALE = 3


def alpha_on(px, a, b):
    """Where each pixel falls on the line from a to b, and how far off it."""
    d = b - a
    t = np.clip(((px - a) @ d) / (d @ d), 0, 1)
    return t, np.linalg.norm(px - (a + t[..., None] * d), axis=-1)


def load(path):
    im = Image.open(path).convert("RGB")
    return np.asarray(
        im.resize((im.width // SCALE, im.height // SCALE), Image.BOX)
    ).astype(float)


def on_page(im):
    return (np.linalg.norm(im[150, :, :] - BACKDROP, axis=1) < 40).mean() > 0.9


def main(frames):
    frames = Path(frames)
    with open(frames / "times.csv") as f:
        times = [(int(r["index"]), float(r["t"])) for r in csv.DictReader(f)]
    path = lambda i: frames / f"{i:06d}.png"
    # Runs of frames less than half a second apart: the simulator records
    # only while something changes.
    runs, run = [], [times[0]]
    for prev, cur in zip(times, times[1:]):
        if cur[1] - prev[1] > 0.5:
            runs.append(run)
            run = []
        run.append(cur)
    runs.append(run)
    pops = [r for r in runs
            if r[-1][1] - r[0][1] > 0.2
            and on_page(load(path(r[0][0])))
            and not on_page(load(path(r[-1][0])))]
    run = pops[-1]
    first, last = load(path(run[0][0])), load(path(run[-1][0]))
    poster = np.median(last[520:580, 200:330].reshape(-1, 3), axis=0)
    backdrop = np.median(first[120:300, 40:360].reshape(-1, 3), axis=0)
    page = np.median(first[600:800, 40:360].reshape(-1, 3), axis=0)
    print(f"palette as recorded: poster {poster} page {page} backdrop {backdrop}")
    t0 = None
    for index, t in run:
        im = load(path(index))
        h, w, _ = im.shape
        px = im.reshape(-1, 3)
        t_page, r_page = alpha_on(px, page, poster)
        t_back, r_back = alpha_on(px, backdrop, poster)
        # The card is where the page shows plain, or the backdrop plain or
        # blended with the poster. A page-and-poster blend is not unique
        # (the covered page's dimmed white sits on that line), nor is the
        # poster itself (the posters at rest).
        plain = np.linalg.norm(px - page, axis=-1) < 6
        card = (plain | ((r_back < 6) & (t_back < 0.75))).reshape(h, w)
        card[:100, :] = False
        ys, xs = np.where(card)
        if len(ys) < 300:
            print(f"{t:8.3f}  no card")
            continue
        box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)
        if t0 is None and box[2] - box[0] < 398:
            t0 = t
        # The poster's opacity from the middle of the card, the page under
        # the picture there, and from the backdrop band across the top.
        on_line = r_page.reshape(h, w) < 10
        for (l, top, r, b) in OTHERS:
            on_line[top:b, l:r] = False
        middle = np.zeros_like(on_line)
        middle[box[1] + (box[3] - box[1]) // 4:box[1] + (box[3] - box[1]) * 3 // 4,
               box[0] + 8:box[2] - 8] = True
        over_page = t_page.reshape(h, w)[on_line & middle]
        band = np.zeros_like(on_line)
        band[box[1] + 8:box[1] + (box[3] - box[1]) // 4, box[0] + 8:box[2] - 8] = True
        over_backdrop = t_back.reshape(h, w)[(r_back.reshape(h, w) < 10) & band]
        alpha = lambda v: f"{np.median(v):.2f}" if len(v) > 50 else "   -"
        rel = f"+{(t - t0) * 1000:4.0f}ms" if t0 is not None else "   rest"
        print(f"{t:8.3f} {rel}  box L{box[0]:4d} T{box[1]:4d} R{box[2]:4d} B{box[3]:4d}"
              f"  w{box[2] - box[0]:4d} h{box[3] - box[1]:4d}"
              f"  poster over page {alpha(over_page)}  over backdrop {alpha(over_backdrop)}")


if __name__ == "__main__":
    main(sys.argv[1])
