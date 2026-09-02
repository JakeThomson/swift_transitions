# swift_transitions: design and implementation plan

Status: proposal, 2026-09-02. Nothing in this document is implemented yet.

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
  out by a third of the width and is dimmed slightly. Flutter uses
  `Curves.fastEaseInToSlowEaseOut` over 500 ms and a barrier colour of
  `0x18000000` for the dim.
- The incoming page's leading corners are clipped to the display corner radius
  while it is in motion. At rest the clip is removed.
- A soft shadow runs along the incoming page's leading edge.
- The back swipe starts on the leading 20 pt (or the notch inset if larger).
  On commit the remaining travel runs over 350 ms; a fling of one screen width
  per second commits regardless of position.
- Navigation bar items do not travel with the page. They belong to the stack
  and cross-fade (Flutter apps that want this use a shell above the navigator,
  see section 8; the package does not draw bar chrome).

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

**Pan down anywhere** (`drag.mov`). A downward drag anywhere on the page
content starts the dismissal immediately: the page scales down about its
touch point and translates with the finger. Scale is a function of drag
distance and keeps decreasing as the finger moves; near the bottom of the
screen the card is about 45 % of its width. The page in the recording was
scrolled to the top; on a scrolled page iOS lets the scroll view consume the
drag until it reaches its top edge.

**Edge back swipe** (`back.mov`). Dragging from the leading edge does not
slide the page. It shrinks it exactly like the pan, with scale driven by
horizontal distance, and the card then follows the finger freely.

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
| Card scale at bottom of a full pan | ~0.45 | `drag.mov` 3.0 s |
| Card scale mid-pinch | ~0.6 | `pinch.mp4` 1.3 s |
| On-screen corner radius at scale 0.55–0.6 | ~13–17 pt | consistent with a radius interpolated in the card's own space, so it scales with the card |
| Covered page luminance during dismissal | −4 % to −7 % | Y average of a thumbnail region: 71.5 at rest vs 66.8 mid-drag |
| Covered page scale during dismissal | 1.0 | no scale-down of the page underneath |
| Landing from near the target | ~0.2 s | `drag_land` strip |

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
///  3. a heuristic from `MediaQuery.viewPaddingOf(context).top`, the same
///     one the SDK's [CupertinoSheetRoute] uses (top inset × 0.9, and zero
///     below a 20 pt inset), refined with a small table of known iOS insets,
///  4. [BorderRadius.zero].
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
    required this.child,
    this.shape,             // RoundedSuperellipseBorder / RoundedRectangleBorder; default: no rounding
    this.background,        // Color drawn behind the content in flight
    this.shadow,            // BoxShadow applied to the source in flight
    this.flightChild,       // what to draw for the source inside the card; defaults to child
    this.enabled = true,
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
    this.dismissSpring,
    this.cancelSpring,
    this.minimumScale = 0.3,
    this.dismissThreshold = 0.75,         // card scale below which a release dismisses
    this.flingVelocity = 700.0,           // logical px/s
    this.snapshotDuringTransition = false,
  });
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
  @override Color? get barrierColor => null; // dimming is the delegated transition's job
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
- **The zoom route is non-opaque and has no barrier.** The source page stays
  visible and interactive-looking underneath. Dimming is painted by the
  delegated transition, not by `barrierColor`, so it can track the
  interactive progress and be blurred.

### 3.2 Corner radius resolution

`DisplayCornerRadii.of(context)` resolves as in section 2.1. Two facts drive
the design:

- Flutter 3.47 has `MediaQueryData.displayCornerRadii`, fed by
  `FlutterView.displayCornerRadii`, and the framework's own predictive-back
  transition uses it. The engine only populates it on Android API 31 and
  later; the iOS embedder does not report it, and the private `UIScreen` key
  that plugins read is not something the engine will adopt.
- The SDK's `CupertinoSheetRoute` already ships a heuristic
  (`viewPadding.top × 0.9`, off below 20 pt). It is within a few points on
  every modern iPhone and is what users of the SDK sheet already see.

The heuristic is refined with a lookup of well-known top insets to radii
(44 → 39, 47 → 47, 48 → 41.5, 50 → 44, 54 → 47, 59 → 55, 62 → 62 pt), falling
back to the SDK formula. The table lives in one file with its provenance and
is easy to extend. Clipping uses `ClipRSuperellipse`, which matches Apple's
continuous corners and is available since Flutter 3.29.

