import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'zoom_dismiss_physics.dart';
import 'zoom_frame.dart';

/// The gesture driving an interactive zoom dismissal.
enum ZoomGesture {
  /// A downward drag on the page.
  pan,

  /// A drag from the leading edge.
  edgeSwipe,

  /// A two-finger pinch.
  pinch,
}

/// What [ZoomTransitionOptions.interactiveDismissShouldBegin] is asked with.
@immutable
class ZoomInteractionContext {
  /// Creates the context of a dismissal about to begin.
  const ZoomInteractionContext({
    required this.gesture,
    required this.location,
    this.primaryScrollMetrics,
  });

  /// The gesture that would dismiss.
  final ZoomGesture gesture;

  /// Where on the page it started, in the page's coordinates.
  final Offset location;

  /// The page's primary scroll view at that moment, if it has one attached
  /// to the route's scroll controller.
  final ScrollMetrics? primaryScrollMetrics;
}

/// Decides whether an interactive dismissal may begin.
typedef ZoomInteractiveDismissPredicate =
    bool Function(ZoomInteractionContext context);

/// The frame and progress a released or interrupted card departs from, so
/// the landing (or the return to full screen) flies from where the card
/// actually is rather than from the flight line.
@immutable
class ZoomDeparture {
  /// Creates a departure.
  const ZoomDeparture({
    required this.frame,
    required this.progress,
    required this.toSource,
  });

  /// The card's frame at release.
  final ZoomFrame frame;

  /// The route animation's value at release.
  final double progress;

  /// Whether the card is flying to the source (a committed dismissal) or
  /// back to full screen (a cancelled one, or an interrupted push resuming).
  final bool toSource;
}

/// Drives one interactive dismissal from grab to settle: turns drag deltas
/// and pointer positions into a [ZoomFrame] and a route progress each frame,
/// and on release decides between committing and cancelling, seeding the
/// spring either way with the release velocity.
///
/// The counterpart of the push route's `BackGestureController`: it is
/// created when a gesture begins (telling the navigator so), scrubs the
/// route's own animation controller, and tells the navigator the gesture
/// has stopped only once the settle animation completes.
///
/// The response is [ZoomDismissPhysics] applied to the card as it was when
/// grabbed ([restingFrame]), which is the full screen for a settled page and
/// the mid-flight card for an interrupted push. Progress scales with the
/// card: a card at 0.75 of its grabbed size reports 0.75 of the grabbed
/// progress.
class ZoomDismissController {
  /// Creates a controller for a dismissal that has just begun, and tells
  /// [navigator] that a user gesture has started.
  ZoomDismissController({
    required this.navigator,
    required this.controller,
    required this.physics,
    required this.gesture,
    required this.restingFrame,
    required this.screen,
    required this.sourceRadii,
    required this.screenRadii,
    required this.grabPoint,
    required this.liveFrame,
    required this.getIsActive,
    required this.getIsCurrent,
    required this.onRelease,
    required this.onSettled,
    required this.settleSpring,
    required TickerProvider vsync,
  }) : restingProgress = controller.isCompleted ? 1 : controller.value,
       _anchor = grabPoint,
       _pointer = grabPoint {
    _ticker = vsync.createTicker(_tick);
    controller.stop();
    navigator.didStartUserGesture();
  }

  /// The navigator the gesture was started on.
  final NavigatorState navigator;

  /// The route's own animation controller, scrubbed by the gesture.
  final AnimationController controller;

  /// The dismissal's response.
  final ZoomDismissPhysics physics;

  /// Which gesture is driving.
  final ZoomGesture gesture;

  /// The card as it was when grabbed.
  final ZoomFrame restingFrame;

  /// The route animation's value when grabbed.
  final double restingProgress;

  /// The navigator's bounds.
  final Rect screen;

  /// The source's corner radii, or null without a source.
  final BorderRadius? sourceRadii;

  /// The display's corner radii.
  final BorderRadius screenRadii;

  /// Where the finger went down, in navigator coordinates.
  final Offset grabPoint;

