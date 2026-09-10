import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The fitted response of an interactive zoom dismissal: how far a drag
/// shrinks the card, how the card follows the finger sideways, and what a
/// release hands to the landing spring. One value object, so the numbers
/// that were measured together stay together.
///
/// The numbers are from the parity rig (parity-plan.md, stages 4–6):
/// scripted drags and pinches on a full-screen zoom page against a native
/// `NavigationStack` zoom, iOS 27.0, with touch rings. The pan's shape —
/// linear shrink to a knee, then iOS's rubber band toward a floor, the
/// shrink pivoting on the grabbed point — is the iOS 26 fit from
/// liquid_glass_widgets' swipe-dismiss morph (`SheetMorphGeometry`, PR
/// #223) by the same author; the parity pass measured its constants for a
/// page and found the fall eases ahead of the shrink. Travel is measured
/// in *card heights* — for a zoomed page the card is the page — the
/// normaliser that fit sheets of different heights and, here, the page.
@immutable
class ZoomDismissPhysics {
  /// Creates a dismissal response. The defaults are [ios26].
  const ZoomDismissPhysics({
    this.scaleGain = 0.67,
    this.travelKnee = 0.52,
    this.minimumScale = 0.37,
    this.fallLag = 0.45,
    this.crossAxisGain = 0.56,
    this.crossAxisLimit = 0.9,
    this.trackingSpring = const SpringDescription(
      mass: 1,
      stiffness: 2000,
      damping: 89,
    ),
    this.returnSpring = const SpringDescription(
      mass: 1,
      stiffness: 484,
      damping: 39.6,
    ),
    this.landingSpring = const SpringDescription(
      mass: 1,
      stiffness: 225,
      damping: 22.5,
    ),
    this.landingQuickening = 0.3,
    this.maxLandingSpeed = 3,
    this.panDismissThreshold = 0.905,
    this.dismissThreshold = 0.70,
    this.pinchDismissThreshold = 0.5,
    this.releaseProjection = 0.12,
    this.maxCommitVelocity = 20,
  });

  /// The iOS 26 fit.
  static const ZoomDismissPhysics ios26 = ZoomDismissPhysics();

  /// Scale lost per card height of damped travel (per card width for the
  /// edge swipe). Native pans past the recognizer's slop lost 0.65–0.68 per
  /// screen height to the knee, and edge drags 0.634–0.678 per width; 0.67
  /// puts every held scale within 0.006 of native's on both.
  final double scaleGain;

  /// Card heights of linear travel before the shrink starts easing: the
  /// native scale is linear to 0.49 of the height (0.693) and 0.545 at 0.8
  /// after the knee, which with [minimumScale] fits to 0.002 RMS.
  final double travelKnee;

  /// The scale the eased travel asymptotes toward and never reaches, so a
  /// long drag parks the card but it never quite stops shrinking. A finger
  /// cannot travel far enough to see the floor itself; 0.37 is what the
  /// curve past the knee implies.
  final double minimumScale;

  /// How far the grabbed point falls behind the finger, in card heights per
  /// cubed card height of travel: nothing to speak of for the first third
  /// of the height, then quickly more — 0.89 of the finger's travel at half
  /// the height, 0.73 at 0.8. Native pans held at 15–80 % of the height
  /// put the page's top within 4 pt of it (a rubber band on the travel is
  /// 8 pt out at 30 % and 20 at 80 %); the edge swipe does not fall.
  final double fallLag;

  /// The spring the card chases the fingers through while they drive it —
  /// a pan's sideways offset, and a pinch's scale, turn and focal point:
  /// stiff and critically damped (ω ≈ 45), so a fast sweep visibly trails
  /// and a slow drag reads as 1:1. Native pinches at 300 pt/s a finger
  /// trailed the fingers' distance by 0.06 of the scale and settled two or
  /// three frames after they stopped, which ω 45 fits to 0.01 RMS.
  final SpringDescription trackingSpring;

  /// The spring a cancelled release returns the card to full screen on, and
  /// the sideways offset home. ω 22, ζ 0.9: the native return from 10 %,
  /// 24 % and 36 % of a page's width fits it to 0.5–1.1 pt, 98 % of the way
  /// back in 230 ms, and it is the back swipe's release spring too.
  final SpringDescription returnSpring;

