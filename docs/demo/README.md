# README clips

The three GIFs the README shows, cut from scripted runs of the example app
on the parity simulator (iPhone 17, iOS 27.0). Recorded with the pointer
rings off and the posters in their own colours, unlike the measurement
runs in `../parity/`.

| Clip | Shows | Run |
|---|---|---|
| `zoom.gif` | The zoom push and pop | `testZoomPoster`, second pass |
| `pinch-rotate.gif` | A pinch to half size and 45°, released above the threshold, springing back | `testZoomRotate45` |
| `back-swipe.gif` | A back swipe to 80 % of the width, released at rest | `testSwipe80Rest` |

To record them again after a change, with the example built for the
simulator and installed on it:

    cd tools/parity
    PARITY_SHOW_TOUCHES=0 ./record.sh flutter testZoomPoster ~/zoom.mov
    python3 gif.py ~/zoom.mov <start> <end> ../../docs/demo/zoom.gif

The window is in the recording's own seconds and differs every run, since
each starts with a cold launch: `python3 extract.py` a few frames to find
where the gesture lands. They are 220 pt wide so three of them fit the
width of a pub.dev README; the README links them by their raw
githubusercontent URL, because `docs/` is not part of the published
package.
