# Parity clips

One clip per stage of `../parity-plan.md`, native on the left and ours on
the right, both from the same scripted run on the parity simulator
(iPhone 17, iOS 27.0), cut to the same frame of the transition by
`tools/parity/sidebyside.py` — the first frame of the flight, or the
frame the finger landed for a gesture. The recordings they come from
live outside the repository, in `../../../swift_transitions_parity/`.
The simulator drops frames when the host is busy, so a clip can carry a
frame or two of skew that the traces in `../parity-plan.md` do not.

| Clip | Shows | Runs |
|---|---|---|
| `stage1-push.mp4` | The push transition | `stage1/*_push` |
| `stage2-back-swipe.mp4` | A back swipe released at 45 % of the width | `stage2/*_testSwipe45Rest` |
| `stage3-zoom.mp4` | The zoom push | `stage3/*_zoom` |
| `stage4-pan.mp4` | A pan to 30 % of the height, released at rest | `stage4/native_ZoomPan30Rest`, `stage9/flutter2_ZoomPan30Rest` |
| `stage5-edge-swipe.mp4` | An edge swipe to 40 % of the width, released at rest | `stage5/native_ZoomEdge40Rest`, `stage9/flutter2_ZoomEdge40Rest` |
| `stage6-pinch.mp4` | A pinch to 45 %, released at rest | `stage6/native_ZoomPinch45Rest`, `stage9/flutter2_ZoomPinch45Rest` |
| `stage7-interruption.mp4` | A finger landing on the card during the push and dragging it | `stage7/native_CatchPushDrag`, `stage9/flutter2_CatchPushDrag` |
| `stage9-fast-landing.mp4` | A pinch released while the fingers are still closing at 800 pt/s | `stage9/native2_ZoomPinch45Fast`, `stage9/flutter2_ZoomPinch45Fast` |
