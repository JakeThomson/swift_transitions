import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../gestures/release_velocity.dart';

/// Where a [SwiftBackGestureDetector] starts its interactive back swipe.
enum BackGestureRegion {
  /// The SDK's own region: the leading 20pt, or the device's leading safe
  /// area inset if it is larger.
  leadingEdge,

  /// A horizontal drag starting anywhere on the page, as iOS 26's
  /// `interactiveContentPopGestureRecognizer` allows by default — and still
  /// from the leading edge, which keeps its own recognizer.
  ///
  /// Only a drag whose first movement runs toward the trailing edge starts
  /// the swipe; a drag that opens the other way is left unclaimed after
  /// that first frame. A horizontal scrollable on the page (a `PageView`,
  /// say) wins a drag begun over it, as it would natively, since the
  /// swipe's recognizer sits above the page in the tree and so enters the
  /// arena after the page's own; a drag begun on the leading edge is the
  /// edge swipe, with its own dead zone and commit line, and wins over the
  /// scrollable as the SDK's does. Natively the scroll view also yields a
  /// drag it cannot scroll — a pager on its first page — to the pop; here
  /// it over-scrolls instead.
  anywhere,
}

/// The measured differences between the two regions' recognizers on the
/// push's page: the edge region is UIKit's screen-edge recognizer (parity
/// stage 2), the anywhere region its content pop recognizer (stage 10).
/// The zoom page's card answers a swipe with its own dead zone and commit
/// line (`ZoomDismissPhysics`).
extension BackGestureRegionMetrics on BackGestureRegion {
  /// How far the finger travels from where it went down before the page
  /// starts to follow it. Native's page stayed put for the first 12 pt of
  /// an edge swipe and then sat 12 pt behind the finger (once a two-frame
  /// display lag is taken out); from anywhere else it waits 27 pt, and
  /// then sits 27 pt behind.
  double get deadZone => switch (this) {
    BackGestureRegion.leadingEdge => 12.0,
    BackGestureRegion.anywhere => 27.0,
  };

  /// The position, as a fraction of the width, a release must reach.
  /// Native sprang back from 51 % and 52 % at rest and popped from 54 % on
  /// an edge swipe, so that line is a little past the midpoint; from
  /// anywhere it sprang back from 41 % and popped from 43 %, whether the
  /// touch was a quarter or a half of the way across.
  double get releaseThreshold => switch (this) {
    BackGestureRegion.leadingEdge => 0.53,
    BackGestureRegion.anywhere => 0.42,
  };
}

const double _kBackGestureWidth = 20.0;

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
  /// passes [threshold], the region's [BackGestureRegionMetrics.releaseThreshold] —
  /// the rule that reproduces the native commit table. The SDK's — commit
  /// past the midpoint, or at a fling of a full screen width per second
  /// either way — sends a short flick springing back. Either way the page
  /// lands on [releaseSpring], seeded with the release velocity.
  void dragEnd(double velocity, {required double threshold}) {
    final isCurrent = getIsCurrent();
    final bool animateForward;

    if (!isCurrent) {
      // Already navigated away from (e.g. a programmatic pop mid-drag): the
      // outcome no longer depends on velocity or position.
      animateForward = getIsActive();
    } else {
      final travelled = 1 - controller.value;
      animateForward = travelled + projectedTravel(velocity) < threshold;
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

  // Which region the touch went down in, which decides the swipe's dead
  // zone and commit line, and the pointer the recognizer was given so the
  // layer around the page does not hand it the one the edge strip already
  // has.
  BackGestureRegion _touched = BackGestureRegion.leadingEdge;
  int? _pointer;

  late HorizontalDragGestureRecognizer _recognizer;
  final ReleaseVelocity _release = ReleaseVelocity();
  Offset _released = Offset.zero;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      // Deltas from the touch point itself, so the dead zone is measured
      // from there rather than from wherever the drag was recognised.
      ..dragStartBehavior = DragStartBehavior.down
      // iOS's own estimate of the speed a finger left at, which a
      // Scrollable on iOS uses for the same reason: the default
      // least-squares tracker reads a flick at a third to a half of the
      // speed the finger was really moving (parity stage 2).
      ..velocityTrackerBuilder = ((event) =>
          IOSScrollViewFlingVelocityTracker(event.kind))
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
    if (_touched == BackGestureRegion.anywhere) {
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
    final deadZone = _touched.deadZone;
    final before = math.max(0.0, _dragged - deadZone);
    _dragged += delta;
    final after = math.max(0.0, _dragged - deadZone);
    _backGestureController?.dragUpdate((after - before) / context.size!.width);
  }

  void _handleDragEnd(DragEndDetails details) {
    _awaitingDirection = false;
    final controller = _backGestureController;
    _backGestureController = null;
    controller?.dragEnd(
      _convertToLogical(
        _release.reported(details.velocity.pixelsPerSecond.dx, _released.dx) /
            context.size!.width,
      ),
      threshold: _touched.releaseThreshold,
    );
  }

  void _handleDragCancel() {
    _awaitingDirection = false;
    final controller = _backGestureController;
    _backGestureController = null;
    controller?.dragEnd(0, threshold: _touched.releaseThreshold);
  }

  /// The edge strip is hit before the layer around the page, so a touch on
  /// the strip is the edge swipe by the time the layer sees it.
  void _handleEdgePointerDown(PointerDownEvent event) =>
      _handlePointerDown(event, BackGestureRegion.leadingEdge);

  void _handleAnywherePointerDown(PointerDownEvent event) =>
      _handlePointerDown(event, BackGestureRegion.anywhere);

  void _handlePointerDown(PointerDownEvent event, BackGestureRegion region) {
    if (event.pointer == _pointer) {
      return;
    }
    _release.reset();
    _released = Offset.zero;
    if (widget.enabledCallback()) {
      _pointer = event.pointer;
      _touched = region;
      _recognizer.addPointer(event);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) =>
      _release.add(event.timeStamp, event.position);

  /// The finger as the pointer stream saw it, for the releases the
  /// recognizer's own tracker reports as standing still ([ReleaseVelocity]).
  /// The raw up arrives before the recognizer's end.
  void _handlePointerUp(PointerEvent event) {
    _released = _release.at(event.timeStamp);
    if (event.pointer == _pointer) {
      _pointer = null;
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
    // The edge strip lies over the page, as the SDK's does, so it wins
    // over whatever the page puts under it; the layer around the page,
    // which takes the rest of the page in the anywhere region, enters the
    // arena after the page's own recognizers, so a horizontal scrollable
    // on the page takes its drags first.
    return Listener(
      onPointerDown: switch (widget.region) {
        BackGestureRegion.leadingEdge => null,
        BackGestureRegion.anywhere => _handleAnywherePointerDown,
      },
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerUp,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[widget.child, _leadingEdgeGestureLayer(context)],
      ),
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
        onPointerDown: _handleEdgePointerDown,
        behavior: HitTestBehavior.translucent,
      ),
    );
  }
}
