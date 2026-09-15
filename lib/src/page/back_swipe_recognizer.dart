import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'back_gesture.dart';

/// The back swipe's drag recognizer, which yields a drag begun anywhere on
/// the page to whatever the page put under the finger.
///
/// Natively the content pop recognizer defers to every other recognizer on
/// the view it covers, so a scroll view, a card that pans, a slider all take
/// their drags before it. Flutter's arena has no such requirement: it goes
/// to the first recognizer to accept, and a [HorizontalDragGestureRecognizer]
/// accepts at the touch slop, 18 pt, where a `PanGestureRecognizer` or a
/// `ScaleGestureRecognizer` waits for the pan slop, 36 pt. Where in the tree
/// the recognizer sits decides nothing: the page's own recognizers enter the
/// arena first, but a drag that reaches 18 pt is the swipe's before a pan
/// on the page has a say.
///
/// So a swipe from anywhere accepts only past the pan slop, the widest slop
/// a recognizer in the SDK asks for: the page's own recognizers see each
/// move first and, wanting the drag at the same distance or a shorter one,
/// claim it on the same move. And it accepts only a drag that opened toward
/// the trailing edge. One that opened the other way is rejected as soon as
/// its direction is known — rejected, not merely ignored, or it would still
/// have won the arena and taken the finger from the page for the rest of
/// the touch.
///
/// A swipe from the leading edge is the SDK's edge swipe and keeps its
/// recognizer's own slop and either direction: the strip lies over the page
/// and wins over it, as `CupertinoPageRoute`'s does.
///
/// The dead zone is measured from the touch (`DragStartBehavior.down`), so
/// a swipe from anywhere, accepted at 36 pt, moves the page on its first
/// update by however far the finger is past the region's dead zone — 9 pt
/// on the push's page, whose dead zone is 27 — rather than holding still
/// until the finger reaches the slop and then trailing it by 36.
class BackSwipeGestureRecognizer extends HorizontalDragGestureRecognizer {
  /// Creates the back swipe's recognizer.
  BackSwipeGestureRecognizer({
    required this.region,
    required this.textDirection,
    super.debugOwner,
  });

  /// Where the touch the recognizer was given went down.
  final ValueGetter<BackGestureRegion> region;

  /// The page's reading direction, which decides which way is trailing.
  final ValueGetter<TextDirection> textDirection;

  /// Whether the drag has moved far enough from the touch for its direction
  /// to be read, and if so whether it opened toward the trailing edge.
  bool? _openedTrailing;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _openedTrailing = null;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    if (region() == BackGestureRegion.leadingEdge) {
      return super.hasSufficientGlobalDistanceToAccept(
        pointerDeviceKind,
        deviceTouchSlop,
      );
    }
    final towardTrailing = switch (textDirection()) {
      TextDirection.ltr => globalDistanceMoved,
      TextDirection.rtl => -globalDistanceMoved,
    };
    // The direction is read once the finger has clearly moved, at the touch
    // slop, so the first jittery pixel of a swipe does not decide it.
    if (_openedTrailing == null) {
      if (towardTrailing.abs() <=
          computeHitSlop(pointerDeviceKind, gestureSettings)) {
        return false;
      }
      _openedTrailing = towardTrailing > 0;
      if (!_openedTrailing!) {
        resolve(GestureDisposition.rejected);
        return false;
      }
    }
    return _openedTrailing! &&
        towardTrailing > computePanSlop(pointerDeviceKind, gestureSettings);
  }
}
