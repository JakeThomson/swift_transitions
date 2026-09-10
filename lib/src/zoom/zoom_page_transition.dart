import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/physics.dart';

import '../corners/display_corner_radii.dart';
import 'zoom_frame.dart';
import 'zoom_interaction.dart';
import 'zoom_transition_layer.dart';

/// What a zoom flight grows out of and shrinks back into, measured when the
/// flight starts.
@immutable
class ZoomFlightSource {
  /// Creates a flight source.
  const ZoomFlightSource({
    required this.rect,
    required this.radii,
    required this.child,
  });

  /// The source's bounds in navigator coordinates.
  final Rect rect;

  /// The source's corner radii.
  final BorderRadius radii;

  /// The source's content, drawn inside the card during the cross-fade.
  final Widget child;
}

/// The zoom transition: the page drawn as a card that flies between
/// [source] and the full navigator, driven by [animation].
///
/// Without a [source] — no matching `ZoomTransitionSource` in the route
/// underneath, or one that has not been laid out — the page scales up from
/// the centre of the screen and fades in, the fallback UIKit uses when a
/// zoom's source view cannot be found.
///
/// While a finger holds the card, [liveFrame] carries the frame the gesture
/// computed and the flight line is ignored. After a release, [departure]
/// says where the card left from, so the landing (or the return to full
/// screen) flies from there rather than from the flight line.
class ZoomPageTransition extends StatelessWidget {
  /// Creates a zoom transition.
  const ZoomPageTransition({
    super.key,
    required this.animation,
    this.source,
    this.liveFrame,
    this.departure,
    this.carry,
    this.cornerRadii,
    this.alignmentRect,
    this.snapshot = false,
    required this.child,
  });

  /// Runs from 0.0 (the card rests on the source) to 1.0 (the page is at
  /// rest, full screen), and a little below zero at the end of a committed
  /// landing, where the card carries past the source and eases back into it
  /// (`ZoomRouteTransitionMixin.createSimulation`).
  final Animation<double> animation;

  /// What the flight grows out of, or null for the centred fallback.
  final ZoomFlightSource? source;

  /// The frame under the finger during an interactive dismissal, or null
  /// when no gesture is live.
  final ValueListenable<ZoomFrame?>? liveFrame;

  /// Where the card departed from at the last release, or null when the
  /// card is on the flight line.
  final ZoomDeparture? departure;

  /// How far the landing card is from its flight line, carrying the motion
  /// it was released with (`ZoomRouteTransitionMixin.createSimulation`).
  final Animation<Offset>? carry;

  /// Overrides [DisplayCornerRadii.of] for the card's corners at the screen
  /// end of the flight.
  final BorderRadius? cornerRadii;

  /// The part of the page that fills the card at the source end of the
  /// flight, or null for the whole page. See [ZoomTransitionLayer].
  final Rect? alignmentRect;

  /// Whether the page is painted from a snapshot while it flies.
  final bool snapshot;

  /// The page.
  final Widget child;

  /// How far the fallback card is inset from the screen at the start of the
  /// flight, as a fraction of each dimension.
  static const double fallbackInset = 0.05;

  /// The card's frame at the start of the centred fallback flight.
  static Rect fallbackRectFor(Rect screen) => Rect.fromCenter(
    center: screen.center,
    width: screen.width * (1 - 2 * fallbackInset),
    height: screen.height * (1 - 2 * fallbackInset),
  );

