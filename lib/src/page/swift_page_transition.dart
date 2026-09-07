import 'package:flutter/cupertino.dart';

import '../corners/display_corner_radii.dart';

// The slide geometry and curves are the SDK's, ported from
// `cupertino/route.dart` (`_kRightMiddleTween`, `_kMiddleLeftTween` and
// `_CupertinoPageTransitionState._setupAnimation`), so a SwiftPageRoute and a
// CupertinoPageRoute move identically. Only the leading-edge shadow and the
// clip differ — see [SwiftPageTransition].

// Offset from offscreen to the right to fully on screen.
final Animatable<Offset> _kRightMiddleTween = Tween<Offset>(
  begin: const Offset(1, 0),
  end: Offset.zero,
);

// Offset from fully on screen to 1/3 offscreen to the left.
final Animatable<Offset> _kMiddleLeftTween = Tween<Offset>(
  begin: Offset.zero,
  end: const Offset(-1 / 3, 0),
);

/// The iOS push transition: the SDK's slide, with the moving page's leading
/// corners clipped to the display's corner radius and its leading-edge shadow
/// cast from that rounded shape.
///
/// The page is clipped while it is in motion — arriving (`primaryRouteAnimation`
/// incomplete) or receding under a route pushed on top of it
/// (`secondaryRouteAnimation` active) — and the clip is removed at rest, so a
/// settled page costs nothing.
///
/// Only the **leading** corners round. A page in flight keeps its trailing
/// edge on or beyond the display's own edge, where the display already rounds
/// it, so a trailing clip can never be seen on a device — but it can be seen
/// wherever the app's radius and the bezel's disagree by a pixel (the
/// simulator's device frame), as a sliver of the window ground in the
/// trailing corners. Leaving those corners square is pixel-identical on
/// hardware and removes the sliver.
///
/// The shadow is why this owns its tree rather than wrapping
/// [CupertinoPageTransition]: that widget paints its shadow as a full-height
/// rectangle beside the page, which reads correctly against a square page but
/// fills the gap a rounded corner leaves — the shadow then looks like content
/// escaping the clip. Here it is a [ShapeDecoration] shadow on the same
/// superellipse the clip uses, so it wraps the corner as iOS's does.
class SwiftPageTransition extends StatefulWidget {
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

  /// Overrides [DisplayCornerRadii.of] for the clip and the shadow.
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
  State<SwiftPageTransition> createState() => _SwiftPageTransitionState();
}

