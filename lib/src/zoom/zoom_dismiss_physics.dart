import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The fitted response of an interactive zoom dismissal: how far a drag
/// shrinks the card, how the card follows the finger sideways, and what a
/// release hands to the landing spring. One value object, so the numbers
/// that were measured together stay together.
///
/// The pan defaults are the iOS 26 fit from liquid_glass_widgets'
/// swipe-dismiss morph (`SheetMorphGeometry`, PR #223 and its follow-up),
/// measured against a cursor-tracked native capture to an RMS scale error
/// of 0.006, ported here by the same author. Travel is measured in *card
/// heights* — for a zoomed page the card is the page — because one
/// card-relative gain explained panels of different heights in that fit.
/// See design.md section 3.4, including the open question of what iOS
/// treats as the card height for a full-screen page. The edge swipe's
/// numbers and the return spring are from the parity rig (parity-plan.md,
/// stage 5): scripted edge drags on a full-screen page, iOS 27.0.
@immutable
class ZoomDismissPhysics {
  /// Creates a dismissal response. The defaults are [ios26].
  const ZoomDismissPhysics({
    this.scaleGain = 0.67,
    this.travelKnee = 0.48,
    this.minimumScale = 0.33,
    this.edgeGive = 0.04,
    this.edgeSwipeVerticalGain = 0.43,
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
    this.dismissThreshold = 0.70,
    this.flingVelocity = 700,
    this.releaseProjection = 0.12,
    this.maxCommitVelocity = 10,
  });

  /// The iOS 26 fit.
  static const ZoomDismissPhysics ios26 = ZoomDismissPhysics();

  /// Scale lost per card height of damped travel (per card width for the
  /// edge swipe). Below 1.0 the fall always outruns the shrink, which is
  /// what keeps the card's bottom edge from lifting into view when the
  /// shrink pivots on the grabbed point. Native edge drags to 16 %, 36 % and
  /// 56 % of the width lost 0.634–0.678 per width past the dead zone; 0.67
  /// puts every held scale within 0.006 of native's.
  final double scaleGain;

  /// Card heights of 1:1 travel before the fall starts easing. Up to here
  /// every ordinary drag is pure direct manipulation.
  final double travelKnee;

  /// The scale the eased travel asymptotes toward and never reaches, so a
  /// long drag parks the card but it never quite stops shrinking.
  final double minimumScale;

  /// How far past a screen edge the card may be pushed, as a fraction of the
  /// screen width — the largest native overshoot measured, about 4 pt on a
  /// 440 pt screen.
  final double edgeGive;

  /// The spring the card chases the finger's sideways offset through while
  /// the finger drives it: stiff and critically damped (ω ≈ 45), so a fast
  /// sweep visibly trails and a slow drag reads as 1:1.
  final SpringDescription trackingSpring;

  /// The spring a cancelled release returns the card to full screen on, and
  /// the sideways offset home. ω 22, ζ 0.9: the native return from 10 %,
  /// 24 % and 36 % of a page's width fits it to 0.5–1.1 pt, 98 % of the way
  /// back in 230 ms, and it is the back swipe's release spring too.
  final SpringDescription returnSpring;

  /// How far the card moves for each point the finger moves down (or up)
  /// during an edge swipe, once it is off the edge: the card trails the
  /// finger rather than riding it. Natively a 200 pt drop moved the card
  /// 86 pt, at the same ratio throughout.
  final double edgeSwipeVerticalGain;

  /// The card scale below which a release dismisses. Native edge swipes
  /// released at rest at 0.715 sprang back and at 0.678 landed (parity
  /// stage 5); the pan shares the value until stage 4 measures its own.
  final double dismissThreshold;

  /// The release speed, in logical pixels per second away from the identity
  /// state, that dismisses a pan regardless of the card's scale.
  final double flingVelocity;

  /// How far ahead an edge swipe's release is projected, in seconds: it
  /// commits if the card, carried on at the release velocity for this long,
  /// would shrink past [dismissThreshold]. The back swipe's 120 ms window;
  /// natively a release at 0.80 moving at 800 pt/s landed, one at rest at
  /// 0.76 sprang back, and a 14 pt flick at 1200 pt/s sprang back, which a
  /// speed threshold alone cannot give.
  final double releaseProjection;