  /// The frame at route progress [t] of a card flying from [departure]: to
  /// the source (or the fallback rect) as [t] falls to zero, or to the full
  /// [screen] as it rises to one.
  static ZoomFrame departureFrameAt({
    required double t,
    required ZoomDeparture departure,
    required ZoomFlightSource? source,
    required Rect screen,
    required BorderRadius screenRadii,
  }) {
    if (departure.toSource) {
      return zoomDepartureFrame(
        t: departure.progress <= 0
            ? 1
            : math.max(0.0, 1 - t / departure.progress),
        from: departure.frame,
        to: source?.rect ?? fallbackRectFor(screen),
        toRadii: source?.radii ?? screenRadii,
        toSource: true,
      );
    }
    return zoomDepartureFrame(
      t: departure.progress >= 1
          ? 1
          : ((t - departure.progress) / (1 - departure.progress)).clamp(
              0.0,
              1.0,
            ),
      from: departure.frame,
      to: screen,
      toRadii: screenRadii,
      toSource: false,
    );
  }

  /// The transition applied to the route underneath a zoom route: it is
  /// scaled down a little, about the screen's centre, as the card grows
  /// over it ([kZoomCoveredPageScale]), and takes no touches for as long as
  /// the route is on screen, the landing included.
  ///
  /// A gesture dragging the card does not move it: natively the page holds
  /// wherever the flight left it until the dismissal commits or is given
  /// up (parity stage 9). The dim the page receives is the zoom route's
  /// modal barrier. The builder must be non-null so that a covered
  /// [CupertinoPageRoute] or [MaterialPageRoute] hands off to it instead of
  /// running its own slide, and it is a static tear-off because
  /// [ModalRoute.didChangeNext] compares delegated transitions by identity.
  static Widget? delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) => _CoveredPage(progress: secondaryAnimation, child: child);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final pageSize = constraints.biggest;
        final screen = Offset.zero & pageSize;
        final screenRadii = cornerRadii ?? DisplayCornerRadii.of(context);
        final source = this.source;
        final fallbackRect = fallbackRectFor(screen);
        final liveFrame = this.liveFrame;
        return AnimatedBuilder(
          animation: liveFrame == null
              ? animation
              : Listenable.merge(<Listenable>[animation, liveFrame]),
          child: child,
          builder: (context, child) {
            final held = liveFrame?.value;
            final departure = this.departure;
            // A spring settles within a tolerance of its end, so read the
            // ends from the status rather than the value. A landing is let
            // past zero, where its overshoot is.
            final t = switch (animation.status) {
              AnimationStatus.completed => 1.0,
              AnimationStatus.dismissed => 0.0,
              AnimationStatus.forward || AnimationStatus.reverse =>
                (departure?.toSource ?? false)
                    ? math.min(animation.value, 1.0)
                    : animation.value.clamp(0.0, 1.0),
            };
            final ZoomFrame frame;
            if (held != null) {
              frame = held;
            } else if (departure != null && !animation.isCompleted) {
              final onLine = departureFrameAt(
                t: t,
                departure: departure,
                source: source,
                screen: screen,
                screenRadii: screenRadii,
              );
              final carried = carry?.value ?? Offset.zero;
              frame = carried == Offset.zero
                  ? onLine
                  : ZoomFrame(
                      rect: onLine.rect.shift(carried),
                      rotation: onLine.rotation,
                      radii: onLine.radii,
                      sourceOpacity: onLine.sourceOpacity,
                    );
            } else {
              frame = zoomFlightFrame(
                t: t,
                source: source?.rect ?? fallbackRect,
                screen: screen,
                sourceRadii: source?.radii ?? screenRadii,
                screenRadii: screenRadii,
                pushing: animation.status == AnimationStatus.forward,
              );
            }
            final atRest = animation.isCompleted && held == null;
            return Opacity(
              opacity: source == null && held == null ? t : 1,
              child: ZoomTransitionLayer(
                frame: frame,
                pageSize: pageSize,
                atRest: atRest,
                flightChild: source?.child,
                sourceSize: source?.rect.size,
                alignmentRect: source == null ? null : alignmentRect,
                child: _FlightSnapshot(
                  enabled: snapshot && !atRest,
                  child: child!,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Paints its child from a snapshot while [enabled], the way Material's
/// zoom transition does: [SnapshotMode.permissive], so a page with a
/// platform view paints live instead of throwing. Always in the tree, so
/// the page's element keeps its position and state either way.
class _FlightSnapshot extends StatefulWidget {
  const _FlightSnapshot({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_FlightSnapshot> createState() => _FlightSnapshotState();
}

class _FlightSnapshotState extends State<_FlightSnapshot> {
  late final SnapshotController _controller = SnapshotController(
    allowSnapshotting: widget.enabled,
  );

  @override
  void didUpdateWidget(_FlightSnapshot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.allowSnapshotting = widget.enabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SnapshotWidget(
      controller: _controller,
      mode: SnapshotMode.permissive,
      child: widget.child,
    );
  }
}

/// The page under a zoom route, scaled down with the flight's [progress]
/// and held where it is while a gesture drags the card.
class _CoveredPage extends StatefulWidget {
  const _CoveredPage({required this.progress, required this.child});

  final Animation<double> progress;
  final Widget? child;

  @override
  State<_CoveredPage> createState() => _CoveredPageState();
}

class _CoveredPageState extends State<_CoveredPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _returning = AnimationController.unbounded(
    vsync: this,
  );
  ValueNotifier<bool>? _gesture;
  double _held = 0;

  @override
  void initState() {
    super.initState();
    widget.progress.addStatusListener(_handleStatusChanged);
  }

  @override
  void didUpdateWidget(_CoveredPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.progress != oldWidget.progress) {
      oldWidget.progress.removeStatusListener(_handleStatusChanged);
      widget.progress.addStatusListener(_handleStatusChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final gesture = Navigator.of(context).userGestureInProgressNotifier;
    if (gesture != _gesture) {
      _gesture?.removeListener(_handleGestureChanged);
      _gesture = gesture..addListener(_handleGestureChanged);
    }
  }

  @override
  void dispose() {
    widget.progress.removeStatusListener(_handleStatusChanged);
    _gesture?.removeListener(_handleGestureChanged);
    _returning.dispose();
    super.dispose();
  }

  // Where the flight left the page, kept for as long as a finger has the
  // card: the route's animation follows the gesture and the page does not.
  void _handleGestureChanged() {
    _held = widget.progress.value;
  }

  /// The page comes home on [kZoomCoveredPageReturn] rather than on the
  /// route's own animation, which a committed dismissal seeds so the card
  /// lands well before the page has finished growing.
  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse) {
      _returning
        ..value = _progress
        ..animateWith(
          SpringSimulation(kZoomCoveredPageReturn, _progress, 0, 0),
        );
    } else if (status == AnimationStatus.forward) {
      _returning.stop();
    }
  }

  /// The flight's progress, held where a gesture found it.
  double get _progress =>
      (_gesture?.value ?? false) ? _held : widget.progress.value;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable?>[
        widget.progress,
        _gesture,
        _returning,
      ]),
      child: widget.child,
      builder: (context, child) {
        final progress = widget.progress.status == AnimationStatus.reverse
            ? _returning.value
            : _progress;
        final scale = zoomCoveredPageScale(progress);
        Widget page = Transform.scale(
          scale: scale,
          filterQuality: FilterQuality.medium,
          child: child,
        );
        if (scale < 1) {
          // The scale uncovers a strip at the screen's edges, 0.086 of the
          // width across at full progress. Natively that strip is the window
          // behind the page and carries the system background, which is why
          // it cannot be seen; a zoom route is not opaque, so without a
          // backdrop of its own the window's black shows through instead.
          page = ColoredBox(
            color: CupertinoTheme.of(context).scaffoldBackgroundColor,
            child: page,
          );
        }
        return IgnorePointer(
          // A popping route passes its pointers by so that a landing card
          // does not eat them, which would otherwise leave the page behind
          // live while the card is still flying home.
          ignoring: widget.progress.status != AnimationStatus.dismissed,
          child: page,
        );
      },
    );
  }
}