  /// The spring a committed release lands on the source with, whichever
  /// gesture released it. ω 15, ζ 0.75: native pans released at rest from
  /// 0.55–0.90 of the screen fit it to 0.4–2.9 pt on the card's edge, 98 %
  /// of the way in 230–270 ms, and overshoot the source by 3 % of the way
  /// before easing onto it over the next 300 ms — slower and looser than
  /// the push's spring (parity stage 8). Edge swipes and pinches land on
  /// it too, from rest within 2.3 pt; released moving they land sooner and
  /// firmer, which is the seed's doing ([commitVelocityFor],
  /// [landingSpringFor]).
  final SpringDescription landingSpring;

  /// How much of [landingSpring]'s frequency a landing gains for each
  /// resting card width per second a finger was moving when it let go.
  /// Native landings shorten with the fingers' own speed rather than with
  /// the shrink they were driving, and by the same amount in either
  /// gesture: 165–245 ms released at rest, 170–217 at 400 pt/s a finger,
  /// 100 (edge swipe) to 117–133 (pinch) at 800 and 103–108 at 1200,
  /// where those speeds mean quite different shrink rates and landing
  /// distances (parity stages 5, 6 and 9). At 0.3 the landing sits inside
  /// that spread everywhere but the edge swipe flung at 800, which
  /// natively lands 36 ms sooner than any one line through the rest can
  /// give. A pan hands nothing over: flung at 150–800 pt/s it lands in
  /// the 233–272 ms of a release at rest.
  final double landingQuickening;

  /// The speed past which a release no longer shortens the landing, in
  /// resting card widths per second. Native landings stop coming down
  /// somewhere under 1200 pt/s a finger — 100–133 ms at 800 and 103–108 at
  /// 1200, no further — where an uncapped quickening would take a flick
  /// thrown at 3000 pt/s down to 60 ms, which reads as the card
  /// disappearing rather than landing (parity stage 9).
  final double maxLandingSpeed;

  /// How far the card moves for each point the finger moves across the
  /// gesture's axis — sideways during a pan, up or down during an edge
  /// swipe once it is off the edge — at first: the card trails the finger
  /// rather than riding it, freely, off the screen included, and the
  /// further it goes the more it trails ([crossAxisLimit]). Natively a
  /// held card moved 26 pt for a 50 pt sweep, 49 for 100, 69 for 150 and
  /// 85 for 195, either way and without touching the scale; a 200 pt drop
  /// during an edge swipe moved it 86 pt and a 240 pt one 99.
  final double crossAxisGain;

  /// What the cross-axis follow is rubber-banded toward, as a fraction of
  /// the resting card's width: the same 364 pt band on a 402 pt page fits
  /// the pan's sideways points and the edge swipe's vertical ones to 1 pt.
  final double crossAxisLimit;

  /// The card scale below which a pan's release dismisses, read from where
  /// [releaseProjection] carries it. Native pans released at rest at 0.914
  /// sprang back and at 0.900 landed — a sixth of the height, far shorter
  /// than the edge swipe's boundary.
  final double panDismissThreshold;

  /// The card scale below which an edge swipe's release dismisses. Native
  /// edge swipes released at rest at 0.715 sprang back and at 0.678 landed
  /// (parity stage 5).
  final double dismissThreshold;

  /// The card scale below which a pinch's release dismisses: half its size,
  /// with no projection — native pinches released at rest at 0.515 sprang
  /// back and at 0.494 landed, and ones released with the fingers still
  /// closing fast went by where the card was, not where they were headed
  /// (parity stage 6).
  final double pinchDismissThreshold;

  /// How far ahead a release is projected, in seconds: it commits if the
  /// card, carried on at the release velocity for this long, would shrink
  /// past its threshold. The back swipe's 120 ms window; natively an edge
  /// swipe released at 0.80 moving at 800 pt/s landed, one at rest at 0.76
  /// sprang back, and a 14 pt flick at 1200 pt/s sprang back, which a
  /// speed threshold alone cannot give. A pan released at 0.765 moving
  /// *up* at 800 pt/s still landed, as the projection says.
  final double releaseProjection;

