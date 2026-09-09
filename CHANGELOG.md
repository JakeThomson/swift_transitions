## 0.1.0-dev

* Match the zoom route's pan to iOS, measured against a native
  `NavigationStack` zoom (parity stage 4): the card holds still for the
  platform's slop, shrinks at 0.67 per screen height about the touch point
  to a knee at 0.52 of the height and eases past it toward 0.37, falls
  behind the finger by the cube of the travel (0.89 of the finger's travel
  at half the height, 0.73 at 0.8), follows the
  finger sideways at 0.56 rubber-banded toward 0.9 of its width (26 pt for
  a 50 pt sweep, 85 for 195) with no pinning at the screen's edges, and
  lands from a sixth of the height on, read through the same 120 ms
  projection as the edge swipe (0.914 at rest sprang back, 0.900 landed).
  A drag that begins on a scrolled list scrolls it to the top and
  over-scrolls there instead of turning into a dismissal, as the native
  page does. `ZoomDismissPhysics` gains `fallLag`, `fallFor`,
  `crossAxisGain`, `crossAxisLimit` and `crossAxisOffsetFor` (which replace
  `edgeSwipeVerticalGain`: the edge swipe's vertical follow is the same
  band as the pan's sideways one) and `panDismissThreshold`, and loses
  `edgeGive`, `horizontalOffsetFor` and `flingVelocity`.
* Match the zoom route's edge swipe to iOS, measured against a native
  `NavigationStack` zoom (parity stage 5): the card waits out the back
  swipe's 12 pt dead zone, shrinks at 0.67 per screen width with no knee,
  follows the finger sideways 1:1 (off the far side of the screen, rather
  than pinned inside it) and up or down at 0.43 of the finger's movement,
  a release commits on where 120 ms of its velocity would carry the card
  against a 0.70 scale boundary (a short fast flick springs back, as it
  does natively), and a cancelled release returns on the back swipe's
  spring (ω 22, ζ 0.9) instead of the flight spring. `ZoomDismissPhysics`
  gains `edgeSwipeVerticalGain`, `edgeSwipeScaleFor` and
  `releaseProjection`; its `returnSpring` now carries the cancel as well
  as the sideways return, and `dismissThreshold` is 0.70.
* Match the zoom transition to iOS, measured against a native
  `NavigationStack` zoom (parity stage 3): the flight is one critically
  damped spring at ω 19 rad/s for push and pop, the card casts the native
  soft shadow (σ 18 pt at 24 %, 4 pt down), the covered page dims linearly
  to 15 % black, and the source's copy cross-fades over the first 55 % of
  the flight. Flights prepare before their first frame when pushed or
  popped from outside a build.
* Match the back swipe to iOS, measured against a native `NavigationStack`
  (parity stage 2): the page waits out a 12 pt dead zone from the touch
  before following the finger, a release commits when the page's position
  plus its velocity over the next 120 ms passes 53 % of the width — so a short
  flick pops and a page pulled back slowly past the midpoint still does —
  and both the pop and the spring back land on one spring
  (`BackGestureController.releaseSpring`, ω 22, ζ 0.85) that covers 98 % of
  its distance in about 210 ms whatever the distance, instead of the SDK's
  350 ms curve.
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
* Match the push transition to iOS, measured frame by frame against a
  native `NavigationStack`: the arriving page's remaining distance decays
  exponentially (`SwiftCurves.push`, a 61 ms time constant over a 400 ms
  transition) with the pop the same decay in reverse, the covered page
  travels 0.30 of the width on the same curve so the two move in lockstep
  and track the finger together, and it is dimmed by the transition at
  0.10 × progress. `SwiftPageRoute` has no barrier colour; a covered
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
