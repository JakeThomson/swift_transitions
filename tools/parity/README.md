# Parity tooling

Dev-only scripts for `docs/parity-plan.md`. Not part of the package.

Requirements: Python 3 with numpy and Pillow, ffmpeg/ffprobe on the path,
Xcode with the `swift_transitions_native` project built for the parity
simulator, and the example built for the simulator
(`flutter build ios --simulator --debug`).

    ./record.sh <native|flutter> <TestName> <out.mov>   # scripted run + recording
    python3 extract.py out.mov frames/                  # timestamped PNG frames
    python3 track.py frames/ out.csv                    # colour-class boxes per frame
    python3 compare.py native.csv ours.csv card_w       # RMS / timing / plot
    python3 analyze_pan.py run.csv                      # stage 4: a pan's scale, pivot, follow, release
    python3 compare_pan.py dir native flutter           # stage 4 side by side, one line per script
    python3 analyze_pinch.py run.csv                    # stage 6: a pinch's scale, turn, focal, release
    python3 compare_pinch.py dir native flutter         # stage 6 side by side, one line per script
    python3 analyze_catch.py run.csv                    # stage 7: a caught card's stop, hold, resumed flight
    python3 compare_catch.py dir native flutter         # stage 7 side by side, one line per script
    python3 analyze_edge.py run.csv                     # stage 5: an edge swipe's gain, follow, release
    python3 compare_edge.py dir native flutter          # stage 5 side by side, one line per script

The driver's `Finger` (ParityDriver.swift) runs multi-segment drags
through XCTest's private event paths, one keyframe per segment; it lifts
8 ms after the last move so the app reads a release velocity.

The simulator UDID lives in `parity.env`, along with the app bundle ids.
`record.sh` forwards the parity switches with xcodebuild's `TEST_RUNNER_`
prefix; for a manual launch use `SIMCTL_CHILD_PARITY_FLAT=1 xcrun simctl
launch <udid> <bundle id>`. Recordings and frames go to
`../swift_transitions_parity/<stage>/`, not the repository.
