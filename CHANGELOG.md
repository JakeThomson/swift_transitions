## 0.1.0-dev

* Make the zoom route's interactive dismissal interruptible the whole way:
  a committed release lands the card before the route pops, so a card on
  its way down — or springing back — can be caught and dragged again, and
  the navigator sees one gesture from the first grab to the last landing.
  A dismissal begun from rest looks the source up again, so a paging page
  that changes `sourceTag` lands on the poster it is showing.
* Add `alignmentRect` and `snapshotDuringTransition` to
  `ZoomTransitionOptions`: the part of the page that aligns with the
  source, asked on the push and again on each pop like UIKit's
  `alignmentRectProvider`, and a Material-style snapshot of the page while
  it flies. Export `ZoomRouteTransitionMixin` for custom routes and for
  pages that set the enclosing route's `sourceTag`.
* Add the pinch to the zoom route's interactive dismissal: two fingers
  scale the card with their distance, rotate it with their angle and move it
  with their focal point, and a second finger turns a pan or swipe into a
  pinch. The card un-rotates on the way to wherever it lands. The pinch is
  read from the page's own pointer layer and takes its finger from a
  scrolling list through the route's scroll controller.
* Add interactive dismissal to the zoom route: a downward pan anywhere on
  the page, or on a vertical scroll view once it reaches its top edge, and a
  swipe from the leading edge shrink the page into a card that follows the
  finger; a release past the threshold or a fling lands it on its source,
  seeded with the release velocity, and an early release springs it back. A
  page still being pushed can be grabbed. The response is
  `ZoomDismissPhysics`, the iOS 26 fit ported from liquid_glass_widgets'
  swipe-dismiss morph; `ZoomTransitionOptions` gains `dismissGestures`,
  `interactiveDismissShouldBegin` and `dismissPhysics`, and the route
  exposes the `ZoomScrollController` it installs as the page's primary
  scroll controller.
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
