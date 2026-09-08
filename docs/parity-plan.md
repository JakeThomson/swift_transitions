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
pop (the debug-build latency above). Not yet measured: the other edges,
the cross-fade, the dim and the card's shadow, the radii.

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

## 8. Everything else, once

Not tuned, just confirmed side by side with a screenshot or short clip
each: Reduce Motion (both cross-fade; check the duration), the dimming
blur (native has none by default; compare against a UIKit sample with
`dimmingVisualEffect`), a missing source (native's centre scale-and-fade
against `fallbackInset`), the tap on a covered page during a flight
(neither app should pass it through), the status bar and home indicator
during flights, and rotation of the device while a card is held (iOS
lets go; confirm we do something sane).

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
