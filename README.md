# swift_transitions

[![CI](https://github.com/JakeThomson/swift_transitions/actions/workflows/ci.yml/badge.svg)](https://github.com/JakeThomson/swift_transitions/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An iOS-style zoom navigation transition for Flutter. A destination page grows
out of the view that opened it and shrinks back into that view when dismissed,
tracking the user's finger during an interactive dismissal.

This is the transition Apple added in iOS 18 as
`navigationTransition(.zoom(sourceID:in:))` in SwiftUI and
`UIViewController.Transition.zoom` in UIKit.

## Status

Early development. There is no public API and no release yet. The design and
the implementation plan live in [docs/design.md](docs/design.md); it covers
the target behaviour measured from iOS 26 recordings, the proposed API, the
architecture, and the delivery milestones. Watch the repository or the
[issue tracker](https://github.com/JakeThomson/swift_transitions/issues) for
progress.

## Goals

* Match the look and feel of the iOS 18 zoom transition: the source-anchored
  scale, the clip-shape morph, the dimming layer and the interactive dismissal.
* Feel native to Flutter. The API should read like `Hero` and plug into the
  existing `Navigator`, `Route` and `PageTransitionsBuilder` machinery rather
  than replacing it.
* Expose the knobs iOS gives you that `Hero` does not, such as the alignment
  rect of the source, dimming appearance and interactive-dismiss gating, in the
  spirit of `UIZoomTransitionOptions`.
* Depend on as little as possible. The package currently depends only on the
  Flutter SDK. If the split-out
  [`cupertino_ui`](https://pub.dev/packages/cupertino_ui) or
  [`material_ui`](https://pub.dev/packages/material_ui) packages turn out to be
  necessary, they will be added deliberately and documented here.

## Non-goals

* Reimplementing `Hero`. Shared-element flights between arbitrary widgets are
  already covered by the SDK.
* A general-purpose page transition library. This package does one transition
  well.

## Design references

* Flutter's `Hero`, `HeroController` and `HeroFlightShuttleBuilder`
  ([source](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/heroes.dart)).
* SwiftUI
  [`matchedTransitionSource(id:in:)`](https://developer.apple.com/documentation/swiftui/view/matchedtransitionsource(id:in:))
  and
  [`navigationTransition(_:)`](https://developer.apple.com/documentation/swiftui/view/navigationtransition(_:)).
* UIKit
  [`UIViewController.Transition.zoom(options:sourceViewProvider:)`](https://developer.apple.com/documentation/uikit/uiviewcontroller/transition/zoom(options:sourceviewprovider:))
  and
  [`UIZoomTransitionOptions`](https://developer.apple.com/documentation/uikit/uizoomtransitionoptions).
* WWDC24 session 10145, *Enhance your UI animations and transitions*.

## Installation

The package is not on pub.dev yet. To try it from source, add a git
dependency:

```yaml
dependencies:
  swift_transitions:
    git: https://github.com/JakeThomson/swift_transitions.git
```

## Example

The `example/` directory contains a runnable app that will demonstrate the
transition once the API lands.

```sh
cd example
flutter run
```

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) for
how to set up the project and what a good pull request looks like. This project
follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## License

MIT. See [LICENSE](LICENSE).