class _SwiftPageTransitionState extends State<SwiftPageTransition> {
  late Animation<Offset> _primaryPositionAnimation;
  late Animation<Offset> _secondaryPositionAnimation;
  late Animation<double> _shadowAnimation;
  CurvedAnimation? _primaryPositionCurve;
  CurvedAnimation? _secondaryPositionCurve;
  CurvedAnimation? _shadowCurve;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  @override
  void didUpdateWidget(covariant SwiftPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryRouteAnimation != widget.primaryRouteAnimation ||
        oldWidget.secondaryRouteAnimation != widget.secondaryRouteAnimation ||
        oldWidget.linearTransition != widget.linearTransition) {
      _disposeCurves();
      _setupAnimation();
    }
  }

  @override
  void dispose() {
    _disposeCurves();
    super.dispose();
  }

  void _disposeCurves() {
    _primaryPositionCurve?.dispose();
    _secondaryPositionCurve?.dispose();
    _shadowCurve?.dispose();
    _primaryPositionCurve = null;
    _secondaryPositionCurve = null;
    _shadowCurve = null;
  }

  void _setupAnimation() {
    if (!widget.linearTransition) {
      _primaryPositionCurve = CurvedAnimation(
        parent: widget.primaryRouteAnimation,
        curve: Curves.fastEaseInToSlowEaseOut,
        reverseCurve: Curves.fastEaseInToSlowEaseOut.flipped,
      );
      _secondaryPositionCurve = CurvedAnimation(
        parent: widget.secondaryRouteAnimation,
        curve: Curves.linearToEaseOut,
        reverseCurve: Curves.easeInToLinear,
      );
      _shadowCurve = CurvedAnimation(
        parent: widget.primaryRouteAnimation,
        curve: Curves.linearToEaseOut,
      );
    }
    _primaryPositionAnimation =
        (_primaryPositionCurve ?? widget.primaryRouteAnimation).drive(
          _kRightMiddleTween,
        );
    _secondaryPositionAnimation =
        (_secondaryPositionCurve ?? widget.secondaryRouteAnimation).drive(
          _kMiddleLeftTween,
        );
    _shadowAnimation = _shadowCurve ?? widget.primaryRouteAnimation;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      'SwiftPageTransition needs a Directionality',
    );
    final textDirection = Directionality.of(context);
    return SlideTransition(
      position: _secondaryPositionAnimation,
      textDirection: textDirection,
      transformHitTests: false,
      child: SlideTransition(
        position: _primaryPositionAnimation,
        textDirection: textDirection,
        child: _ClippedPage(
          primaryRouteAnimation: widget.primaryRouteAnimation,
          secondaryRouteAnimation: widget.secondaryRouteAnimation,
          shadowAnimation: _shadowAnimation,
          cornerRadii: widget.cornerRadii,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The page clipped to the display radius on its leading corners, with the
/// leading-edge shadow cast from the same shape. Both only exist while the
/// page is in motion.
class _ClippedPage extends StatelessWidget {
  const _ClippedPage({
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.shadowAnimation,
    required this.cornerRadii,
    required this.child,
  });

  final Animation<double> primaryRouteAnimation;
  final Animation<double> secondaryRouteAnimation;
  final Animation<double> shadowAnimation;
  final BorderRadius? cornerRadii;
  final Widget child;

  /// Peak darkness of the shadow, matching the SDK's `0x04000000` gradient
  /// start once the blur has spread it.
  static const double _shadowAlpha = 0.03;

  /// The shadow's reach as a fraction of the page width — the SDK's 5%.
  static const double _shadowWidthFraction = 0.05;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        primaryRouteAnimation,
        secondaryRouteAnimation,
        shadowAnimation,
      ]),
      child: child,
      builder: (context, child) {
        final displayRadii = cornerRadii ?? DisplayCornerRadii.of(context);
        final radii = _leadingCorners(displayRadii, textDirection);
        final inMotion =
            primaryRouteAnimation.value < 1 ||
            secondaryRouteAnimation.value > 0;
        final active = inMotion && radii != BorderRadius.zero;
        final shape = RoundedSuperellipseBorder(
          borderRadius: active ? radii : BorderRadius.zero,
        );
        final shadowWidth =
            MediaQuery.sizeOf(context).width * _shadowWidthFraction;
        final shadowStrength = inMotion
            ? shadowAnimation.value.clamp(0.0, 1.0)
            : 0.0;
        return DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            shadows: <BoxShadow>[
              if (shadowStrength > 0)
                BoxShadow(
                  color: const Color(
                    0xFF000000,
                  ).withValues(alpha: _shadowAlpha * shadowStrength),
                  // Cast toward the leading edge only; the page covers the rest.
                  offset: Offset(switch (textDirection) {
                    TextDirection.ltr => -shadowWidth / 2,
                    TextDirection.rtl => shadowWidth / 2,
                  }, 0),
                  blurRadius: shadowWidth,
                ),
            ],
          ),
          child: ClipRSuperellipse(
            borderRadius: active ? radii : BorderRadius.zero,
            clipBehavior: active ? Clip.antiAlias : Clip.none,
            child: child,
          ),
        );
      },
    );
  }

  /// [radii] reduced to the corners on the page's leading edge — the edge
  /// that travels across the display. See [SwiftPageTransition].
  static BorderRadius _leadingCorners(
    BorderRadius radii,
    TextDirection textDirection,
  ) => switch (textDirection) {
    TextDirection.ltr => BorderRadius.only(
      topLeft: radii.topLeft,
      bottomLeft: radii.bottomLeft,
    ),
    TextDirection.rtl => BorderRadius.only(
      topRight: radii.topRight,
      bottomRight: radii.bottomRight,
    ),
  };
}