  /// Where the frame under the finger is published each update.
  final ValueNotifier<ZoomFrame?> liveFrame;

  /// Whether the route is still in the history.
  final ValueGetter<bool> getIsActive;

  /// Whether the route is still the topmost route.
  final ValueGetter<bool> getIsCurrent;

  /// Called at release with where the card is departing from and, for a
  /// commit, the progress velocity to seed the landing with. The pop itself
  /// follows this call, so the route's simulation can read the seed.
  final void Function(ZoomDeparture departure, double velocity) onRelease;

  /// Called once the settle animation completes.
  final VoidCallback onSettled;

  /// The spring a cancelled dismissal returns to full screen on.
  final SpringDescription settleSpring;

  late final Ticker _ticker;
  final Offset _anchor;
  double _travelPixels = 0;
  Offset _pointer;
  Offset? _pointerAtOpen;
  double _horizontalRaw = 0;
  double _horizontalOffset = 0;
  double _horizontalVelocity = 0;
  double _horizontalTarget = 0;
  SpringDescription? _horizontalSpring;
  Duration _lastTick = Duration.zero;
  bool _released = false;

  /// The card's current scale relative to [restingFrame].
  double get scale => physics.scaleFor(_travel);

  /// Whether the card has been dragged away from where it was grabbed.
  bool get isDragged => _travelPixels > 0;

  /// Travel in card heights (or widths, for the edge swipe).
  double get _travel => switch (gesture) {
    ZoomGesture.pan ||
    ZoomGesture.pinch => _travelPixels / restingFrame.rect.height,
    ZoomGesture.edgeSwipe => _travelPixels / restingFrame.rect.width,
  };

  /// Feeds the gesture's primary-axis movement: downward pixels for a pan,
  /// pixels toward the trailing edge for an edge swipe.
  void dragUpdate(double delta) {
    if (_released) {
      return;
    }
    _travelPixels += delta;
    _publish();
  }

  /// Feeds the finger's position in navigator coordinates, for the pivot
  /// and the sideways chase.
  void pointerMoved(Offset position) {
    if (_released) {
      return;
    }
    _pointer = position;
    _trackHorizontal();
    _publish();
  }

