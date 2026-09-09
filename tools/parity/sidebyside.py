"""Stage 9: one clip of a native run beside ours, cut to the same frame.

    python3 sidebyside.py native.csv ours.csv out.mp4 [--seconds=2.5] [--width=360]
                            [--which=push|pop] [--at=16.4,18.1]

Each recording is cut to start a fifth of a second before its own trigger
— the first frame of the last transition it recorded — so the two runs
play in step whatever the launch and the daemon took, and they are
stacked native on the left. Writing a `.gif` writes an animated GIF
instead, for the README.

Frames are selected by index and re-timed from the tracker's timestamps:
the recordings' own are shifted by an edit list, so seeking them lands
somewhere else, and the simulator writes a frame only when something
changes, so the clip has to carry each frame's real duration.
"""
import csv
import os
import subprocess
import sys
import tempfile

LEAD = 0.2
GAP = 0.9
TAIL = 0.6
FPS = 60
BOXES = ("card", "zoom_pg", "push_pg")


def rows_of(path):
    return [r for r in csv.DictReader(open(path)) if r["app"] == "1"]


def trigger(rows, which):
    """The time of a transition's first frame. Motion is grouped into
    transitions on the stills longer than a gesture's hold; the last group
    is taken, or the last one the card grew over (`--which=push`) or shrank
    over (`pop`), and the run's own last group is skipped when the
    recording stops on it, as it does when the app quits."""
    moved = []
    for a, b in zip(rows, rows[1:]):
        step = 0.0
        for key in BOXES:
            cols = [f"{key}_{e}" for e in "ltrb"]
            if all(a[c] and b[c] for c in cols):
                step = max(step, max(abs(float(b[c]) - float(a[c])) for c in cols))
        if step > 2:
            moved.append(float(b["t"]))
    if not moved:
        raise SystemExit("nothing moved")
    groups = [[moved[0]]]
    for t in moved[1:]:
        if t - groups[-1][-1] > GAP:
            groups.append([])
        groups[-1].append(t)
    end = float(rows[-1]["t"])
    for group in reversed(groups):
        if end - group[-1] < TAIL:
            continue
        if which == "last" or grew(rows, group) == (which == "push"):
            return group[0]
    return groups[-1][0]


def grew(rows, group):
    """Whether the card is wider at the end of a group than at its start."""
    seen = [r for r in rows if group[0] <= float(r["t"]) <= group[-1] and r["card_l"]]
    if not seen:
        return False
    width = [float(r["card_r"]) - float(r["card_l"]) for r in (seen[0], seen[-1])]
    return width[1] > width[0]


def side(csv_path, start, seconds, width, out, work):
    """One app's half of the clip, at a constant [FPS]."""
    rows = rows_of(csv_path)
    cut = [r for r in rows if start <= float(r["t"]) <= start + seconds]
    first, last = int(cut[0]["index"]) - 1, int(cut[-1]["index"]) - 1
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-i", os.path.splitext(csv_path)[0] + ".mov",
         "-vf", f"select='between(n,{first},{last})',scale={width}:-2",
         "-fps_mode", "passthrough", os.path.join(work, "%04d.png")], check=True)
    times = [float(r["t"]) for r in cut] + [start + seconds]
    with open(os.path.join(work, "list.txt"), "w") as f:
        for i in range(len(cut)):
            f.write(f"file '{i + 1:04d}.png'\nduration {max(times[i + 1] - times[i], 1 / 240):.4f}\n")
        f.write(f"file '{len(cut):04d}.png'\n")
    subprocess.run(
        ["ffmpeg", "-y", "-v", "error", "-f", "concat", "-i", os.path.join(work, "list.txt"),
         "-r", str(FPS), "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "20", out],
        check=True)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=") for a in sys.argv[1:] if a.startswith("--"))
    native, ours, out = args
    seconds = float(opts.get("seconds", 2.5))
    width = int(opts.get("width", 240 if out.endswith(".gif") else 360))
    if "at" in opts:
        starts = [float(v) for v in opts["at"].split(",")]
    else:
        which = opts.get("which", "last")
        starts = [max(0, trigger(rows_of(p), which) - LEAD) for p in (native, ours)]
    with tempfile.TemporaryDirectory() as tmp:
        halves = []
        for i, (path, start) in enumerate(zip((native, ours), starts)):
            work = os.path.join(tmp, str(i))
            os.mkdir(work)
            halves.append(os.path.join(tmp, f"{i}.mp4"))
            side(path, start, seconds, width, halves[-1], work)
        chain = "[0:v][1:v]hstack[v]"
        if out.endswith(".gif"):
            chain += ";[v]fps=20,split[a][b];[a]palettegen[p];[b][p]paletteuse[o]"
        cmd = ["ffmpeg", "-y", "-v", "error", "-i", halves[0], "-i", halves[1],
               "-filter_complex", chain, "-map", "[o]" if out.endswith(".gif") else "[v]"]
        if not out.endswith(".gif"):
            cmd += ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "26"]
        subprocess.run(cmd + [out], check=True)
    print(f"{out} ({os.path.getsize(out) // 1024} KB), from {starts[0]:.2f} s and {starts[1]:.2f} s")


if __name__ == "__main__":
    main()
