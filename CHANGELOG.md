## 0.1.0-dev

* Match the push transition's covered page to iOS: it travels 0.29 of the
  width on the same curve as the arriving page, so the two move in lockstep
  and track the finger together, and it is dimmed by the transition at
  0.115 × progress. `SwiftPageRoute` has no barrier colour; a covered
  `CupertinoPageRoute` or Material route gets the same motion and dim
  through `SwiftPageTransition.delegatedTransition`.
* Add `ZoomPageRoute`, `ZoomPage` and `ZoomTransitionSource`: the iOS 18
  zoom transition, non-interactive. A page grows out of the source tagged
  with its `sourceTag` and shrinks back into it on pop, cross-fading with
  the source's content and morphing from the source's corner radius to the
  display's; the source is hidden behind a placeholder of its own size while
  the route is up. The covered page stays put and is dimmed through the
  route's modal barrier, configurable with `ZoomTransitionOptions`. A
  missing source falls back to a centred scale-and-fade, and Reduce Motion
  to a cross-fade.
* Add `SwiftPageRoute`, `SwiftPage` and `SwiftPageTransitionsBuilder`: the
  iOS push transition with display-radius corner clipping, plus a
  `BackGestureRegion` to swipe back from the leading edge or anywhere on
  the page. The leading-edge shadow is cast from the clipped shape, so it
  wraps the rounded corner rather than filling it as a rectangle.
* Add `DisplayCornerRadii`, resolving the physical display corner radius from
  an override, `MediaQuery`, or the iOS device table.
* Add `SwiftSprings.standard`, the SDK's Cupertino modal spring.
* Initial project scaffold.
