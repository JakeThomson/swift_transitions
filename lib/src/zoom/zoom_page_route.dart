import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import 'zoom_frame.dart';
import 'zoom_page_transition.dart';
import 'zoom_transition_options.dart';
import 'zoom_transition_source.dart';

/// Turns any [PageRoute] it is mixed into after [CupertinoRouteTransitionMixin]
/// into a zoom route: non-opaque, dimming the page underneath through its
/// modal barrier, and flown between the matching [ZoomTransitionSource] and
/// the full screen by [ZoomPageTransition].
///
/// The source is looked up in the route underneath when a flight starts —
/// on the push and again on each pop, because [sourceTag] may have changed
/// while the route was open — and stays hidden behind a placeholder of its
/// own size until the route leaves the stack.
mixin ZoomRouteTransitionMixin<T> on PageRoute<T> {
  /// The tag of the [ZoomTransitionSource] to fly from and to.
  ///
  /// Read when a flight starts, like UIKit's source view provider being
  /// called again on dismiss. A paging detail page sets it to the tag of the
  /// item currently shown so the pop lands on that item's source.
  Object get sourceTag;
  set sourceTag(Object value);

  /// The transition's options.
  ZoomTransitionOptions get options;

  /// Overrides `DisplayCornerRadii.of` for the card's corners at the screen
  /// end of the flight.
  BorderRadius? get cornerRadii => null;

  Route<dynamic>? _previousRoute;
  ZoomTransitionSourceState? _source;
  ZoomFlightSource? _flightSource;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => options.dimmingColor;

  @override
  Curve get barrierCurve => kZoomDimmingCurve;

  @override
  ImageFilter? get filter => options.dimmingBlurSigma > 0
      ? ImageFilter.blur(
          sigmaX: options.dimmingBlurSigma,
          sigmaY: options.dimmingBlurSigma,
        )
      : null;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      ZoomPageTransition.delegatedTransition;

  @override
  Simulation? createSimulation({required bool forward}) =>
      SpringSimulation(options.pushSpring, forward ? 0 : 1, forward ? 1 : 0, 0);

  @override
  void install() {
    super.install();
    animation!.addStatusListener(_handleStatusChanged);
  }

  @override
  void didChangePrevious(Route<dynamic>? previousRoute) {
    _previousRoute = previousRoute;
    super.didChangePrevious(previousRoute);
  }

  @override
  TickerFuture didPush() {
    _scheduleFlight();
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    _scheduleFlight();
    return super.didPop(result);
  }

  @override
  void dispose() {
    _source?.show();
    _source = null;
    super.dispose();
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _source?.show();
      _source = null;
      _flightSource = null;
    }
  }

  /// Prepares the flight at the end of the current frame, the deferral
  /// [HeroController] makes for the same reasons: the route underneath has
  /// certainly been laid out by then, and the element tree can be walked,
  /// which it cannot during a build — where a pages-based [Navigator] pushes
  /// and pops. The first frame of a push therefore draws nothing (the
  /// fallback card at zero opacity) and the first frame of a pop draws the
  /// previous flight's card at full screen; neither is visible.
  void _scheduleFlight() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (navigator == null) {
        return; // Disposed before the frame ended.
      }
      _prepareFlight();
      changedInternalState();
    }, debugLabel: 'ZoomRouteTransitionMixin.prepareFlight');
  }

  /// Finds the source for [sourceTag] in the route underneath, measures it
  /// for the flight about to start, and swaps which source is hidden if the
  /// tag has changed. With animations disabled there is no flight, and the
  /// source stays put under the fade.
  void _prepareFlight() {
    final navigator = this.navigator;
    final previous = _previousRoute;
    final overlay = navigator?.overlay?.context.findRenderObject();
    final animate =
        navigator != null &&
        !(MediaQuery.maybeOf(navigator.context)?.disableAnimations ?? false);
    ZoomTransitionSourceState? found;
    if (animate &&
        overlay != null &&
        previous is ModalRoute<Object?> &&
        previous.subtreeContext != null) {
      found = ZoomTransitionSource.sourceFor(
        previous.subtreeContext!,
        sourceTag,
        navigator,
      );
    }
    final rect = overlay == null ? null : found?.boundsIn(overlay);
    if (found == null || rect == null) {
      found = null;
      _flightSource = null;
    } else {
      _flightSource = ZoomFlightSource(
        rect: rect,
        radii: found.borderRadius,
        child: found.flightChild,
      );
    }
    if (found != _source) {
      _source?.show();
      _source = found;
      found?.hide();
    }
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return ZoomPageTransition(
      animation: animation,
      source: _flightSource,
      cornerRadii: cornerRadii,
      child: child,
    );
  }
}

/// A page that zooms out of the [ZoomTransitionSource] tagged [sourceTag]
/// and back into it when popped.
///
/// The counterpart of SwiftUI's `navigationTransition(.zoom)`. Mixes in
/// [CupertinoRouteTransitionMixin], so [CupertinoNavigationBar] keeps its
/// automatic back title and other Cupertino routes treat this as one of
/// their own; [ZoomRouteTransitionMixin] then replaces the transition and
/// the barrier.
///
/// See also:
///
///  * [ZoomPage], the [Page] counterpart for a declarative [Navigator].
class ZoomPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T>, ZoomRouteTransitionMixin<T> {
  /// Creates a page route with the zoom transition.
  ZoomPageRoute({
    required this.builder,
    required this.sourceTag,
    this.options = const ZoomTransitionOptions(),
    super.settings,
    this.maintainState = true,
    this.title,
    this.cornerRadii,
  });

  /// Builds the primary contents of the route.
  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  Object sourceTag;

  @override
  final ZoomTransitionOptions options;

  @override
  final String? title;

  @override
  final bool maintainState;

  @override
  final BorderRadius? cornerRadii;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';
}

/// A page that creates a [ZoomPageRoute].
class ZoomPage<T> extends Page<T> {
  /// Creates a page with the zoom transition.
  const ZoomPage({
    required this.child,
    required this.sourceTag,
    this.options = const ZoomTransitionOptions(),
    this.maintainState = true,
    this.title,
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

  /// The tag of the [ZoomTransitionSource] the route flies from and to.
  final Object sourceTag;

  /// The transition's options.
  final ZoomTransitionOptions options;

  /// {@macro flutter.widgets.ModalRoute.maintainState}
  final bool maintainState;

  /// {@macro flutter.cupertino.CupertinoRouteTransitionMixin.title}
  final String? title;

  /// Overrides `DisplayCornerRadii.of` for the card's corners at the screen
  /// end of the flight.
  final BorderRadius? cornerRadii;

  @override
  Route<T> createRoute(BuildContext context) =>
      _PageBasedZoomPageRoute<T>(page: this);
}

class _PageBasedZoomPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T>, ZoomRouteTransitionMixin<T> {
  _PageBasedZoomPageRoute({required ZoomPage<T> page})
    : sourceTag = page.sourceTag,
      super(settings: page);

  ZoomPage<T> get _page => settings as ZoomPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  Object sourceTag;

  @override
  ZoomTransitionOptions get options => _page.options;

  @override
  String? get title => _page.title;

  @override
  bool get maintainState => _page.maintainState;

  @override
  BorderRadius? get cornerRadii => _page.cornerRadii;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';
}
