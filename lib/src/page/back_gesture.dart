import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Where a [SwiftBackGestureDetector] starts its interactive back swipe.
enum BackGestureRegion {
  /// The SDK's own region: the leading 20pt, or the device's leading safe
  /// area inset if it is larger.
  leadingEdge,

  /// A horizontal drag starting anywhere on the page, as in iOS 26.
  ///
  /// Only a drag whose first movement runs toward the trailing edge starts
  /// the swipe; a drag that opens the other way is left unclaimed after
  /// that first frame. This does not resolve the gesture arena against
  /// another full-width horizontal recognizer (a nested `PageView`, say) —
  /// it only stops the swipe from visibly starting in the wrong direction.
  anywhere,
}

const double _kBackGestureWidth = 20.0;

/// `UIScrollView.DecelerationRate.normal`: how a release coasts on iOS.
const double _kDecelerationRate = 0.998;
const Duration _kDroppedSwipePageAnimationDuration = Duration(
  milliseconds: 350,
);

/// A controller for an iOS-style back gesture, ported from the SDK's
/// private `_CupertinoBackGestureController` (`cupertino/route.dart`) so
/// [SwiftPageRoute] gets the same drag-to-progress and release semantics.
///
/// Works entirely in logical coordinates: 0.0 is the new page dismissed,
/// 1.0 is the new page on top.
class BackGestureController<T> {
  /// Creates a controller for an iOS-style back gesture, and tells
  /// [navigator] that a user gesture has started.
  BackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsActive,
    required this.getIsCurrent,
  }) {
    navigator.didStartUserGesture();
  }

  /// The route's own animation controller, scrubbed directly by the drag.
  final AnimationController controller;

  /// The navigator the gesture was started on.
  final NavigatorState navigator;

  /// Whether the route is still in the history, even if not current.
  final ValueGetter<bool> getIsActive;

  /// Whether the route is still the topmost route.
  final ValueGetter<bool> getIsCurrent;

  /// Scrubs the controller by [delta], a fraction of the drag axis.
  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  /// Where a release at [velocity] (screen widths per second) would coast
  /// to, in screen widths, at the iOS scroll deceleration: the projection
  /// from "Designing Fluid Interfaces" (WWDC 2018),
  /// `velocity × rate / (1 − rate)` with velocity per millisecond.
  static double projectedTravel(double velocity) =>
      velocity / 1000 * _kDecelerationRate / (1 - _kDecelerationRate);

  /// Ends the gesture with a release [velocity] (a fraction of the drag axis
  /// per second, positive toward the pop), committing or cancelling it.
  ///
  /// The pop commits if the page, coasting from where it is at the release
  /// velocity, would pass the midpoint. The SDK's rule — commit past the
  /// midpoint, or at a fling of a full screen width per second in either
  /// direction — leaves a short flick springing back and lets a page that
  /// is being pulled back past the midpoint pop anyway; a projection
  /// handles both, and is the rule iOS uses for coasting releases. Its
  /// calibration against the native pop is parity-plan stage 2.
  void dragEnd(double velocity) {
    const animationCurve = Curves.fastEaseInToSlowEaseOut;
    final isCurrent = getIsCurrent();
    final bool animateForward;

    if (!isCurrent) {
      // Already navigated away from (e.g. a programmatic pop mid-drag): the
      // outcome no longer depends on velocity or position.
      animateForward = getIsActive();
    } else {
      final travelled = 1 - controller.value;
      animateForward = travelled + projectedTravel(velocity) < 0.5;
    }

    if (animateForward) {
      controller.animateTo(
        1,
        duration: _kDroppedSwipePageAnimationDuration,
        curve: animationCurve,
      );
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      // The pop above may have finished the controller inline.
      if (controller.isAnimating) {
        controller.animateBack(
          0,
          duration: _kDroppedSwipePageAnimationDuration,
          curve: animationCurve,
        );
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener onStatusChanged;
      onStatusChanged = (status) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(onStatusChanged);
      };
      controller.addStatusListener(onStatusChanged);
    } else {
      navigator.didStopUserGesture();
    }
  }
}

