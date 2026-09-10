"""A README GIF cut out of a simulator recording.

    python3 gif.py in.mov 54.25 56.7 out.gif [width] [fps]

Resamples the window between the two timestamps to a constant rate,
holding each frame until the next one's timestamp passes, so a recording
that dropped frames still plays at the speed it was recorded at.

A recording carries a handful of frames whose timestamp is nonsense — one
straggler part way through, a few more at the end — which ffmpeg's own
`trim` reads as the end of the stream. The longest run of non-decreasing
timestamps is the real recording; the rest are dropped.
"""
import bisect
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def timestamps(video):
    """Every decoded frame's timestamp, in decode order."""
    info = subprocess.run(
        ["ffmpeg", "-i", video, "-vf", "showinfo", "-f", "null", "-"],
        capture_output=True, text=True).stderr
    return [float(m.group(1)) for m in re.finditer(r"pts_time:([0-9.]+)", info)]


def sound(times):
    """The indices of the longest non-decreasing run of `times`."""
    ends, at, back = [], [], [None] * len(times)
    for i, t in enumerate(times):
        j = bisect.bisect_right(ends, t)
        if j == len(ends):
            ends.append(t)
            at.append(i)
        else:
            ends[j], at[j] = t, i
        back[i] = at[j - 1] if j else None
    run, i = [], at[-1]
    while i is not None:
        run.append(i)
        i = back[i]
    return run[::-1]


def main(video, start, end, out, width=220, fps=30):
    times = timestamps(video)
    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        subprocess.run(
            ["ffmpeg", "-v", "error", "-i", video, "-vf", f"scale={width}:-1",
             "-fps_mode", "passthrough", str(work / "%04d.png")], check=True,
            stderr=subprocess.DEVNULL)
        frames = sorted(work.glob("*.png"))
        kept = [(times[i], frames[i]) for i in sound(times)]

        seq = work / "seq"
        seq.mkdir()
        i, t, n = 0, start, 0
        while t <= end:
            while i + 1 < len(kept) and kept[i + 1][0] <= t:
                i += 1
            (seq / f"{n:04d}.png").hardlink_to(kept[i][1])
            t, n = t + 1 / fps, n + 1

        subprocess.run(
            ["ffmpeg", "-v", "error", "-framerate", str(fps),
             "-i", str(seq / "%04d.png"), "-vf",
             "split[a][b];[a]palettegen=max_colors=160[p];"
             "[b][p]paletteuse=dither=bayer:bayer_scale=3",
             "-loop", "0", out, "-y"], check=True)
    print(f"{out}: {n} frames, {n / fps:.2f} s, {Path(out).stat().st_size // 1024} KB")


if __name__ == "__main__":
    main(sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4],
         *[int(a) for a in sys.argv[5:]])
