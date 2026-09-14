## 0.2.0

* The back swipe starts anywhere on the page by default, on the push and
  the zoom route alike, as it does on iOS 26 — where it had been written off
  as having no native equivalent, and the example's "anywhere" row never
  turned it on. Measured against native from a quarter, a half and three
  quarters of the way across: the push page waits out 27 pt and then follows
  the finger, and a release commits from 42 % of the width where the edge
  swipe's line is 53 %; the zoom card shrinks about the touch at the edge
  swipe's rate after 18 pt and lands from a scale of 0.79 where the edge
  swipe's is 0.70. A swipe begun on the leading edge is still the edge swipe,
  with its own numbers, and still wins over a horizontal scrollable under it;
  one begun anywhere else yields to the scrollable, so a `PageView` keeps
  paging — including, unlike native, at its first page.
* `ZoomDismissGestures.edgeSwipe` and `ZoomGesture.edgeSwipe` are
  `backSwipe`, `ZoomTransitionOptions` takes a `backGestureRegion`, and
  `ZoomDismissPhysics.dismissThreshold` is `edgeSwipeDismissThreshold` beside
  a new `anywhereSwipeDismissThreshold`.

## 0.1.2

* A zoom's flight meets its source where the source rests. The source was
  measured in the overlay and read back through the covered page's scale as
  the route's animation implied it, and the two disagree whenever the page
  was drawn for another frame than the one being prepared — under a first
  frame slower than the push, a router's deferred preparation found the push
  complete while the page had been built at its start — so the card met a
  rect 9 % too big and toward the screen's edges, the page cover-fitted into
  it showing around a source that does not stretch, and snapped onto the
  source when the route left. It is now measured in the page's own
  coordinates, which the scale never touches; a route underneath that
  declines the transition, and so takes no scale, lands right too.
* A pop's cross-fade comes in from the start of the flight, as native's
  does — solid from about a third of the way, with most of the flight still
  to go — and a landing's over the first part of the landing. It ran over
  the last part of the flight, the push's window mirrored, which a page that
  is its own poster hides and a page that leads with anything else shows as a
  double exposure: the page through the poster until the card had all but
  landed. Measured on a film page, which the example now has: a poster row
  whose pages lead with a backdrop, another picture at another size.

## 0.1.1

* An aligned zoom flies the way UIKit's does with an `alignmentRectProvider`,
  measured against it: behind the ordinary card the page scales as one
  picture so the art lands on the source, its position a beat behind its
  scale, fading out with the flight while the source's picture comes in
  over the art. It was a window on the page that closed in on the art
  while the page stayed near full size.
* `ZoomAlignmentRectContext` carries the page, laid out, as
  `UIZoomTransitionAlignmentRectContext` carries its `zoomedViewController`:
  `pageContext`, and `rectOf` for a widget's bounds in the page's
  coordinates, so a provider measures the art it aligns to through a key
  rather than guessing a rect. It is asked once the page is laid out; a push
  from a tap handler asks at the end of its first frame, which the cross-fade
  draws as the source anyway. The example's still row shows the pattern.
* `ZoomTransitionSource`: a source that is not being painted no longer takes
  part in a flight — one on a non-selected `IndexedStack` tab, under a
  `Visibility` that is not visible, or under a `HeroMode` that is not
  enabled. A page that keeps its tabs mounted and shows the same item on two
  of them tripped the duplicate-tag assertion, and in profile and release
  flew to whichever source the tree walk reached last: the offstage one,
  leaving the visible tile in place and landing the card beside it.

## 0.1.0

First release. iOS's navigation transitions for Flutter, fitted against a
native SwiftUI reference app driven through the same scripted gestures on the
same device (iPhone 17 simulator, iOS 27.0) and tracked frame by frame. Every
calibrated constant is in `docs/design.md` section 1.6 with the recording it
came from, the deviations that remain are in section 1.7, and the method is in
`docs/parity-plan.md`.

### The zoom transition

* `ZoomPageRoute`, `ZoomPage` and `ZoomTransitionSource`: the iOS 18 zoom
  transition. A page grows out of the source tagged with its `sourceTag` and
  shrinks back into it, cross-fading with the source's content over the first
  55 % of the flight and morphing from the source's corner radius to the
  display's. The source is hidden behind a placeholder of its own size while
  the route is up. `sourceTag` is read again on each pop, so a paging page
  lands on the item it is showing. A missing source falls back to a centred
  scale-and-fade, and Reduce Motion to a 140 ms cross-fade.
