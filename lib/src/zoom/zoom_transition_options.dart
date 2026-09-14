import 'package:flutter/widgets.dart';

import '../page/back_gesture.dart';
import 'zoom_dismiss_physics.dart';
import 'zoom_interaction.dart';

/// Options for a zoom route, mirroring `UIZoomTransitionOptions`.
@immutable
class ZoomTransitionOptions {
  /// Creates zoom transition options.
  const ZoomTransitionOptions({
    this.dismissGestures = ZoomDismissGestures.all,
    this.backGestureRegion = BackGestureRegion.anywhere,
    this.interactiveDismissShouldBegin,
    this.dismissPhysics = ZoomDismissPhysics.ios26,
    this.dimmingColor = const Color(0x26000000),
    this.dimmingBlurSigma = 0.0,
    this.alignmentRect,
    this.pushSpring = kZoomPushSpring,
    this.snapshotDuringTransition = false,
  });

  /// Which gestures may dismiss the route interactively.
  final ZoomDismissGestures dismissGestures;

  /// Where the back swipe may start, when [ZoomDismissGestures.backSwipe]
  /// allows it: the leading edge, or anywhere on the page as on iOS 26.
  final BackGestureRegion backGestureRegion;

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
  /// Asked once the page is laid out, on the push and again on each pop.
  /// The rect is in the page's coordinates; the card grows out of the
  /// source showing that part of the page, and shrinks back onto it. Null,
  /// or a null result, aligns the whole page to the source: the page fills
  /// the card, anchored at its top centre.
  ///
  /// A source is a preview of its page, and this is how the page says
  /// where the preview is. Without it a page whose top does not look like
  /// the source — the art lower down, under a title — reads as a double
  /// exposure while the card is on its way, the source's picture over the
  /// scaled page, as it does natively. Returning the art's own rect, from
  /// [ZoomAlignmentRectContext.rectOf], is the fix UIKit prescribes.
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
      other.backGestureRegion == backGestureRegion &&
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
    backGestureRegion,
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

/// What [ZoomTransitionOptions.alignmentRect] is asked with, the
/// counterpart of `UIZoomTransitionAlignmentRectContext`.
@immutable
class ZoomAlignmentRectContext {
  /// Creates the context of a flight about to start.
  const ZoomAlignmentRectContext({
    required this.sourceRect,
    required this.pageSize,
    required this.direction,
    required this.pageContext,
  });

  /// The source's bounds, in the navigator's coordinates.
  final Rect sourceRect;

  /// The size the page is laid out at.
  final Size pageSize;

  /// Which way the flight is going.
  final ZoomFlightDirection direction;

  /// The page, laid out, as `zoomedViewController` is natively: what a
  /// provider measures its art in ([rectOf]), or reads which item the page
  /// is showing from.
  final BuildContext pageContext;

  /// The bounds of the widget at [context], in the page's coordinates —
  /// the rect to return for the art the source is a preview of. Null if
  /// either is not laid out.
  Rect? rectOf(BuildContext context) {
    final box = context.findRenderObject();
    final page = pageContext.findRenderObject();
    if (box is! RenderBox ||
        page is! RenderBox ||
        !box.hasSize ||
        !page.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(page),
      Offset.zero & box.size,
    );
  }
}

/// Chooses the part of the page that aligns with the source.
typedef ZoomAlignmentRectProvider =
    Rect? Function(ZoomAlignmentRectContext context);

/// The default zoom flight spring: critically damped, ω = 19 rad/s (a
/// 52 ms time constant), written out because
/// [SpringDescription.withDurationAndBounce] is not const. Fitted to the
/// card's width on a native `NavigationStack` zoom, push and pop alike, to
/// 4–6 pt RMS of 282 pt of travel (parity stage 3, iOS 27.0 simulator);
/// a pure exponential misses by three times that, so the flight does have
/// a short ease-in.
const SpringDescription kZoomPushSpring = SpringDescription(
  mass: 1,
  stiffness: 361, // ω²
  damping: 38, // 2ω
);

/// Which gestures may dismiss a zoom route interactively.
@immutable
class ZoomDismissGestures {
  /// Creates a set of dismissal gestures.
  const ZoomDismissGestures({
    this.pan = true,
    this.backSwipe = true,
    this.pinch = true,
  });

  /// Every gesture.
  static const ZoomDismissGestures all = ZoomDismissGestures();

  /// No interactive dismissal; the route pops only programmatically.
  static const ZoomDismissGestures none = ZoomDismissGestures(
    pan: false,
    backSwipe: false,
    pinch: false,
  );

  /// A downward drag anywhere on the page, or on a vertical scroll view
  /// once it reaches its top edge.
  final bool pan;

  /// The back swipe, as the push transition's: a drag from the leading
  /// edge, or from anywhere on the page
  /// ([ZoomTransitionOptions.backGestureRegion]).
  final bool backSwipe;

  /// A two-finger pinch, which scales the card with the fingers' distance,
  /// rotates it with their angle and moves it with their focal point.
  final bool pinch;

  @override
  bool operator ==(Object other) =>
      other is ZoomDismissGestures &&
      other.pan == pan &&
      other.backSwipe == backSwipe &&
      other.pinch == pinch;

  @override
  int get hashCode => Object.hash(pan, backSwipe, pinch);
}
