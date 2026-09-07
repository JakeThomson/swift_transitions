import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../corners/display_corner_radii.dart';
import 'zoom_frame.dart';
import 'zoom_gestures.dart';
import 'zoom_interaction.dart';
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
///
/// Interactive dismissal is installed by [ZoomDismissGestureDetector]
/// around the page and driven by a [ZoomDismissController]; the page's
/// vertical scroll views take part through [scrollController], installed as
/// the page's [PrimaryScrollController].
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
  ZoomDismissController? _dismiss;
  ZoomDeparture? _departure;
  double _releaseVelocity = 0;
  final ValueNotifier<ZoomFrame?> _liveFrame = ValueNotifier<ZoomFrame?>(null);

  /// The scroll controller that hands a top-edge downward drag to the
  /// dismissal, installed as the page's [PrimaryScrollController] so that
  /// vertical scroll views on iOS pick it up without configuration. Pages
  /// with their own controllers can pass this one instead.
  ZoomScrollController get scrollController => _scrollController;
  final ZoomScrollController _scrollController = ZoomScrollController(
    debugLabel: 'ZoomPageRoute',
  );

  /// The zoom route enclosing [context], or null if there is none.
  static ZoomRouteTransitionMixin<Object?>? of(BuildContext context) {
    final route = ModalRoute.of(context);
    return route is ZoomRouteTransitionMixin<Object?> ? route : null;
  }

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

  /// A spring from wherever the controller is: from the flight's far end
  /// after a push or a programmatic pop, and from the release point — with
  /// the release velocity — after an interactive dismissal.
  @override
  Simulation? createSimulation({required bool forward}) {
    final velocity = _releaseVelocity;
    _releaseVelocity = 0;
    return SpringSimulation(
      options.pushSpring,
      controller!.value,
      forward ? 1 : 0,
      forward ? velocity : -velocity,
    );
  }

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
    _liveFrame.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      _source?.show();
      _source = null;
      _flightSource = null;
    }
    if (status == AnimationStatus.dismissed ||
        status == AnimationStatus.completed) {
      _departure = null;
    }
  }

  /// Whether an interactive dismissal may begin now: the route is current
  /// and can pop, no other gesture holds the navigator, and the options'
  /// predicate agrees. Unlike [popGestureEnabled], a running push does not
  /// block it — the push is grabbed instead (design.md section 3.8).
  bool _canBeginDismiss(ZoomGesture gesture, Offset grabPoint) {
    final navigator = this.navigator;
    if (navigator == null ||
        !isCurrent ||
        isFirst ||
        navigator.userGestureInProgress ||
        popDisposition == RoutePopDisposition.doNotPop ||
        _dismiss != null) {
      return false;
    }
    final shouldBegin = options.interactiveDismissShouldBegin;
    if (shouldBegin == null) {
      return true;
    }
    return shouldBegin(
      ZoomInteractionContext(
        gesture: gesture,
        location: grabPoint,
        primaryScrollMetrics: _scrollController.hasClients
            ? _scrollController.position
            : null,
      ),
    );
  }

  /// The card's frame at the controller's current value: on the flight
  /// line, or on the way from the last departure. The same frames
  /// [ZoomPageTransition] draws.
  ZoomFrame _currentFrame(Rect screen, BorderRadius screenRadii) {
    final source = _flightSource;
    // A spring settles within a tolerance of its end; read the ends from
    // the status, as ZoomPageTransition does.
    final t = controller!.isCompleted
        ? 1.0
        : controller!.isDismissed
        ? 0.0
        : controller!.value.clamp(0.0, 1.0);
    final departure = _departure;
    if (departure == null) {
      return zoomFlightFrame(
        t: t,
        source: source?.rect ?? ZoomPageTransition.fallbackRectFor(screen),
        screen: screen,
        sourceRadii: source?.radii ?? screenRadii,
        screenRadii: screenRadii,
      );
    }
    return ZoomPageTransition.departureFrameAt(
      t: t,
      departure: departure,
      source: source,
      screen: screen,
      screenRadii: screenRadii,
    );
  }

  /// Begins an interactive dismissal at [grabPoint] (navigator
  /// coordinates), or returns null if it may not begin.
  ZoomDismissController? _beginDismiss(ZoomGesture gesture, Offset grabPoint) {
    if (!_canBeginDismiss(gesture, grabPoint)) {
      return null;
    }
    final navigator = this.navigator!;
    final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
    final screen = Offset.zero & overlay.size;
    final context = subtreeContext;
    final screenRadii =
        cornerRadii ??
        (context == null ? BorderRadius.zero : DisplayCornerRadii.of(context));
    final resting = _currentFrame(screen, screenRadii);
    _departure = null;
    return _dismiss = ZoomDismissController(
      navigator: navigator,
      controller: controller!,
      physics: options.dismissPhysics,
      gesture: gesture,
      restingFrame: resting,
      screen: screen,
      sourceRadii: _flightSource?.radii,
      screenRadii: screenRadii,
      grabPoint: grabPoint,
      liveFrame: _liveFrame,
      getIsActive: () => isActive,
      getIsCurrent: () => isCurrent,
      onRelease: (departure, velocity) {
        _dismiss = null;
        _departure = departure;
        _releaseVelocity = velocity;
        changedInternalState();
      },
      onSettled: () {
        // A committed dismissal has usually disposed the route by now.
        if (this.navigator != null && navigator.mounted) {
          changedInternalState();
        }
      },
      settleSpring: options.pushSpring,
      vsync: navigator,
    );
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
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return PrimaryScrollController(
      controller: _scrollController,
      child: super.buildPage(context, animation, secondaryAnimation),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final gestures = options.dismissGestures;
    final page = ZoomDismissGestureDetector(
      pan: gestures.pan,
      edgeSwipe: gestures.edgeSwipe,
      pinch: gestures.pinch,
      isPushing: () => animation.status == AnimationStatus.forward,
      onStart: _beginDismiss,
      scrollController: _scrollController,
      child: child,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: page);
    }
    return ZoomPageTransition(
      animation: animation,
      source: _flightSource,
      liveFrame: _liveFrame,
      departure: _departure,
      cornerRadii: cornerRadii,
      child: page,
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