/// Installs the interactive back swipe over [child], in the given [region].
class SwiftBackGestureDetector<T> extends StatefulWidget {
  /// Creates a back-swipe detector.
  const SwiftBackGestureDetector({
    super.key,
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.region,
    required this.child,
  });

  /// The page below the gesture layer.
  final Widget child;

  /// Whether the gesture is currently allowed to start.
  final ValueGetter<bool> enabledCallback;

  /// Called on the first pointer down inside the active region; the
  /// returned controller receives the rest of the gesture.
  final ValueGetter<BackGestureController<T>> onStartPopGesture;

  /// Where the drag may start.
  final BackGestureRegion region;

  @override
  State<SwiftBackGestureDetector<T>> createState() =>
      _SwiftBackGestureDetectorState<T>();
}

class _SwiftBackGestureDetectorState<T>
    extends State<SwiftBackGestureDetector<T>> {
  BackGestureController<T>? _backGestureController;

  // In BackGestureRegion.anywhere, the pop only starts once the first drag
  // delta is known to run toward the trailing edge, so a drag that opens
  // the wrong way never touches the navigator's user-gesture state at all.
  bool _awaitingDirection = false;

  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    if (_backGestureController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_backGestureController?.navigator.mounted ?? false) {
          _backGestureController?.navigator.didStopUserGesture();
        }
        _backGestureController = null;
      });
    }
    super.dispose();
  }

  void _handleDragStart(DragStartDetails details) {
    if (widget.region == BackGestureRegion.anywhere) {
      _awaitingDirection = true;
    } else {
      _backGestureController = widget.onStartPopGesture();
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = _convertToLogical(
      details.primaryDelta! / context.size!.width,
    );
    if (_awaitingDirection) {
      _awaitingDirection = false;
      if (delta <= 0) {
        return;
      }
      _backGestureController = widget.onStartPopGesture();
    }
    _backGestureController?.dragUpdate(delta);
  }

  void _handleDragEnd(DragEndDetails details) {
    _awaitingDirection = false;
    final controller = _backGestureController;
    _backGestureController = null;
    controller?.dragEnd(
      _convertToLogical(
        details.velocity.pixelsPerSecond.dx / context.size!.width,
      ),
    );
  }

  void _handleDragCancel() {
    _awaitingDirection = false;
    final controller = _backGestureController;
    _backGestureController = null;
    controller?.dragEnd(0);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (widget.enabledCallback()) {
      _recognizer.addPointer(event);
    }
  }

  double _convertToLogical(double value) =>
      switch (Directionality.of(context)) {
        TextDirection.rtl => -value,
        TextDirection.ltr => value,
      };

  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      'SwiftBackGestureDetector needs a Directionality',
    );
    final gestureLayer = switch (widget.region) {
      BackGestureRegion.leadingEdge => _leadingEdgeGestureLayer(context),
      BackGestureRegion.anywhere => Positioned.fill(
        child: Listener(
          onPointerDown: _handlePointerDown,
          behavior: HitTestBehavior.translucent,
        ),
      ),
    };
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[widget.child, gestureLayer],
    );
  }

  Widget _leadingEdgeGestureLayer(BuildContext context) {
    // For devices with notches, the drag area needs to be larger on the
    // side that has the notch.
    final dragAreaWidth = switch (Directionality.of(context)) {
      TextDirection.rtl => MediaQuery.paddingOf(context).right,
      TextDirection.ltr => MediaQuery.paddingOf(context).left,
    };
    return PositionedDirectional(
      start: 0,
      width: math.max(dragAreaWidth, _kBackGestureWidth),
      top: 0,
      bottom: 0,
      child: Listener(
        onPointerDown: _handlePointerDown,
        behavior: HitTestBehavior.translucent,
      ),
    );
  }
}