* The flight is one critically damped spring at ω 19 rad/s for both push and
  pop, the card casts the native soft shadow (σ 18 pt at 24 %, 4 pt down) and
  fades it out as it reaches its source, the covered page dims linearly to
  15 % black and scales to 0.914 over a backdrop of the ambient scaffold
  background, and the landing carries 2 % past the source before easing back
  in over 200 ms.
* `ZoomTransitionOptions`, mirroring `UIZoomTransitionOptions`: `dimmingColor`
  and `dimmingBlurSigma`, `dismissGestures`, `interactiveDismissShouldBegin`,
  `dismissPhysics`, `alignmentRect` (the counterpart of
  `alignmentRectProvider`, asked on the push and again on each pop) and
  `snapshotDuringTransition`, a Material-style snapshot of the page while it
  flies.
* `ZoomRouteTransitionMixin` for custom routes, and for pages that set the
  enclosing route's `sourceTag`.

### Interactive dismissal

* A downward pan anywhere on the page, a swipe from the leading edge, or a
  two-finger pinch shrinks the page into a card that tracks the fingers. A
  release past the threshold lands it on its source and an early release
  springs it back, both on the landing spring (ω 15, ζ 0.75), quickened by how
  fast the fingers were moving when they let go and carrying the release's
  momentum on both axes before it turns for the source.
* The pan shrinks at 0.67 per screen height about the touch point to a knee at
  0.52, falls behind the finger by the cube of the travel, and follows it
  sideways at 0.56 rubber-banded toward 0.9 of the width. The edge swipe
  shrinks at 0.67 per screen width, follows the finger 1:1 sideways and at
  0.43 vertically, and commits on where 120 ms of its velocity would carry the
  card. The pinch holds until the fingers' distance has moved half the
  platform's slop, then scales, turns and moves with them 1:1, and commits on
  where the fingers were headed rather than on the card's lagging scale.
* Vertical scroll views take part through the `ZoomScrollController` the route
  installs as the page's `PrimaryScrollController`: a drag at the top edge
  becomes a dismissal, and one begun on a scrolled list scrolls to the top and
  over-scrolls there instead, as the native page does.
* Everything is interruptible. A card in flight can be caught by a pan or a
  pinch and the flight completes underneath the gesture; a cancelled
  dismissal's return can be grabbed again; and the navigator sees one gesture
  from the first touch to the settle. A landing card is not grabbed — the
  route pops at once and the source takes the tap, so a tap on its spot
  pushes again.
* `ZoomDismissPhysics` carries the fitted response, `ZoomDismissPhysics.ios26`
  by default, with every constant documented and overridable.

### The push transition

* `SwiftPageRoute`, `SwiftPage` and `SwiftPageTransitionsBuilder`: the iOS
  push, with the arriving page's remaining distance decaying exponentially
  (`SwiftCurves.push`, a 61 ms time constant over 400 ms), the covered page
  travelling 0.30 of the width on the same curve and dimmed at 0.10 ×
  progress, and the moving page clipped to the display's own corner radius
  with the leading-edge shadow cast from the clipped shape — the page
  receding underneath keeps square corners, as native's does. A covered
  `CupertinoPageRoute` or Material route gets the same motion and dim through
  `SwiftPageTransition.delegatedTransition`.
* `SwiftPageTransitionMixin` for custom routes, and `SwiftPageTransition` for
  the transition widget on its own.
* `BackGestureRegion` chooses where the back swipe may start: the SDK's
  leading edge, or anywhere on the page as in iOS 26. The page waits out a
  12 pt dead zone, a release commits when its position plus 120 ms of its
  velocity passes 53 % of the width, and both outcomes land on one spring
  (ω 22, ζ 0.85) that covers 98 % of its distance in about 210 ms whatever
  the distance, instead of the SDK's 350 ms curve.

### Supporting API

* `DisplayCornerRadii`, resolving the physical display corner radius from an
  override, `MediaQuery`, or the iOS device table.
* `SwiftCurves.push` and `SwiftSprings.standard`, the measured curve and the
  SDK's Cupertino modal spring, usable on their own.
* Releases are read with `IOSScrollViewFlingVelocityTracker`, the way iOS
  reads them: Flutter's default tracker measures a 1200 pt/s fling as 497, so
  a flick that natively pops would spring back instead.
