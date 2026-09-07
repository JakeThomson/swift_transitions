import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

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
    this.cornerRadii,
    required this.child,
  });

  /// Runs from 0.0 (the card rests on the source) to 1.0 (the page is at
  /// rest, full screen).
  final Animation<double> animation;

  /// What the flight grows out of, or null for the centred fallback.
  final ZoomFlightSource? source;

  /// The frame under the finger during an interactive dismissal, or null
  /// when no gesture is live.
  final ValueListenable<ZoomFrame?>? liveFrame;

  /// Where the card departed from at the last release, or null when the
  /// card is on the flight line.
  final ZoomDeparture? departure;

  /// Overrides [DisplayCornerRadii.of] for the card's corners at the screen
  /// end of the flight.
  final BorderRadius? cornerRadii;

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
            : (1 - t / departure.progress).clamp(0.0, 1.0),
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

  /// The transition applied to the route underneath a zoom route: none.
  ///
  /// The covered page stays put at full scale while the card grows over it,
  /// as on iOS; the dim it receives is the zoom route's modal barrier. The
  /// builder must be non-null so that a covered [CupertinoPageRoute] or
  /// [MaterialPageRoute] hands off to it instead of running its own slide,
  /// and it is a static tear-off because [ModalRoute.didChangeNext] compares
  /// delegated transitions by identity.
  static Widget? delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) => child;

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
            // A spring settles within a tolerance of its end, so read the
            // ends from the status rather than the value.
            final t = switch (animation.status) {
              AnimationStatus.completed => 1.0,
              AnimationStatus.dismissed => 0.0,
              AnimationStatus.forward ||
              AnimationStatus.reverse => animation.value.clamp(0.0, 1.0),
            };
            final held = liveFrame?.value;
            final departure = this.departure;
            final ZoomFrame frame;
            if (held != null) {
              frame = held;
            } else if (departure != null && !animation.isCompleted) {
              frame = departureFrameAt(
                t: t,
                departure: departure,
                source: source,
                screen: screen,
                screenRadii: screenRadii,
              );
            } else {
              frame = zoomFlightFrame(
                t: t,
                source: source?.rect ?? fallbackRect,
                screen: screen,
                sourceRadii: source?.radii ?? screenRadii,
                screenRadii: screenRadii,
              );
            }
            return Opacity(
              opacity: source == null && held == null ? t : 1,
              child: ZoomTransitionLayer(
                frame: frame,
                pageSize: pageSize,
                atRest: animation.isCompleted && held == null,
                flightChild: source?.child,
                sourceSize: source?.rect.size,
                child: child!,
              ),
            );
          },
        );
      },
    );
  }
}