  /// The most a release may seed the landing with, in units of what the
  /// landing has left per second: enough for the card to carry on at the
  /// rate the fingers left it at. It was 8 while the landing's overshoot
  /// was clipped, where any more read as the card stopping dead early;
  /// with the overshoot drawn a fast pinch lands in native's own 117 ms
  /// (parity stage 9) and the cap binds only on the fastest releases.
  final double maxCommitVelocity;

  /// The damped travel the scale floor implies, in card heights.
  double get maximumTravel => (1 - minimumScale) / scaleGain;

  /// iOS's rubber-band curve: direct at first, asymptotically stiffer, and
  /// never past [limit]. `f(x) = (1 − 1/(x·tension/limit + 1))·limit`, the
  /// platform's over-scroll shape; [tension] is the slope at the origin.
  static double rubberBand(
    double offset, {
    required double limit,
    double tension = 1.0,
  }) {
    if (limit <= 0) {
      return 0;
    }
    final magnitude = offset.abs();
    final damped = (1 - 1 / (magnitude * tension / limit + 1)) * limit;
    return offset.isNegative ? -damped : damped;
  }

  /// The travel the card shrinks by for the finger's [travel], both in card
  /// heights: 1:1 up to [travelKnee], then rubber-banded toward
  /// [maximumTravel] so a long drag parks the card instead of sliding it off
  /// the screen.
  double dampedTravel(double travel) {
    final raw = travel.clamp(0.0, maximumTravel * 4);
    if (raw <= travelKnee) {
      return raw;
    }
    return travelKnee +
        rubberBand(raw - travelKnee, limit: maximumTravel - travelKnee);
  }

  /// The card's uniform scale after [travel] card heights of drag: linear in
  /// [dampedTravel], so all the easing lives in the travel and there is one
  /// curve to reason about.
  double scaleFor(double travel) => 1 - scaleGain * dampedTravel(travel);

  /// How far the grabbed point has fallen after [travel] card heights of
  /// drag, in card heights: the travel less [fallLag] times its cube, so
  /// the content under the finger slips behind it imperceptibly at first
  /// and by a fifth of the height near the bottom of the screen. Held where
  /// the lag would start to outgrow the travel, past any finger's reach.
  double fallFor(double travel) {
    final t = math.max(0.0, travel).clamp(0.0, 1 / math.sqrt(3 * fallLag));
    return t - fallLag * t * t * t;
  }

  /// How far the card follows the finger across the gesture's axis for the
  /// finger's [offset] from where the axis opened, on a card [width] wide:
  /// [crossAxisGain] of it at first, iOS's rubber band toward
  /// [crossAxisLimit] of the width from there.
  double crossAxisOffsetFor(double offset, {required double width}) =>
      rubberBand(offset, limit: width * crossAxisLimit, tension: crossAxisGain);

  /// How fast the card follows a finger crossing the gesture's axis, for
  /// the finger's [offset] from where the axis opened: the slope of
  /// [crossAxisOffsetFor], [crossAxisGain] at the origin and easing off as
  /// the card nears [crossAxisLimit] of its [width]. A release carries the
  /// card's own motion, not the finger's ([ZoomDeparture.velocity]).
  double crossAxisFollowFor(double offset, {required double width}) {
    final limit = width * crossAxisLimit;
    if (limit <= 0) {
      return 0;
    }
    final band = offset.abs() * crossAxisGain / limit + 1;
    return crossAxisGain / (band * band);
  }

  /// The card's uniform scale after [travel] card widths of edge swipe:
  /// linear in the travel with no knee — native drags shrink at one rate to
  /// at least 0.56 of the width, and a finger cannot travel far enough to
  /// reach [minimumScale] — measured past the recognizer's dead zone.
  double edgeSwipeScaleFor(double travel) =>
      math.max(minimumScale, 1 - scaleGain * math.max(0, travel));

