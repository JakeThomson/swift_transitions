import 'package:flutter/cupertino.dart';

import '../corners/display_corner_radii.dart';
import '../physics/curves.dart';

// The incoming page's slide is the SDK's, ported from `cupertino/route.dart`
// (`_kRightMiddleTween` and `_CupertinoPageTransitionState._setupAnimation`),
// on the measured curve [SwiftCurves.push] rather than the SDK's
// `fastEaseInToSlowEaseOut`. The covered page's motion was measured too
// (design.md section 1.1, parity stage 1) and differs from the SDK in three
// ways. It travels 0.30 of the width rather than a third, it follows the
// same curve as the incoming page rather than its own `linearToEaseOut`, so
// the two pages move in lockstep, and it is dimmed by the transition rather
// than a barrier, so the dim also tracks the finger and exists under a
// route with no barrier colour.

// Offset from offscreen to the right to fully on screen.
final Animatable<Offset> _kRightMiddleTween = Tween<Offset>(
  begin: const Offset(1, 0),
  end: Offset.zero,
);

/// How far the covered page travels, as a fraction of the width. Native
/// measured 0.299–0.302 at every frame of a push and a pop (parity stage 1),
/// and 0.283–0.288 across a held back swipe in an earlier recording.
const double _kCoveredPageTravel = 0.30;

// Offset from fully on screen to [_kCoveredPageTravel] offscreen to the left.
final Animatable<Offset> _kMiddleLeftTween = Tween<Offset>(
  begin: Offset.zero,
  end: const Offset(-_kCoveredPageTravel, 0),
);

/// The black overlaid on the covered page at full progress. Native measured
/// 0.089–0.104 × progress at every frame of a push, linear, read from a
/// patch beside the arriving page's edge (parity stage 1).
const double _kCoveredPageDimAlpha = 0.10;

/// The iOS push transition: the SDK's slide for the arriving page, the
/// measured parallax and dim for the covered page, and the moving page's
/// leading corners clipped to the display's corner radius with its
/// leading-edge shadow cast from that rounded shape.
///
/// The page is clipped while it is in motion — arriving (`primaryRouteAnimation`
/// incomplete) or receding under a route pushed on top of it
/// (`secondaryRouteAnimation` active) — and the clip is removed at rest, so a
/// settled page costs nothing. The covered page moves on the same curve as
/// the page covering it and darkens in proportion, so the two read as one
/// motion; both are linear while a back swipe is tracking the finger.
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

  /// The transition applied to a route underneath a [SwiftPageRoute] that
  /// does not share it — a [CupertinoPageRoute], or a [MaterialPageRoute]
  /// with another theme: the covered page's slide, clip and dim, linear
  /// while a back swipe is in progress.
  ///
  /// A static tear-off, because [ModalRoute.didChangeNext] compares delegated
  /// transitions by identity: two stacked Swift routes share it and so each
  /// keeps driving its own [SwiftPageTransition]. The reverse stack — a Swift
  /// route under a stock [CupertinoPageRoute] — receives the SDK's delegate
  /// and moves as the SDK does, without the clip or the measured dim.
  static Widget? delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (child == null) {
      return null;
    }
    return SwiftPageTransition(
      primaryRouteAnimation: kAlwaysCompleteAnimation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: ModalRoute.of(context)?.popGestureInProgress ?? false,
      child: child,
    );
  }

  @override
  State<SwiftPageTransition> createState() => _SwiftPageTransitionState();
}

class _SwiftPageTransitionState extends State<SwiftPageTransition> {
  late Animation<Offset> _primaryPositionAnimation;
  late Animation<Offset> _secondaryPositionAnimation;
  late Animation<double> _dimAnimation;
  CurvedAnimation? _primaryPositionCurve;
  CurvedAnimation? _secondaryPositionCurve;

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
    _primaryPositionCurve = null;
    _secondaryPositionCurve = null;
  }

  void _setupAnimation() {
    if (!widget.linearTransition) {
      _primaryPositionCurve = CurvedAnimation(
        parent: widget.primaryRouteAnimation,
        curve: SwiftCurves.push,
        reverseCurve: SwiftCurves.push.flipped,
      );
      // The same curve as the primary, so the covered page keeps pace with
      // the page covering it (the SDK gives it linearToEaseOut of its own).
      _secondaryPositionCurve = CurvedAnimation(
        parent: widget.secondaryRouteAnimation,
        curve: SwiftCurves.push,
        reverseCurve: SwiftCurves.push.flipped,
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
    _dimAnimation = _secondaryPositionCurve ?? widget.secondaryRouteAnimation;
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
          dimAnimation: _dimAnimation,
          cornerRadii: widget.cornerRadii,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The page clipped to the display radius on its leading corners, with the
/// leading-edge shadow cast from the same shape and the covered page's dim
/// painted inside the clip. All three only exist while the page is in
/// motion.
class _ClippedPage extends StatelessWidget {
  const _ClippedPage({
    required this.primaryRouteAnimation,
    required this.secondaryRouteAnimation,
    required this.dimAnimation,
    required this.cornerRadii,
    required this.child,
  });

  final Animation<double> primaryRouteAnimation;
  final Animation<double> secondaryRouteAnimation;

  /// The covered page's progress, on the same curve as its slide; the dim is
  /// [_kCoveredPageDimAlpha] of black at 1.
  final Animation<double> dimAnimation;
  final BorderRadius? cornerRadii;
  final Widget child;

  // The leading-edge shadow, from the luminance profile beside a native
  // page's edge at mid-flight (parity stage 1): about 2 % darker at the
  // edge, gone within 18 pt, the same at every progress of a push and a
  // pop. A Gaussian of this radius offset this far under the page gives
  // 2.1 % at 2 pt, 1.5 % at 6 pt and 0.4 % at 14 pt.
  static const double _shadowAlpha = 0.03;
  static const double _shadowOffset = 6;
  static const double _shadowBlurRadius = 12;

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[
        primaryRouteAnimation,
        secondaryRouteAnimation,
        dimAnimation,
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
        final dim = inMotion
            ? _kCoveredPageDimAlpha * dimAnimation.value.clamp(0.0, 1.0)
            : 0.0;
        return DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            shadows: <BoxShadow>[
              if (inMotion)
                BoxShadow(
                  color: const Color(
                    0xFF000000,
                  ).withValues(alpha: _shadowAlpha),
                  // Cast toward the leading edge only; the page covers the rest.
                  offset: Offset(switch (textDirection) {
                    TextDirection.ltr => -_shadowOffset,
                    TextDirection.rtl => _shadowOffset,
                  }, 0),
                  blurRadius: _shadowBlurRadius,
                ),
            ],
          ),
          child: ClipRSuperellipse(
            borderRadius: active ? radii : BorderRadius.zero,
            clipBehavior: active ? Clip.antiAlias : Clip.none,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                color: dim > 0
                    ? const Color(0xFF000000).withValues(alpha: dim)
                    : null,
              ),
              child: child,
            ),
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