  /// Ends the gesture with the primary axis's release [velocity] in pixels
  /// per second, positive away from the identity state.
  void dragEnd(double velocity) {
    if (_released) {
      return;
    }
    _released = true;
    final bool commit;
    if (!getIsCurrent()) {
      commit = !getIsActive();
    } else if (velocity.abs() >= physics.flingVelocity) {
      commit = velocity > 0;
    } else {
      commit = scale < physics.dismissThreshold;
    }
    final departure = ZoomDeparture(
      frame: _frame(),
      progress: controller.value,
      toSource: commit,
    );
    liveFrame.value = null;
    _retargetHorizontal(0, physics.returnSpring);
    final cardExtent = switch (gesture) {
      ZoomGesture.pan || ZoomGesture.pinch => restingFrame.rect.height,
      ZoomGesture.edgeSwipe => restingFrame.rect.width,
    };
    final seed =
        physics.commitVelocityFor(
          velocity: commit ? velocity : -velocity,
          cardHeight: cardExtent,
        ) *
        restingProgress;
    onRelease(departure, seed);
    if (commit) {
      if (getIsCurrent()) {
        navigator.pop();
      }
    } else {
      controller.animateWith(
        SpringSimulation(settleSpring, controller.value, 1, seed),
      );
    }
    if (controller.isAnimating) {
      late AnimationStatusListener onStatusChanged;
      onStatusChanged = (status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          controller.removeStatusListener(onStatusChanged);
          _settle();
        }
      };
      controller.addStatusListener(onStatusChanged);
    } else {
      _settle();
    }
  }

  void _settle() {
    if (navigator.mounted) {
      navigator.didStopUserGesture();
    }
    onSettled();
  }

  /// Releases the ticker. Called by whoever created the controller when the
  /// page is torn down mid-gesture; a released controller has already handed
  /// the animation back to the route.
  void dispose() {
    _ticker.dispose();
  }

  ZoomFrame _frame() {
    final rest = restingFrame.rect;
    final scale = this.scale;
    final Rect rect;
    switch (gesture) {
      case ZoomGesture.pan:
      case ZoomGesture.pinch:
        rect = physics.dismissedRect(
          restingRect: rest,
          travel: _travel,
          horizontalOffset: _horizontalOffset,
          anchor: _anchor,
        );
      case ZoomGesture.edgeSwipe:
        // The edge swipe shrinks like the pan but the card then follows the
        // finger freely, pivoting on the grabbed point.
        final delta = _pointer - _anchor;
        final pivot = _anchor;
        final scaled = Rect.fromLTRB(
          pivot.dx + (rest.left - pivot.dx) * scale,
          pivot.dy + (rest.top - pivot.dy) * scale,
          pivot.dx + (rest.right - pivot.dx) * scale,
          pivot.dy + (rest.bottom - pivot.dy) * scale,
        );
        rect = scaled.shift(Offset(_horizontalOffset, delta.dy));
    }
    final progress = restingProgress * scale;
    // Radii interpolate in the card's own space and scale with the card, so
    // a card at 0.57 shows roughly the 13–17 pt measured natively.
    final radii =
        BorderRadius.lerp(sourceRadii ?? screenRadii, screenRadii, progress)! *
        scale;
    return ZoomFrame(rect: rect, rotation: 0, radii: radii, sourceOpacity: 0);
  }

  void _publish() {
    controller.value = restingProgress * scale;
    liveFrame.value = _frame();
  }

  /// Opens the sideways axis once the drag is [kTouchSlop] under way and
  /// chases the damped finger offset through the tracking spring.
  void _trackHorizontal() {
    final open = switch (gesture) {
      ZoomGesture.pan || ZoomGesture.pinch => _travelPixels > kTouchSlop,
      ZoomGesture.edgeSwipe => true,
    };
    if (!open) {
      if (_pointerAtOpen != null) {
        _pointerAtOpen = null;
        _horizontalRaw = 0;
        _retargetHorizontal(0, physics.returnSpring);
      }
      return;
    }
    // Anchored when the axis opens, not at pointer down, so sideways wander
    // on the way here does not snap in.
    final origin = _pointerAtOpen ??= _pointer;
    _horizontalRaw = _pointer.dx - origin.dx;
    final cardRect = physics.dismissedRect(
      restingRect: restingFrame.rect,
      travel: _travel,
      anchor: _anchor,
    );
    _retargetHorizontal(
      physics.horizontalOffsetFor(
        rawOffset: _horizontalRaw,
        cardRect: cardRect,
        screenWidth: screen.width,
      ),
      physics.trackingSpring,
    );
  }

  /// Points the chase at [target] without disturbing its position or
  /// velocity: the spring only changes its mind about where it is going.
  void _retargetHorizontal(double target, SpringDescription spring) {
    _horizontalTarget = target;
    _horizontalSpring = spring;
    if (_ticker.isActive) {
      return;
    }
    if ((_horizontalOffset - target).abs() < 0.01 &&
        _horizontalVelocity.abs() < 0.01) {
      return;
    }
    _lastTick = Duration.zero;
    _ticker.start();
  }

  /// One closed-form spring step per frame toward wherever the target is
  /// now. Integrated by hand because `animateWith` restarts its clock on
  /// every retarget, which would freeze the chase under a moving finger.
  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    if (dt > 0) {
      final simulation = SpringSimulation(
        _horizontalSpring!,
        _horizontalOffset,
        _horizontalTarget,
        _horizontalVelocity,
      );
      _horizontalOffset = simulation.x(dt);
      _horizontalVelocity = simulation.dx(dt);
    }
    if ((_horizontalOffset - _horizontalTarget).abs() < 0.01 &&
        _horizontalVelocity.abs() < 0.5) {
      _horizontalOffset = _horizontalTarget;
      _horizontalVelocity = 0;
      _ticker.stop();
    }
    if (!_released) {
      liveFrame.value = _frame();
    }
  }
}
