# swift_transitions

[![pub package](https://img.shields.io/pub/v/swift_transitions.svg)](https://pub.dev/packages/swift_transitions)
[![CI](https://github.com/JakeThomson/swift_transitions/actions/workflows/ci.yml/badge.svg)](https://github.com/JakeThomson/swift_transitions/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

iOS's navigation transitions for Flutter, measured frame by frame from the
real thing.

A destination page grows out of the view that opened it and shrinks back into
it, following the finger through a drag, a swipe or a pinch — the transition
Apple added in iOS 18 as `navigationTransition(.zoom(sourceID:in:))` in SwiftUI
and `UIViewController.Transition.zoom` in UIKit. The ordinary push is here too,
with the same curve, the same back swipe and the display's own rounded corners.

Every curve, spring, threshold and gesture in this package was fitted against a
native SwiftUI app driven through the same scripted gestures on the same
device. [How it is calibrated](#how-it-is-calibrated) has the numbers.

| Zoom push and pop | Pinch and rotate | Back swipe |
|:--:|:--:|:--:|
| ![The zoom transition](https://raw.githubusercontent.com/JakeThomson/swift_transitions/main/docs/demo/zoom.gif) | ![A pinch dismissal springing back](https://raw.githubusercontent.com/JakeThomson/swift_transitions/main/docs/demo/pinch-rotate.gif) | ![The interactive back swipe](https://raw.githubusercontent.com/JakeThomson/swift_transitions/main/docs/demo/back-swipe.gif) |

The example app on an iPhone 17 simulator. The pinch is released above the
dismiss threshold, so the card springs back to full screen and un-rotates on
the way.

## Features

* **The zoom transition.** A page flies out of a `ZoomTransitionSource` and
  back into it, cross-fading with the source's content and morphing from the
  source's corner radius to the display's.
* **Interactive dismissal.** A downward pan anywhere on the page, a swipe from
  the leading edge, or a two-finger pinch shrinks the page into a card that
  tracks the fingers. Release past the threshold and it lands on its source;
  release early and it springs back.
* **Interruptible.** A card in flight can be caught and dragged, a cancelled
  dismissal can be grabbed again, and the navigator sees one gesture from the
  first touch to the settle.
* **Scroll views take part.** A drag on a vertical scroll view at its top edge
  becomes a dismissal, without any wiring, through the route's own
  `PrimaryScrollController`.
* **The push transition.** iOS's push and pop, its 12 pt dead zone, its release
  projection and its spring, applied per route or to every `MaterialPageRoute`
  on iOS through a `PageTransitionsBuilder`. The back swipe can start from the
  leading edge or anywhere on the page, as in iOS 26.
* **Display-radius corner clipping.** Pages are clipped to the device's actual
  screen corners, resolved from `MediaQuery` or the iOS device table, and the
  leading-edge shadow is cast from the clipped shape.
* **Idiomatic.** `PageRoute`s and `Page`s that compose with Cupertino and
  Material neighbours, `Hero`-style source lookup, `of(context)` accessors, and
  a `PageTransitionsBuilder` for theme-wide use. Reduce Motion replaces the
  zoom flight with a cross-fade, as the native page does.
* **No dependencies** beyond the Flutter SDK.

## Installation

```sh
flutter pub add swift_transitions
```

## Usage

### The zoom transition

Mark what the page grows out of with `ZoomTransitionSource`, and push a
`ZoomPageRoute` with the matching tag:

```dart
import 'package:swift_transitions/swift_transitions.dart';

ZoomTransitionSource(
  tag: poster.id,
  borderRadius: BorderRadius.circular(12),
  child: GestureDetector(
    onTap: () => Navigator.of(context).push(
      ZoomPageRoute<void>(
        sourceTag: poster.id,
        builder: (context) => PosterPage(poster),
      ),
    ),
    child: PosterArt(poster),
  ),
)
```

The source is hidden behind a placeholder of its own size for as long as the
route is up, so the row or grid around it does not reflow. A tag with no source
falls back to a centred scale-and-fade.

For a declarative `Navigator` — go_router included — use `ZoomPage`:

```dart
Page<void> buildPage(BuildContext context, GoRouterState state) => ZoomPage<void>(
  key: state.pageKey,
  sourceTag: state.pathParameters['id']!,
  child: PosterPage.byId(state.pathParameters['id']!),
);
```

`sourceTag` is read again on every pop, so a paging detail page can set it to
whichever item it is showing and the dismissal lands on that item's source.

### The push transition

Per route:

```dart
Navigator.of(context).push(
  SwiftPageRoute<void>(builder: (context) => const DetailPage()),
);
```

Or for every route on iOS, including `MaterialPageRoute`:

```dart
MaterialApp(
  theme: ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.iOS: SwiftPageTransitionsBuilder()},
    ),
  ),
)
```

Both take a `backGestureRegion`: `BackGestureRegion.leadingEdge` (the default,
the SDK's own region) or `BackGestureRegion.anywhere`, the iOS 26 behaviour
where a horizontal drag anywhere on the page swipes back.

A covered `CupertinoPageRoute` or Material route gets the matching motion and
dim through `SwiftPageTransition.delegatedTransition`, so pages half in and out
of the package still move in lockstep.

### Options

`ZoomTransitionOptions` mirrors `UIZoomTransitionOptions`:

```dart
ZoomPageRoute<void>(
  sourceTag: poster.id,
  options: ZoomTransitionOptions(
    // Which gestures may dismiss the route.
    dismissGestures: const ZoomDismissGestures(pinch: false),
    // Vetoed dismissals are left to the page, like
    // UIZoomTransitionOptions.interactiveDismissShouldBegin.
    interactiveDismissShouldBegin: (context) =>
        context.gesture != ZoomGesture.pan || !hasUnsavedEdits,
    // The dim, and an optional blur, over the page underneath.
    dimmingColor: const Color(0x26000000),
    dimmingBlurSigma: 0,
    // The part of the page that lines up with the source, the counterpart of
    // alignmentRectProvider. Null aligns the whole page.
    alignmentRect: (context) => Rect.fromLTWH(0, 0, context.pageSize.width, 240),
    // Rasterise the page once per flight, for pages that are expensive to paint.
    snapshotDuringTransition: true,
  ),
  builder: (context) => PosterPage(poster),
)
```

The response of the dismissal itself is `ZoomDismissPhysics`, whose default
`ZoomDismissPhysics.ios26` carries every fitted constant. Each one is
documented and overridable if you want a different feel.

### Scroll views

A `ZoomPageRoute` installs a `ZoomScrollController` as the page's
`PrimaryScrollController`, so a vertical `ListView` or `CustomScrollView` on
iOS hands a downward drag at its top edge to the dismissal with no
configuration. A scroll view with its own controller should be given the
route's instead:

```dart
ListView(
  controller: ZoomRouteTransitionMixin.of(context)?.scrollController,
  children: ...,
)
```

## API

| | |
|---|---|
| `ZoomPageRoute`, `ZoomPage` | The zoom transition as a route and as a page |
| `ZoomTransitionSource` | What a zoom route grows out of and lands on |
| `ZoomTransitionOptions` | Dimming, gestures, alignment rect, snapshotting |
| `ZoomDismissPhysics` | The fitted response of the interactive dismissal |
| `ZoomRouteTransitionMixin` | The zoom transition on your own `PageRoute` |
| `ZoomScrollController` | The scroll controller that feeds the dismissal |
| `SwiftPageRoute`, `SwiftPage` | The push transition as a route and as a page |
| `SwiftPageTransitionsBuilder` | The push transition for every route on iOS |
| `SwiftPageTransitionMixin` | The push transition on your own `PageRoute` |
| `SwiftPageTransition` | The transition widget on its own |
| `BackGestureRegion` | Where the back swipe may start |
| `DisplayCornerRadii` | The display's corner radius, resolved or overridden |
| `SwiftCurves`, `SwiftSprings` | The measured curves and springs, on their own |

## Example

The [`example/`](example) directory is a runnable gallery: a list that pushes,
and a row of posters that zoom.

```sh
cd example
flutter run
```

## How it is calibrated

The behaviour here was not eyeballed. A native SwiftUI reference app and the
example app were driven through the same scripted gestures on the same device
(iPhone 17 simulator, iOS 27.0), recorded at 60 fps, and the card's position,
size and corner radius tracked frame by frame in both.

The push, the back swipe and the zoom flight follow native's curves to 1–6 pt
RMS. A held card's scale is within 0.006 of native's in every gesture, releases
agree with native's commit tables, and landings from rest agree within a frame.

Every calibrated constant, the recording it came from, and the deviations that
remain are written up in
[`docs/design.md`](https://github.com/JakeThomson/swift_transitions/blob/main/docs/design.md);
the method is in
[`docs/parity-plan.md`](https://github.com/JakeThomson/swift_transitions/blob/main/docs/parity-plan.md)
and side-by-side clips of each stage are in
[`docs/parity/`](https://github.com/JakeThomson/swift_transitions/tree/main/docs/parity).

### Known differences

Section 1.7 of the design document lists these in full, with the size of each.
The ones you are most likely to see:

* **Navigation bars.** Natively the bar's items stay above the flying card and
  cross-fade in place. With a `CupertinoNavigationBar` on each page the SDK's
  own bar hero runs instead, sliding the title across for the length of the
  flight. A bar above the navigator does not fly at all, which is the native
  shape.
* **Touches during a landing.** Natively a touch on a landing card reaches the
  page underneath and can push again. Here the page underneath is blocked until
  the pop has finished, by choice — a half-finished dismissal that opens
  something else reads as a misfire.
* **An edge swipe flung hard.** One released at 800 pt/s lands in 147 ms where
  native takes 100. Releases from rest, and pinches, match.
* **A source that has never been built.** A pop to a cell far outside a lazy
  list's cache extent has no frame to fly to and falls back to a centred rect.

## Compatibility

Flutter 3.44 and later, Dart 3.12 and later. The package is pure Dart and runs
on every platform Flutter supports; the transitions are iOS-styled wherever
they run, which is the point of using them.

## Non-goals

* Reimplementing `Hero`. Shared-element flights between arbitrary widgets are
  already covered by the SDK.
* A general-purpose transition library. This package does iOS's navigation
  transitions and nothing else.

## References

* SwiftUI
  [`matchedTransitionSource(id:in:)`](https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:))
  and
  [`navigationTransition(_:)`](https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)).
* UIKit
  [`UIViewController.Transition.zoom(options:sourceViewProvider:)`](https://developer.apple.com/documentation/uikit/uiviewcontroller/transition/zoom(options:sourceviewprovider:))
  and
  [`UIZoomTransitionOptions`](https://developer.apple.com/documentation/uikit/uizoomtransitionoptions).
* WWDC24 session 10145, *Enhance your UI animations and transitions*.

## Contributing

Contributions are welcome. See
[CONTRIBUTING.md](https://github.com/JakeThomson/swift_transitions/blob/main/CONTRIBUTING.md)
for how to set the project up and what a good pull request looks like. This
project follows the
[Contributor Covenant](https://github.com/JakeThomson/swift_transitions/blob/main/CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE](LICENSE).
