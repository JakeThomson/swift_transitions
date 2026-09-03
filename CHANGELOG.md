## 0.1.0-dev

* Add `SwiftPageRoute`, `SwiftPage` and `SwiftPageTransitionsBuilder`: the
  iOS push transition with display-radius corner clipping, plus a
  `BackGestureRegion` to swipe back from the leading edge or anywhere on
  the page. The leading-edge shadow is cast from the clipped shape, so it
  wraps the rounded corner rather than filling it as a rectangle.
* Add `DisplayCornerRadii`, resolving the physical display corner radius from
  an override, `MediaQuery`, or the iOS device table.
* Add `SwiftSprings.standard`, the SDK's Cupertino modal spring.
* Initial project scaffold. No zoom route yet.
