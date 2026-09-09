import 'dart:math' as math;
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
  ZoomFlightDirection? _pendingFlight;
  ZoomTransitionSourceState? _source;
  ZoomFlightSource? _flightSource;
  Rect? _alignmentRect;
  ZoomDismissController? _dismiss;

  /// What the next pop's simulation is seeded with, in units of what the
  /// landing has left per second: a committed dismissal's release rate
  /// over the shrink still to come. It also stiffens the landing spring
  /// ([ZoomDismissPhysics.landingSpringFor]).
  double _releaseSeed = 0;

  /// How fast the fingers were moving at that release, in resting card
  /// widths per second: what the landing spring is quickened by.
  double _landingSpeed = 0;

  /// The landing spring while it runs, read by [_flightProgress] for the
  /// part of it the controller cannot report.
  Simulation? _landingSimulation;
  bool _userGestureInProgress = false;
  ZoomDeparture? _departure;
  final ValueNotifier<ZoomFrame?> _liveFrame = ValueNotifier<ZoomFrame?>(null);
  late final Animation<double> _flightProgress = _ZoomFlightProgress(this);

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

  /// The cross-fade's length with Reduce Motion on; the springs set the
  /// pace otherwise ([createSimulation]).
  @override
  Duration get transitionDuration => kZoomReduceMotionDuration;

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

  /// A spring from wherever the controller is: the flight's far end after
  /// a push or a programmatic pop, mid-flight when a push is popped before
  /// it lands, or the departure frame of a committed dismissal, which
  /// lands on the dismissal's own spring seeded with its release rate.
  @override
  Simulation? createSimulation({required bool forward}) {
    if (MediaQuery.maybeOf(navigator!.context)?.disableAnimations ?? false) {
      // A cross-fade over [transitionDuration], not a flight.
      return null;
    }
    final seed = forward ? 0.0 : _releaseSeed;
    final speed = forward ? 0.0 : _landingSpeed;
    _releaseSeed = 0;
    _landingSpeed = 0;
    final landing = !forward && (_departure?.toSource ?? false);
    final simulation = SpringSimulation(
      landing
          ? options.dismissPhysics.landingSpringFor(speed)
          : options.pushSpring,
      controller!.value,
      forward ? 1 : 0,
      // The seed is per unit of the landing, which runs from here to zero.
      -seed * controller!.value,
    );
    _landingSimulation = landing ? simulation : null;
    return simulation;
  }

  /// Where the flight is: the animation's own value, except while a
  /// landing spring is past the source, which the controller reports as
  /// zero.
  double get _flightValue {
    final landing = _landingSimulation;
    final elapsed = controller!.lastElapsedDuration;
    if (landing == null || elapsed == null || !controller!.isAnimating) {
      return animation!.value;
    }
    return math.min(
      landing.x(elapsed.inMicroseconds / Duration.microsecondsPerSecond),
      animation!.value,
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
    // The navigator announces the route underneath after didPush, still
    // before the frame: a push's flight can be prepared now.
    _prepareFlightNowOrLater();
  }

  @override
  TickerFuture didPush() {
    _scheduleFlight(ZoomFlightDirection.push);
    return super.didPush();
  }

  @override
  bool didPop(T? result) {
    if (_departure == null) {
      // A committed dismissal has its flight: the departure it was released
      // from, looked up when it was grabbed.
      _scheduleFlight(ZoomFlightDirection.pop);
    }
    return super.didPop(result);
  }

  @override
  void dispose() {
    _stopUserGesture();
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
      _landingSimulation = null;
    }
  }

  /// Whether an interactive dismissal may begin now: the route is current
  /// and can pop, no other route's gesture holds the navigator, and the
  /// options' predicate agrees. Unlike [popGestureEnabled], a card flying
  /// to full screen does not block it: a gesture begun during the push, or
  /// the return of a cancelled dismissal, takes the card as it flies
  /// (design.md section 3.8). A landing card is not grabbed: the route is
  /// popping and passes its pointers by ([buildTransitions]), as iOS lets a
  /// touch through to the page underneath.
  bool _canBeginDismiss(ZoomGesture gesture, Offset grabPoint) {
    final navigator = this.navigator;
    if (navigator == null ||
        !isCurrent ||
        isFirst ||
        controller!.status == AnimationStatus.reverse ||
        (navigator.userGestureInProgress && !_userGestureInProgress) ||
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
    // A spring settles within a tolerance of its end; read the ends from
    // the status, as ZoomPageTransition does.
    final t = controller!.isCompleted
        ? 1.0
        : controller!.isDismissed
        ? 0.0
        : controller!.value.clamp(0.0, 1.0);
    return _frameAt(
      t,
      screen,
      screenRadii,
      departure: _departure,
      pushing: controller!.status == AnimationStatus.forward,
    );
  }

  /// The card's frame at progress [t] of the flight [departure] describes,
  /// or of the flight line.
  ZoomFrame _frameAt(
    double t,
    Rect screen,
    BorderRadius screenRadii, {
    required ZoomDeparture? departure,
    required bool pushing,
  }) {
    final source = _flightSource;
    if (departure == null) {
      return zoomFlightFrame(
        t: t,
        source: source?.rect ?? ZoomPageTransition.fallbackRectFor(screen),
        screen: screen,
        sourceRadii: source?.radii ?? screenRadii,
        screenRadii: screenRadii,
        pushing: pushing,
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
    if (controller!.isCompleted) {
      // From rest the landing is a new flight: look the source up again,
      // since the tag may have changed while the page was open.
      _prepareFlight(ZoomFlightDirection.pop);
    }
    final resting = _currentFrame(screen, screenRadii);
    // A flight to full screen completes underneath the gesture; a settled
    // page or a landed one has nothing to fly.
    final animation = controller!;
    final departure = _departure;
    final flight = animation.status == AnimationStatus.forward
        ? ZoomFlight(
            spring: departure == null
                ? options.pushSpring
                : options.dismissPhysics.returnSpring,
            velocity: animation.velocity,
            frameAt: (t) => _frameAt(
              t,
              screen,
              screenRadii,
              departure: departure,
              pushing: departure == null,
            ),
          )
        : null;
    _departure = null;
    _dismiss = ZoomDismissController(
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
      onRelease: (departure) {
        _dismiss = null;
        _departure = departure;
        if (departure.toSource) {
          // A landing cannot be grabbed again, so the gesture is over now:
          // every route's modal scope ignores pointers while the navigator
          // reports one, and a touch on the landing card must reach the
          // page underneath.
          _stopUserGesture();
        }
        changedInternalState();
      },
      onCommit: (rate, speed) {
        // The rate over the shrink the landing still has to make.
        final source =
            _flightSource?.rect ?? ZoomPageTransition.fallbackRectFor(screen);
        _releaseSeed = options.dismissPhysics.commitVelocityFor(
          rate: rate,
          remainingScale:
              (_departure!.frame.rect.width - source.width) / screen.width,
        );
        _landingSpeed = speed;
        navigator.pop();
      },
      onSettled: () {
        if (_dismiss != null) {
          // Grabbed again while settling; that gesture settles for both.
          return;
        }
        _stopUserGesture();
        // A committed dismissal has usually disposed the route by now.
        if (this.navigator != null && navigator.mounted) {
          changedInternalState();
        }
      },
      vsync: navigator,
      flight: flight,
    );
    if (!_userGestureInProgress) {
      final controller = this.controller!;
      if (controller.status == AnimationStatus.forward) {
        // Grabbed in flight. A hero flight — a [CupertinoNavigationBar]'s,
        // say — diverts from the push into a pop only if the route reads as
        // reversing, so turn the stopped controller around first: reverse()
        // sets the status, stop() keeps it from moving.
        controller
          ..reverse()
          ..stop();
      }
      _userGestureInProgress = true;
      navigator.didStartUserGesture();
    }
    return _dismiss;
  }

  /// Tells the navigator the user gesture has stopped, once per gesture no
  /// matter how many grabs it took.
  void _stopUserGesture() {
    if (!_userGestureInProgress) {
      return;
    }
    _userGestureInProgress = false;
    final navigator = this.navigator;
    if (navigator != null && navigator.mounted) {
      navigator.didStopUserGesture();
    }
  }

  /// Prepares the flight for a push or pop that has just happened: now if
  /// it came from outside a frame — a tap handler, say — where the route
  /// underneath is laid out and the element tree can be walked, so the
  /// very first frame is a flight frame (a frame late and the card appears
  /// a fifth of the way along, as the parity recordings showed). Otherwise
  /// at the end of the frame, the deferral [HeroController] makes for the
  /// same reason: the tree cannot be walked during a build, which is where
  /// a pages-based [Navigator] pushes and pops. The first frame then draws
  /// nothing (the fallback card at zero opacity) or the previous flight's
  /// card at full screen; neither is visible.
  void _scheduleFlight(ZoomFlightDirection direction) {
    _pendingFlight = direction;
    _prepareFlightNowOrLater();
  }

  void _prepareFlightNowOrLater() {
    final direction = _pendingFlight;
    if (direction == null) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    final outsideFrame =
        phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;
    // A push's route underneath is announced by didChangePrevious, which
    // follows didPush; until then there is nothing to look in.
    if (outsideFrame &&
        (direction == ZoomFlightDirection.pop || _previousRoute != null)) {
      _pendingFlight = null;
      _prepareFlight(direction);
      if (direction == ZoomFlightDirection.pop) {
        changedInternalState();
      }
      return;
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (navigator == null || _pendingFlight != direction) {
        return; // Disposed before the frame ended, or prepared already.
      }
      _pendingFlight = null;
      _prepareFlight(direction);
      changedInternalState();
    }, debugLabel: 'ZoomRouteTransitionMixin.prepareFlight');
  }

  /// Finds the source for [sourceTag] in the route underneath, measures it
  /// for the flight about to start, asks the options which part of the
  /// page aligns with it, and swaps which source is hidden if the tag has
  /// changed. With animations disabled there is no flight, and the source
  /// stays put under the fade.
  void _prepareFlight(ZoomFlightDirection direction) {
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
      _alignmentRect = null;
    } else {
      _flightSource = ZoomFlightSource(
        rect: rect,
        radii: found.borderRadius,
        child: found.flightChild,
      );
      _alignmentRect = options.alignmentRect?.call(
        ZoomAlignmentRectContext(
          sourceRect: rect,
          pageSize: (overlay as RenderBox).size,
          direction: direction,
        ),
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
      onStart: _beginDismiss,
      scrollController: _scrollController,
      child: child,
    );
    final transition = MediaQuery.disableAnimationsOf(context)
        ? FadeTransition(opacity: animation, child: page)
        : ZoomPageTransition(
            animation: _flightProgress,
            source: _flightSource,
            liveFrame: _liveFrame,
            departure: _departure,
            cornerRadii: cornerRadii,
            alignmentRect: _alignmentRect,
            snapshot: options.snapshotDuringTransition,
            child: page,
          );
    // A popping route passes its pointers by — the SDK's modal scope does
    // for the page, and the card and its gesture layer sit outside that —
    // so a touch on a landing card reaches the page underneath, as on iOS,
    // where the source takes the tap and pushes again (parity stage 7).
    return IgnorePointer(
      ignoring: animation.status == AnimationStatus.reverse,
      child: transition,
    );
  }
}

/// The route's animation with a landing's overshoot restored.
///
/// [AnimationController] clamps every simulation value to its bounds, so
/// the controller stops reporting a committed landing the moment it reaches
/// the source; the spring itself carries on a little past it and eases back,
/// as native landings do — 2 % of the flight released at rest, 8 % released
/// on a fast pinch (parity stage 9) — and the route is still the card's to
/// draw until that spring settles and the pop finishes.
class _ZoomFlightProgress extends Animation<double>
    with AnimationWithParentMixin<double> {
  _ZoomFlightProgress(this._route);

  final ZoomRouteTransitionMixin<Object?> _route;

  @override
  Animation<double> get parent => _route.animation!;

  @override
  double get value => _route._flightValue;
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