### 3.3 Push transition mechanics

`SwiftPageTransition` is `CupertinoPageTransition` plus a clip:

```
SlideTransition (secondary, −⅓ width, transformHitTests: false)
  └ SlideTransition (primary, from +1 width)
      └ DecoratedBoxTransition (leading edge shadow, as in the SDK)
          └ ClipRSuperellipse (leading corners = DisplayCornerRadii, only while primary < 1 or secondary > 0)
              └ child
```

The clip is removed at rest (`BorderRadius.zero` and `Clip.none`) so a
settled page costs nothing. The delegated transition applied to the covered
route is the SDK slide plus a dim matching Cupertino's barrier colour.

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
  final double dimming;     // 0..1 for the covered route
}
```

Two regimes produce a `ZoomFrame`:

**Flight** (push, committed dismissal, cancel): `t` is the route animation
(or a spring on the controller). `rect = Rect.lerp(alignedSource, screen, t)`,
`radii = lerp(source.radii, display.radii, t)` interpolated in the card's own
space so the visible radius scales with the card, `sourceOpacity` fades out
over the first ~40 % of a push and in over the last ~40 % of a pop, and
`dimming` is an ease-in of `t`.

**Interaction** (finger down): the gesture owns a `ZoomInteraction` with
`focalPoint`, `translation`, `scale` and `rotation`. The frame is the full
page transformed by scale and rotation about the focal point, then
translated; `radii` follow the same interpolation using the scale-derived
progress. The route's `controller.value` is set to the scale-derived
progress each frame so that everything else in the framework (secondary
animations, shells, Hero) sees a consistent scalar.

Pan and edge swipe map distance to scale with a soft curve
(`scale = 1 − k · d`, clamped at `minimumScale`, with `k` calibrated so that
a full-height pan reaches ~0.45); the pinch uses the recognizer's scale and
rotation directly, clamped.

**Rendering** of a `ZoomFrame`:

```
Stack (navigator-sized)
  ├ [delegated, on the route underneath] ColoredBox(dimmingColor × dimming) [+ BackdropFilter if blur]
  └ Transform (rotation about frame centre)
      └ Positioned.fromRect(frame.rect)
          └ DecoratedBox (shadow, RoundedSuperellipseBorder)
              └ ClipRSuperellipse(frame.radii)
                  └ Stack
                      ├ OverflowBox(alignment from alignmentRect, default topCenter)
                      │   └ Transform.scale(rect.width / pageWidth)
                      │       └ SizedBox(page size) ─ the live page
                      └ Opacity(sourceOpacity) ─ source flightChild, fitted to the source rect's aspect
