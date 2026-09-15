# Changelog

All notable changes to this package are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the package
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.1] - 2026-09-15

### Fixed

- A back swipe from anywhere yields to a pan on the page — a swipe deck's
  card — not only to a horizontal scrollable, and a drag that opens toward
  the leading edge is left to the page rather than claimed and dropped.

## [0.2.0] - 2026-09-14

### Added

- `ZoomTransitionOptions.backGestureRegion`, where the zoom route's back swipe
  may start.
- `ZoomDismissPhysics.anywhereSwipeDismissThreshold`, the commit line of a back
  swipe begun anywhere on the page (0.79; the edge swipe's stays 0.70).

### Changed

- The back swipe starts anywhere on the page by default, on both routes, as on
  iOS 26; a swipe begun on the leading edge is still the edge swipe and wins
  over a horizontal scrollable, one begun elsewhere yields to it.
- The push page's swipe from anywhere waits out 27 pt and commits from 42 % of
  the width; the zoom card's waits out 18 pt and commits below 0.79, measured
  against native.
- `ZoomDismissGestures.edgeSwipe` and `ZoomGesture.edgeSwipe` are `backSwipe`;
  `ZoomDismissPhysics.dismissThreshold` is `edgeSwipeDismissThreshold`.

## [0.1.2] - 2026-09-11

### Fixed

- A zoom's flight lands on the source's resting rect rather than one read back
  through the covered page's scale, which was 9 % too big under a deferred
  push.
- A pop's cross-fade comes in from the start of the flight, as native's does,
  instead of over its last half.

## [0.1.1] - 2026-09-11

### Added

- `ZoomAlignmentRectContext.pageContext` and `rectOf`, so an alignment rect can
  be measured from a key once the page is laid out.

### Fixed

- An aligned zoom scales the page as one picture so the art lands on the
  source, as UIKit's `alignmentRectProvider` does, rather than closing a window
  in on it.
- A `ZoomTransitionSource` that is not being painted (an offstage tab, a hidden
  `Visibility`) no longer takes part in a flight.

## [0.1.0] - 2026-09-11

First release: iOS's navigation transitions for Flutter, fitted against a
native reference app frame by frame. The calibrated constants and the known
deviations are in `docs/design.md`.

### Added

- `ZoomPageRoute`, `ZoomPage` and `ZoomTransitionSource`: the iOS 18 zoom
  transition, with `ZoomTransitionOptions` mirroring `UIZoomTransitionOptions`.
- Interactive dismissal by pan, edge swipe and pinch, interruptible throughout,
  with `ZoomDismissPhysics` carrying the fitted response and
  `ZoomScrollController` handing a top-edge drag across from a scroll view.
- `SwiftPageRoute`, `SwiftPage` and `SwiftPageTransitionsBuilder`: the iOS push
  with the measured curve, dim and display-radius corner clip, and a back swipe
  from the leading edge or anywhere (`BackGestureRegion`).
- `DisplayCornerRadii`, `SwiftCurves` and `SwiftSprings`.

[Unreleased]: https://github.com/JakeThomson/swift_transitions/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/JakeThomson/swift_transitions/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/JakeThomson/swift_transitions/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/JakeThomson/swift_transitions/compare/d68dd87...v0.1.1
[0.1.0]: https://github.com/JakeThomson/swift_transitions/compare/1b9662d...d68dd87
