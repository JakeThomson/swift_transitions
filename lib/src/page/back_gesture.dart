import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
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

/// How far the finger travels from where it went down before the page
/// starts to follow it. Native's page stayed put for the first 12 pt of
/// every swipe and then sat 12 pt behind the finger (parity stage 2, once
/// a two-frame display lag is taken out).
const double _kDeadZone = 12.0;

/// How long a release's velocity is projected over when deciding whether
/// the page has passed the midpoint. From the native commit table (parity
/// stage 2): 16 % at 1200 pt/s popped, 29 % at 400 pt/s sprang back, and
/// 66 % moving back at 500 pt/s still popped — one window of 115–130 ms
/// separates them all; the scroll view's deceleration would be 500 ms.
const double _kReleaseProjection = 0.12;

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

  /// The spring a released page lands on, popping or springing back:
  /// ω = 22 rad/s, ζ = 0.85. Fitted to native releases from seven
  /// positions between 16 % and 76 % of the width (parity stage 2) to
  /// 0.7–6 pt RMS; every one covers 98 % of its distance in 200–220 ms
  /// however far it has to go, so it is one spring rather than a duration.
  static const SpringDescription releaseSpring = SpringDescription(
    mass: 1,
    stiffness: 484, // ω²
    damping: 37.4, // 2ζω
  );

  /// How far a release at [velocity] (screen widths per second) is taken
  /// to carry the page, in screen widths, when deciding the outcome.
  static double projectedTravel(double velocity) =>
      velocity * _kReleaseProjection;

  /// Ends the gesture with a release [velocity] (a fraction of the drag axis
  /// per second, positive toward the pop), committing or cancelling it.
  ///
  /// The pop commits if the page's position plus its projected travel
  /// passes the midpoint, the rule that reproduces the native commit
  /// table. The SDK's — commit past the midpoint, or at a fling of a full
  /// screen width per second either way — sends a short flick springing
  /// back. Either way the page lands on [releaseSpring], seeded with the
  /// release velocity.
  void dragEnd(double velocity) {
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

    // The controller runs from 1 (page on top) down to 0 (popped), so the
    // page's velocity toward the pop is the controller's negative velocity.
    if (animateForward) {
      controller.animateWith(
        SpringSimulation(releaseSpring, controller.value, 1, -velocity),
      );
    } else {
      if (isCurrent) {
        navigator.pop();
      }
      // The pop above may have finished the controller inline.
      if (controller.isAnimating) {
        controller.animateBackWith(
          SpringSimulation(releaseSpring, controller.value, 0, -velocity),
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

  // Travel since the touch went down, in pixels toward the pop; the page
  // follows only the part beyond the dead zone.
  double _dragged = 0;

  late HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      // Deltas from the touch point itself, so the dead zone is measured
      // from there rather than from wherever the drag was recognised.
      ..dragStartBehavior = DragStartBehavior.down
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
    _dragged = 0;
    if (widget.region == BackGestureRegion.anywhere) {
      _awaitingDirection = true;
    } else {
      _backGestureController = widget.onStartPopGesture();
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = _convertToLogical(details.primaryDelta!);
    if (_awaitingDirection) {
      _awaitingDirection = false;
      if (delta <= 0) {
        return;
      }
      _backGestureController = widget.onStartPopGesture();
    }
    final before = math.max(0.0, _dragged - _kDeadZone);
    _dragged += delta;
    final after = math.max(0.0, _dragged - _kDeadZone);
    _backGestureController?.dragUpdate((after - before) / context.size!.width);
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
