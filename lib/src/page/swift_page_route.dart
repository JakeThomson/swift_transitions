import 'package:flutter/cupertino.dart';

import 'back_gesture.dart';
import 'swift_page_transition.dart';

/// Replaces [CupertinoRouteTransitionMixin]'s transition with
/// [SwiftPageTransition] and [SwiftBackGestureDetector] on any [PageRoute]
/// it is mixed into after that mixin, mirroring
/// [CupertinoRouteTransitionMixin.buildPageTransitions] with the display
/// clip and the configurable back-gesture region added.
mixin SwiftPageTransitionMixin<T> on PageRoute<T> {
  /// How long a push or pop takes: 400 ms, by which point
  /// [SwiftCurves.push] has half a point of the width left. The SDK's
  /// Cupertino routes take 500 ms on a different curve.
  static const Duration kTransitionDuration = Duration(milliseconds: 400);

  /// Where the interactive back swipe may start. Defaults to anywhere on
  /// the page, as on iOS 26.
  BackGestureRegion get backGestureRegion => BackGestureRegion.anywhere;

  @override
  Duration get transitionDuration => kTransitionDuration;

  /// Overrides [DisplayCornerRadii.of] for the incoming page's clip.
  BorderRadius? get cornerRadii => null;

  /// No barrier: the covered page's dim is painted by [SwiftPageTransition]
  /// (measured, and tracking the finger) rather than by
  /// [CupertinoRouteTransitionMixin]'s barrier colour.
  @override
  Color? get barrierColor => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return buildPageTransitions<T>(
      this,
      animation,
      secondaryAnimation,
      child,
      region: backGestureRegion,
      cornerRadii: cornerRadii,
    );
  }

  /// Builds the transition and back-swipe detector for any [route], for use
  /// by [SwiftPageTransitionsBuilder] on routes that don't mix in this
  /// class themselves (a plain [MaterialPageRoute] on iOS, say).
  static Widget buildPageTransitions<T>(
    PageRoute<T> route,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child, {
    BackGestureRegion region = BackGestureRegion.anywhere,
    BorderRadius? cornerRadii,
  }) {
    final linearTransition = route.popGestureInProgress;
    if (route.fullscreenDialog) {
      return CupertinoFullscreenDialogTransition(
        primaryRouteAnimation: animation,
        secondaryRouteAnimation: secondaryAnimation,
        linearTransition: linearTransition,
        child: child,
      );
    }
    return SwiftPageTransition(
      primaryRouteAnimation: animation,
      secondaryRouteAnimation: secondaryAnimation,
      linearTransition: linearTransition,
      cornerRadii: cornerRadii,
      child: SwiftBackGestureDetector<T>(
        enabledCallback: () => route.popGestureEnabled,
        onStartPopGesture: () {
          assert(
            route.popGestureEnabled,
            'a back gesture requires popGestureEnabled',
          );
          return BackGestureController<T>(
            navigator: route.navigator!,
            getIsActive: () => route.isActive,
            getIsCurrent: () => route.isCurrent,
            controller: route.controller!,
          );
        },
        region: region,
        child: child,
      ),
    );
  }
}

/// An iOS push transition with display-radius corner clipping.
///
/// Mixes in [CupertinoRouteTransitionMixin], so [CupertinoNavigationBar]
/// keeps its automatic back title and other Cupertino routes treat this as
/// one of their own — [SwiftPageTransitionMixin] then replaces only the
/// transition and the back gesture.
///
/// See also:
///
///  * [SwiftPage], the [Page] counterpart for a declarative [Navigator].
///  * [SwiftPageTransitionsBuilder], to apply this transition to every
///    [MaterialPageRoute] on iOS from a [PageTransitionsTheme].
class SwiftPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T>, SwiftPageTransitionMixin<T> {
  /// Creates a page route with the iOS push transition.
  SwiftPageRoute({
    required this.builder,
    super.settings,
    this.maintainState = true,
    super.fullscreenDialog,
    this.title,
    this.backGestureRegion = BackGestureRegion.anywhere,
    this.cornerRadii,
  }) {
    assert(opaque, 'SwiftPageRoute must be opaque');
  }

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  final String? title;

  @override
  final bool maintainState;

  @override
  final BackGestureRegion backGestureRegion;

  @override
  final BorderRadius? cornerRadii;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      SwiftPageTransition.delegatedTransition;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

/// A page that creates a [SwiftPageRoute].
class SwiftPage<T> extends Page<T> {
  /// Creates a page with the iOS push transition.
  const SwiftPage({
    required this.child,
    this.maintainState = true,
    this.title,
    this.fullscreenDialog = false,
    this.backGestureRegion = BackGestureRegion.anywhere,
    this.cornerRadii,
    super.canPop,
    super.onPopInvoked,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  /// The content to be shown in the route created by this page.
  final Widget child;

  /// {@macro flutter.widgets.ModalRoute.maintainState}
  final bool maintainState;

  /// {@macro flutter.cupertino.CupertinoRouteTransitionMixin.title}
  final String? title;

  /// {@macro flutter.widgets.PageRoute.fullscreenDialog}
  final bool fullscreenDialog;

  /// Where the interactive back swipe may start.
  final BackGestureRegion backGestureRegion;

  /// Overrides [DisplayCornerRadii.of] for the incoming page's clip.
  final BorderRadius? cornerRadii;

  @override
  Route<T> createRoute(BuildContext context) =>
      _PageBasedSwiftPageRoute<T>(page: this);
}

class _PageBasedSwiftPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T>, SwiftPageTransitionMixin<T> {
  _PageBasedSwiftPageRoute({required SwiftPage<T> page})
    : super(settings: page) {
    assert(opaque, 'SwiftPage must be opaque');
  }

  SwiftPage<T> get _page => settings as SwiftPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  String? get title => _page.title;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  BackGestureRegion get backGestureRegion => _page.backGestureRegion;

  @override
  BorderRadius? get cornerRadii => _page.cornerRadii;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      fullscreenDialog ? null : SwiftPageTransition.delegatedTransition;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';
}