  /// The card's frame after [travel] card heights of drag: [restingRect]
  /// carried down by [fallFor] and shrunk about the pivot, then shifted by
  /// [horizontalOffset].
  ///
  /// [anchor] is the grabbed point in the resting card's frame. Carried down
  /// with the fall it keeps the grabbed content just behind the finger, the
  /// direct-manipulation feel of the native gesture. Without it the card
  /// shrinks about its own centre. The bottom edge is clamped to its
  /// resting line, an invariant [scaleGain] below 1.0 already guarantees;
  /// the clamp guards it against a future retune.
  Rect dismissedRect({
    required Rect restingRect,
    required double travel,
    double horizontalOffset = 0.0,
    Offset? anchor,
  }) {
    final fall = Offset(0, fallFor(travel) * restingRect.height);
    final fallen = restingRect.shift(fall);
    final scale = scaleFor(travel);
    final pivot = anchor == null ? fallen.center : anchor + fall;
    final scaled = Rect.fromLTRB(
      pivot.dx + (fallen.left - pivot.dx) * scale,
      pivot.dy + (fallen.top - pivot.dy) * scale,
      pivot.dx + (fallen.right - pivot.dx) * scale,
      pivot.dy + (fallen.bottom - pivot.dy) * scale,
    );
    final lift = restingRect.bottom - scaled.bottom;
    final grounded = lift > 0 ? scaled.shift(Offset(0, lift)) : scaled;
    return grounded.shift(Offset(horizontalOffset, 0));
  }

  /// What a release shrinking the card at [rate] of its resting size per
  /// second seeds the landing with, in units of what the landing has left
  /// per second: the rate over the [remainingScale] it has to cover,
  /// capped at [maxCommitVelocity]. Zero for a release that was not
  /// shrinking, so the landing starts from rest. Native pinches released
  /// with the fingers still closing landed in 133 ms at 800 pt/s a finger
  /// and an edge swipe flung at 1200 in 103 ms, where rest releases took
  /// 200–270 ms, both fitting the fingers' rate over what was left; pans
  /// hand nothing over (parity stages 8 and 9).
  double commitVelocityFor({
    required double rate,
    required double remainingScale,
  }) {
    if (remainingScale <= 0 || rate <= 0) {
      return 0;
    }
    return math.min(maxCommitVelocity, rate / remainingScale);
  }

  /// [landingSpring] quickened for a release at [speed] resting card
  /// widths per second, per [landingQuickening]: the same damping, so a
  /// quick landing overshoots the source by the same 3 % a slow one does.
  /// A release at rest lands on the spring itself.
  SpringDescription landingSpringFor(double speed) {
    if (speed <= 0) {
      return landingSpring;
    }
    final quicker =
        1 + landingQuickening * math.min(speed, maxLandingSpeed);
    return SpringDescription(
      mass: landingSpring.mass,
      stiffness: landingSpring.stiffness * quicker * quicker,
      damping: landingSpring.damping * quicker,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ZoomDismissPhysics &&
      other.scaleGain == scaleGain &&
      other.travelKnee == travelKnee &&
      other.minimumScale == minimumScale &&
      other.fallLag == fallLag &&
      other.crossAxisGain == crossAxisGain &&
      other.crossAxisLimit == crossAxisLimit &&
      other.trackingSpring == trackingSpring &&
      other.returnSpring == returnSpring &&
      other.landingSpring == landingSpring &&
      other.landingQuickening == landingQuickening &&
      other.panDismissThreshold == panDismissThreshold &&
      other.dismissThreshold == dismissThreshold &&
      other.pinchDismissThreshold == pinchDismissThreshold &&
      other.releaseProjection == releaseProjection &&
      other.maxCommitVelocity == maxCommitVelocity &&
      other.maxLandingSpeed == maxLandingSpeed;

  @override
  int get hashCode => Object.hash(
    scaleGain,
    travelKnee,
    minimumScale,
    fallLag,
    crossAxisGain,
    crossAxisLimit,
    trackingSpring,
    returnSpring,
    landingSpring,
    landingQuickening,
    panDismissThreshold,
    dismissThreshold,
    pinchDismissThreshold,
    releaseProjection,
    maxCommitVelocity,
    maxLandingSpeed,
  );
}
