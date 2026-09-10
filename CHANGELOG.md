## 0.1.0-dev

* Tune every transition and gesture in this release against a native
  SwiftUI reference app, recorded and measured the same way on the same
  device (iPhone 17 simulator, iOS 27.0 build 24A5408d), in the nine
  stages of `docs/parity-plan.md`. The push, the back swipe and the zoom
  flight follow native's curves to 1–6 pt RMS; a held card's scale is
  within 0.006 of native's in every gesture, the release outcomes agree
  on the commit tables, and landings from rest agree within a frame.
  What is knowingly different, with the size of each difference, is
  listed in `docs/design.md` section 1.7, and every calibrated constant
  is in section 1.6 with the recording it came from.
* Estimate the back swipe's release velocity the way iOS does, with
  `IOSScrollViewFlingVelocityTracker` (parity stage 2). Flutter's default
  tracker read a 1200 pt/s fling as 497, so a flick that natively pops
  sprang back instead; all nine scripted swipes now agree with native.
  The zoom dismissal's pan and edge swipe read the same way, which also
  takes an edge swipe flung at 800 pt/s from a 168 ms landing to 147
  against native's 100.
* Fade the zoom card's shadow out as it reaches its source (parity
  stage 9). A native card lands with no shadow at all — the page 12 and
  20 pt beside it reads its own colour from a twentieth of the flight in
  — where ours kept a full one to the end and lost it the frame the route
  popped.
* Keep a release's momentum when the recognizer's own tracker throws it
  away. That tracker calls a finger still once 40 ms of wall clock have
  passed since the last move it saw, which one dropped frame under a
  heavy dismissal is enough to do, and the card then landed as if it had
  been let go at rest. The zoom's pan and edge swipe and the page back
  swipe fall back to the finger as the pointer stream saw it, which is
  how the pinch has always read its own.
* Block the page under a zoom route from taking touches until the pop has
  finished. Natively a landing card passes them through and the source
  takes the tap; here a half-finished dismissal cannot open something
  else (`docs/design.md` section 1.7).
* Scale the page under a zoom route down as the card grows over it, which
  iOS does and the package did not (parity stage 9): 0.914 at full screen,
  straight with the flight and about the screen's centre, held still while
  a gesture drags the card, and home on its own spring afterwards, which
  finishes after the card lands rather than with it.
* Carry a flung card's motion into its landing (parity stage 9). Natively
  a card released travelling keeps going its own way before it turns for
  the source — 28 pt past the line an edge swipe flung at 800 pt/s takes,
  38 at 1200 — where ours ran straight home. `ZoomDeparture` carries the
  release's velocity and the route runs it as a decaying offset on the
  landing spring, on both axes — a drag recognizer reports only its own,
  so the gesture layer tracks the finger itself for the other.
* Draw the landing's overshoot, which iOS has and the SDK clipped
  (parity stage 9): `AnimationController` clamps a simulation to the
  controller's bounds, so the part of the landing spring that carries the
  card past the source never reached the screen. The route reads the
  spring's own value while the controller is pinned at zero, and the card
  goes 2 % of the flight past the source and eases back into it over
  200 ms, against native's 1.9–2.3 % from rest.
* Match the zoom route's landing speed to iOS, measured against a native
  `NavigationStack` zoom (parity stage 9): a landing shortens with the
  speed the fingers themselves were moving when they let go — 170–217 ms
  at 400 pt/s a finger against 200–245 from rest, 100–133 at 800 — and
  not with the shrink that speed was driving, so `ZoomDismissPhysics`
  gains `landingQuickening` and `landingSpringFor`, which raise the
  landing spring's frequency with the release speed and leave its damping
  alone. A pan still lands in a rest release's time however hard it was
  flung. A second finger landing on a card already held by a pan no
  longer moves the point the pan measures its travel from, which jerked
  the card back to full screen when that finger left without a pinch
  beginning.
* Match the zoom route's landing to iOS, measured against a native
  `NavigationStack` zoom (parity stage 8): a committed release lands on
  its own spring, `ZoomDismissPhysics.landingSpring` (ω 15, ζ 0.75 —
  98 % of the way in 230–270 ms with a 3 % overshoot), not the push's,
  seeded with the release rate over what the landing has left for a
  pinch or an edge swipe and not at all for a pan, which natively lands
  from rest however it was flung; `commitVelocityFor` takes the rate and
  the remaining scale, and `maxCommitVelocity` is 20. The card's corners,
  measured through the flight, already run straight from the source's
  radius to the display's. A held card is let go of when the window's
  size changes, as iOS lets go when the device turns. Under Reduce
  Motion the zoom cross-fades over 140 ms, as the native page does. The
  example's poster page keeps its bar opaque at the top of the scroll,
  as SwiftUI's is.
* Match the zoom route's response to a touch in flight to iOS, measured
  against a native `NavigationStack` zoom (parity stage 7): a finger on a
  flying card no longer stops it — the pan begins as it leaves its dead
  zone, the pinch as it leaves its own — and a pan begun during the push,
  or during the return of a cancelled dismissal, takes the card as it
  flies: the flight completes underneath the gesture, as the native card
  kept growing under a drag and then read as the pan's scale of the full
  screen. A landing card is not grabbed: a committed release pops the
  route at once and lands on the pop's own transition, the popping route
  passes its pointers by, and the hidden `ZoomTransitionSource` still
  takes them, so a tap on its spot during the landing pushes again. The
  pan's and edge swipe's travel is read in global coordinates, which a
  card in flight had scaled.
* Match the zoom route's pinch to iOS, measured against a native
  `NavigationStack` zoom (parity stage 6): the card holds its size until
  the fingers' distance has changed by half the platform's slop (8.7 pt
  natively), then scales 1:1 with the distance from there, turns 1:1
  with the fingers' angle — a turn alone does nothing — and follows their
  focal point, chasing all three through the tracking spring as the
  native card does, and a release lands below half the size wherever the
  fingers were headed (0.515 at rest sprang back, 0.494 landed; fast
  releases went by the fingers' distance, not the card's lagging scale).
  A scroll view winning the first finger's arena no longer ends the pinch
  as it begins. `ZoomDismissPhysics` gains `pinchDismissThreshold`;
  `dismissThreshold` is the edge swipe's alone.
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
* Make the zoom route's cancelled release interruptible: a card springing
  back can be grabbed and dragged again, and the navigator sees one
  gesture from the first grab to the settle. A dismissal begun from rest
  looks the source up again, so a paging page that changes `sourceTag`
  lands on the poster it is showing.
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
