<div align="center">

# Swift Transitions

iOS's navigation transitions for Flutter — the iOS 18 zoom transition with its
interactive dismissal, and the push, both measured frame by frame from the
real thing.

[![pub package](https://img.shields.io/pub/v/swift_transitions.svg)](https://pub.dev/packages/swift_transitions)
[![pub points](https://img.shields.io/pub/points/swift_transitions)](https://pub.dev/packages/swift_transitions/score)
[![likes](https://img.shields.io/pub/likes/swift_transitions)](https://pub.dev/packages/swift_transitions/score)
[![CI](https://github.com/JakeThomson/swift_transitions/actions/workflows/ci.yml/badge.svg)](https://github.com/JakeThomson/swift_transitions/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<img src="https://raw.githubusercontent.com/JakeThomson/swift_transitions/main/docs/demo/zoom.gif" width="220" alt="A page zooming out of a poster and back into it">
&nbsp;
<img src="https://raw.githubusercontent.com/JakeThomson/swift_transitions/main/docs/demo/pinch-dismiss.gif" width="220" alt="A page pinched, turned and dragged, then landing on its poster">
&nbsp;
<img src="https://raw.githubusercontent.com/JakeThomson/swift_transitions/main/docs/demo/back-swipe.gif" width="220" alt="A back swipe from the leading edge">

</div>

A destination page grows out of the view that opened it and shrinks back into
it, following the finger through a drag, a swipe or a pinch — the transition
Apple added in iOS 18 as `navigationTransition(.zoom)` in SwiftUI and
`UIViewController.Transition.zoom` in UIKit. The ordinary push is here too,
with the same curve, the same back swipe and the display's own rounded corners.

## Features

- **The zoom transition** — a page flies out of a `ZoomTransitionSource` and
  back into it, cross-fading with the source and morphing from the source's
  corner radius to the display's.
- **Interactive dismissal** — a downward pan, a swipe from the leading edge or
  a two-finger pinch shrinks the page into a card that tracks the fingers. Let
  go past the threshold and it lands on its source; let go early and it springs
  back.
- **Interruptible** — a card in flight can be caught and dragged, a cancelled
  dismissal can be grabbed again, and the navigator sees one gesture from the
  first touch to the settle.
- **Scroll views take part** — a drag on a vertical scroll view at its top edge
  becomes a dismissal with no wiring, through the route's own
  `PrimaryScrollController`.
- **The push transition** — iOS's push and pop, its dead zone, its release
  projection and its spring, per route or for every `MaterialPageRoute` on iOS
  through a `PageTransitionsBuilder`. The back swipe can start from the leading
  edge or anywhere on the page, as in iOS 26.
- **Display-radius corner clipping** — pages are clipped to the device's actual
  screen corners, and the leading-edge shadow is cast from the clipped shape.
- **Measured, not eyeballed** — every curve, spring and threshold was fitted
  against a native SwiftUI app driven through the same scripted gestures on the
  same device. See [Fidelity](#fidelity).
- **Idiomatic** — `PageRoute`s and `Page`s that compose with Cupertino and
  Material neighbours, `Hero`-style source lookup, `of(context)` accessors and a
  `PageTransitionsBuilder`.
- **Zero dependencies** beyond the Flutter SDK.

## Installation

```yaml
dependencies:
  swift_transitions: ^0.1.0
```

```sh
flutter pub add swift_transitions
```

> Requires Flutter 3.44 and Dart 3.12 or later. Pure Dart: no native code, no
> platform setup.

## Quick start

### Step 1: Mark the source

Wrap whatever the page should grow out of in a `ZoomTransitionSource` with a
tag. Its `borderRadius` is where the card's corners start from.

```dart
import 'package:swift_transitions/swift_transitions.dart';

ZoomTransitionSource(
  tag: poster.id,
  borderRadius: BorderRadius.circular(12),
  child: PosterArt(poster),
)
```

### Step 2: Push a zoom route

```dart
Navigator.of(context).push(
  ZoomPageRoute<void>(
    sourceTag: poster.id,
    builder: (context) => PosterPage(poster),
  ),
);
```

That's it. The page flies out of the source, the source is hidden behind a
placeholder of its own size so the row around it doesn't reflow, and every
dismissal gesture is already wired up.

> **Using a declarative `Navigator` or go_router?** Use `ZoomPage`:
>
> ```dart
> Page<void> buildPage(BuildContext context, GoRouterState state) =>
>     ZoomPage<void>(
>       key: state.pageKey,
>       sourceTag: state.pathParameters['id']!,
>       child: PosterPage.byId(state.pathParameters['id']!),
>     );
> ```

> **No matching source?** The route falls back to a centred scale-and-fade,
> the same fallback UIKit uses when a zoom's source view can't be found.

`sourceTag` is read again on every pop, so a paging detail page can set it to
whichever item it's showing and the dismissal lands on that item's source.

## The push transition

Per route:

```dart
Navigator.of(context).push(
  SwiftPageRoute<void>(builder: (context) => const DetailPage()),
);
```

Or for every route on iOS, `MaterialPageRoute` included:

```dart
MaterialApp(
  theme: ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.iOS: SwiftPageTransitionsBuilder()},
    ),
  ),
)
```

Both take a `backGestureRegion`:

| Region | Behaviour |
|---|---|
| `BackGestureRegion.leadingEdge` | The SDK's own region: the leading 20 pt, or the safe-area inset if larger. **Default.** |
| `BackGestureRegion.anywhere` | A horizontal drag anywhere on the page swipes back, as in iOS 26. |

> A covered `CupertinoPageRoute` or Material route gets the matching motion and
> dim through `SwiftPageTransition.delegatedTransition`, so pages half in and
> out of the package still move in lockstep.

## Interactive dismissal

Every zoom route can be dismissed three ways, all on by default:

| Gesture | How it starts | What commits |
|---|---|---|
| **Pan** | A downward drag anywhere on the page, or on a vertical scroll view once it reaches its top | Released far enough down, or flung |
| **Edge swipe** | A drag from the leading edge | Released past the threshold, or flung — a short, fast flick springs back, as it does natively |
| **Pinch** | Two fingers closing; the card scales, turns and moves with them | Released below half size, wherever the fingers were headed |

A second finger turns a pan or a swipe into a pinch. A card that's springing
back can be grabbed again, and a card still being pushed can be caught.

### Scroll views

The route installs a `ZoomScrollController` as the page's
`PrimaryScrollController`, so a `ListView` or `CustomScrollView` on iOS hands a
top-edge drag to the dismissal with no configuration. A scroll view with its
own controller should be given the route's instead:

```dart
ListView(
  controller: ZoomRouteTransitionMixin.of(context)?.scrollController,
  children: ...,
)
```

## Options

`ZoomTransitionOptions` mirrors `UIZoomTransitionOptions`:

```dart
ZoomPageRoute<void>(
  sourceTag: poster.id,
  options: ZoomTransitionOptions(
    dismissGestures: const ZoomDismissGestures(pinch: false),
    interactiveDismissShouldBegin: (context) =>
        context.gesture != ZoomGesture.pan || !hasUnsavedEdits,
    dimmingColor: const Color(0x26000000),
    dimmingBlurSigma: 0,
    alignmentRect: (context) =>
        Rect.fromLTWH(0, 0, context.pageSize.width, 240),
    snapshotDuringTransition: true,
  ),
  builder: (context) => PosterPage(poster),
)
```

| Parameter | Default | Purpose |
|---|---|---|
| `dismissGestures` | all | Which of the pan, the edge swipe and the pinch may dismiss |
| `interactiveDismissShouldBegin` | allow | Asked before a dismissal begins, with the gesture and where it started; return `false` to leave it to the page |
| `dismissPhysics` | `ZoomDismissPhysics.ios26` | The fitted response of the dismissal — every constant documented and overridable |
| `dimmingColor` | 15 % black | The dim over the page underneath, eased in with the flight and tracking a dismissal |
| `dimmingBlurSigma` | `0` | A blur under the dim, the counterpart of `dimmingVisualEffect` |
| `alignmentRect` | whole page | The part of the page that lines up with the source, asked on the push and again on each pop |
| `pushSpring` | measured | The spring that drives the push and a non-interactive pop |
| `snapshotDuringTransition` | `false` | Rasterise the page once per flight — for pages that are expensive to paint |

## Fidelity

A native SwiftUI reference app and the example app were driven through the
same scripted gestures on the same device, recorded at 60 fps, and the card's
position, size and corner radius tracked frame by frame in both.

- The push, the back swipe and the zoom flight follow native's curves to
  1–6 pt RMS.
- A held card's scale is within 0.006 of native's in every gesture.
- Releases agree with native's commit tables, and landings from rest agree
  within a frame.

### Known differences

| | |
|---|---|
| **Navigation bars** | Natively the bar's items stay above the flying card and cross-fade in place. With a `CupertinoNavigationBar` on each page the SDK's own bar hero runs instead. A bar above the navigator doesn't fly at all, which is the native shape. |
| **Touches during a landing** | Natively a touch on a landing card reaches the page underneath. Here it's blocked until the pop has finished, by choice — a half-finished dismissal that opens something else reads as a misfire. |
| **An edge swipe flung hard** | One released at 800 pt/s lands in 147 ms where native takes 100. Releases from rest, and pinches, match. |
| **A source that was never built** | A pop to a cell far outside a lazy list's cache extent has no frame to fly to and falls back to a centred rect. |

## Platform support

| Platform | Support | Notes |
|---|---|---|
| iOS | ✅ | The display's corner radius from a device table |
| Android | ✅ | Corner radius from `MediaQuery` on Android 12+ |
| macOS | ✅ | |
| Web | ✅ | |
| Windows | ✅ | |
| Linux | ✅ | |

The transitions are iOS-styled wherever they run — that's the point. Where no
corner radius is reported, `DisplayCornerRadii` can supply one for a subtree:

```dart
DisplayCornerRadii(
  radii: BorderRadius.circular(24),
  child: MyApp(),
)
```

## Accessibility

With Reduce Motion on, the zoom flight is replaced by a cross-fade, as the
native page does. Nothing to configure.

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

The [`example/`](example) directory is a runnable gallery — a list that pushes
and a row of posters that zoom.

```sh
cd example
flutter run
```

## Contributing

Contributions are welcome. See
[CONTRIBUTING.md](https://github.com/JakeThomson/swift_transitions/blob/main/CONTRIBUTING.md)
for how to set the project up and what a good pull request looks like. This
project follows the
[Contributor Covenant](https://github.com/JakeThomson/swift_transitions/blob/main/CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE](LICENSE).

## Links

- [pub.dev](https://pub.dev/packages/swift_transitions)
- [Repository](https://github.com/JakeThomson/swift_transitions)
- [Issue tracker](https://github.com/JakeThomson/swift_transitions/issues)
- Apple: [`navigationTransition(_:)`](https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)), [`matchedTransitionSource(id:in:)`](https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:)), [`UIZoomTransitionOptions`](https://developer.apple.com/documentation/uikit/uizoomtransitionoptions)