```

The page is laid out at its full size once and scaled; it does not reflow,
matching iOS. `transformHitTests` stays true so the page remains tappable at
rest (the transform is identity then).

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

- `ZoomPageRoute.install` records `previousRoute` from `didChangePrevious`.
- On push (and again on each pop, because `sourceTag` may have changed) the
  route walks `previousRoute.subtreeContext` for a `ZoomTransitionSource`
  whose tag matches, applying `Hero`'s nested-navigator rule: a source inside
  another navigator counts only if its own route is a current `PageRoute`.
- The source's rect is measured after the destination's first layout, using
  the same end-of-frame deferral `HeroController` uses (`offstage` for the
  first frame so the page lays out at its final size).
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
  pattern need no changes. Pages with their own controllers can read
  `ZoomPageRoute.of(context).scrollController` or gate dismissal in
  `interactiveDismissShouldBegin` using the scroll metrics in the context.
- **Pinch arena.** Scrollables accept a pointer as soon as it moves past the
  touch slop, which usually happens before a second finger lands. The
  recognizer therefore calls `resolve(GestureDisposition.accepted)` for both
  pointers the moment it tracks two, and the route tells the scrollable's
  drag to cancel through the same `_dragCancelCallback` hook the sheet keeps.
  This is the riskiest part of the package and gets a spike before
  implementation (section 6, M4).
- **Release rules.** Dismiss if the card's scale is below
  `dismissThreshold`, or if the release velocity points away from the
  identity state (downwards for a pan, trailing for a swipe, contracting for
  a pinch) faster than `flingVelocity`. Otherwise cancel. Both outcomes use
  springs seeded with the release velocity so there is no visible kink.
- **Gates.** A dismissal begins only if `interactiveDismissShouldBegin`
  returns true (default: true), the route is current, and no other user
  gesture is in progress on the navigator. Unlike the SDK's
  `popGestureEnabled`, a running push animation does not block it (see
  3.8).
- **Chrome.** The package never freezes or replays navigation bar chrome.
  Shells that hoist chrome above the navigator get the signals they need
  from the navigator gesture flags and the route status.

### 3.8 Interruptible push

Apple: a push is never cancelled; grabbing during it completes the push and
begins a pop. In Flutter terms:

- A pointer down on the zooming page while `controller.status == forward`
  stops the controller, captures the current `ZoomFrame` as the interaction's
  starting state, and calls `didStartUserGesture()`.
- On release, "commit" pops the route (it is the current route, so this is a
  normal pop from a partial state), and "cancel" animates the controller
  forward again. Both are springs seeded with the release velocity.
- While the gesture is live the route's page is fully built and laid out, so
  taps that the gesture recognizers reject reach the page as on iOS.

### 3.9 Physics

- Push: `SpringDescription.withDurationAndBounce(duration: 500 ms, bounce: 0)`
  as the starting point, calibrated against the 60 fps push strip (most of
  the travel in the first ~120 ms).
- Dismissal landing and cancel: the same constructor with a slightly shorter
  duration, seeded with the release velocity projected onto the remaining
  travel. Rotation and translation share the spring's normalised progress so
  the card lands as one object.
- The SDK's Cupertino spring (stiffness 522.35, critically damped, 0.404 s)
  is available as `SwiftSprings.standard` for apps that want the exact SDK
  feel on the push transition.

### 3.10 Accessibility and platforms

- `MediaQuery.disableAnimationsOf(context)` (Reduce Motion) turns both
  transitions into a cross-fade of the same duration; gestures still pop.
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
  scrolled down scrolls instead until the top is reached, then hands off; a
  short pan cancels and restores identity; edge swipe drives scale; pinch
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

**M3 Interactive dismissal: pan and edge swipe (3–4 days).**
Gesture recognizers, scroll handoff position, release rules, springs seeded
with velocity, navigator gesture plumbing, `interactiveDismissShouldBegin`.
Acceptance: section 5 interaction tests except pinch; on device the three
recordings' pan and swipe behaviours are reproduced side by side.

**M4 Pinch (2–3 days, after a half-day spike).**
Spike: prove that a two-finger pinch over a scrolled `ListView` on iOS wins
the arena reliably with the eager-accept recognizer plus drag cancel. If it
cannot, fall back to a `Listener`-level pinch that only activates when the
scroll position is at rest, and document the limitation. Then: rotation,
focal point, un-rotate on landing. Acceptance: pinch tests; recording
`pinch.mp4` reproduced.

**M5 Fluidity and options (2–3 days).**
Interruptible push, dynamic `sourceTag` for paging detail pages,
`alignmentRect`, `snapshotDuringTransition`, `dimmingBlurSigma`. Performance
pass on a real device with a heavy page (the host app's glass surfaces):
frame times during flight with and without snapshotting recorded in the
CHANGELOG.

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
- *Corner radius on iOS* is a heuristic until the engine reports it.
  Mitigation: the override widget, the table, and the same numbers the SDK
  sheet already shows users.
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
   `PageRoute`. The plan assumes the mixin.
4. Whether to publish `ZoomFrame` and the rendering layer as public API for
   apps that want a custom presentation, or keep them private until 1.0.
   The plan keeps them private.

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
  route stops being active. Section 3.1 satisfies all three. This also
  matches what the recordings show: bar items stay pinned while the zoomed
  card shrinks, and cross-fade only when the pop commits.
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
- exeshka/swiftuikit 0.2.1: `zoom_route.dart` and `page_transitions.dart`,
  read as a reference implementation (Hero-based zoom with a frozen page
  snapshot, delegated dimming, full-width back swipe). Its dependency set
  (`auto_route`, `flutter_physics`, `screen_corner_radius`) and its lack of
  a pinch gesture are why this package is a separate implementation.
- Recordings: `drag.mov`, `back.mov`, `pinch.mp4` captured on iOS 26 on
  2026-09-02. Not committed; the frame-strip tool in `tool/` reproduces the
  readings from any recording.
