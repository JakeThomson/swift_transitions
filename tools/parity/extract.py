"""Frames from a simulator recording, with the recording's own timestamps.

    python3 extract.py in.mov frames/

Writes frames/000123.png and frames/times.csv (index, seconds). Frame
index is a bad clock — the simulator drops frames under load — so every
later step keys on the timestamp.
"""
import csv
import json
import subprocess
import sys
from pathlib import Path


def main(video, out):
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_frames",
         "-show_entries", "frame=pts_time", "-of", "json", video],
        capture_output=True, text=True, check=True)
    times = [float(f["pts_time"]) for f in json.loads(probe.stdout)["frames"]]
    subprocess.run(
        ["ffmpeg", "-v", "error", "-i", video, "-vsync", "passthrough",
         str(out / "%06d.png")], check=True)
    with open(out / "times.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["index", "t"])
        for i, t in enumerate(times, start=1):
            w.writerow([i, f"{t:.4f}"])
    print(f"{len(times)} frames, {times[-1] - times[0]:.2f} s")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
