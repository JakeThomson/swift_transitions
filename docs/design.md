# swift_transitions: design and implementation plan

Status: proposal, 2026-09-02; M0–M5 implemented as of 2026-09-08, with the
deviations noted inline.

This package recreates two iOS navigation transitions in Flutter, with the
gestures that iOS 18 and iOS 26 attach to them:

1. **The push transition** (`SwiftPageRoute`): the standard iOS slide with the
   incoming page's leading corners clipped to the physical display corner
   radius, the receding page's parallax, and the back swipe.
2. **The zoom transition** (`ZoomPageRoute` + `ZoomTransitionSource`): a page
   that grows out of a source cell and shrinks back into it, with continuously
   interactive dismissal by dragging down anywhere on the page, by the edge
   back swipe, or by pinching.

The design borrows its vocabulary from Flutter's `Hero` (tags, source and
destination, placeholders, `transitionOnUserGestures`) and its options from
Apple's `UIZoomTransitionOptions` and SwiftUI's `matchedTransitionSource`.
It depends on the Flutter SDK only.

Contents:

- [1. Reference behaviour](#1-reference-behaviour)
- [2. Public API](#2-public-api)
- [3. Architecture](#3-architecture)
- [4. Package layout](#4-package-layout)
- [5. Testing](#5-testing)
- [6. Delivery plan](#6-delivery-plan)
- [7. Risks and open decisions](#7-risks-and-open-decisions)
- [8. Host app integration notes](#8-host-app-integration-notes)
- [9. References](#9-references)

---

## 1. Reference behaviour

Everything below was measured from three screen recordings of the Apple TV app
on iOS 26 (a show page opened from a poster in a "Related" row), plus Apple's
documentation. Frame strips were extracted with `ffmpeg` at 30 and 60 fps;
luminance was measured with `signalstats`. Numbers are approximate and are
inputs to the calibration tasks in section 6, not specifications.

### 1.1 Push transition (standard navigation push)

Apple's behaviour, which Flutter's `CupertinoPageTransition` already models
except for the corners:

- The incoming page slides in from the trailing edge; the covered page slides
  out by 0.29 of the width on the same curve and is dimmed in proportion
  (measured below). Flutter uses `Curves.fastEaseInToSlowEaseOut` over 500 ms
  for the incoming page, a third of the width on a curve of its own for the
  covered page, and a barrier colour of `0x18000000` for the dim.
- The incoming page's leading corners are clipped to the display corner radius
  while it is in motion. At rest the clip is removed.
- A soft shadow runs along the incoming page's leading edge.
- The back swipe starts on the leading 20 pt (or the notch inset if larger).
  On commit the remaining travel runs over 350 ms; a fling of one screen width
  per second commits regardless of position.
- Navigation bar items do not travel with the page. They belong to the stack
  and cross-fade (Flutter apps that want this use a shell above the navigator,
  see section 8; the package does not draw bar chrome).

Measured 2026-09-07 from a native Settings recording (`push.mov`, iPhone
Mirroring, the push read at 60 fps and a held back swipe at 5 fps, the top
page's edge and the covered page's shift found by matching against the
at-rest frames):

| Quantity | Observed | Flutter SDK |
|---|---|---|
| Covered page travel at full progress | 0.30 of the width (0.299–0.302 at every frame of a push and a pop, parity stage 1; 0.283–0.288 across a held swipe in the earlier device recording) | 1/3 |
| Arriving page's curve | exponential decay of the remaining distance, time constant 61 ms (log-linear fit over 24 frames, residual 0.06); the pop is the same decay toward the far side; no ease-in (the first frame moves a fifth of the width); settled to half a point at 400 ms (parity stage 1, iOS 27.0 simulator) | `fastEaseInToSlowEaseOut` over 500 ms |
| Covered page timing | linear in the top page's progress: one progress drives both pages, in the push and under the finger | its own `linearToEaseOut` curve; linear only during the gesture, and only when the covered route runs its own transition |
| Dim on the covered page | black at alpha 0.10 × progress, linear (0.089–0.104 at every frame of a push, read beside the arriving edge; parity stage 1. The earlier device recording read 0.115 under the settled page, where the arriving page's shadow also falls) | barrier `0x18000000` (alpha 0.094) on `Curves.ease`; none at all for a Material route |
| Leading-edge shadow | about 2 % darker at the edge, gone within 16–18 pt, at every progress (parity stage 1) | `0x04000000` gradient over 5 % of the width |

The same app recorded through swift_transitions installed as a
`PageTransitionsTheme` showed the covered page lagging on a curve during the
swipe (0.25 of the width at 87 % progress, not tracking the finger) and no
dim: `MaterialRouteTransitionMixin` has no barrier colour, and a covered
route that does not share the top route's delegated transition (a
`CupertinoPage` under a Material page, or the reverse) receives the SDK's
static delegate, which always curves and knows nothing about the gesture.
swiftuikit 0.2.1 has the same SDK curves and dim, a 0.40 overlap and a
blur-100 shadow; it does not address either point.

### 1.2 Zoom push

From the recording at 60 fps (`pinch.mp4`, 5.55 s to 5.70 s):

- The source poster begins to enlarge in place. Within about 120 ms the card
  covers most of the screen; the settle to full screen takes the remainder of
  roughly 0.5 s. This is a spring with little or no bounce and a fast initial
  travel.
- The card's shape interpolates from the poster's frame and corner radius to
  the full screen and the display corner radius. The aspect ratio changes
  during the flight, so this is a rect interpolation, not a uniform scale.
- The card's content cross-fades from the source's pixels to the page's pixels
  during the first part of the flight.
- The page underneath stays at full scale and dims progressively. At the end
  of the push the strips of the covered page still visible at the card's edges
  are heavily darkened.
- The source cell is hidden for as long as the zoomed page is presented. Its
  slot keeps its size (an empty gap is visible in the row underneath during
  the dismissal).

### 1.3 Zoom dismissal

Three gestures drive the same shrink. In every case the whole page becomes a
scaled card that follows the finger, the page underneath is visible at full
scale with a light dim, and the navigation bar items stay pinned at the top of
the screen at full size.

**Pan down anywhere** (`drag.mov`; parity stage 4). A downward drag on the
page content starts the dismissal after the platform's slop (the card holds
still for the first 16–20 pt): the page scales down about its touch point,
linearly at 0.67 per screen height to a knee at half the height and eased
past it (0.545 at 0.8 of the height; a floor near 0.37 is implied), and
falls with the finger — behind it by the cube of the travel: 0.89 of the
finger's travel at half the height, 0.73 at 0.8. Sideways it follows
at 0.56 of the finger at first and less as it goes (26 pt for 50, 85 for
195), freely, off either side of the screen. A release
lands from a sixth of the height on (0.914 at rest sprang back, 0.900
landed). A drag that begins on a scrolled page scrolls it to its top and
over-scrolls there; it never becomes a dismissal, and a drag 12 pt under
the bar does nothing.

**Edge back swipe** (`back.mov`; parity stage 5). Dragging from the leading
edge does not slide the page. It shrinks it about the grabbed point, with
scale driven by horizontal distance past a 12 pt dead zone (0.67 per screen
width, no knee to at least 0.56 of the width), and the card follows the
finger sideways 1:1 — off the far side of the screen if the finger goes
that far — and vertically through the pan's cross-axis band (86 pt for a
200 pt drop). A cancelled
release returns on the back swipe's spring (ω 22, ζ 0.9).

**Pinch** (`pinch.mp4`). Two fingers scale the page with the pinch, rotate it
with the two-finger rotation, and translate it with the focal point. The card
can be rotated by tens of degrees mid-gesture.

**Release.** If the gesture is released far enough or fast enough, the card
flies into the source cell's frame, un-rotating on the way, and its content
cross-fades to the source's content over the last part of the flight. The
source cell reappears at the end. Landing from a nearby position took about
six frames at 30 fps (0.2 s); from further away it is a velocity-seeded
spring. If released early the card springs back to full screen. In the
`drag.mov` recording a short drag released after 0.3 s snapped back.

**Interruption.** Apple documents that the push is never cancelled: a grab
during the push completes the push and starts a pop within one run loop
iteration, and a cancelled pop returns to the appeared state. The user can
grab the card at any time during any animation.

### 1.4 Measurements

| Quantity | Observed | Notes |
|---|---|---|
| Push travel to ~90 % of screen | ~120 ms | 60 fps strip, `pinch.mp4` 5.57–5.68 s |
| Push settle (visual) | ~0.4–0.5 s total | includes dim ramp |
| Card scale mid-pan | ~0.54 | `drag.mov` 3.0 s, card width 370 of 686 px |
| Card scale at the end of a long, wandering pan | ~0.42 | `drag_land` strip |
| Card scale mid-pinch | ~0.6 | `pinch.mp4` 1.3 s |
| Pinch scale vs fingers' distance | 1:1 from 8.7 pt of closing; turn 1:1; 0.515 sprang back, 0.494 landed | parity stage 6, `native_ZoomPinch*` |
| On-screen corner radius during a flight | 13 pt at the source, 22 a quarter of the way, 33 at half, 44 at three quarters | a straight line from the source's radius to the display's in the flight's progress (parity stage 8, `native_zoom_f`) |
| Release velocity of a flick | the default tracker reads 497 and 121 pt/s where the finger moved at 1200 and 400, and a zoom edge swipe's 800 as 301; `IOSScrollViewFlingVelocityTracker` reads the first two at 1312 and 288 | parity stage 2, `testSwipe20Fling`, `testSwipe35Medium`, `testZoomEdge40Fling` |
| Card shadow during a zoom flight | 10 % darker 4 pt out, 3 % at 20, gone by 40; none at all within a twentieth of the source | parity stages 3 and 9, the page beside a landing card |
| Covered page luminance during dismissal | −4 % to −7 % | Y average of a thumbnail region: 71.5 at rest vs 66.8 mid-drag |
| Covered page scale under a zoom | 0.914 at full screen, straight with the flight (0.989 at 0.12 of it, 0.968 at 0.36, 0.944 at 0.65), about the screen's centre; held still under a gesture; home on a critically damped ω 15 that finishes 270 ms after the card lands | parity stage 9, the poster row's outer edges in `native_ZoomPinch45Rest`, `native_ZoomPan30Rest` |
| Landing from a release | ω 15, ζ 0.75; 98 % in 230–270 ms from rest, 170–217 ms at 400 pt/s a finger, 100–133 at 800, 103–108 at 1200 | parity stages 8 and 9, `native_ZoomPan*`, `native_ZoomPinch*`, `native_ZoomEdge*Fling*` |
| Landing carry | an edge swipe flung at 800 pt/s takes the card 28–30 pt past the line from the release to the source, at 800 pt/s peaking 48–63 ms in and at 1200 38 pt at 92 ms | parity stage 9, `native_ZoomEdge40/60Fling`, `native2_ZoomEdge40Fling1200` |
| Landing overshoot | 2 % of the flight past the source, 8 % released on a fast pinch; back within a point of it over 170–250 ms | parity stage 9, the same runs read past the frame the landing settles on (`tools/parity/analyze_overshoot.py`) |
| Pan scale on a screen-sized card | 0.812 at 0.3 screen heights, 0.678 at 0.5, 0.545 at 0.8 | `ZoomDismissPhysics.ios26`, section 3.4; parity stage 4 (the 0.42 of `drag.mov` was a long, wandering drag) |

### 1.5 Apple's API surface

UIKit (iOS 18): `UIViewController.preferredTransition = .zoom(options:sourceViewProvider:)`.
`ZoomOptions` exposes `alignmentRectProvider`, `dimmingColor`,
`dimmingVisualEffect` (a `UIBlurEffect`) and `interactiveDismissShouldBegin`
(a closure receiving an `InteractionContext` with the gesture's location and
velocity). The source view provider is called on both push and pop, so the
source can change while the page is open (a paging detail view).

SwiftUI (iOS 18): `.navigationTransition(.zoom(sourceID:in:))` on the
destination and `.matchedTransitionSource(id:in:configuration:)` on the
source, where the configuration supports `background(Color)`,
`clipShape(RoundedRectangle)` and `shadow(color:radius:x:y:)`, all of which are
"smoothly interpolated when a zoom transition originates from this source".

The package mirrors both: `ZoomPageRoute.sourceTag` is the zoom's source ID,
`ZoomTransitionSource` carries the configuration, and `ZoomTransitionOptions`
carries the UIKit options.

### 1.6 Calibrated parameters

Every constant the parity pass fitted, with the runs it came from
(`../swift_transitions_parity/stage<n>/`, iOS 27.0, iPhone 17). The
reasoning behind each is on the constant itself.

| Parameter | Value | Fitted from |
|---|---|---|
| `SwiftPageRoute.kTransitionDuration` | 400 ms | stage 1, `native_push_a`–`e` |
| `SwiftCurves.push` | exponential decay, 61 ms per 1/e | stage 1, the same runs |
| Covered page travel | 0.30 of the width | stage 1 |
| Covered page dim | 0.10 × progress | stage 1 |
| Leading-edge shadow | α 0.03, 6 pt down, 12 pt blur | stage 1 |
| Back gesture width | 20 pt | the SDK's; stage 2 |
| Back swipe dead zone | 12 pt | stage 2, `native_testSwipe*` |
| Back swipe release threshold | 0.53 of the width | stage 2, `native_testSwipe52/54/56/58Rest` |
| `BackGestureController.releaseSpring` | ω 22, ζ 0.85 | stage 2, seven release positions |
| `kZoomPushSpring` | ω 19, ζ 1 | stage 3, `native_zoom_a`–`f` |
| Zoom vertical lead | −0.05 pushing, +0.03 popping | stage 3, the same runs |
| `kZoomCrossFadeWindow` | 0.55 of the flight | stage 3 |
| `ZoomTransitionOptions.dimmingColor` | 15 % black, linear in progress | stage 3 |
| Flight corner radii | straight from the source's to the display's | stage 8, `native_zoom_f` |
| `kZoomCoveredPageScale` | 0.086 of the covered page, linear in the flight | stage 9, `native_ZoomPinch45Rest`, `native_ZoomPan30Rest` |
| `kZoomCoveredPageReturn` | ω 15, ζ 1 | stage 9, the same runs' landings |
| Zoom card shadow | α 0.24, 4 pt down, 30 pt blur, fading out over the last tenth of the flight | stage 3, `native_zoom_a`–`f`; stage 9, `native_ZoomPinch45Rest` |
| `scaleGain` | 0.67 per card height | stages 4 and 5, `native_ZoomPan*Rest`, `native_ZoomEdge*Rest` |
| `travelKnee`, `minimumScale` | 0.52 card heights, 0.37 | stage 4, `native_ZoomPan15/30/50/80Rest` |
| `fallLag` | 0.45 | stage 4, the same runs |
| `crossAxisGain`, `crossAxisLimit` | 0.56, 0.9 of the card's width | stage 4, `native_ZoomPan30Right50/150`, `native_ZoomPan30Left150`; stage 5, `native_ZoomEdge40Down` |
| `trackingSpring` | ω 45, ζ 1 | stage 6, `native_ZoomPinch60/80Slow` |
| `returnSpring` | ω 22, ζ 0.9 | stages 4 and 5, the cancelled releases |
| `landingSpring` | ω 15, ζ 0.75 | stage 8, twenty landings refitted on the card's left edge |
| `landingQuickening` | 0.3 of the frequency per card width per second | stage 9, `native_ZoomPinch45Medium/Fast`, `native_ZoomEdge40Fling*` |
| `maxCommitVelocity` | 20 progress per second | stages 8 and 9, `native_ZoomPinch45Fast` |
| `panDismissThreshold` | 0.905 | stage 4, `native_ZoomPan17Rest`, `native_ZoomPan19Rest` |
| `dismissThreshold` | 0.70 | stage 5, `native_ZoomEdge44/48/52Rest` |
| `pinchDismissThreshold` | 0.5 | stage 6, `native_ZoomPinch45Rest`, `native_ZoomPinch48Rest` |
| `releaseProjection` | 0.12 s | stages 2, 5 and 6, the commit tables |
| `kZoomReduceMotionDuration` | 140 ms | stage 8, `native_ReduceMotion` |

### 1.7 Known deviations

Where the package knowingly differs from the native reference, with the
size of the difference.

- **The navigation bar.** Natively the bar's items stay above the card and
  cross-fade in place: the back button fades in over the first 140 ms of a
  push, the title swaps in a 50 ms cross-fade 90 ms in, a dismissal swaps
  the bar to the covered page's items 150 ms into the drag, and a landing
  fades the back button out over its 235 ms. With a `CupertinoNavigationBar`
  on each page the SDK's own bar hero runs instead, sliding the title across
  for the length of the flight and switching on the pop. Its shuttle is the
  bar's, with no hook to replace it; a bar above the navigator, which does
  not fly at all, is the native shape (section 8).
- **The status bar zone.** It follows the bar: native dims it with the
  covered page, and under the hero it is white from the first frame.
- **A source that was never built.** A pop to a poster two and a half
  widths outside a lazy row flies toward the poster's off-screen position
  natively; the package has no frame for a source that has never been laid
  out and takes `fallbackInset`'s centred rect instead. A source one width
  out, still inside the row's cache extent, flies off the right edge in
  both (parity stage 8).
- **An edge swipe flung away.** A native edge swipe released at 800 pt/s
  lands in 100 ms where ours takes 147, and at 1200 in 108 against our
  132. Its position and its size are also on separate clocks: native's
  card hardly shrinks for the first 100 ms while the carry plays out,
  where ours shrinks throughout, so one released at 60 % of the width
  nets leftward where native's nets right (parity stage 9). The landing is quickened by the
  fingers' speed (`landingQuickening`), and the same speed buys a pinch
  three times the shrink it buys an edge swipe, so one line through both
  gestures cannot hit both ends (parity stage 9). Pinches land within a
  frame of native at 800 pt/s, and every release from rest matches.
- **A fast pinch's overshoot.** A landing carries the card past the source
  and eases back, 2 % of the flight released at rest and 2.1 % on a pinch
  released at 800 pt/s a finger where native goes 8 %. Native puts a
  release's speed into the landing's seed and ours into the spring's
  frequency (`landingQuickening`), and a quicker spring travels less past
  the target for the same seed; the settle times both fit, so telling the
  two apart needs the whole trace refitting (parity stage 9). Pans, edge
  swipes and releases from rest are within 0.3 % of native.
- **Touches during a landing.** Natively a touch on a landing card reaches
  the page underneath: the source takes it and pushes again, and the list
  behind can be scrolled while the card is still flying (parity stage 7).
  The package blocks the covered page for as long as the route is on
  screen, by choice — a half-finished dismissal that opens something else
  reads as a misfire — so a tap on the source lands only once the pop has
  finished.
- **The first frame after a tap.** In the simulator's debug build — the
  only build it runs — the example's first flight frame lands 30–80 ms
  after the tap where native's lands at once (parity stage 0).

---

## 2. Public API

Names are proposals. They follow Flutter conventions (`Route`, `Page`,
`PageTransitionsBuilder`, `InheritedWidget` lookups via `of(context)`), and
Apple's names where a concept maps directly.

### 2.1 Display corner radius

```dart
/// Resolves the physical display corner radius for a subtree.
///
/// Resolution order:
///  1. an enclosing [DisplayCornerRadii] override,
///  2. [MediaQuery.displayCornerRadiiOf] (populated by the engine on
///     Android 12 and later; null on iOS as of Flutter 3.47),
///  3. the iOS device table (section 3.2), keyed by logical size, device
///     pixel ratio and top view padding,
///  4. [BorderRadius.zero]. Anything not in the table has no rounding.
class DisplayCornerRadii extends InheritedWidget {
  const DisplayCornerRadii({super.key, required this.radii, required super.child});
  final BorderRadius radii;
  static BorderRadius of(BuildContext context);
  static BorderRadius? maybeOf(BuildContext context);
}
```

Apps that know their device's radius (from a plugin, or a fixed value in a
test) wrap the app in `DisplayCornerRadii`. The package never touches native
code; a companion plugin can be added later without changing this API.

### 2.2 Push transition

```dart
/// iOS push transition with display-radius corner clipping.
///
/// Mixes in [CupertinoRouteTransitionMixin] so that [CupertinoNavigationBar]
/// keeps its automatic back title and other Cupertino routes treat it as one
/// of their own. Only the transition and the gesture are replaced.
class SwiftPageRoute<T> extends PageRoute<T> with CupertinoRouteTransitionMixin<T> {
  SwiftPageRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
    this.title,
    this.backGestureRegion = BackGestureRegion.leadingEdge,
    this.cornerRadii,               // overrides DisplayCornerRadii.of
    this.transitionSpring,          // null = SDK curve and 500 ms
  });
}

/// Page counterpart for Navigator 2.0 / go_router.
class SwiftPage<T> extends Page<T> { ... createRoute → _PageBasedSwiftPageRoute<T> }

/// For MaterialApp users: one line in PageTransitionsTheme turns every
/// MaterialPage into this transition on iOS.
class SwiftPageTransitionsBuilder extends PageTransitionsBuilder { ... }

/// The transition widget itself, for custom routes that want the look
/// without the route class. Mirrors CupertinoPageTransition.
class SwiftPageTransition extends StatefulWidget {
  const SwiftPageTransition({
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.linearTransition,
    this.cornerRadii,
    required this.child,
  });
  /// Slide and dim applied to the route underneath. Static so that
  /// `ModalRoute.didChangeNext`'s identity comparison holds.
  static Widget? delegatedTransition(BuildContext, Animation<double>, Animation<double>, bool, Widget?);
}

enum BackGestureRegion {
  /// The SDK behaviour: 20 pt or the notch inset on the leading edge.
  leadingEdge,
  /// A horizontal drag anywhere on the page. iOS 26 behaviour.
  anywhere,
}
```

### 2.3 Zoom transition

```dart
/// Marks the widget a [ZoomPageRoute] zooms out of and back into.
///
/// The counterpart of SwiftUI's `matchedTransitionSource`. The source is
/// hidden (its slot keeps its size) while a zoom route with a matching
/// [tag] is on the stack, like a [Hero] during a flight.
class ZoomTransitionSource extends StatefulWidget {
  const ZoomTransitionSource({
    super.key,
    required this.tag,
    this.borderRadius = BorderRadius.zero, // the card interpolates radii, so a radius rather than a shape; drawn as a superellipse
    this.flightChild,       // what to draw for the source inside the card; defaults to child
    this.enabled = true,
    required this.child,
  });
}

/// Options mirroring UIViewController.Transition.ZoomOptions.
class ZoomTransitionOptions {
  const ZoomTransitionOptions({
    this.dismissGestures = ZoomDismissGestures.all,
    this.interactiveDismissShouldBegin,   // bool Function(ZoomInteractionContext)
    this.dimmingColor = const Color(0x33000000),
    this.dimmingBlurSigma = 0.0,          // UIKit dimmingVisualEffect
    this.alignmentRect,                   // Rect? Function(ZoomAlignmentRectContext)
    this.pushSpring,                      // SpringDescription; default calibrated
    this.dismissPhysics = ZoomDismissPhysics.ios26,
    this.snapshotDuringTransition = false,
  });
}

/// The fitted response of the interactive dismissal. One value object so the
/// numbers that were measured together stay together.
///
/// The shape is the iOS 26 fit from liquid_glass_widgets' swipe-dismiss
/// morph (`SheetMorphGeometry`); the numbers are the parity rig's, stages 4
/// and 5. Section 3.4 explains each term.
class ZoomDismissPhysics {
  const ZoomDismissPhysics({
    this.scaleGain = 0.67,        // scale lost per card height (width, for the edge swipe) of travel
    this.travelKnee = 0.52,       // card heights of linear shrink before easing (pan only)
    this.minimumScale = 0.37,     // the floor the eased travel asymptotes to
    this.fallLag = 0.45,          // card heights the fall trails by per cubed card height of travel (pan only)
    this.crossAxisGain = 0.56,    // card movement per point of finger movement across the gesture's axis, at first
    this.crossAxisLimit = 0.9,    // card widths the cross-axis follow is rubber-banded toward
    this.trackingSpring = const SpringDescription(mass: 1, stiffness: 2000, damping: 89),
    this.returnSpring = const SpringDescription(mass: 1, stiffness: 484, damping: 39.6), // ω 22, ζ 0.9
    this.panDismissThreshold = 0.905, // card scale below which a pan's release dismisses (0.914 sprang back, 0.900 landed)
    this.dismissThreshold = 0.70, // card scale below which an edge swipe's release dismisses (0.715 sprang back, 0.678 landed)
    this.pinchDismissThreshold = 0.5, // the same for a pinch, read without projection (0.515 sprang back, 0.494 landed)
    this.releaseProjection = 0.12, // seconds of release velocity a release is projected by
    this.maxCommitVelocity = 10.0, // progress units/s the commit spring may be seeded with
  });
  static const ios26 = ZoomDismissPhysics();
}

class ZoomDismissGestures {
  const ZoomDismissGestures({this.pan = true, this.edgeSwipe = true, this.pinch = true});
  static const all = ZoomDismissGestures();
  static const none = ZoomDismissGestures(pan: false, edgeSwipe: false, pinch: false);
}

/// What `interactiveDismissShouldBegin` and `alignmentRect` receive.
class ZoomInteractionContext { final ZoomGesture gesture; final Offset location; final Offset velocity; final ScrollMetrics? primaryScrollMetrics; }
class ZoomAlignmentRectContext { final Rect sourceRect; final Size pageSize; final ZoomFlightDirection direction; }

/// A page that zooms out of the [ZoomTransitionSource] whose tag is [sourceTag].
class ZoomPageRoute<T> extends PageRoute<T> with CupertinoRouteTransitionMixin<T> {
  ZoomPageRoute({
    required this.builder,
    required Object sourceTag,
    this.options = const ZoomTransitionOptions(),
    super.settings,
    this.maintainState = true,
    this.title,
  });

  /// Read and updated while the route is open, like UIKit's source view
  /// provider being called again on dismiss. A paging detail screen sets it
  /// to the tag of the item currently shown.
  Object get sourceTag; set sourceTag(Object value);

  /// The controller of the enclosing zoom route, for pages that need to
  /// drive dismissal themselves or expose the scroll controller.
  static ZoomPageRoute<Object?>? of(BuildContext context);

  /// The scroll controller that hands a top-edge downward drag to the
  /// dismissal. Installed as the [PrimaryScrollController] of the page so
  /// vertical scroll views on iOS pick it up without configuration.
  ScrollController get scrollController;

  @override bool get opaque => false;      // the source page stays visible
  @override Color? get barrierColor => options.dimmingColor; // the dim is the modal barrier, see 3.1
  @override Curve get barrierCurve => Curves.easeIn;
  @override ImageFilter? get filter => /* blur of dimmingBlurSigma */;
}

class ZoomPage<T> extends Page<T> { ... }
```

### 2.4 Usage

Imperative navigator:

```dart
// Source cell.
ZoomTransitionSource(
  tag: show.id,
  shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12)),
  child: PosterTile(show),
)

// Push.
Navigator.of(context).push(
  ZoomPageRoute<void>(
    sourceTag: show.id,
    builder: (_) => ShowPage(show),
  ),
);
```

go_router, where every route builds its own `Page`:

```dart
@override
Page<void> buildPage(BuildContext context, GoRouterState state) => ZoomPage<void>(
  key: state.pageKey,
  sourceTag: showId,
  child: ShowPage(showId: showId),
);
```

MaterialApp, everything at once:

```dart
MaterialApp(
  theme: ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.iOS: SwiftPageTransitionsBuilder(),
    }),
  ),
)
```

---

## 3. Architecture

### 3.1 Route contract

Both routes are ordinary `PageRoute`s and obey the same rules as
`CupertinoPageRoute`, so they compose with Cupertino and Material neighbours
and with anything that reads route animations (navigation shells, observers):

- **`delegatedTransition` is non-null and identity-stable.** `TransitionRoute`
  only wires the covered route's `secondaryAnimation` if
  `canTransitionTo(next)` is true, and `CupertinoRouteTransitionMixin`
  answers true for a next route that carries a delegated transition. A bare
  `PageRoute` (what go_router's `CustomTransitionPage` builds) freezes the
  route underneath. Our delegates are static tear-offs because
  `ModalRoute.didChangeNext` compares them by identity.
- **`canTransitionFrom` accepts any `PageRoute`**, so a zoom route pushed on
  top of a `MaterialPageRoute` still slides or dims it.
- **Gestures go through the navigator.** Every interactive dismissal calls
  `NavigatorState.didStartUserGesture()` when it begins and
  `didStopUserGesture()` when its animation settles, and scrubs the route's
  own `controller`, exactly as `_CupertinoBackGestureController` does. Hero
  flights, `HeroController`, and navigation shells all key off
  `userGestureInProgress`, and `HeroController.didStopUserGesture` cleans up
  flights that never moved.
- **Pops are real pops.** A committed dismissal calls `navigator.pop()` and
  then drives the controller back with `animateWith` (a spring simulation),
  so `animation.status` is `reverse` for the whole exit. Code that filters on
  `isActive || status == reverse` keeps working.
- **`maintainState` defaults to true.** Hero-style gesture transitions
  require the route underneath to keep its layout, and the zoom needs the
  source's current position at any moment.
- **The zoom route is non-opaque, and its dim is its modal barrier.** The
  source page stays visible and interactive-looking underneath. The dim uses
  the stock `ModalRoute` hooks — `barrierColor`, `barrierCurve` (an ease-in)
  and `filter` for the blur — which already track the route animation, and
  so the interactive progress once the gesture scrubs the controller. The
  proposal had the delegated transition paint it, but a delegated transition
  is a static tear-off with no access to the route's options; the zoom
  route's delegate instead holds the covered page still at full scale, which
  is what stops a covered Cupertino or Material route running its own slide.

### 3.2 Corner radius resolution

`DisplayCornerRadii.of(context)` resolves as in section 2.1. Two facts drive
the design:

- Flutter 3.47 has `MediaQueryData.displayCornerRadii`, fed by
  `FlutterView.displayCornerRadii`, and the framework's own predictive-back
  transition uses it. The engine only populates it on Android API 31 and
  later; the iOS embedder does not report it, and the private `UIScreen` key
  that plugins read is not something the engine will adopt.
- The values that key reports are public knowledge. The ScreenCorners
  project (kylebshr/ScreenCorners) publishes them per device, read from
  `UIScreen._displayCornerRadius`. That table is the source of truth here;
  devices it does not list have no rounding.

The published values, in points:

| Devices | Radius |
|---|---|
| iPhone X, XS, XS Max, 11 Pro, 11 Pro Max | 39 |
| iPhone XR, 11 | 41.5 |
| iPhone 12 mini, 13 mini | 44 |
| iPhone 12, 12 Pro, 13, 13 Pro, 14, 16e | 47.33 |
| iPhone 12 Pro Max, 13 Pro Max, 14 Plus | 53.33 |
| iPhone 14 Pro, 14 Pro Max, 15, 15 Plus, 15 Pro, 15 Pro Max, 16, 16 Plus | 55 |
| iPhone 16 Pro, 16 Pro Max, 17, 17 Pro, 17 Pro Max, Air | 62 |
| iPad Air, iPad Pro 11-inch and 12.9-inch | 18 |

Pure Dart cannot read the model identifier, so the table is keyed by what
`MediaQuery` exposes: logical size, device pixel ratio and top view padding.
Size and pixel ratio alone are ambiguous in exactly one place (the ScreenCorners
author's reason for not using resolution): iPhone X-class and the 12 and 13
mini share 375 × 812 at 3×. Their top insets differ (44 versus 50 pt), which
is why the inset is part of the key. Every other row maps to a distinct
size and ratio. The table lives in one file with the README as its provenance,
each row carrying the key it was derived from, so a new device is one line.
The override widget covers anything the table misses, and a plugin-fed
override stays possible without an API change.

Clipping uses `ClipRSuperellipse`, which matches Apple's continuous corners
and is available since Flutter 3.29.

### 3.3 Push transition mechanics

`SwiftPageTransition` is `CupertinoPageTransition` plus a clip:

```
SlideTransition (secondary, −0.29 width on the primary's curve, transformHitTests: false)
  └ SlideTransition (primary, from +1 width)
      └ DecoratedBox (leading edge shadow, cast from the clip shape)
          └ ClipRSuperellipse (leading corners = DisplayCornerRadii, only while primary < 1 or secondary > 0)
              └ DecoratedBox (foreground dim, 0.115 × the secondary's curved value)
                  └ child
```

The clip is removed at rest (`BorderRadius.zero` and `Clip.none`) so a
settled page costs nothing. The covered page's slide uses the *same* curve as
the incoming page's, so the two move in lockstep as measured in section 1.1,
and its dim is painted here rather than by a barrier so that it tracks a
back swipe and exists under a top route with no barrier colour;
`SwiftPageRoute.barrierColor` is null. The delegated transition applied to a
covered route that does not share it (a `CupertinoPageRoute`, or a Material
route with another theme) is this same widget with a completed primary
animation, linear while `popGestureInProgress`. The reverse stack — a Swift
route under a stock `CupertinoPageRoute` — receives the SDK's delegate and
moves as the SDK does, without the clip or the measured dim.

The back gesture reuses the SDK controller semantics (they are private, so
they are copied with attribution as go_router and swiftuikit do): drag
updates scrub `controller.value` by `dx / width`, a fling of one screen width
per second commits, otherwise the midpoint decides, and the drop animation is
350 ms `fastEaseInToSlowEaseOut`. `BackGestureRegion.anywhere` replaces the
20 pt edge `Listener` with a horizontal drag recognizer over the whole page
that only claims drags starting in the trailing direction, so horizontal
scrollables and page views still win their arena.

Curves: the SDK's `fastEaseInToSlowEaseOut` over 500 ms by default. An
optional `transitionSpring` switches the primary animation to
`SpringDescription.withDurationAndBounce`, which the SDK documents as
equivalent to SwiftUI's `spring(duration:bounce:)`.

### 3.4 Zoom geometry model

All zoom rendering is driven by one value object, computed once per frame:

```dart
class ZoomFrame {
  final Rect rect;          // card frame in navigator coordinates
  final double rotation;    // radians, non-zero only during a pinch
  final BorderRadius radii; // on-screen corner radii
  final double sourceOpacity; // cross-fade of the source's pixels inside the card
}
```

The covered route's dim is not part of the frame: it is the route's modal
barrier (section 3.1), driven by the same controller through an ease-in
`barrierCurve`.

Two regimes produce a `ZoomFrame`:

**Flight** (push, committed dismissal, cancel): `t` is the route animation
(or a spring on the controller). `rect = Rect.lerp(alignedSource, screen, t)`,
`radii = lerp(source.radii, display.radii, t)` interpolated in the card's own
space so the visible radius scales with the card, and `sourceOpacity` fades
out over the first ~40 % of a push and in over the last ~40 % of a pop. A
spring settles within a tolerance of its end, so the ends are read from the
animation status rather than its value.

**Interaction** (finger down): the gesture owns a `ZoomInteraction` with
`focalPoint`, `translation`, `scale` and `rotation`. The frame is the full
page transformed by scale and rotation about the focal point, then
translated; `radii` follow the same interpolation using the scale-derived
progress. The route's `controller.value` is set to the scale-derived
progress each frame so that everything else in the framework (secondary
animations, shells, Hero) sees a consistent scalar.

**The pan response.** The shape is liquid_glass_widgets' swipe-dismiss
morph (PR #223, `SheetMorphGeometry`), which reproduced the iOS 26 zoom
dismissal of a sheet from a cursor-tracked capture; its author is this
package's author, so it was ported rather than re-derived, and the parity
rig (parity-plan.md stage 4) then measured its constants for a full-screen
page and found one term the sheet fit did not have. The model, in
`ZoomDismissPhysics` terms:

- The pan waits out the platform's slop (`kTouchSlop`, 18 px; natively the
  card holds still for the first 16–20 pt), counted from the touch in the
  gesture layer because a recognizer alone in its arena wins at the touch.
- Travel past it is measured in *card heights* (the card here is the whole
  page, so one card height is the screen height). The shrink is linear up
  to `travelKnee` (0.52), then rubber-banded with iOS's over-scroll curve
  `f(x) = (1 − 1/(x/limit + 1)) · limit` toward the travel at which the scale
  would reach `minimumScale` (0.37). A long drag parks the card instead of
  sliding it off screen; it never quite stops shrinking. Natively: 0.812 at
  0.3 of the height, 0.678 at 0.5, 0.545 at 0.8; the fit is 0.002 RMS.
- Scale is linear in the *damped* travel: `1 − scaleGain · travel`, with
  `scaleGain` 0.67.
- The shrink pivots on the grabbed point, carried down by the *fall*: the
  travel less `fallLag` (0.45) times its cube, so the content under the
  finger rides with it for the first third of the height and then trails —
  0.89 of the finger's travel at half the height, 0.73 at 0.8. The native
  page's top sat within 4 pt of this at every held position from a grab
  just under the bar to one low on the page; a rubber band on the travel
  was 8 pt out at 30 % and 20 at 80 %. With the gain below 1.0
  per card height the fall always outruns the shrink, so the card's bottom
  edge cannot lift into view.
- The sideways axis opens with the drag, anchored on the move that opens
  it. The card does not copy the finger's x; it chases the finger's offset
  rubber-banded at `crossAxisGain` (0.56) toward `crossAxisLimit` (0.9 of
  the card's width) through a stiff, critically damped tracking spring
  (ω ≈ 45), so fast sweeps visibly trail — natively a held card moved 26 pt
  for a 50 pt sweep, 49 for 100, 69 for 150 and 85 for 195, either way, off
  the screen's edge with no give; the same band gives the edge swipe's
  vertical follow (86 for 200, 99 for 240). Sideways movement only
  translates; the native scale and height did not change by a point.
  On release the same chase is retargeted home on `returnSpring`, carrying
  its momentum. The chase is integrated by hand on one `Ticker`, because
  `animateWith` restarts its clock on every retarget.
- The rendered transform is *derived from* the geometry function that also
  hands the release frame to the commit flight, and a render-versus-geometry
  equivalence test locks them together.

The edge swipe was calibrated on the same rig (stage 5): it has no knee —
the card shrinks at `scaleGain` per screen width all the way, and a finger
cannot travel far enough to reach the floor — measured past the same 12 pt
dead zone as the back swipe, and it does not fall; it follows the finger
up or down at `crossAxisGain` instead. The pinch (stage 6) takes hold
once the fingers' distance has changed by half the slop (natively 8.7 pt)
and from there scales the card 1:1 with their distance, never past the
size it was pinched at, turns it 1:1 with their angle and carries it 1:1
with their focal point, about the card as it was, all three chased
through `trackingSpring` (the native card settles two or three frames
behind the fingers); a turn alone, the fingers never closing, does
nothing.

**Rendering** of a `ZoomFrame`:

```
[modal barrier entry] AnimatedModalBarrier(dimmingColor, barrierCurve) [under BackdropFilter if blur]
[modal scope entry]
  Stack (navigator-sized)
    └ Positioned.fromRect(frame.rect)
        └ Transform.rotate(frame.rotation)
            └ ClipRSuperellipse(frame.radii)
                └ Stack
                    ├ OverflowBox(alignment topCenter)
                    │   └ Transform.scale(max(rect.width / pageWidth, rect.height / pageHeight))
                    │       └ SizedBox(page size) ─ the live page
                    └ Opacity(sourceOpacity) ─ source flightChild, FittedBox(cover) at the source's size
```

The page is laid out at its full size once and scaled; it does not reflow,
matching iOS. The scale is an aspect fill anchored at the top centre, so a
poster taller than the screen's aspect shows the top of the page at the
card's width and a wide list row shows the page's top strip at full scale;
the width-only scale first proposed leaves a gap under the page for the
first case. The tree has the same shape at rest and in flight — the clip and
transforms become identities rather than being removed — so the page's
element subtree keeps its position and state. `transformHitTests` stays true
so the page remains tappable at rest.

Optionally, `snapshotDuringTransition` wraps the page in a `SnapshotWidget`
with `SnapshotMode.permissive` for the duration of a flight, the same
technique Material's `ZoomPageTransitionsBuilder` uses. Pages containing
platform views fall back to live painting automatically in that mode.

### 3.5 Why the zoom is not a `Hero` flight

`Hero` is the natural first thought, and the swiftuikit package builds its
zoom on it. Reading `heroes.dart` argues against it for this transition:

- A flight animates a **copy** (the shuttle) in the navigator's overlay while
  the real destination is replaced by a placeholder. For a whole page that
  means building the page twice and freezing a copy, which is what
  swiftuikit's frozen-child and generation-keyed `Hero` work around.
- Flights are axis-aligned rect tweens driven by the route's scalar
  animation. The pinch needs rotation and free 2-D translation, and the
  documentation is explicit: "Don't rotate your heroes."
- `Hero` decides its participants in `didChangeTop` and
  `didStartUserGesture`; a dismissal that starts as a pan, is interrupted,
  and re-grabbed mid-flight has no equivalent in that model.

What is kept from `Hero` is everything about **matching**: tags, discovery by
walking the previous route's element subtree (`Hero._allHeroesFor`, including
its rule for nested navigators), hiding the source with a size-preserving
placeholder while keeping its element alive, and measuring rects with
`RenderBox.getTransformTo` against `route.subtreeContext`. `Hero` widgets
inside a zoomed page keep working for their own flights.

### 3.6 Source discovery and hiding

- The route records `previousRoute` from `didChangePrevious`.
- On push (and again on each pop, because `sourceTag` may have changed) the
  route walks `previousRoute.subtreeContext` for a `ZoomTransitionSource`
  whose tag matches, applying `Hero`'s nested-navigator rule: a source inside
  another navigator counts only if its own route is a current `PageRoute`.
- Discovery and measurement run in an end-of-frame callback scheduled from
  `didPush` and `didPop`, the deferral `HeroController` makes: the element
  tree cannot be walked during a build, and a pages-based `Navigator` pushes
  and pops during one. The first frame of a push draws the fallback card at
  zero opacity and the first frame of a pop draws the previous flight's card
  at full screen; neither is visible. The source is measured against the
  navigator's overlay, which is the card's coordinate space.
- The source state enters `hidden`: it keeps its child mounted and laid out
  inside an `Offstage` with `TickerMode` off, and paints a `SizedBox` of the
  frozen size, exactly like `_HeroState`. It leaves `hidden` when the zoom
  route's animation is dismissed or the route is disposed.
- No global registry and no `NavigatorObserver` are required, so the package
  works unchanged with go_router, auto_route or a hand-built `Navigator`.

### 3.7 Interactive dismissal pipeline

```
pointer events
  ├ pan / edge swipe: VerticalDragGestureRecognizer + HorizontalDragGestureRecognizer
  │   installed by the route around the page (RawGestureDetector, translucent)
  ├ scroll handoff: ZoomPageRoute.scrollController → _ZoomScrollPosition
  │   (applyUserOffset / goBallistic, copied from _CupertinoSheetScrollPosition)
  └ pinch: ScaleGestureRecognizer subclass that accepts as soon as two pointers are tracked
        │
        ▼
   ZoomInteraction (focalPoint, translation, scale, rotation, velocity)
        │  per frame
        ▼
   ZoomFrame → rendering; controller.value ← progress
        │  on release
        ▼
   commit?  yes → navigator.pop(); controller.animateWith(spring seeded with velocity); frame tweens to source
            no  → controller.animateWith(spring back to 1.0); frame tweens to identity
```

Details that matter:

- **Scroll handoff.** The route installs its own `ScrollController` as the
  page's `PrimaryScrollController`. Its `ScrollPosition` diverts a downward
  drag to the dismissal when the list is at its top edge and otherwise
  scrolls, and `goBallistic` hands the release velocity across. This is the
  SDK's `CupertinoSheetRoute` mechanism, so pages that already use the sheet
  pattern need no changes — with one departure from the sheet: only a drag
  that *began* at the top hands across. A drag that begins on a scrolled
  list scrolls it to the top and over-scrolls there, which is what the
  native page does (parity stage 4). Pages with their own controllers can read
  `ZoomPageRoute.of(context).scrollController` or gate dismissal in
  `interactiveDismissShouldBegin` using the scroll metrics in the context.
- **Pinch arena.** Scrollables accept a pointer as soon as it moves past the
  touch slop, which usually happens before a second finger lands. The
  recognizer therefore calls `resolve(GestureDisposition.accepted)` for both
  pointers the moment it tracks two, and the route tells the scrollable's
  drag to cancel through the same `_dragCancelCallback` hook the sheet keeps.
  This is the riskiest part of the package and gets a spike before
  implementation (section 6, M4).
- **Release rules.** A pan or edge swipe is projected `releaseProjection`
  (120 ms) ahead on its release velocity, and dismisses if the card's scale
  there is below its threshold: `panDismissThreshold` (0.905, a sixth of the
  height) for the pan and `dismissThreshold` (0.70) for the edge swipe. So
  a short flick lands, a pull back up past the boundary springs back, and
  a card released moving up from well past it still lands, as natively. A
  pinch is read where the fingers are, without projection: it dismisses
  below `pinchDismissThreshold` (0.5, half the size), however fast the
  fingers were closing. Otherwise cancel. Both
  outcomes use springs seeded with the release velocity so there is no
  visible kink. The
  commit seed is the rate the shrink was running at, converted to progress
  units (`scaleGain · v / cardHeight`), capped at `maxCommitVelocity` and
  never slower than the resting spring's own start, so a flick hurries the
  landing but cannot drag it out. That is the `closeVelocityFor` rule from
  the liquid_glass_widgets follow-up, read at the moment of dismissal rather
  than at pointer up.
- **Gates.** A dismissal begins only if `interactiveDismissShouldBegin`
  returns true (default: true), the route is current, and no other user
  gesture is in progress on the navigator. Unlike the SDK's
  `popGestureEnabled`, a running push animation does not block it (see
  3.8).
- **Chrome.** The package never freezes or replays navigation bar chrome.
  Shells that hoist chrome above the navigator get the signals they need
  from the navigator gesture flags and the route status.

As implemented (M3), with the departures from the sketch above:

- `ZoomDismissController` is the counterpart of the push route's
  `BackGestureController`: created when a gesture begins (it stops the
  controller and calls `didStartUserGesture`), fed primary-axis deltas and
  raw pointer positions, and on release it decides, records a
  `ZoomDeparture` (the frame and progress the card left from) on the route,
  and either pops — the route's `createSimulation` then seeds the landing
  spring with the release velocity — or springs the controller back to 1.
  `didStopUserGesture` follows the settle. Progress under the finger is the
  grabbed progress times the card's relative scale, so a settled page reads
  its scale as progress and an interrupted push continues from where it was.
- The dismissal begins on the first *diverted* scroll delta, not when the
  scroll drag starts, so an ordinary scroll never counts as a navigator
  gesture; and the scroll position keeps diverting only while the card has
  actually left rest, so an upward drag on an undisturbed list scrolls it.
- The route's own recognizers use `DragStartBehavior.down`, so the card
  takes up the slop distance instead of losing it, and the gesture layer is
  an opaque `Listener`: a translucent one reports a miss where no page
  content is hit, which let pointers fall through to the modal barrier and
  put its tap recognizer into the arena.
- The source's flight copy inside the card ignores pointers, so a grab
  during the push reaches the page.
- The edge swipe waits out a 12 pt dead zone, then shrinks by horizontal
  travel over the card's width about the grabbed point and follows the
  finger: sideways 1:1 through the tracking spring with no pinning (the
  native card runs off the far side of the screen), up or down through
  the pan's cross-axis band (natively a 200 pt drop moved the card 86 pt). Its controller is fed from the edge recognizer
  rather than the raw pointer stream, which runs a move ahead of the
  recognizer and would see the dead zone late. Radii under the finger
  interpolate in the card's own space and scale with the card, which lands
  near the 13–17 pt measured natively at 0.55–0.6.
- The pinch (M4) is read from the same opaque `Listener` rather than from
  a `ScaleGestureRecognizer`. The spike was settled by reading the
  recognizer lifecycle: a scroll view accepts a finger at the touch slop,
  usually before the second finger lands, and a recognizer that lost that
  arena stops tracking the finger, so an eager-accept recognizer can never
  see both fingers over a scrolled list. The `Listener` sees every finger
  regardless of the arena; once the second one has landed and their
  distance has changed by half the slop, the live gesture (or a new one)
  becomes a pinch with the card as it is at that moment as its resting
  frame, anchored on the distance where the dead zone ended, and the route
  cancels the scroll view's drag through the
  scroll position's cancel hook — the sheet's mechanism — after which the
  scroll view ignores the rest of that drag. This is the plan's fallback
  without its "only at rest" limitation. The card scales with the fingers'
  distance (never past the size it was pinched at), rotates with their
  angle and moves with their focal point, about the initial focal point;
  the release speed is the fingers' closing rate over the last 100 ms, and
  the departure frame un-rotates over the landing. Trackpad pinches are not
  handled yet.
- A committed release pops the route at once, and the landing is the pop's
  own transition (`createSimulation`) seeded with the release velocity and
  flown from the departure frame; the user gesture ends at the commit.
  Popping once landed, as the SDK's back gesture does, would cancel a
  finger that landed on the way down (the navigator cancels active
  pointers on every navigation), and iOS gives that finger to the page
  underneath (section 3.8). A card springing back from a cancelled release
  can be grabbed again, as the same gesture to the navigator. A change of
  the window's size while a card is held lets go of it — a release at
  rest, landing or returning to the window as it is now, and the rest of
  that touch is not a new grab — as iOS lets go when the device turns.
  Not yet: trackpad pinches.

### 3.8 Interruptible push

Apple: a push is never cancelled, and a touch never stops it. Measured
(parity stage 7): the native card flies on under a finger; a pan begun on
the way applies its scale to the card *as it completes* — the card kept
growing for three frames after the drag began and then read as the pan's
scale of the full screen, not of the card as grabbed — and a pinch begun
on the way takes the card from where it is. A touch during the landing
reaches the page underneath (the poster took the tap and pushed again). In
Flutter terms:

- A pointer down on a zooming page is nothing to the card: the pan begins
  as it leaves its dead zone, the pinch as it leaves its own, and either
  captures the current `ZoomFrame` and calls `didStartUserGesture()`.
- Grabbed during a flight to full screen — the push, or the return of a
  cancelled dismissal — the controller carries `restingFrame` on with the
  flight's own spring from the controller's value and velocity
  (`ZoomFlight`), and the gesture applies on top; the route's progress is
  the flight's times the gesture's scale, so it has one writer and never
  jumps. A pinch scales a snapshot, so a flight stops where a pinch begins.
- On release, "commit" pops the route from the composed frame, and "cancel"
  animates the controller forward again. Both are springs seeded with the
  release velocity.
- A landing card is not grabbed: the popping route ignores pointers — the
  SDK's modal scope does so for the page, and the card and its gesture
  layer sit outside it — so the touch reaches the page underneath, where
  the hidden source still hit-tests (`Visibility` with
  `maintainInteractivity`) and a tap on it pushes again, as on iOS.
- While the gesture is live the route's page is fully built and laid out, so
  taps that the gesture recognizers reject reach the page as on iOS.

### 3.9 Physics

- Zoom push and pop: one critically damped spring from rest at ω = 19 rad/s
  (stiffness 361, damping 38; a 52 ms time constant, 330 ms response),
  fitted to the card's width on a native `NavigationStack` zoom to 4–6 pt
  RMS of 282 pt of travel, push and pop alike (parity stage 3). A pure
  exponential misses by three times that: the flight has a short ease-in,
  unlike the push transition's slide. It reaches the controller through
  `TransitionRoute.createSimulation`, so the route's `animateWith` plumbing
  is the SDK's.
- Dismissal landing: `ZoomDismissPhysics.landingSpring`, ω = 15 rad/s,
  ζ = 0.75 (stiffness 225, damping 22.5), fitted to the card's edge on
  native pans released at rest from 0.55–0.90 of the screen to 0.4–2.9 pt,
  98 % of the way in 230–270 ms (parity stage 8); edge swipes and pinches
  land on it too. Its overshoot is drawn: `AnimationController` clamps a
  simulation to its bounds, so the route reads the spring's own value while
  the controller is pinned at zero, and the card carries 2 % of the flight
  past the source and eases back into it over 200 ms, as native landings do
  (parity stage 9). It is seeded with the release rate over what the
  landing has left — a pinch's fingers or an edge swipe's speed, never a
  pan's, which natively lands from rest however it was flung — carries the
  motion the card was released with as a decaying offset on the plain
  landing spring (`ZoomDeparture.velocity`), on both axes, so a flung card
  keeps going its own way before it turns for the source rather than
  running home on one plane. The flight is over when the card has
  arrived rather than when its progress has, or a card still carrying
  when the route left would jump the rest of the way as the source took
  over. The seed is capped at
  `maxCommitVelocity` 20, and quickened by `landingSpringFor`: a native
  landing shortens with the fingers' own speed rather than the shrink they
  were driving, to 170 ms at 400 pt/s a finger and 100–133 at 800 in either
  gesture, which `landingQuickening` 0.3 puts on the spring's frequency and
  not its damping — which is also why a fast pinch travels less past the
  source than native's does (section 1.7).
  Rotation and translation share the spring's normalised progress so the
  card lands as one object.
- Back swipe release: `BackGestureController.releaseSpring`, ω = 22 rad/s,
  ζ = 0.85, fitted to native releases from seven positions, pop and cancel
  alike (parity stage 2). The page follows the finger after a 12 pt dead
  zone, and a release commits when its position plus 120 ms of its
  velocity passes the midpoint. That velocity is estimated by
  `IOSScrollViewFlingVelocityTracker`, iOS's own fling estimate, which a
  `Scrollable` on iOS uses for the same reason: the default least-squares
  tracker reads a flick at a third to a half of the speed the finger was
  really moving, and a fling that natively pops sprang back instead
  (parity stage 2). Either tracker gives up on a release once 40 ms of
  wall clock have passed since the last move it saw — one dropped frame
  under a heavy transition — and reports a finger that was standing
  still; a release that comes back empty falls back to the finger as the
  pointer stream saw it (`ReleaseVelocity`), keyed on when the moves
  happened rather than on when they were delivered.
- The SDK's Cupertino spring (stiffness 522.35, critically damped, 0.404 s)
  is available as `SwiftSprings.standard` for apps that want the exact SDK
  feel on the push transition.
- The covered page is scaled down under a zoom route, straight with the
  flight and about the screen's centre (`kZoomCoveredPageScale`), applied
  by `ZoomPageTransition.delegatedTransition`, which also holds its
  pointers off for as long as the route is on screen (section 1.7). A
  gesture dragging the card does not move it — the route's animation follows the finger and the page
  holds where the flight left it, as native's does — and it comes home on
  `kZoomCoveredPageReturn` rather than on the route's own animation, which
  a committed dismissal seeds so the card lands well before the page has
  finished growing. A source measured while the page is scaled is read
  back to its resting rect, which is where both ends of a flight meet it.
- The dismissal's pan and edge swipe estimate their release velocity with
  `IOSScrollViewFlingVelocityTracker`, as the back swipe does and for the
  same reason (section 3.2); a pinch measures its fingers directly, over
  the last 100 ms. The commit outcome of every scripted pan and edge swipe
  matches native either way, but the landing a fling is quickened by does
  not: reading the fingers truthfully takes an edge swipe flung at 800 pt/s
  from 168 ms to 147 (parity stage 2).
- The interactive dismissal's sideways chase uses the fitted tracking spring
  (stiffness 2000, damping 89) while the finger drives it and the return
  spring (stiffness 484, damping 39.6: ω 22, ζ 0.9, measured in parity
  stage 5) on the way home and for a cancelled release, both from
  `ZoomDismissPhysics`.

### 3.10 Accessibility and platforms

- `MediaQuery.disableAnimationsOf(context)` (Reduce Motion) turns both
  transitions into a cross-fade — the zoom's over `kZoomReduceMotionDuration`,
  140 ms, as a native page fades in and out (parity stage 8); gestures
  still pop.
- The zoomed page keeps `Semantics(scopesRoute: true)` and the dimmed page
  underneath is excluded from semantics while covered, as `ModalRoute` does
  with its barrier.
- Web: `SnapshotWidget` is disabled on CanvasKit (the SDK does the same);
  the transitions run live. Desktop: the pinch is trackpad-scale aware via
  `ScaleGestureRecognizer.trackpadScrollCausesScale`.

---

## 4. Package layout

```
lib/
  swift_transitions.dart                 exports
  src/
    corners/display_corner_radii.dart    DisplayCornerRadii widget, heuristic table
    physics/springs.dart                 SwiftSprings, velocity helpers
    page/swift_page_route.dart           SwiftPageRoute, SwiftPage, _PageBasedSwiftPageRoute
    page/swift_page_transition.dart      SwiftPageTransition, delegatedTransition, edge shadow
    page/swift_page_transitions_builder.dart
    page/back_gesture.dart               detector + controller (SDK semantics), BackGestureRegion
    zoom/zoom_transition_source.dart     ZoomTransitionSource + state (hide/show, measure)
    zoom/zoom_page_route.dart            ZoomPageRoute, ZoomPage, source discovery
    zoom/zoom_transition_options.dart    options, gestures, contexts
    zoom/zoom_frame.dart                 ZoomFrame + interpolation
    zoom/zoom_interaction.dart           gesture state machine, release rules
    zoom/zoom_gestures.dart              recognizers, scroll position handoff
    zoom/zoom_transition_layer.dart      rendering of a ZoomFrame, delegated dimming
example/lib/
  main.dart                              gallery: push demo, zoom grid, paging detail, scroll page
test/
  corners/, page/, zoom/                 see section 5
```

---

## 5. Testing

Widget tests drive everything through a real `Navigator` with
`WidgetTester.pump` and assert on geometry read from render objects, never
on implementation details.

- **Corner radii.** Override wins over MediaQuery; MediaQuery wins over the
  heuristic; the heuristic table maps each known inset; zero below the
  threshold.
- **Push transition.** At `t = 0.5` the incoming page's render box is at the
  expected offset and clipped with the display radii; at rest no clip layer
  exists. Covered route's `secondaryAnimation` is live (regression test for
  the `canTransitionTo` trap). Back swipe: commit on fling, commit past the
  midpoint, cancel before it, `userGestureInProgress` true throughout and
  false after settle. `PageTransitionsTheme` integration builds the same
  widget tree as the route.
- **Zoom flight.** With a source at a known rect, the card rect at `t = 0`,
  `0.5`, `1` matches `Rect.lerp`; the source is hidden while the route is
  active and visible after pop; the source's slot keeps its size; a changed
  `sourceTag` lands on the new source; a missing source falls back to a
  centre scale-and-fade.
- **Interaction.** Pan down from the top of a scrolled-to-top list shrinks
  the card and pops on release past the threshold; the same pan on a list
  scrolled down scrolls instead and over-scrolls at the top, never handing
  off; a short pan cancels and restores identity; edge swipe drives scale; pinch
  with `TestGesture` on two pointers scales and rotates; every path calls
  `didStartUserGesture` and `didStopUserGesture` exactly once.
- **Interrupt.** A pointer down during a push stops the controller and a
  release cancels or commits correctly.
- **Reduce Motion** produces a fade and no transform.
- **Goldens** are not used for motion. A small set of static goldens covers
  the clip shape at rest and mid-transition on a fixed device profile.

Calibration is a separate, manual activity: the `ffmpeg` frame-strip
commands used for section 1 will be kept in `tool/reference_frames.sh` so a
reading of a new recording is reproducible.

---

## 6. Delivery plan

Each milestone ends with tests green, the example app demonstrating the
milestone, and a CHANGELOG entry. Estimates assume one person.

**M0 Foundations (1–2 days).**
`DisplayCornerRadii` with the heuristic table; `SwiftSprings`; `ZoomFrame`
and its interpolation as pure functions; test harness for device profiles
(view padding, size, pixel ratio). Acceptance: unit tests for every
resolution branch and for frame interpolation endpoints.

**M1 Push transition (2–3 days).**
`SwiftPageTransition`, `SwiftPageRoute`, `SwiftPage`,
`SwiftPageTransitionsBuilder`, back gesture with both regions. Acceptance:
section 5 push tests; example app pushes between two pages with the clip
visible on a device with rounded corners; Cupertino and Material routes as
neighbours transition correctly in both directions.

**M2 Zoom push and pop, non-interactive (3–4 days).**
`ZoomTransitionSource`, `ZoomPageRoute`, `ZoomPage`, discovery, hiding,
flight rendering, cross-fade, dimming via the delegated transition, missing
source fallback, Reduce Motion. Acceptance: section 5 flight tests; example
grid of posters opens a detail page and the back button zooms it home.

**M2b Push parallax and dim (1 day).**
Bring the push in line with the section 1.1 measurements. `SwiftPageTransition`
drives the covered page from the top page's progress at 0.29 of the width,
so both pages share one curve and one gesture, and paints the dim itself at
0.115 × progress (`SwiftPageRoute.barrierColor` becomes null; the dim then
exists under a Material top route too). `SwiftPageTransition.delegatedTransition`
becomes the package's own static, gesture-aware builder, so a covered
Cupertino or Material route gets the same motion, dim and clip under a Swift
top route. The trade-off is the reverse stack: a Swift route covered by a
stock `CupertinoPageRoute` receives the SDK's delegate and moves as the SDK
does, without its clip; documented, and moot for apps that use `SwiftPage`
or the theme builder throughout. Acceptance: tests for the fraction, the dim
alpha, and linearity under the gesture in mixed stacks; the example captured
on the simulator and read with the same script gives 0.29 and 0.115 (done:
0.289–0.290 and 0.106–0.118 across a held swipe).

**M3 Interactive dismissal: pan and edge swipe (3–4 days).** *Done
2026-09-07; see the notes at the end of section 3.7.*
Port the fitted model from liquid_glass_widgets (`SheetMorphGeometry`'s
travel, scale, rubber band, horizontal offset and commit-velocity functions,
plus the presenter's hand-integrated chase) into `ZoomDismissPhysics` and the
geometry function, with their tests (render-versus-geometry equivalence, RTL
mirror symmetry, the invariant that the bottom edge never lifts). Then
gesture recognizers, scroll handoff position, release rules, navigator
gesture plumbing, `interactiveDismissShouldBegin`. Acceptance: section 5
interaction tests except pinch; on device the three recordings' pan and
swipe behaviours are reproduced side by side, and the edge swipe's
horizontal gain is calibrated against `back.mov`.

**M4 Pinch (2–3 days, after a half-day spike).** *Done 2026-09-07; the
spike's outcome is in the section 3.7 notes.*
Spike: prove that a two-finger pinch over a scrolled `ListView` on iOS wins
the arena reliably with the eager-accept recognizer plus drag cancel. If it
cannot, fall back to a `Listener`-level pinch that only activates when the
scroll position is at rest, and document the limitation. Then: rotation,
focal point, un-rotate on landing. Acceptance: pinch tests; recording
`pinch.mp4` reproduced.

**M5 Fluidity and options (2–3 days).** *Done 2026-09-08 except the device
performance pass, which needs the host app's glass surfaces and is folded
into the host-app adapter work in M6.*
Interruptible push, dynamic `sourceTag` for paging detail pages,
`alignmentRect`, `snapshotDuringTransition`, `dimmingBlurSigma`. Performance
pass on a real device with a heavy page (the host app's glass surfaces):
frame times during flight with and without snapshotting recorded in the
CHANGELOG. The alignment rect is applied in the transition layer as a
window on the page — the rect at the source end, widening to the page's
bounds as the card grows, by the square root of the card's area between
the two — so the dragged and landing frames need no separate treatment.

**M6 Release (1–2 days).**
README with API tour and GIFs from the example, dartdoc pass (the analyzer
already enforces public docs), pub score check (`pana`), `0.1.0` tag and
publish through the tag workflow. Host-app adapter (section 8) opened as a
separate PR in that app.

Total: roughly three to four weeks of focused work.

---

## 7. Risks and open decisions

**Risks**

- *Pinch over scrollables* (M4). The gesture arena is single-winner per
  pointer; the eager-accept strategy is a known technique but untested with
  Cupertino's multitouch drag strategy. Mitigation: the spike, and a
  documented fallback.
- *Corner radius on iOS* is a table until the engine reports it. A new
  device is a missing row (no rounding) until added. Mitigation: the
  override widget, one-line rows keyed by observable metrics, and a test
  that every row's key is unique.
- *Performance* with expensive pages (backdrop filters, shaders) transformed
  every frame. Mitigation: optional snapshotting; the transform is a single
  layer so the page is not rebuilt during the flight.
- *Framework churn.* `CupertinoRouteTransitionMixin` internals are private
  and copied; a future SDK change to the back gesture would need a mirror
  change here. Mitigation: the copies are small and marked with their origin.
- *go_router*: `CustomTransitionPage` cannot be subclassed into a different
  route type, so apps must use `SwiftPage` and `ZoomPage`; they are
  drop-in in `buildPage`.

**Decisions to make before M1**

1. Names. `SwiftPageRoute` and `ZoomPageRoute` are proposals; alternatives
   are `IosPageRoute` or `StackPageRoute` for the push, and
   `ZoomTransitionRoute` for the zoom.
2. Default `BackGestureRegion`. `leadingEdge` matches the SDK; `anywhere`
   matches iOS 26. The SDK default is safer for horizontal scrollables.
3. Whether the zoom route mixes in `CupertinoRouteTransitionMixin` (for
   automatic back titles in `CupertinoNavigationBar`) or stays a plain
   `PageRoute`. *Decided (2026-09-07): the mixin.* Its `previousTitle` only
   reads a previous route that is itself the mixin, so a plain route would be
   the one page in a stack that loses its back title in both directions; its
   `canTransitionTo` makes the zoom route a recognised neighbour of stock
   Cupertino and Material routes without leaning on the delegate alone; and
   `buildPage` scopes the route's semantics. The push route already carries
   the framework-churn risk, so the zoom route adds none.
4. Whether to publish `ZoomFrame` and the rendering layer as public API for
   apps that want a custom presentation, or keep them private until 1.0.
   *Decided (2026-09-07): private.* The frame's shape changes with M3–M5
   (pan geometry, rotation and focal point, alignment rects), the rendering
   layer is coupled to the interaction state machine, and the source's
   `flightChild` and the options' `alignmentRect` already cover what UIKit
   exposes. The frame is a pure value type, so exporting it later is a
   one-line change if a concrete custom presentation asks for it.

---

## 8. Host app integration notes

Written against an app that uses go_router, a `CupertinoApp.router`, and the
liquid_glass_widgets `GlassNavigationShell` above the root navigator. The
observations generalise to any app that reads route animations from outside
the route.

- Integrate at the `Page`. Every route builds its page in a `buildPage`
  override, so swapping `CupertinoPage` for `SwiftPage`, and a hand-rolled
  card-expand page for `ZoomPage`, is a per-route change. Scaffolds and page
  content are untouched.
- The shell hoists navigation bar chrome above the navigator and retreats it
  on the covered route's `secondaryAnimation`, freezes it while
  `userGestureInProgress` is true, and plays its own commit animation when the
  route stops being active. Section 3.1 satisfies all three. The native
  bar itself (parity stage 8) keeps its items pinned above the card, which
  passes under them, and cross-fades them in place: on a push the back
  button fades in over the first 140 ms and the title swaps in a 50 ms
  cross-fade 90 ms in, while a dismissal swaps the bar to the covered
  page's items 150 ms into the drag and back if it is cancelled. With a
  `CupertinoNavigationBar` on each page the Cupertino hero flight runs
  instead, sliding the new title in over the whole flight and switching
  on the pop rather than the drag; a bar above the navigator is the
  native shape.
- The zoom route is non-opaque. An app that decides whether native chrome
  under a route must hide by reading `route.opaque` needs a subclass of
  `ZoomPageRoute` implementing its own "obscures chrome" interface, the same
  way that app already subclasses go_router's page for its shell. This is a
  five-line app-side adapter and is out of scope for the package.
- Pinned chrome is correct for both transitions here, so the zoom
  destination can keep a pinned bar.

---

## 9. References

- Flutter SDK 3.47.1: `widgets/heroes.dart`, `cupertino/route.dart`
  (`CupertinoRouteTransitionMixin`, `_CupertinoBackGestureController`,
  `CupertinoPageTransition.delegatedTransition`), `cupertino/sheet.dart`
  (`_CupertinoSheetScrollPosition`, corner radius heuristic),
  `material/page_transitions_theme.dart` (`SnapshotWidget` usage),
  `widgets/media_query.dart` (`displayCornerRadii`),
  `physics/spring_simulation.dart` (`withDurationAndBounce`).
- Apple: *Enhancing your app with fluid transitions* (UIKit article),
  `UIViewController.Transition.zoom(options:sourceViewProvider:)`,
  `UIViewController.Transition.ZoomOptions`, SwiftUI
  `navigationTransition(_:)`, `NavigationTransition.zoom(sourceID:in:)`,
  `matchedTransitionSource(id:in:configuration:)`,
  `MatchedTransitionSourceConfiguration`. WWDC24 session 10145.
- kylebshr/ScreenCorners README: the per-device display corner radii read
  from `UIScreen._displayCornerRadius`, reproduced in section 3.2.
- sdegenaar/liquid_glass_widgets: PR #223 "morph swipe-dismissals back into
  the trigger" (`SheetMorphGeometry.dismissedRect`, `dampedDismissTravel`,
  `dismissScale`, `rubberBand`, and the presenter's tracking chase), its follow-up commit `ee2b97f` (`closeVelocityFor`, RTL
  symmetry) on the `feat/modal-sheet-swipe-follow-ups` branch, and PR #256's
  scroll handover. Same author as this package; ported with attribution.
- exeshka/swiftuikit 0.2.1: `zoom_route.dart` and `page_transitions.dart`,
  read as a reference implementation (Hero-based zoom with a frozen page
  snapshot, delegated dimming, full-width back swipe). Its dependency set
  (`auto_route`, `flutter_physics`, `screen_corner_radius`) and its lack of
  a pinch gesture are why this package is a separate implementation.
- Recordings: `drag.mov`, `back.mov`, `pinch.mp4` captured on iOS 26 on
  2026-09-02, and `push.mov` (Settings, push and held back swipe) on
  2026-09-07. Not committed; the frame-strip tool in `tool/` reproduces the
  readings from any recording.
