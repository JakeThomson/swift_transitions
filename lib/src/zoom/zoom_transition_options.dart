import 'package:flutter/widgets.dart';

import 'zoom_dismiss_physics.dart';
import 'zoom_interaction.dart';

/// Options for a zoom route, mirroring `UIZoomTransitionOptions`.
@immutable
class ZoomTransitionOptions {
  /// Creates zoom transition options.
  const ZoomTransitionOptions({
    this.dismissGestures = ZoomDismissGestures.all,
    this.interactiveDismissShouldBegin,
    this.dismissPhysics = ZoomDismissPhysics.ios26,
    this.dimmingColor = const Color(0x33000000),
    this.dimmingBlurSigma = 0.0,
    this.alignmentRect,
    this.pushSpring = kZoomPushSpring,
    this.snapshotDuringTransition = false,
  });

  /// Which gestures may dismiss the route interactively.
  final ZoomDismissGestures dismissGestures;

  /// Asked before an interactive dismissal begins, the counterpart of
  /// `UIZoomTransitionOptions.interactiveDismissShouldBegin`. Returning
  /// false leaves the gesture to the page. Null allows every dismissal.
  final ZoomInteractiveDismissPredicate? interactiveDismissShouldBegin;

  /// The fitted response of the interactive dismissal.
  final ZoomDismissPhysics dismissPhysics;

  /// The colour the covered page is dimmed with at the end of the push.
  ///
  /// The dim eases in with the flight and tracks an interactive dismissal.
  /// It is painted as the route's modal barrier, so a transparent colour
  /// leaves the covered page undimmed but still shielded from pointers.
  final Color dimmingColor;

  /// The blur applied to the covered page under the dim, the counterpart of
  /// `UIZoomTransitionOptions.dimmingVisualEffect`. Zero for no blur.
  final double dimmingBlurSigma;

  /// The part of the page that aligns with the source during a flight, the
  /// counterpart of `UIZoomTransitionOptions.alignmentRectProvider`.
  ///
  /// Asked when a flight starts, on the push and again on each pop. The
  /// rect is in the page's coordinates; the card grows out of the source
  /// showing that part of the page, and shrinks back onto it. Null, or a
  /// null result, aligns the whole page to the source: the page fills the
  /// card, anchored at its top centre.
  final ZoomAlignmentRectProvider? alignmentRect;

  /// The spring that drives the push and the non-interactive pop.
  final SpringDescription pushSpring;

  /// Whether the page is painted from a snapshot while it flies, the way
  /// Material's zoom transition does. A page whose paint is expensive —
  /// backdrop filters, shaders — is then rasterised once per flight rather
  /// than every frame. Pages containing platform views fall back to live
  /// painting. Off by default.
  final bool snapshotDuringTransition;

  @override
  bool operator ==(Object other) =>
      other is ZoomTransitionOptions &&
      other.dismissGestures == dismissGestures &&
      other.interactiveDismissShouldBegin == interactiveDismissShouldBegin &&
      other.dismissPhysics == dismissPhysics &&
      other.dimmingColor == dimmingColor &&
      other.dimmingBlurSigma == dimmingBlurSigma &&
      other.alignmentRect == alignmentRect &&
      other.pushSpring == pushSpring &&
      other.snapshotDuringTransition == snapshotDuringTransition;

  @override
  int get hashCode => Object.hash(
    dismissGestures,
    interactiveDismissShouldBegin,
    dismissPhysics,
    dimmingColor,
    dimmingBlurSigma,
    alignmentRect,
    pushSpring,
    snapshotDuringTransition,
  );
}

/// Which way a zoom flight is going.
enum ZoomFlightDirection {
  /// Out of the source to the full screen.
  push,

  /// Back into the source.
  pop,
}

/// What [ZoomTransitionOptions.alignmentRect] is asked with.
@immutable
class ZoomAlignmentRectContext {
  /// Creates the context of a flight about to start.
  const ZoomAlignmentRectContext({
    required this.sourceRect,
    required this.pageSize,
    required this.direction,
  });

  /// The source's bounds, in the navigator's coordinates.
  final Rect sourceRect;

  /// The size the page is laid out at.
  final Size pageSize;

  /// Which way the flight is going.
  final ZoomFlightDirection direction;
}

/// Chooses the part of the page that aligns with the source.
typedef ZoomAlignmentRectProvider =
    Rect? Function(ZoomAlignmentRectContext context);

/// The default zoom flight spring: [SpringDescription.withDurationAndBounce]
/// for 500 ms with no bounce, written out because that constructor is not
/// const. Calibration against the 60 fps push strip is pending; see
/// design.md section 3.9.
const SpringDescription kZoomPushSpring = SpringDescription(
  mass: 1,
  stiffness: 157.91367041742973, // (2π / 0.5 s)²
  damping: 25.132741228718345, // 4π / 0.5 s
);

/// Which gestures may dismiss a zoom route interactively.
@immutable
class ZoomDismissGestures {
  /// Creates a set of dismissal gestures.
  const ZoomDismissGestures({
    this.pan = true,
    this.edgeSwipe = true,
    this.pinch = true,
  });

  /// Every gesture.
  static const ZoomDismissGestures all = ZoomDismissGestures();

  /// No interactive dismissal; the route pops only programmatically.
  static const ZoomDismissGestures none = ZoomDismissGestures(
    pan: false,
    edgeSwipe: false,
    pinch: false,
  );

  /// A downward drag anywhere on the page, or on a vertical scroll view
  /// once it reaches its top edge.
  final bool pan;

  /// A drag from the leading edge, as the push transition's back swipe.
  final bool edgeSwipe;

  /// A two-finger pinch, which scales the card with the fingers' distance,
  /// rotates it with their angle and moves it with their focal point.
  final bool pinch;

  @override
  bool operator ==(Object other) =>
      other is ZoomDismissGestures &&
      other.pan == pan &&
      other.edgeSwipe == edgeSwipe &&
      other.pinch == pinch;

  @override
  int get hashCode => Object.hash(pan, edgeSwipe, pinch);
}
