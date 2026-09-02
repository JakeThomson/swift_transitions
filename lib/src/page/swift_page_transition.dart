import 'package:flutter/cupertino.dart';

import '../corners/display_corner_radii.dart';

/// The iOS push transition: [CupertinoPageTransition] plus corner clipping.
///
/// The incoming page's corners are clipped to the display's physical corner
/// radius while it is in motion — arriving (`primaryRouteAnimation`
/// incomplete) or receding under a route pushed on top of it
/// (`secondaryRouteAnimation` active) — and the clip is removed at rest, so
/// a settled page costs nothing. Everything else (the slide, the parallax
/// on the covered route, the leading-edge shadow) is
/// [CupertinoPageTransition] unchanged.
class SwiftPageTransition extends StatelessWidget {
  /// Creates an iOS-style page transition with corner clipping.
  const SwiftPageTransition({
    super.key,
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.linearTransition,
    this.cornerRadii,
    required this.child,
  });

  /// Linear from 0.0 to 1.0 while this page is being pushed.
  final Animation<double> primaryRouteAnimation;

  /// Linear from 0.0 to 1.0 while a route above this one is being pushed.
  final Animation<double> secondaryRouteAnimation;

  /// Whether to skip easing, to track a back-swipe drag exactly.
  final bool linearTransition;

  /// Overrides [DisplayCornerRadii.of] for the clip.
  final BorderRadius? cornerRadii;

  /// The page content.
  final Widget child;

  /// The transition applied to the route underneath this one.
  ///
  /// The same function as [CupertinoPageTransition.delegatedTransition],
  /// not a forwarding wrapper: [ModalRoute.didChangeNext] only hands a route
  /// its own live `secondaryAnimation` (rather than delegating to this one)
  /// when the route above it carries the *same* [delegatedTransition], so a
  /// [SwiftPageRoute] and a [CupertinoPageRoute] must share one function
  /// identity to clip and slide correctly stacked in either order.
  static const DelegatedTransitionBuilder delegatedTransition =
      CupertinoPageTransition.delegatedTransition;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageTransition(
      primaryRouteAnimation: primaryRouteAnimation,
      secondaryRouteAnimation: secondaryRouteAnimation,
      linearTransition: linearTransition,
      child: _CornerClip(
        primaryRouteAnimation: primaryRouteAnimation,
        secondaryRouteAnimation: secondaryRouteAnimation,
        cornerRadii: cornerRadii,
        child: child,
      ),
    );
  }
}

class _CornerClip extends StatelessWidget {
  const _CornerClip({
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.cornerRadii,
    required this.child,
  });

  final Animation<double> primaryRouteAnimation;
  final Animation<double> secondaryRouteAnimation;
  final BorderRadius? cornerRadii;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        primaryRouteAnimation,
        secondaryRouteAnimation,
      ]),
      child: child,
      builder: (context, child) {
        final radii = cornerRadii ?? DisplayCornerRadii.of(context);
        final inMotion =
            primaryRouteAnimation.value < 1 ||
            secondaryRouteAnimation.value > 0;
        final active = inMotion && radii != BorderRadius.zero;
        return ClipRSuperellipse(
          borderRadius: active ? radii : BorderRadius.zero,
          clipBehavior: active ? Clip.antiAlias : Clip.none,
          child: child,
        );
      },
    );
  }
}
