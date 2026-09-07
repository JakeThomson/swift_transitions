import 'package:flutter/widgets.dart';

import '../corners/display_corner_radii.dart';
import 'zoom_frame.dart';
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
class ZoomPageTransition extends StatelessWidget {
  /// Creates a zoom transition.
  const ZoomPageTransition({
    super.key,
    required this.animation,
    this.source,
    this.cornerRadii,
    required this.child,
  });

  /// Runs from 0.0 (the card rests on the source) to 1.0 (the page is at
  /// rest, full screen).
  final Animation<double> animation;

  /// What the flight grows out of, or null for the centred fallback.
  final ZoomFlightSource? source;

  /// Overrides [DisplayCornerRadii.of] for the card's corners at the screen
  /// end of the flight.
  final BorderRadius? cornerRadii;

  /// The page.
  final Widget child;

  /// How far the fallback card is inset from the screen at the start of the
  /// flight, as a fraction of each dimension.
  static const double fallbackInset = 0.05;

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
        final fallbackRect = Rect.fromCenter(
          center: screen.center,
          width: screen.width * (1 - 2 * fallbackInset),
          height: screen.height * (1 - 2 * fallbackInset),
        );
        return AnimatedBuilder(
          animation: animation,
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
            final frame = zoomFlightFrame(
              t: t,
              source: source?.rect ?? fallbackRect,
              screen: screen,
              sourceRadii: source?.radii ?? screenRadii,
              screenRadii: screenRadii,
            );
            return Opacity(
              opacity: source == null ? t : 1,
              child: ZoomTransitionLayer(
                frame: frame,
                pageSize: pageSize,
                atRest: animation.isCompleted,
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