  /// The most a fling may seed the landing spring with, in progress units
  /// per second — about four times the resting landing's own start.
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

  /// The travel the card renders at for the finger's [travel], both in card
  /// heights: 1:1 up to [travelKnee], then rubber-banded toward
  /// [maximumTravel] so a long drag parks the card instead of sliding it off
  /// the screen. The shrink and the fall both read this, so they settle as
  /// one object.
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

  /// The card's uniform scale after [travel] card widths of edge swipe:
  /// linear in the travel with no knee — native drags shrink at one rate to
  /// at least 0.56 of the width, and a finger cannot travel far enough to
  /// reach [minimumScale] — measured past the recognizer's dead zone.
  double edgeSwipeScaleFor(double travel) =>
      math.max(minimumScale, 1 - scaleGain * math.max(0, travel));

  /// The sideways offset the chase is targeted with for the finger's
  /// [rawOffset]: free until the card's leading edge meets the screen's,
  /// then pinned there with [edgeGive]. Resistance is a function of where
  /// the card is, not of finger displacement, so pushing toward open room is
  /// free for the whole distance and pushing into an edge resists at once.
  double horizontalOffsetFor({
    required double rawOffset,
    required Rect cardRect,
    required double screenWidth,
  }) {
    final slack = rawOffset.isNegative
        ? math.max(0.0, cardRect.left)
        : math.max(0.0, screenWidth - cardRect.right);
    final magnitude = rawOffset.abs();
    if (magnitude <= slack) {
      return rawOffset;
    }
    final damped =
        slack + rubberBand(magnitude - slack, limit: screenWidth * edgeGive);
    return rawOffset.isNegative ? -damped : damped;
  }

  /// The card's frame after [travel] card heights of drag: [restingRect]
  /// carried down by the damped fall and shrunk about the pivot, then
  /// shifted by [horizontalOffset].
  ///
  /// [anchor] is the grabbed point in the resting card's frame. Carried down
  /// with the fall it keeps the grabbed content exactly under the finger
  /// below the knee, the direct-manipulation feel of the native gesture.
  /// Without it the card shrinks about its own centre. The bottom edge is
  /// clamped to its resting line, an invariant [scaleGain] below 1.0 already
  /// guarantees; the clamp guards it against a future retune.
  Rect dismissedRect({
    required Rect restingRect,
    required double travel,
    double horizontalOffset = 0.0,
    Offset? anchor,
  }) {
    final fall = Offset(0, dampedTravel(travel) * restingRect.height);
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

  /// What a release at [velocity] logical pixels per second (positive away
  /// from the identity state) seeds the landing spring with, in progress
  /// units per second toward the source: the rate the shrink was running
  /// at, [scaleGain] per card height, capped at [maxCommitVelocity]. Zero for
  /// a release that was not shrinking, so the landing starts from rest.
  double commitVelocityFor({
    required double velocity,
    required double cardHeight,
  }) {
    if (cardHeight <= 0 || velocity <= 0) {
      return 0;
    }
    return math.min(maxCommitVelocity, scaleGain * velocity / cardHeight);
  }

  @override
  bool operator ==(Object other) =>
      other is ZoomDismissPhysics &&
      other.scaleGain == scaleGain &&
      other.travelKnee == travelKnee &&
      other.minimumScale == minimumScale &&
      other.edgeGive == edgeGive &&
      other.edgeSwipeVerticalGain == edgeSwipeVerticalGain &&
      other.trackingSpring == trackingSpring &&
      other.returnSpring == returnSpring &&
      other.dismissThreshold == dismissThreshold &&
      other.flingVelocity == flingVelocity &&
      other.releaseProjection == releaseProjection &&
      other.maxCommitVelocity == maxCommitVelocity;

  @override
  int get hashCode => Object.hash(
    scaleGain,
    travelKnee,
    minimumScale,
    edgeGive,
    edgeSwipeVerticalGain,
    trackingSpring,
    returnSpring,
    dismissThreshold,
    flingVelocity,
    releaseProjection,
    maxCommitVelocity,
  );
}
