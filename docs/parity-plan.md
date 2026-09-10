# Native parity: test plan

Status: plan, 2026-09-08. Follows M5 of `design.md`; runs before the 0.1.0
release (M6), whose README GIFs and CHANGELOG numbers come out of it.

The goal is one number per parameter and one verdict per behaviour: for
every animation, transition and gesture the package has, a native
reference built the same way, recorded the same way, measured the same
way, and tuned until the two traces sit on top of each other and the two
apps feel the same in the hand. Every tuned constant ends up in
`design.md` section 1 with the recording it came from.

The work is in stages. Stage 0 builds the rig; each later stage owns a
handful of parameters, has a fixed set of recordings, and is done when
its acceptance criteria hold. Stages 1–3 are non-interactive and can be
measured in the simulator to the frame. Stages 4–7 are gestures: the
curves are measured from scripted gestures in the simulator, the feel is
judged on a device.

---

## 0. The rig

### 0.1 The native reference app

A SwiftUI app, `NativeReference`, in a sibling folder to the package
(`../swift_transitions_native/`, its own repository; it is not part of the
pub package). iOS 26 deployment target, iPhone only, portrait only. It
mirrors `example/lib/main.dart` screen for screen and point for point:

| Flutter example | Native |
|---|---|
| `CupertinoApp` + `CupertinoNavigationBar` | `NavigationStack` with the default bar, `.navigationBarTitleDisplayMode(.inline)` |
| Gallery list: two push rows, chevrons | `List` with two `NavigationLink` rows |
| `SwiftPageRoute` (push) | `NavigationLink` push (UIKit's push transition) |
| `BackGestureRegion.anywhere` | none — see the note below |
| Poster row: 120×180 pt cards, 12 pt radius, 12 pt gaps, 16 pt insets | horizontal `ScrollView` + `LazyHStack`, the same numbers |
| `ZoomTransitionSource(tag:, borderRadius:)` | `.matchedTransitionSource(id:in:) { $0.clipShape(.rect(cornerRadius: 12)) }` |
| `ZoomPageRoute(sourceTag:, options:)` | destination with `.navigationTransition(.zoom(sourceID:in:))` |
| `PosterPager` (`PageView`) setting `sourceTag` | `TabView(.page)`; the zoom's `sourceID` bound to the selected poster |
| `alignmentRect` = the art under the bar | the art placed the same; UIKit `alignmentRectProvider` is not exposed by SwiftUI, so the native default is the reference for the *unaligned* case and the aligned case is compared against the UIKit sample (see stage 3) |
| `PosterArt` gradient, SF text, weights | identical colours and fonts |

Rules:

- Every element of the two apps that a measurement will find has a flat,
  unique colour with no gradient across the measured edge: the poster
  card's outer 4 pt is solid, page backgrounds are pure white, the covered
  page's list background is one grey. Measurement is pixel classification,
  so the palette is the instrument.
- No text in a region that will be measured; text anti-aliasing shifts
  edges by a pixel.
- The same device size everywhere: the iPhone 17 (402 × 874 pt, 3×) — the
  simulator for curves, the physical phone for feel. Every measurement
  is stated in points on that device; the design doc's 390-wide numbers
  are re-derived, not reused.
- Version-pin the reference: iOS build number, Xcode, Flutter, and the
  engine in a `VERSIONS` file next to the recordings. Apple retunes these
  transitions between releases; a number is only meaningful with its
  iOS version.

The back-swipe-anywhere region has no native equivalent (iOS pops only
from the edge; the "anywhere" variant is the package's own feature). It
is compared against the edge swipe's response for the same finger travel
and otherwise tested for consistency with itself.

### 0.2 Driving both apps identically

Feel needs a finger, but curves need the same input twice. One XCUITest
target in the native project drives *both* apps on the simulator — an
`XCUIApplication(bundleIdentifier:)` reaches the Flutter example too — so
every scripted gesture is one function taking a bundle id:

- taps at named points (poster centre, row centre, back button);
- drags as a list of `(point, timestamp)` samples replayed with
  `XCUICoordinate.press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`
  or, for shaped paths, a chain of `pressForDuration…thenDragTo` calls;
- two-finger pinches and rotations with `pinch(withScale:velocity:)` and
  `rotate(_:withVelocity:)`.

The Flutter example also needs, for scripted runs, `--dart-define`
switches the test can read from the launch environment:
`PARITY_SHOW_TOUCHES` (draw a 12 pt ring under every pointer) and
`PARITY_FLAT` (swap gradients for the flat palette). The native app has
the same two flags. Touch rings are how a recording of a *human* gesture
becomes measurable: the finger's position is in the frame.

The simulator records with `xcrun simctl io <udid> recordVideo --codec h264
--force out.mov`; it drops frames under load, which is why every scripted
run is recorded three times and the run with the most frames is kept.
Device recordings are QuickTime screen recordings over USB (60 fps; a
ProMotion phone records at 60 even when displaying 120) and only ever
used for feel and for confirming that a simulator curve is not an
artefact of the simulator.

### 0.3 Measuring

`tools/parity/` in the package repository (dev-only, not shipped; Python,
ffmpeg, numpy, OpenCV):

- `extract.py`: frames from a recording at native rate, cropped to the
  app, with the recording's timestamps (`ffprobe -show_frames`), because
  dropped frames make frame index a bad clock.
- `track.py`: per frame, bounding boxes of the classified colours — the
  card (poster orange, page white with orange inside), the covered page,
  the touch rings — plus the mean luminance of a fixed patch of the
  covered page. Output one CSV per recording: `t, card_l, card_t, card_r,
  card_b, rotation, dim_y, finger_x, finger_y`.
- `align.py`: aligns two CSVs on the trigger (the first frame the card
  moves, or the first frame with a touch ring) and resamples both to 120 Hz.
- `compare.py`: for a named quantity, RMS and max error between native
  and ours in points, the time of 50 % and 90 % travel, and a plot. Also
  fits a `SpringDescription` to a native trace (least squares over
  stiffness and damping with mass 1, from the release velocity) so the
  numbers to put in the code fall out rather than being guessed.

This replaces the two ad hoc scripts in the scratchpad (`measure.py`,
`measure_png.py`) that produced the section 1.1 push numbers; their
method (frame matching on the covered page's left edge) becomes the
covered-page tracker.

Recordings and CSVs live in `../swift_transitions_parity/<stage>/`
(outside the package; videos are large). CSVs and plots for the final
tuned run of each stage are copied into `docs/parity/<stage>/` so the
numbers in `design.md` are reproducible from the repository.

### 0.4 What "done" means, for every stage

- A curve is *matched* when RMS error ≤ 2 pt over the motion and the
  50 % and 90 % times are within one frame at 60 fps (17 ms). Opacity and
  luminance quantities: RMS ≤ 2 % of range.
- A gesture *tracks* when, for the same finger path, the card's position
  and scale under the finger match to 2 pt at every sample, and the
  release outcome (commit or cancel) agrees on a fixed set of release
  cases.
- A behaviour *feels native* when the reviewer, with the two apps on the
  same phone and the same gesture, cannot say which is which in a blind
  A/B (the tester swaps apps behind a cover; five trials, majority wrong
  or split). Feel is assessed after the curves match, never instead.
- Each stage ends with the tuned constants committed, the recordings that
  justify them named next to the constants, and a row per constant in
  `design.md` section 1.4 (or a new 1.6 "Calibrated parameters" table).

Stage 0 is done when: the native app builds and matches the example
screen for screen in a side-by-side screenshot at rest (pixel diff of the
home and poster screens under 1 % of pixels differing, excluding the
status bar and the nav bar's text), the XCUITest drives both apps through
a push and a pop, and the tracker produces a plausible CSV for one
recording of each.

*Done 2026-09-08.* What the rig turned out to need, for whoever re-runs it:

- **Reference iOS is 27.0 (24A5408d), not 26.** The iOS 26.0.1 runtime's
  SpringBoard crashes at boot under this Xcode 27 / macOS 27 host, so the
  parity simulator is an iPhone 17 on the 27.0 runtime (`Parity iPhone 17`,
  UDID in `tools/parity/parity.env`), separate from any simulator in daily
  use. `VERSIONS` in the recordings folder pins it.
- The native project is generated with `xcodegen` from `project.yml`
  (`../swift_transitions_native`, its own repository). Its home screen is
  laid out by hand rather than with `List`, since SwiftUI's list rows are
  52 pt and the example's tiles are 44 pt; the measured offsets are in
  `Gallery.swift`. Home screens differ by 0.8 % of pixels at rest.
- `xcodebuild test-without-building` forwards only environment variables
  prefixed `TEST_RUNNER_` to the test runner, and Dart on iOS cannot read
  the launch environment at all, so the example's Runner hands the
  `PARITY_*` variables to Dart over a method channel. For a manual launch
  use `SIMCTL_CHILD_PARITY_FLAT=1 xcrun simctl launch …`. The example
  also hides its debug banner.
- The tracker keys the start of a recording on the first frame the nav
  bar is white and latches, because the simulator's home wallpaper is
  orange and the bar dims during flights. Anti-aliased text blends toward
  the palette colours, so the flat palette carries no poster titles and a
  box needs 300 matching pixels.
- The simulator records at 60 fps while something moves (median 16.6 ms)
  with a handful of gaps over 40 ms per run; the three-runs rule stands.
  The example is a debug build (release does not run on the simulator);
  its first zoom-push frame lands 130 pt further along than native's,
  which is either the post-frame flight preparation or debug-mode frame
  pacing — stage 3's first question.

---

## 1. The push transition

**Owns** (`lib/src/page/`): the push curve and duration
(`Curves.fastEaseInToSlowEaseOut` today, or a spring), the covered page's
travel (`_kCoveredPageTravel` 0.29) and dim (`_kCoveredPageDimAlpha`
0.115) and their curves, the leading-edge shadow (`_shadowAlpha` 0.03,
`_shadowWidthFraction` 0.05), the corner clip radius during the slide, and
the nav bar hero timing (`CupertinoNavigationBar`'s own, noted if it
differs).

**Recordings** (scripted, simulator; three each):

1. `push_row`: tap the first list row; hold 1.5 s; tap back.
2. `push_deep`: push twice (row, then a link inside the pushed page) and
   pop twice, for the covered-page motion under a second push.
3. `push_flat`: 1 with the flat palette, for the dim luminance.

**Measure**: incoming page left edge vs time; covered page left edge vs
time; covered page luminance vs time; shadow profile (a 40 pt horizontal
luminance slice across the incoming edge at 50 % travel); corner clip
(the row of pixels at the top-left corner at 50 % travel).

**Tune**: replace the curve with whatever fits the native edge best —
the existing 1.1 measurements say lockstep and linear-in-progress for the
covered page, so the question is only the incoming page's curve; then dim
and travel gains; then the shadow by matching the luminance slice.

**Done when** the incoming and covered edges are matched, the dim is
matched, the shadow slice is within 2 % luminance, and pop is checked
with the same three quantities (pop is the reverse of push on iOS; verify
rather than assume).

*Measured 2026-09-08, five native runs.* The arriving edge's remaining
distance decays exponentially from the first frame, τ = 59–61 ms, and
the pop is the same decay toward the far side (τ = 60), settled at
450 ms; the covered page travels 0.301–0.302 of the arriving page's at
every frame; the dim is 0.096–0.100 of black per unit of progress; the
shadow is 2.1–2.5 % at 2 pt from the edge, 1.2 % at 10 pt, 0.4 % at 16 pt.
All four are now the package's constants (`SwiftCurves.push` over
400 ms, 0.30, 0.10, and a 12 pt Gaussian offset 6 pt at 3 %). Ours reads
0.300, 0.099 and a shadow within 0.5 % of native's at every offset. The
curve itself could not be confirmed to the frame on the simulator: the
Flutter example is a debug build (release does not run there), whose
first frame after a tap arrives 30–80 ms late, and the host was loaded
during every Flutter run. Confirm the curve and the latency on a device.

## 2. The back swipe

**Owns** (`lib/src/page/back_gesture.dart`): the edge width
(`_kBackGestureWidth` 20), the tracking (1:1 today), the commit rule, the
commit and cancel animations (spring or curve, and duration from the
release point), and the covered page and dim while tracking.

The commit rule is the first known deviation. The SDK's
`_CupertinoBackGestureController` (and swiftuikit, which copies it)
commits past the midpoint or at a fling of a full screen width per
second — 402 pt/s on the reference device — so a short flick springs
back unless it is fast, which is not what iOS does. Since 2026-09-08 the
package projects the release instead: commit if the page, coasting from
the release point at `UIScrollView.DecelerationRate.normal` (0.998,
`velocity × rate / (1 − rate)` per WWDC 2018 "Designing Fluid
Interfaces"), would pass the midpoint. That is a hypothesis about UIKit's
rule, not a measurement; this stage measures it. Note that a mouse drag
on the simulator releases at far lower velocities than a finger, so the
commit table is taken from scripted drags with stated velocities and
checked by hand on the device.

**Recordings** (scripted, simulator): edge drags to 20 %, 45 %, 55 % and
80 % of the width, each released at rest and with a fling (fast, slow);
one drag that goes back to the edge before release; one drag that wanders
vertically. Then the same set on the device by hand, with touch rings.

**Measure**: page left edge vs finger x while tracking (should be
identity for the edge swipe); the commit and cancel curves from release
to settle, and their duration as a function of the release position;
which releases commit, over a grid of release position (10 %, 20 %, 35 %,
50 %, 65 %, 80 %) × release velocity (−600, −200, 0, +150, +300, +600,
+1200 pt/s), the negative rows released while moving back toward the
edge.

**Tune**: the commit and cancel springs (fit them; iOS uses a spring here
and its duration depends on remaining distance); the commit rule — keep
the projection if the grid fits it with one deceleration rate, otherwise
whatever boundary the grid draws (a velocity sign rule with a position
fallback is the other common reading of UIKit). The anywhere region: same
response per pt of travel as the edge, with the tracking start at the
touch slop rather than at the edge.

**Done when** tracking is identity, the release curves are matched from
each of the four positions, and the commit table (position × velocity →
outcome) agrees on all cases.

*Measured 2026-09-08, thirteen native runs.* Tracking is not identity:
the page stays put for the first 12 pt from the touch and then sits
12 pt behind the finger (26 pt while moving at 300 pt/s, of which
~10 pt is a two-frame display lag that the ring shares with any real
finger). Every release lands on one spring, ω = 22, ζ = 0.85, from
positions of 16–76 % of the width, popping and springing back alike, to
0.7–6 pt RMS; 98 % of the distance is covered in 200–220 ms whatever the
distance, so there is no duration scaling. Outcomes: 16 % at 1200 pt/s
popped; 29 % at 400 pt/s, 30 % at 150 pt/s, 41 % and 51 % at rest sprang
back; 60 % at 150 pt/s and 76 % at rest popped; 66 % moving *back* at
500 pt/s popped. Around the boundary at rest: 52 % back, 54 % and 56 %
popped, 58 % back — so the synthetic lift carries velocity jitter and
the boundary is 0.50–0.53 with a projection window of 115–130 ms on
whatever velocity iOS reads. The package now uses the 12 pt dead zone,
that spring, and the midpoint with a 120 ms projection. XCUITest lifts
leave Flutter's velocity tracker reading zero (its 40 ms stopped-pointer
rule) where UIKit still reads the drag speed; real fingers on a device
are needed for the velocity column of the table.

## 3. The zoom push and programmatic pop

**Owns** (`lib/src/zoom/`): `kZoomPushSpring` (500 ms, no bounce; the
design doc calls its calibration pending), the card rect interpolation
(linear in progress today), `kZoomCrossFadeWindow` (0.4),
`kZoomDimmingCurve` (`easeIn`) and `dimmingColor` (0x33), the corner
radius interpolation, the alignment window (`ZoomTransitionLayer._growth`,
square-root-of-area), and the fallback flight for a missing source
(`fallbackInset` 0.05).

Seen in the stage 0 recording and not yet drawn by the package: the
native card casts a soft shadow onto the covered page, wide enough to
darken a strip 20 pt from its edge. It belongs to this stage's tuning.

**Recordings** (scripted, simulator): tap each of the three visible
posters and pop each with the back button (three source positions: near
the left edge, centre, right); the poster row scrolled so a source is
partly off-screen; the paging page swiped to another poster before the
pop (the dynamic source); the flat palette variant for cross-fade and dim.

The aligned case has no SwiftUI equivalent. Build the UIKit sample —
`UIViewController.preferredTransition = .zoom(options:)` with an
`alignmentRectProvider` returning the art's frame — as a second scene in
the native app, reached from a debug menu, and record it for this case
only.

**Measure**: card rect (all four edges) vs time; the source's content
opacity inside the card vs time (flat palette: the card's colour is a
blend of the poster orange and the page white); covered page luminance;
corner radius (fit a circle to the top-left corner's edge pixels at
25 %, 50 %, 75 %); with the alignment sample, the art's top edge inside
the card vs time.

**Tune**: fit the push spring to the width trace; fit the pop spring
separately (iOS may not use the same one); the cross-fade window and its
curve from the opacity trace; the dim curve and colour; the radius
interpolation space (card space vs screen space, section 1.4's
observation); the alignment window's growth function if the art edge
trace disagrees with square-root-of-area.

**Done when** the card's four edges are matched for all three source
positions on push and pop, opacity and dim are matched, radius is within
1 pt at the three checkpoints, and the dynamic-source pop lands on the
right poster in both.

*Measured 2026-09-08, four native runs (width only so far).* Push and pop
each fit one critically damped spring from rest at ω = 18–19.75 rad/s to
2.3–7.9 pt RMS; the pop reads as the same spring started 16–24 ms early
(its first frame is already a quarter of the way), which a spring with
initial velocity does not fit better. `kZoomPushSpring` is now ω = 19.
Ours, aligned on the first moving frame, is within 5 pt of native at
every sample of the push and fits ω = 19 to 1.3–2.1 pt RMS on the pop;
before alignment it starts 60–80 ms late on the push and 30 ms on the
pop (the debug-build latency above).

*Measured 2026-09-09, flat palette.* SwiftUI scales the whole page into
the card from its top, bar strip and all — there is no art alignment —
so the example no longer passes an `alignmentRect` (the option stays for
apps that want UIKit's provider). The card's shadow beside it at
mid-flight: 10.5 % at 4 pt, 6.1 % at 12, 3.1 % at 20, 1.7 % at 28, gone
by 40; below it 14 % at 2 pt, 9.2 % at 10, 5.7 % at 18, 3.1 % at 26 — a
Gaussian of σ ≈ 18 pt at α 0.24 offset 4 pt down, now drawn by
`ZoomTransitionLayer`. The dim, from a patch of the covered page far
from the card, is 0.15 × progress at every frame; ours was 0.2 eased in
and is now 0.15 linear. The source copy's opacity over the page's light
top strip: 0.58 at progress 0.21, 0.39 at 0.33, 0.03 at 0.63 — a
straight fade over 0.55 (ours was 0.4). The card's outline against the
covered page (dim-compensated differencing) gives its bottom edge: on the
push it trails the side edges by up to 0.05 of the travel (0.29 at 0.33,
0.58 at 0.63, 0.83 at 0.85), on the pop it leads by about 0.03; the
frame now carries both (`zoomVerticalProgress`). Verified: our push
bottom edge is within 1–3 pt of native's at every width up to 93 % of
the travel (native's page tint ends 17 pt above the screen bottom, so
the last 7 % cannot be read); pop within 13 pt over five samples before
the lead was applied. Still open: the radii, and the pop lead's
verification.

## 4. The pan dismissal

**Owns** (`ZoomDismissPhysics`): `scaleGain` 0.64, `travelKnee` 0.48,
`minimumScale` 0.33, `edgeGive` 0.04, `trackingSpring` 2000/89,
`returnSpring` 220/30, `dismissThreshold` 0.75, `flingVelocity` 700,
`maxCommitVelocity` 10; the landing spring (currently the push spring);
the pivot rule (grab point carried with the fall); the scroll handoff
(`ZoomScrollController`).

The fit these numbers come from was made on a sheet, not a page, and the
design doc flags that a full-screen card could not reach the 0.42 scale
seen natively (section 1.4). This stage settles that.

**Recordings** (scripted, simulator, then by hand on the device with
touch rings):

1. Straight drags down from the page centre to 15 %, 30 %, 50 % and 80 %
   of the height, held 1 s, released at rest.
2. The same, released with a downward fling; one released with an upward
   fling from 50 %.
3. Diagonal drags: 30 % down then 100 pt right; the same to the left; one
   that pushes past the screen edge.
4. A drag on the scrolled list page: scroll down 200 pt, then drag down
   400 pt in one motion (scroll to top, then hand off).
5. A drag from a grab point near the top of the page and one near the
   bottom, for the pivot.
6. Release cases for the commit table: 20 %, 40 %, 60 % with slow, medium
   and fast release.

**Measure**: card scale vs finger travel (in pt and in card heights);
card centre vs finger (the pivot: the grabbed content's offset from the
finger); horizontal offset vs finger x, including the lag while sweeping
(the tracking spring) and the overshoot at the edge; the landing and
return curves from release; the outcome table.

**Tune**: `scaleGain`, `travelKnee`, `minimumScale` from the scale trace —
this is where the 0.42 question is answered; the pivot rule from the
centre trace; `edgeGive` and the tracking spring from the horizontal
trace; the landing spring (fit; probably not the push spring) and
`maxCommitVelocity` from the fling landings; the return spring from
cancels; `dismissThreshold` and `flingVelocity` from the table.

**Done when** scale and centre track for all six recordings, the
horizontal lag and edge give match, landing and return curves match for
rest and fling releases, and the outcome table agrees.

*Measured 2026-09-09, flat palette, twenty-six native runs.* Scripted
with the stage 5 synthesizer: straight drags from (201, 160) to 15–80 %
of the height at 150–800 pt/s, the first 20 pt at 300; sideways sweeps
of 50–195 pt after a 30 % drop; grabs 12 pt under the bar (nothing
happens natively) and 30 pt under it, and one low on the page; a drag on
the scrolled page. The native card: still for the first 16–20 pt (the
platform's slop), then scaled about the touch point at 1 − 0.67 ×
travel/height, linear to 0.49 of the height (0.693) and eased past a
knee — 0.545 at 0.8 — which the sheet model's knee-and-floor fits at
0.52 and 0.37 to 0.002 RMS; the 0.42 in `drag.mov` was a long, wandering
drag. The touch point falls behind the finger by the cube of the travel
past the slop (0 pt at 0.13 of the height, 9 at 0.28, 39 at 0.48, 185 at
0.78; a rubber band on the travel is 8 pt out at 30 % and 20 at 80 %).
Sideways the card moves 26 pt for a 50 pt sweep, 49 for 100, 69 for 150
and 85 for 195, either way, off the screen with no give, without
touching the scale: a 0.56 gain rubber-banded toward 364 pt (0.9 of the
width), and the same band reproduces the edge swipe's vertical follow
(86 for 200, 99 for 240). A drag that begins on the scrolled page
scrolls it to the top and over-scrolls there; it never hands across.
Releases: at rest 0.914 sprang back and 0.900, 0.883, 0.881 landed —
a sixth of the height — and every slow, medium and fast release from
20 % on landed, a 120 pt pull back up at 800 pt/s from 50 % (0.766)
included: the stage 5 projection against a 0.905 boundary. Cancels
return on the stage 5 spring (ω 22.5, ζ 0.9, 0.3 pt RMS); landings on
the flight spring (98 % in 310–350 ms). The package now waits out
`kTouchSlop` from the touch (the scroll handoff catches up the slop the
scroll view kept), has `travelKnee` 0.52, `minimumScale` 0.37, the
cubic `fallLag` 0.45, `crossAxisGain` 0.56 with `crossAxisLimit` 0.9 on
both gestures (`edgeGive` and the edge pinning are gone),
`panDismissThreshold` 0.905 read through `releaseProjection`
(`flingVelocity` is gone), and the scroll position hands across only a
drag that began at the top. Verified on the rebuilt example: held scale
within 0.006 of native at 15–80 % (ours reads about 6 pt more dead zone
than the native 16–20), the page's top within 7 pt at rest,
sideways offsets within 1.5 pt at 50–195 pt, cancel curves within a
frame, and the outcome table agrees on all seventeen cases. Not
measured: the tracking spring's lag while sweeping (the sweeps were
held before release) and `maxCommitVelocity` (native fast landings
settled in the same 300–340 ms as rest ones, so the seed barely
matters).

## 5. The edge-swipe dismissal

**Owns**: the horizontal gain (travel normalised by width, pending
calibration against `back.mov` per section 3.6), the pivot while
following the finger freely, the edge width, and the shared release
rules.

**Recordings**: edge drags to 20 %, 40 %, 60 % of the width released at
rest and flung; one that continues downward after 40 %; one that returns
to the edge.

**Measure and tune**: scale vs finger x (the gain); card centre vs finger
once free; the same release fits as stage 4, checking whether iOS uses
the same landing here.

**Done when** the gain trace and the free-follow trace match and the
release curves match.

*Measured 2026-09-08, flat palette, twelve native runs.* The driver
gained a touch synthesizer (XCTest's private `XCPointerEventPath`, as
WebDriverAgent uses) so a drag can turn or reverse without lifting and
lift 8 ms after its last move; one keyframe per segment, since dense
keyframes play back compressed. A fast first move past the edge region
misses the edge recognizer and the poster pager takes the swipe, so
flings start their first 20 pt at 300 pt/s. The native card: still for
the first 12 pt from the touch (the back swipe's dead zone), then scaled
uniformly about the grab point — its left edge at the finger less the
dead zone (−4 to −15 pt at rest, −20 to −26 moving at 300 pt/s, the
display lag included), its right edge off the screen — at 1 − 0.67 ×
travel/width with no knee to 0.56 of the width (0.898 at 16 %, 0.761 at
36 %, 0.620 at 56 %). A 200 pt drop moved the card 86 pt and a 240 pt one
99 pt, at one ratio throughout (0.41–0.43) and without changing the
scale; the horizontal follow reverses 1:1. Releases: at rest 0.732 and
0.715 sprang back, 0.678 and 0.620 landed; 0.805 moving at 800 pt/s
landed, 0.659 at 800 landed, and a 14 pt flick at 1200 pt/s sprang back
— the back swipe's projection (position plus 120 ms of velocity against
a 0.70 scale boundary) fits all seven, a speed threshold does not. Every
cancel returns on the back swipe's spring (ω 22, ζ 0.9, 0.5–1.1 pt RMS
from 10–36 % of the width); a landing from rest covers 98 % in
350 ms. The package now uses the dead zone, a knee-free edge scale at
`scaleGain` 0.67, `edgeSwipeVerticalGain` 0.43, a free sideways follow
(the card was pinned inside the screen and its chase anchored a move
late, leaving it 29 pt behind the finger), `returnSpring` at ω 22 ζ 0.9
for cancels, `releaseProjection` 120 ms and `dismissThreshold` 0.70 (the
pan shares both; stage 4 measures them for it). Verified on the new
build: held scale within 0.006 of native at 16–56 %, left edge within
3 pt at rest, vertical follow 0.43, cancel curves within one frame of
native's, and the outcome table agrees on ten of eleven cases: the
exception is the 67 ms flick to 20 % at 1200 pt/s, which UIKit's edge
recognizer had barely begun to track (its card reached 0.999 and sprang
back) while ours followed the finger to 0.90 and, projected, landed. A
real finger's flick is worth checking on the device. The native touch
ring vanishes ~200 ms into a stationary hold, so rest releases are timed
from the motion's start, not the ring.

## 6. The pinch

**Owns**: scale from the fingers' distance (1:1 today, never above the
grabbed size), rotation from their angle (1:1), translation with the
focal point, the un-rotate over the landing (linear in the spring's
progress), the closing-rate release velocity window (100 ms), and the
scroll-drag cancel.

**Recordings**: XCUITest pinches at scales 0.8, 0.6, 0.4 with slow and
fast velocity; rotations of 15° and 45° at scale 0.7; a pinch that starts
over a scrolled list; on the device by hand: a pinch that opens back past
1.0, a rotate-only, and a pinch released with the fingers still moving.

**Measure**: card scale vs finger distance ratio; rotation vs finger
angle; card centre vs focal point; the un-rotate curve against the
landing's scale curve (same progress or its own); the outcome table for
pinch releases.

**Tune**: any gain or clamp that differs from 1:1; the un-rotate
relation; the velocity window; `dismissThreshold` for pinches if it is
not the pan's.

**Done when** all three traces are identity to 2 pt / 1° and the landing
matches. Trackpad pinches are out of scope (not implemented).

*Measured 2026-09-09, flat palette, twenty-eight native runs.* Two
synthesized fingers 300 pt apart about the page's centre, closed to
0.4–0.9 of their distance at 150–800 pt/s each and released at rest or
still moving; turned 15° at 0.7 and 45° at 0.5 along an arc, and 30°
without closing; carried 100 pt sideways at 0.7; spread to 1.3; closed to
0.6 and reopened to 0.9; a pinch on the scrolled page. The native card
holds its size until the fingers' distance has changed by 8.7 pt (half
the slop) and from there scales 1:1 with the distance about the focal
point — 0.925 held at 0.9 of the start, 0.824 at 0.8, 0.618 at 0.6,
0.412 at 0.4: `distance / (start − 8.7)` to 0.003 — never past 1.0
(spreading does nothing, and a card reopened to 0.9 sits at 0.925 as if
it had only closed that far), turns 1:1 with the fingers' angle and
follows the focal point 1:1, all three settling two or three frames
behind the fingers: a spring of ω 45, ζ 0.7–1.0 fits the scale trace to
0.01 RMS, which is the pan's `trackingSpring`. A turn alone, the fingers
never closing, does nothing. A pinch on the scrolled page works as on the
unscrolled one. Releases: at rest 0.515 sprang back and 0.494, 0.463,
0.412 landed — half the size — and a release still closing goes by where
the fingers are, not where the card has caught up to (fingers at 0.458
with the card at 0.630 landed; at 0.553 with the card at 0.744 sprang
back), with no projection: a 37 ms pinch to 0.8 at 800 pt/s sprang back
from a card that had not yet moved. Cancels return on the stage 5 spring
(ω 22.5, ζ 0.9); a turned card un-rotates over the return slightly ahead
of the scale (at 15°, within 0.8° of linear in the scale's progress
either way; at 45°, 4–8° ahead of linear and 4° behind a lerp of the
transform), which the rounded corners bias at large turns. Landings at
rest reach the source in 180 ms with a 6 % overshoot (ω 17, ζ 0.7, 0.015
RMS) rather than on the critically damped flight spring; native short
pan landings in the stage 4 recordings read the same (ω 16, ζ 0.8) while
long ones fit ζ ≥ 1, so the landing's spring is a cross-gesture question
for stage 8, not a pinch rule. The package now waits out `kTouchSlop / 2`
of distance and anchors the pinch where the dead zone ends, chases the
scale, turn and focal offset through `trackingSpring`, commits on the
fingers' ratio against `pinchDismissThreshold` 0.5 without projection,
and no longer ends a pinch when a scroll view wins the first finger's
arena (which cancelled the pan recognizer under it — every two-finger
pinch begun on a list died on its first move). Verified on the rebuilt
example, twenty-three runs each: held scale within 0.009 of native at
0.4–0.9 (ours reads 11 pt of dead zone to the native 8.7), the scale
within 0.01 of native's at every finger position on the way and settled
within two frames of it, the card where the fingers were at release
within 0.04 on every moving release, the focal follow within 1 pt, the
turn within 2° (the box reading is biased by the corner radii, which
stage 3 has yet to match), and the outcome table agrees on all
twenty-three cases. Not measured: the un-rotate at large turns beyond
the reading above, the landing seed for fast releases (native lands in
65–127 ms from a fast pinch, ours in 200–300), and a second finger
landing during a pan. The example's poster pager follows one finger, so
a two-finger turn over it can scroll the posters (75 pt in one of two
runs) where UIKit's centroid stays put: an example-app difference, not
the transition's.

## 7. Interruptions

**Owns**: the grab during a push (the frame it is caught at, and that the
push completes into the gesture), catching a landing card and a
returning card, the re-grab, the nav bar hero during all of these, and
the paging page's source change mid-gesture.

**Recordings** (scripted: the timing has to be exact): tap a poster and
touch down 80 ms, 200 ms and 350 ms into the push, hold 500 ms, release;
commit a pan and touch down 60 ms and 150 ms into the landing, then drag
back up and release; cancel a pan and touch down during the return; the
same on the device by hand with rings.

**Measure**: the card rect on the frame of the touch down versus the
frame before (a caught card must not jump: ≤ 1 pt); the rect during the
hold (must not move); the resumed curve after release against the native
one from the same state; the nav bar's title and back button through the
sequence, frame by frame.

**Tune**: whatever jumps. Known candidates: the first-frame hand-off from
the flight line to the departure frame, the `_kReturnStart` nudge (0.02),
and the hero flight's placeholder timing.

**Done when** no catch jumps more than 1 pt in either app and the resumed
curves match.

*Measured 2026-09-09, flat palette, nineteen native runs.* The rig cannot
land a finger a set number of milliseconds into a flight: fingers in one
touch sequence must land together (the daemon plays a path that starts
later as a move of the finger before it, which never lifts — the first
batch's rings show one finger sliding from the tap to the catch point),
it refuses a sequence while another plays (`XCTDaemonErrorDomain` 21),
and it reports a sequence played about 240 ms after its last event, so
the earliest a second sequence's finger lands is ~250 ms after a tap's
lift or a pan's. That reaches a push (the native card is at 0.7–0.95 of
its width) but not a 220 ms landing or return, which were over by the
time the finger arrived; those need a device and a hand. What the push
showed: **a touch does not stop the native card.** Held from before the
push began to after it ended, the finger changed nothing, and moved 0.3 s
later it panned the open page from its own touch point. Landed at
0.78–0.82 of the width and dragged at once (300 pt/s), the card kept
growing for three or four frames after the drag began — to 0.99 at 40 pt
of travel — and then read as the pan's scale of the *full* screen, 0.848
at 200 pt in both runs, not of the card as grabbed, which would have been
a fifth smaller for the rest of the pan; released at rest it landed. A
flick at 0.70 and 0.83 of the push (100 pt at 800 pt/s, lifted moving)
landed both times, from a card that had grown to 0.955 under it. A pinch
begun at 0.95 took the card from where it was and read as a pinch on the
open page (0.618 at 0.6 of the fingers' distance, the stage 6 rule). A
touch during the landing reached the page underneath: the poster took it
as a tap and, lifted half a second later, pushed again. The package no
longer grabs on a pointer down — the pan begins as it leaves its dead
zone, the pinch as it leaves its own — and a pan or edge swipe begun
during a flight to full screen (the push, or the return of a cancelled
dismissal) carries the card on with the flight's own spring from the
controller's value and velocity while the gesture applies on top
(`ZoomFlight`), so the route's progress has one writer; a pinch scales a
snapshot and stops the flight where it begins. A landing card is not
grabbed, and the touch reaches the page underneath: a committed release
now pops at once, the landing being the pop's own transition seeded with
the release velocity (popping once landed, with the finger down, made
the navigator cancel it), the user gesture ends at the commit (every
route's modal scope ignores pointers while one is reported), the popping
route ignores pointers above its gesture layer, and the hidden source
stays hit-testable. Two rig findings fell out: the pan's and edge
swipe's travel came from the recognizer's local delta, which a card in
flight scales (30 pt of finger read as 40 of travel at 0.5), and a lone
drag recognizer wins the arena on the pointer down, so the old
grab-on-down reported a user gesture for a mere touch. Verified on the
rebuilt example, eight runs: a held finger and the push flies on to full
screen; a drag begun in flight reads 0.844–0.851 at 200 pt to native's
0.848–0.859 and lands; a flick lands from 0.937–0.950 to native's
0.952–0.955;
a pinch in flight takes the card; a touch during the landing lets it
land and, lifted, pushes again (the tile's tap handler fires, checked
from the app's log); a touch during the return lets it return. The rig
lands the finger later in our push than in native's (0.94 of the width
against 0.7–0.83, our push starting sooner after the tap), so the
in-flight growth under a drag is native's to see, not ours; on the way,
the flight completing under the pan is the model the tests hold.

## 8. Everything else, once

Not tuned, just confirmed side by side with a screenshot or short clip
each: Reduce Motion (both cross-fade; check the duration), the dimming
blur (native has none by default; compare against a UIKit sample with
`dimmingVisualEffect`), a missing source (native's centre scale-and-fade
against `fallbackInset`), the tap on a covered page during a flight
(neither app should pass it through), the status bar and home indicator
during flights, and rotation of the device while a card is held (iOS
lets go; confirm we do something sane).

*Measured 2026-09-09, flat palette, from the stage 3–7 native runs plus
eight new ones.* The landing first: the stage 4–6 analyzers fitted a
landing on the art's top edge, which the copy fading in pulls up
mid-flight, so native's landings from 0.55–0.81 of the screen read as a
stiff, overdamped spring settling in 340 ms while the short ones read
ω 15–16, ζ 0.8. Refitted on the left edge (`analyze_landing.py`, whose
seed is signed toward the target), every native pan landing, released at
rest or flung at 150–800 pt/s from 0.55–0.90 of the screen, is one
spring: ω 13.5–17.5, ζ 0.65–0.85, no seed, 0.4–2.9 pt RMS over twenty
runs, 98 % of the way in 200–270 ms, and it overshoots the source by 3 %
of the way (6.6 pt on two runs, ζ 0.73) and eases back over the next
300 ms before the source itself shows. Edge swipes released at rest fit
ω 10–12, ζ 0.6–0.65 (0.4–1.5 pt) and one spring for all three gestures,
ω 15 ζ 0.75, holds every rest release to 2.4 pt. Released moving, a
pinch lands sooner — 117 ms at 800 pt/s a finger, 170 at 400, 165–215 at
rest — as the fingers' closing rate over the scale still to go, and an
edge fling at 800 pt/s landed in 100 ms; a flung pan lands in the rest
ones' time. The package now lands on `landingSpring` (ω 15, ζ 0.75)
seeded with the release rate over what the landing has left for pinches
and edge swipes, nothing for pans, capped at 8 in progress per second
(a seeded linear spring bounces where native's fast landings do not: 8
trades the last 60 ms for a 3.6 % overshoot). Verified on the rebuilt
example: pans ω 15.5 ζ 0.75 to 0.4–0.8 pt, 98 % in 202–245 ms (native
233–270); an edge swipe at rest 213 ms (213); pinches at rest 178–182 ms
(165–215), at 400 pt/s 168 (170), at 800 pt/s 167 (117, the cap); an edge
fling 198 ms (100) — the two fast residuals stand.

The corner radius, read by fitting a circle to the card's top-left corner
(the orange copy early, the white page top late; iOS's continuous corners
read 13–14 for the poster's 12): native 13 at the source, 16.5 at 0.13 of
the way, 21.5 at 0.25, 27 at 0.37, 33 at 0.48, 36 at 0.47 on the pop, 44
at 0.72 and 55 at 0.78 — a straight line from the poster's radius to the
display's in the flight's progress, which is what `zoomFlightFrame`
already draws: ours read 17, 19, 21, 24, 28 and 30 at 0.08–0.36, within
3 pt. No change but the frame's doc.

The bar: natively the bar's items stay pinned above the card, which
passes under them with its own white top strip showing through, and
cross-fade in place — on a push the back button fades in over the first
140 ms and the title swaps in a 50 ms cross-fade 90 ms in; a dismissal
swaps the bar to the home items 150 ms into the drag and back on a
cancel; a landing fades the back button out over its 235 ms. With a
`CupertinoNavigationBar` on each page the Cupertino hero flight runs
instead, sliding the new title in over the whole flight and switching on
the pop, a known deviation without an idiomatic hook (the hero's shuttle
is the bar's own); the status bar zone follows the same split, dimming
with the covered page natively and white from the first frame under the
hero. The example's poster bar read blue (221, 239, 252) at rest against
native's white: `CupertinoNavigationBar` hides its background at the top
of the scroll, which SwiftUI's does not here, so the example turns
`automaticBackgroundVisibility` off. The once-over: a tap beside the
flying card at 0.95 of the screen (as soon as the daemon allows) reached
the covered page in neither app; the home indicator dims with the page
in both; neither app blurs the dim by default, and the UIKit
`dimmingVisualEffect` sample was not built. A pop to a poster four
swipes along — Quartz, two and a half widths past the row's edge and
built by neither app's lazy row — flew toward the poster's off-screen
position natively, the card shrinking off the right edge while the
Dunes poster faded back in, where ours takes the centred fallback; to
Nimbus, one width past the edge and inside the example's cache extent,
both apps fly the card off the right edge toward it, native's gone in
130 ms and ours in 80. Reduce Motion: native cross-fades the page in over
about 140 ms on the push and out over the same on the pop, the bar
switching with it; the example still zoomed with the setting on, before
and after a simulator reboot, so Flutter's process did not report it
here — the package's own cross-fade is exercised by its test and now
runs over `kZoomReduceMotionDuration`, 140 ms, to be confirmed on a
device. The native app is portrait-only and the
driver cannot turn the device mid-sequence, so rotation while a card is
held is the package's reading of the plan's premise alone: a change of
the window's size lets go — a release at rest, landing or returning to
the window as it is now, the rest of that touch not a new grab — tested
in the package, not against native.

## 9. Sign-off

- One side-by-side video per stage, native left and ours right, both
  from the same scripted run, cut to the same trigger frame, in
  `docs/parity/` at a size pub.dev tolerates (these are the README GIFs
  too).
- `design.md` section 1.4 extended with the calibrated table and every
  constant's recording; the "pending calibration" notes in 3.4, 3.6 and
  3.9 resolved or moved to a "known deviations" list with the measured
  size of each deviation.
- CHANGELOG entry for 0.1.0 stating what was matched and to what
  tolerance, and which iOS build was the reference.
- The blind A/B run once more across all gestures at the end, because
  tuning one stage can shift the feel of another (the landing spring is
  shared by stages 4–7).

Carried in from stages 3–8, to settle before the sign-off:

- **Fast landings.** An edge swipe flung at 800 pt/s lands natively in
  100 ms and a pinch released still closing in 117, where ours take 198
  and 167 (stage 8): a linear spring seeded that hard overshoots, native
  does not, so the landing is probably a duration-driven completion.
  Record the flings at 400, 800 and 1200 pt/s in both gestures, fit the
  settle time against the release rate, and either seed differently or
  give the landing a duration from the rate.
- **The pop lead.** Stage 3 measured the pop's bottom edge leading by
  0.03 of the travel and applied it, then never re-verified it; one
  `native_zoom` against the current build settles it.
- **A second finger during a pan.** Stage 6 measured a pinch from rest
  and from a scroll, not one begun on a card already held by a pan;
  one native run each of a pan at 30 % joined by a second finger that
  closes, and one where it merely lands and lifts.
- **The bar.** Native cross-fades the title and back button in place
  within 140 ms of a push and swaps them to the covered page's 150 ms
  into a drag; the Cupertino hero slides the title over the flight and
  switches on the pop (stage 8). No idiomatic hook exists, so this goes
  on the known deviations list with those numbers, and the host app
  notes say a bar above the navigator is the native shape.
- **On a device, by hand.** Reduce Motion for the example (the Flutter
  process never reported the simulator's setting); the 67 ms edge
  flick and the 14 pt zoom flick, whose outcomes turn on a real
  finger's velocity (stages 2 and 5); the first frame after a tap,
  30–80 ms late in the simulator's debug build (stage 1); the pinch
  un-rotate at 45° (stage 6); rotation while a card is held, which the
  package answers by letting go (stage 8).

*Measured 2026-09-09, flat palette, from six new native runs at three
release rates in each gesture plus the stage 4–6 landings refitted.* The
landing is not seeded harder for a fast release; it is a quicker spring.
Native settle times go with the speed a *finger* was moving at the
release, not with the shrink that speed was driving and not with the
distance the card has left: 165–245 ms released at rest, 170–217 at
400 pt/s a finger, 100 (edge swipe) to 117–133 (pinch) at 800, and
103–108 at 1200, where the edge swipe's card is shrinking at a third of
the rate the pinch's is and lands from half as far. A pan is the
exception it always was, landing in 233–272 ms however hard it was
flung. So `ZoomDismissPhysics` gains `landingQuickening` and
`landingSpringFor`, which put the release speed on the landing spring's
frequency and leave its damping alone — a quick landing overshoots the
source by the same 3 % a slow one does — and the seed stays what it was,
the card carrying on at the rate the fingers left it at. At 0.3 of the
frequency per resting card width per second the modelled landing sits
inside native's spread everywhere but the edge swipe flung at 800 pt/s,
which lands 36 ms sooner than any one line through the rest allows.
Two of the six runs do not land at all in either app: an edge swipe to
0.4 of the width released at 400 and 800 pt/s springs back, natively and
here, which is the boundary stage 5 measured working as it should.

Verified on the rebuilt example: a pinch released at 800 pt/s a finger
lands in 118 ms against native's 117–133, where it took 167 before, and
at 1200 in 117; at 400 it takes 137 against native's 170–217, a landing
that is now a little quick rather than a lot slow. The edge swipe flung
at 800 lands in 168 ms against native's 100 — 34 ms better than before
and the residual that stands, since the same release speed buys the
pinch three times the shrink. Pans are untouched by the quickening and
stage 8's verification stands; this batch's pan run dropped a fifth of a
second of frames on a host at a load average of 50 and cannot time a
landing at all.

The pop's lead is not resolvable on this rig. The tracker's card box
during a pop is the source's copy fading in, not the card, and the card
itself cannot be differenced out of the covered page — its white page
over the gallery's white leaves nothing to see, so a dim-compensated
difference (`analyze_outline.py`) reads the card's edges to about 0.05
of the travel, where the lead is 0.03. Stage 3's measurement stands and
the package applies it; the check moves to the device list.

A second finger during a pan was scriptable after all, in the package
rather than on the rig: the synthesizer cannot land a finger while
another is down, but the widget test can, and it found a bug. A finger
landing on a held card moved the point the pan counts its travel from,
so a pinch that never began — the second finger inside its dead zone,
then gone — jerked the card back to full screen as soon as the first
finger moved on. The pan now keeps the pointer it started with, and both
cases are tested: the finger that closes takes the gesture as a pinch
from where the fingers are, the finger that only rests leaves the pan
alone. What native does with either is still unmeasured, and joins the
device list.

*Measured 2026-09-10, from the stage 2 scripts re-run with a probe on the
release.* A flung back swipe sprang back where native popped, and the
momentum was gone before the physics saw it: Flutter's default
least-squares velocity tracker reported 497 pt/s for the 1200 pt/s fling
of `testSwipe20Fling` and 121 for the 400 of `testSwipe35Medium`, which
the commit rule reads as 0.35 and 0.38 of the width — both short of the
0.53 threshold stage 2 fitted. `IOSScrollViewFlingVelocityTracker`, which
a `Scrollable` on iOS already uses to match the platform's own fling,
reads the same two releases at 1312 and 288 and leaves a release at rest
at zero. With it the outcome of all nine stage 2 scripts matches native,
the fling included, and a cancelled flick carries on past the finger
first as native's does — 6 pt against native's 5.4. The release curve is
unchanged (the fling settles in 212 ms against native's 193, τ 38 against
43; the slow pop 217 against 232).

*Measured 2026-09-10, from the grid the covered page carries.* The page
under a zoom route is scaled down, which the package did not do at all.
The poster row's outer edges — 384 pt apart at rest, and the card never
covers both until it is nearly full screen — close to 0.914 of that with
the card at full screen, about a point at x 202 where the screen's centre
is 201. The scale runs straight with the flight: 0.989 at 0.12 of it,
0.968 at 0.36, 0.944 at 0.65, 0.931 at 0.78, within 0.003 of the line
everywhere. It does not follow a gesture — the page holds at 0.914 while
a pinch takes the card from 327 pt to 186 — and on a committed dismissal
it comes home on its own critically damped ω 15, finishing 270 ms after
the card has landed where the card's seeded landing takes 215. Ours now
reads 0.938 at the same card width native does, holds through the whole
gesture, and finishes 233 ms after the card. A source measured while the
page is scaled is read back to its resting rect, or a pop would fly to a
poster 10 pt small.

*Measured 2026-09-10, from the native edge flings against the line each
takes from its release to the source.* A landing does not run the card
straight home. Native carries the card the way it was going first: an
edge swipe flung at 800 pt/s takes it 28–30 pt past that line, peaking 48
to 63 ms after the lift, and one at 1200 takes it 38 pt at 92 ms — far
enough that the card sits 23 pt past the poster's own left edge while it
is still 190 pt wide, which one progress along a line cannot express.
Ours carried 2 to 3. The departure now carries the release's motion
(`ZoomDeparture.velocity`) and the route runs it as a decaying offset on
the landing spring, in points, added to the flight frame; the spring is
the plain one, since native's carry peaks at 60 to 90 ms whatever the
release speed where the quickened spring would pull it to 40. Verified:
21 pt at 63 ms against native's 30 at 63, and 34 at 55 against 38 at 92.
A release at rest seeds nothing and pans are unchanged. A landing ends
when the card has arrived, not when its progress has: the carry outlives
the progress spring, and a card 43 pt from its source when the route left
jumped the rest of the way as the source took over — visible on a swipe
pulled down and to the right, where the carry is largest.
`testZoomEdge65DownFling` is that gesture scripted, out to 65 % and 200 pt
down in one move; on it the card now rides in to the source and sits
through its overshoot (120 to 116.6 pt and back) as native's does (114.7
and back), neither of them jumping at the handover. The carry is on
both axes: a drag recognizer reports only its own — a horizontal one
zeroes the vertical — so the gesture layer keeps its own tracker on the
finger and the card carries the follow's slope across the axis as well as
the chase's speed along it, or an edge swipe let go on the move lands on
one plane. Verified: 23.7 pt across and 23.9 down against native's 30.5
and 36.8, and a swipe released at 60 % now carries forward (13.4 pt)
where it used to net backward. What is left is
that native's position and size are on separate clocks — its card hardly
shrinks for the first 100 ms of a fling's landing while the carry plays
out — where ours shrinks throughout, so an edge swipe released at 60 % of
the width still nets leftward where native's nets right.

The same tracker goes on the dismissal's pan and edge swipe, which read
the 800 pt/s edge fling of `testZoomEdge40Fling` as 301. Fifteen scripted
pans and edge swipes were re-recorded across stages 4 and 5, at every
speed each has: every outcome still matches native, held scales within
0.01, and the edge swipe flung at 800 now lands in 147 ms against
native's 100 where it took 168, at 1200 in 132 against 108. The residual
stands and its cause is unchanged — the same finger speed buys a pinch
three times the shrink it buys an edge swipe — but a third of it was our
own reading of the finger.

*Measured 2026-09-09, from every native landing already recorded, read
past the frame `analyze_landing.py` stops at.* A landing does not stop on
the source: it carries the card past it and eases back. Native goes 1.9 %
of the flight past on a pinch released at rest, 2.2 % on a pan, 2.3 % on
an edge swipe and 8.0 % on a pinch released at 800 pt/s a finger, back
within a point of the source over 172–250 ms. Ours went nowhere past it,
because `AnimationController` clamps every simulation value to the
controller's bounds (`_tick`): the ζ = 0.75 stage 8 fitted always implied
an overshoot, and the half of it below zero never reached the screen.
The route now reads the landing spring's own value while the controller
is pinned at zero — the pop still finishes when the spring settles, so
nothing about its timing moves — and `zoomDepartureFrame` carries the card
on past the source, where it is the source and its corners shrink with it.
The programmatic pop does not overshoot in either app, and does not here.

Verified on the rebuilt example: 2.1 % past the source on the pan against
native's 2.2, 2.0 % on the edge swipe against 2.3, 1.0 % on the pinch at
rest against 1.9, and 2.1 % on the pinch at 800 pt/s against 8.0 with the
landing still settling in native's own 117 ms. The fast pinch is the
residual, and its cause is the model: native puts a release's speed into
the seed, `landingQuickening` puts it into the frequency, and a quicker
spring travels less past the target for the same seed — the whole native
traces refit to ω 11.5–13 with the seed carrying the speed instead
(−6.5 at rest to −26 fast), which is a re-fit of the landing law rather
than a constant to move. `maxCommitVelocity` rises from 8 to 20: the 8
was there so the landing would not bounce, which is no longer something
to avoid. The tool is `analyze_overshoot.py`.

The covered page is a second thing the same runs show. Natively it is
scaled while the zoom is open — a sibling poster in the grid reads 116.6
pt wide mid-flight against 119.3 at rest, its left edge 32.0 against
16.7, so the page is at 0.914 or smaller — and it comes back to rest
about 200 ms after the card lands. Ours holds it at full scale
throughout. Section 1.4's measurement said 1.0 and was wrong; both it and
1.7 now carry the number. Matching it touches the push as much as the
landing and is not part of this stage.

*Measured 2026-09-09, from the native and rebuilt runs of the same
script.* The card sheds its shadow before it lands. The page 12 and 20 pt
beside a native card reads its own colour from a twentieth of the flight
in — 0.0 % and 0.0 % against the same page well away from the card — and
the shadow is still there at a tenth (10.6 % darker 2 pt out, 7.9 at 6,
4.6 at 12, 2.4 at 20), which is the profile stage 3 fitted at mid-flight.
Ours carried it all the way in: 5.3 % and 2.8 % darker at 12 and 20 pt
for the whole landing, and gone the frame the route popped, a snap the
overshoot only made more visible by keeping the card there longer. The
shadow now fades out over the last tenth of the flight, and the same
probe reads 0.0 % at both offsets with no step at the pop. Where between
a tenth and a twentieth native's own fade sits is not readable on this
rig: the neighbouring poster is in the band at every offset small enough
to see it.

The sign-off itself: eight clips in `docs/parity/`, one per stage that
has a gesture or a flight of its own, cut by `sidebyside.py`; the
calibrated parameters and the known deviations in `design.md` 1.6 and
1.7; and the release's CHANGELOG entry. Two things are left, and both
need a phone rather than the rig: the by-hand list above, and the blind
A/B across all gestures.

---

## Order and estimates

| Stage | Depends on | Estimate |
|---|---|---|
| 0 Rig | — | 2–3 days (native app 1, driver 1, tracker 1) |
| 1 Push | 0 | 1 day |
| 2 Back swipe | 1 | 1 day |
| 3 Zoom push/pop | 0 | 1–2 days (UIKit alignment sample adds half a day) |
| 4 Pan | 3 | 2 days (the scale model may need reworking, not just retuning) |
| 5 Edge swipe | 4 | half a day |
| 6 Pinch | 4 | 1 day |
| 7 Interruptions | 4–6 | 1 day |
| 8 Everything else | 3 | half a day |
| 9 Sign-off | all | half a day |

Stages 1–2 and 3 are independent and can be interleaved. Stage 4 is the
one most likely to change code rather than constants; if the scale trace
does not fit the knee-and-asymptote model, the model changes there, and
stages 5–7 wait for it.

## Risks

- **The simulator is not the phone.** Simulator recordings drop frames and
  its springs run on the host clock. Curves are fitted from the simulator
  because it is scriptable, then spot-checked on the device by hand: one
  recording per stage, aligned on the touch ring, must agree with the
  simulator fit to the same tolerance, or the device trace wins.
- **iOS versions.** A tuned constant is for the pinned iOS build. The
  `VERSIONS` file and the per-constant recording names make a retune
  mechanical when iOS 27 ships.
- **SwiftUI vs UIKit.** SwiftUI's zoom is UIKit's underneath, but the nav
  bar, the sheet-like paging and the back gesture have SwiftUI-specific
  behaviour. Where a difference looks like a SwiftUI quirk rather than the
  transition, the UIKit sample scene is the reference; note which was used.
- **Measurement error.** 2 pt on a 3× display is 6 px; the tracker must
  be validated first on a synthetic recording (a rendered rectangle moving
  on a known curve) to confirm it reports the curve to within 1 px.
