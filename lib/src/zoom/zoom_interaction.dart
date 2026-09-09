import 'dart:math' as math;

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

/// How far short of full progress a cancelled dismissal's return starts
/// from when the card is already at full progress. See
/// [ZoomDismissController.dragEnd].
const double _kReturnStart = 0.02;

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

/// A flight to full screen — the push, or the return of a cancelled
/// dismissal — that a gesture began during. The card keeps flying under the
/// gesture, as the native card does: a touch never stops it, a pan begun on
/// the way scales the card as it grows, and the release departs from the
/// composed frame (parity stage 7).
@immutable
class ZoomFlight {
  /// Creates a flight from where the route's controller is.
  const ZoomFlight({
    required this.spring,
    required this.velocity,
    required this.frameAt,
  });

  /// The spring the flight is on.
  final SpringDescription spring;

  /// The controller's velocity when grabbed, in progress per second.
  final double velocity;

  /// The card's frame at a route progress.
  final ZoomFrame Function(double progress) frameAt;
}

/// Drives one interactive dismissal from grab to settle: turns drag deltas
/// and pointer positions into a [ZoomFrame] and a route progress each frame,
/// and on release decides between committing and cancelling, seeding the
/// spring either way with the release velocity.
///
/// The counterpart of the push route's `BackGestureController`: it is
/// created when a gesture begins, scrubs the route's own animation
/// controller, and reports through [onSettled] only once the settle
/// animation completes. A committed dismissal pops the route at once
/// through [onCommit], and the landing is the pop's own transition seeded
/// with the release velocity, so the route's hero flights and the covered
/// route's delegated transition run with it; popping later, once landed,
/// would cancel a finger that landed on the way down, which the page
/// underneath is due. The route that creates the controller tells the
/// navigator when the user gesture starts and stops: at the commit for a
/// landing, which cannot be grabbed again, and at the settle for a return,
/// which can, as the same gesture.
///
/// The response is [ZoomDismissPhysics] applied to the card as it was when
/// grabbed ([restingFrame]): the full screen for a settled page, and for a
/// gesture begun during a [flight] the card as it flies, since the flight
/// completes underneath the gesture. Progress scales with the card: a card
/// at 0.75 of its grabbed size reports 0.75 of the grabbed progress.
///
/// A second finger turns any gesture into a pinch ([beginPinch]): from then
/// on the card scales with the fingers' distance, rotates with their angle
/// and moves with their focal point, about the card as it was at that
/// moment.
class ZoomDismissController {
  /// Creates a controller for a dismissal that has just begun and stops the
  /// route's animation where it is.
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
    required this.onCommit,
    required this.onSettled,
    required this.settleSpring,
    required TickerProvider vsync,
    this.flight,
  }) : restingProgress = controller.isCompleted ? 1 : controller.value,
       _anchor = grabPoint,
       _pointer = grabPoint {
    _ticker = vsync.createTicker(_tick);
    final flight = this.flight;
    if (flight != null && !controller.isCompleted) {
      _flightSimulation = SpringSimulation(
        flight.spring,
        controller.value,
        1,
        flight.velocity,
      );
      _ticker.start();
    }
    controller.stop();
  }

  /// The route's navigator, for whoever tears the page down under a live
  /// gesture to check it is still there.
  final NavigatorState navigator;

  /// The route's own animation controller, scrubbed by the gesture.
  final AnimationController controller;

  /// The dismissal's response.
  final ZoomDismissPhysics physics;

  /// Which gesture is driving. A pan or swipe becomes a pinch when a second
  /// finger lands ([beginPinch]).
  ZoomGesture gesture;

  /// The card as it was when grabbed, or when the pinch began.
  ZoomFrame restingFrame;

  /// The route animation's value when grabbed, or when the pinch began.
  double restingProgress;

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

  /// Called at release with where the card is departing from.
  final ValueSetter<ZoomDeparture> onRelease;

  /// Called at a committed release, after [onRelease], with what the
  /// landing spring is seeded with in progress units per second: the route
  /// pops now and lands on the pop's transition.
  final ValueSetter<double> onCommit;

  /// Called once the settle animation completes.
  final VoidCallback onSettled;

  /// The spring a committed dismissal lands on. A cancelled one returns on
  /// [ZoomDismissPhysics.returnSpring].
  final SpringDescription settleSpring;

  /// The flight the gesture began during, or null on a settled page. The
  /// controller flies [restingFrame] on to full screen itself, so the route
  /// has one writer of its progress.
  final ZoomFlight? flight;

  late final Ticker _ticker;
  Simulation? _flightSimulation;
  Duration? _flightStart;
  final Offset _anchor;
  double _travelPixels = 0;
  Offset _pointer;
  Offset? _pointerAtOpen;
  double _horizontalRaw = 0;
  final _Chase _horizontal = _Chase(0, tolerance: 0.01);
  Duration _lastTick = Duration.zero;
  bool _released = false;

  // Pinch state: the fingers' initial distance, angle and focal point, the
  // scale, turn and focal offset the card chases them with, where the
  // fingers are now, and a short history of distances for the release
  // speed.
  double _pinchDistance0 = 1;
  double _pinchAngle0 = 0;
  Offset _pinchFocal0 = Offset.zero;
  final _Chase _pinchScale = _Chase(1, tolerance: 0.0001);
  final _Chase _pinchRotation = _Chase(0, tolerance: 0.0001);
  final _Chase _pinchShiftX = _Chase(0, tolerance: 0.01);
  final _Chase _pinchShiftY = _Chase(0, tolerance: 0.01);
  double _pinchFingersScale = 1;
  final List<(Duration, double)> _pinchSamples = <(Duration, double)>[];

  /// The card's current scale relative to [restingFrame].
  double get scale => switch (gesture) {
    ZoomGesture.pan => physics.scaleFor(_travel),
    ZoomGesture.edgeSwipe => physics.edgeSwipeScaleFor(_travel),
    ZoomGesture.pinch => _pinchScale.value,
  };

  /// Whether the card has been dragged away from where it was grabbed.
  bool get isDragged => _travelPixels > 0;

  /// Travel in card heights (or widths, for the edge swipe).
  double get _travel => switch (gesture) {
    ZoomGesture.pan ||
    ZoomGesture.pinch => _travelPixels / restingFrame.rect.height,
    ZoomGesture.edgeSwipe => _travelPixels / restingFrame.rect.width,
  };

  /// Feeds the gesture's primary-axis movement: downward pixels for a pan,
  /// pixels toward the trailing edge for an edge swipe. Ignored once a pinch
  /// has taken over.
  void dragUpdate(double delta) {
    if (_released || gesture == ZoomGesture.pinch) {
      return;
    }
    _travelPixels += delta;
    // The sideways axis anchors on the move that opens it, which the raw
    // pointer stream has already delivered, rather than on the next one.
    _trackHorizontal();
    _publish();
  }

  /// Feeds the finger's position in navigator coordinates, for the pivot
  /// and the sideways chase. Ignored once a pinch has taken over.
  void pointerMoved(Offset position) {
    if (_released || gesture == ZoomGesture.pinch) {
      return;
    }
    _pointer = position;
    _trackHorizontal();
    _publish();
  }

  /// A second finger has landed at [second] with the first at [first]: the
  /// card as it is right now becomes the resting frame of a pinch.
  void beginPinch(Offset first, Offset second, Duration timeStamp) {
    if (_released) {
      return;
    }
    // The pinch scales a snapshot: a flight underneath stops here.
    _flightSimulation = null;
    restingFrame = _frame();
    restingProgress = controller.value;
    gesture = ZoomGesture.pinch;
    _retarget(_horizontal, 0, physics.returnSpring);
    _pinchDistance0 = math.max(1, (second - first).distance);
    _pinchAngle0 = (second - first).direction;
    _pinchFocal0 = (first + second) / 2;
    _pinchFingersScale = 1;
    for (final chase in [
      _pinchScale,
      _pinchRotation,
      _pinchShiftX,
      _pinchShiftY,
    ]) {
      chase.settle();
    }
    _pinchSamples
      ..clear()
      ..add((timeStamp, _pinchDistance0));
    _publish();
  }

  /// Feeds the two fingers' positions in navigator coordinates. The card
  /// chases their distance, angle and focal point through the tracking
  /// spring: natively it settles a few frames behind them.
  void pinchUpdate(Offset first, Offset second, Duration timeStamp) {
    if (_released || gesture != ZoomGesture.pinch) {
      return;
    }
    final distance = math.max(1.0, (second - first).distance);
    // A card cannot grow past the size it was pinched at.
    _pinchFingersScale = (distance / _pinchDistance0).clamp(
      physics.minimumScale,
      1.0,
    );
    final shift = (first + second) / 2 - _pinchFocal0;
    _retarget(_pinchScale, _pinchFingersScale, physics.trackingSpring);
    _retarget(
      _pinchRotation,
      (second - first).direction - _pinchAngle0,
      physics.trackingSpring,
    );
    _retarget(_pinchShiftX, shift.dx, physics.trackingSpring);
    _retarget(_pinchShiftY, shift.dy, physics.trackingSpring);
    _pinchSamples.add((timeStamp, distance));
    while (_pinchSamples.length > 2 &&
        timeStamp - _pinchSamples[1].$1 > const Duration(milliseconds: 100)) {
      _pinchSamples.removeAt(0);
    }
    _publish();
  }

  /// How fast the fingers are closing, in pixels per second, from the
  /// samples of the last hundred milliseconds. Positive means contracting,
  /// which is away from the identity state.
  double get pinchReleaseVelocity {
    if (_pinchSamples.length < 2) {
      return 0;
    }
    final (t0, d0) = _pinchSamples.first;
    final (t1, d1) = _pinchSamples.last;
    final seconds = (t1 - t0).inMicroseconds / Duration.microsecondsPerSecond;
    if (seconds <= 0) {
      return 0;
    }
    return (d0 - d1) / seconds;
  }

  /// Ends the gesture with the primary axis's release [velocity] in pixels
  /// per second, positive away from the identity state.
  void dragEnd(double velocity) {
    if (_released) {
      return;
    }
    _released = true;
    _flightSimulation = null;
    final bool commit;
    if (!getIsCurrent()) {
      commit = !getIsActive();
    } else {
      // Where the card would be after coasting on the release velocity.
      commit = switch (gesture) {
        ZoomGesture.pan =>
          physics.scaleFor(
                _travel +
                    velocity *
                        physics.releaseProjection /
                        restingFrame.rect.height,
              ) <
              physics.panDismissThreshold,
        ZoomGesture.edgeSwipe =>
          physics.edgeSwipeScaleFor(
                _travel +
                    velocity *
                        physics.releaseProjection /
                        restingFrame.rect.width,
              ) <
              physics.dismissThreshold,
        // Read where the fingers are, not where the card has caught up to.
        ZoomGesture.pinch => _pinchFingersScale < physics.pinchDismissThreshold,
      };
    }
    if (!commit && controller.value > 1 - _kReturnStart) {
      // The return spring on the route's controller is also the clock the
      // card un-rotates and re-centres by, so a card that was only rotated
      // or moved — progress still 1 — starts a hair short of the end.
      controller.value = 1 - _kReturnStart;
    }
    final departure = ZoomDeparture(
      frame: _frame(),
      progress: controller.value,
      toSource: commit,
    );
    liveFrame.value = null;
    _retarget(_horizontal, 0, physics.returnSpring);
    // The rate the shrink was running at, in progress units per second.
    // A pinch's scale is the fingers' distance over their initial distance,
    // so its rate needs no gain.
    final towardTarget = commit ? velocity : -velocity;
    final seed =
        switch (gesture) {
          ZoomGesture.pan => physics.commitVelocityFor(
            velocity: towardTarget,
            cardHeight: restingFrame.rect.height,
          ),
          ZoomGesture.edgeSwipe => physics.commitVelocityFor(
            velocity: towardTarget,
            cardHeight: restingFrame.rect.width,
          ),
          ZoomGesture.pinch =>
            towardTarget <= 0
                ? 0.0
                : math.min(
                    physics.maxCommitVelocity,
                    towardTarget / _pinchDistance0,
                  ),
        } *
        restingProgress;
    onRelease(departure);
    if (commit) {
      onCommit(seed);
    } else {
      controller.animateWith(
        SpringSimulation(physics.returnSpring, controller.value, 1, seed),
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
    var rotation = restingFrame.rotation;
    final Rect rect;
    switch (gesture) {
      case ZoomGesture.pinch:
        // Scaled and rotated about the initial focal point, then carried
        // with the focal point. The layer rotates the card about its own
        // centre, so the centre is placed where rotating about the focal
        // point would put it.
        final pivot = _pinchFocal0;
        final scaledCentre = pivot + (rest.center - pivot) * scale;
        final spun =
            pivot + _rotate(scaledCentre - pivot, _pinchRotation.value);
        final centre = spun + Offset(_pinchShiftX.value, _pinchShiftY.value);
        rect = Rect.fromCenter(
          center: centre,
          width: rest.width * scale,
          height: rest.height * scale,
        );
        rotation += _pinchRotation.value;
      case ZoomGesture.pan:
        rect = physics.dismissedRect(
          restingRect: rest,
          travel: _travel,
          horizontalOffset: _horizontal.value,
          anchor: _anchor,
        );
      case ZoomGesture.edgeSwipe:
        // The edge swipe shrinks the card about the grabbed point and then
        // follows the finger: sideways as far as it goes, off the screen
        // included, and up or down at a fraction of the finger's movement.
        final delta = _pointer - _anchor;
        final pivot = _anchor;
        final scaled = Rect.fromLTRB(
          pivot.dx + (rest.left - pivot.dx) * scale,
          pivot.dy + (rest.top - pivot.dy) * scale,
          pivot.dx + (rest.right - pivot.dx) * scale,
          pivot.dy + (rest.bottom - pivot.dy) * scale,
        );
        rect = scaled.shift(
          Offset(
            _horizontal.value,
            physics.crossAxisOffsetFor(delta.dy, width: rest.width),
          ),
        );
    }
    final progress = restingProgress * scale;
    // Radii interpolate in the card's own space and scale with the card, so
    // a card at 0.57 shows roughly the 13–17 pt measured natively.
    final radii =
        BorderRadius.lerp(sourceRadii ?? screenRadii, screenRadii, progress)! *
        scale;
    return ZoomFrame(
      rect: rect,
      rotation: rotation,
      radii: radii,
      sourceOpacity: 0,
    );
  }

  static Offset _rotate(Offset v, double angle) {
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  void _publish() {
    controller.value = restingProgress * scale;
    liveFrame.value = _frame();
  }

  /// Opens the sideways axis once the drag is under way and chases the
  /// finger offset through the tracking spring: rubber-banded for a pan,
  /// 1:1 for an edge swipe, freely for both — the native card leaves the
  /// screen on either side.
  void _trackHorizontal() {
    final open = switch (gesture) {
      ZoomGesture.pan => _travelPixels > 0,
      ZoomGesture.edgeSwipe => true,
      ZoomGesture.pinch => false,
    };
    if (!open) {
      if (_pointerAtOpen != null) {
        _pointerAtOpen = null;
        _horizontalRaw = 0;
        _retarget(_horizontal, 0, physics.returnSpring);
      }
      return;
    }
    // Anchored when the axis opens, not at pointer down, so sideways wander
    // on the way here does not snap in.
    final origin = _pointerAtOpen ??= _pointer;
    _horizontalRaw = _pointer.dx - origin.dx;
    _retarget(
      _horizontal,
      gesture == ZoomGesture.pan
          ? physics.crossAxisOffsetFor(
              _horizontalRaw,
              width: restingFrame.rect.width,
            )
          : _horizontalRaw,
      physics.trackingSpring,
    );
  }

  /// Every value chasing a target through a spring.
  /// Carries the resting card on with its flight to [progress] of the way.
  void _flyTo(double progress) {
    restingProgress = progress;
    restingFrame = flight!.frameAt(progress);
  }

  List<_Chase> get _chases => [
    _horizontal,
    _pinchScale,
    _pinchRotation,
    _pinchShiftX,
    _pinchShiftY,
  ];

  /// Points [chase] at [target] without disturbing its position or
  /// velocity: the spring only changes its mind about where it is going.
  void _retarget(_Chase chase, double target, SpringDescription spring) {
    chase
      ..target = target
      ..spring = spring;
    if (_ticker.isActive || chase.atRest) {
      return;
    }
    _lastTick = Duration.zero;
    _ticker.start();
  }

  /// One closed-form spring step per frame toward wherever each target is
  /// now. Integrated by hand because `animateWith` restarts its clock on
  /// every retarget, which would freeze the chase under a moving finger.
  void _tick(Duration elapsed) {
    final dt =
        (elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;
    if (dt > 0) {
      for (final chase in _chases) {
        if (!chase.atRest) {
          chase.step(dt);
        }
      }
    }
    final simulation = _flightSimulation;
    if (simulation != null) {
      final t =
          (elapsed - (_flightStart ??= elapsed)).inMicroseconds /
          Duration.microsecondsPerSecond;
      if (simulation.isDone(t)) {
        _flightSimulation = null;
        _flyTo(1);
      } else {
        _flyTo(simulation.x(t).clamp(0.0, 1.0));
      }
    }
    if (_flightSimulation == null && _chases.every((chase) => chase.atRest)) {
      for (final chase in _chases) {
        chase.settle();
      }
      _ticker.stop();
    }
    if (!_released) {
      _publish();
    }
  }
}

/// A value chasing a moving target through a spring, one closed-form step
/// per frame.
class _Chase {
  _Chase(this.value, {required this.tolerance}) : target = value;

  double value;
  double velocity = 0;
  double target;
  SpringDescription? spring;

  /// How close to the target, and how slow, counts as there.
  final double tolerance;

  bool get atRest =>
      spring == null ||
      (value - target).abs() < tolerance && velocity.abs() < tolerance * 50;

  void step(double dt) {
    final simulation = SpringSimulation(spring!, value, target, velocity);
    value = simulation.x(dt);
    velocity = simulation.dx(dt);
  }

  /// Puts the value on its target, at rest.
  void settle() {
    value = target;
    velocity = 0;
  }
}
