import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../gestures/release_velocity.dart';
import '../page/back_gesture.dart';
import 'zoom_interaction.dart';

/// Called when a gesture wants to begin a dismissal at [grabPoint] (in
/// navigator coordinates); returns the controller driving it, or null if the
/// dismissal may not begin. [swipeRegion] is where a back swipe began —
/// the leading edge, or anywhere else — which sets its commit line.
typedef ZoomDismissStartCallback =
    ZoomDismissController? Function(
      ZoomGesture gesture,
      Offset grabPoint, {
      required BackGestureRegion swipeRegion,
    });

const double _kEdgeSwipeWidth = 20.0;

/// How far a back swipe travels before the card moves. From the leading
/// edge, the same 12 pt as the push's page: UIKit's edge recognizer holds
/// the page still for that long (parity stage 2), and the zoom page's card
/// behaves the same way (stage 5). From anywhere else, the platform's slop,
/// as the pan: the native card shrank from 18 ± 4 pt of travel whether the
/// touch was a quarter, a half or three quarters of the way across (stage
/// 10) — not the 27 pt the push's page waits for. The finger then leads
/// the card by this much for the rest of the gesture.
double _swipeDeadZone(BackGestureRegion region) => switch (region) {
  BackGestureRegion.leadingEdge => 12.0,
  BackGestureRegion.anywhere => kTouchSlop,
};

/// How far a pan travels before the card moves: the native card holds
/// still for the first 16–20 pt of a drag (parity stage 4), the platform's
/// slop. Waited out here rather than through the recognizer's own slop,
/// because a recognizer alone in its arena wins at the touch and sees
/// every move from the first pixel.
const double _kPanDeadZone = kTouchSlop;

/// How far two fingers' distance changes before a pinch takes the card:
/// natively the card held its size until the fingers had closed 8.7 pt
/// (parity stage 6), half the slop, and scaled from that distance on.
const double _kPinchDeadZone = kTouchSlop / 2;

/// Installs the dismissal gestures over a zoom route's page.
///
/// Three inputs feed one [ZoomDismissController]: a vertical drag
/// recognizer for pages without a vertical scroll view, the route's
/// [ZoomScrollController] for pages with one (the scroll view wins the
/// arena and hands a top-edge drag across, see [ZoomScrollController]), and
/// a horizontal drag recognizer for the back swipe — on the leading edge,
/// or over the whole page. An opaque [Listener] underneath tracks the raw
/// pointers for the pivot and the sideways chase, grabs a page that is
/// still being pushed, and drives the pinch.
///
/// The page is the [Listener]'s child, so the page's own recognizers enter
/// the arena first: a horizontal scrollable on the page takes the drags it
/// wants ahead of a back swipe from anywhere, as it does natively. The
/// leading-edge strip lies over the page instead, and a swipe begun there
/// is the edge swipe, which wins over the scrollable as the SDK's does.
///
/// The pinch is read from the raw pointers rather than from a
/// [ScaleGestureRecognizer], because a scroll view accepts a finger as soon
/// as it passes the touch slop, before a second finger usually lands, and
/// a recognizer that lost that arena stops tracking the finger. The
/// [Listener] sees every finger regardless; when the second one lands the
/// scroll view's live drag is cancelled through [ZoomScrollController],
/// the mechanism the SDK's sheet keeps for the same handover, and the
/// scroll view then ignores the rest of the drag.
class ZoomDismissGestureDetector extends StatefulWidget {
  /// Creates the dismissal gesture layer.
  const ZoomDismissGestureDetector({
    super.key,
    required this.pan,
    required this.backSwipe,
    required this.backGestureRegion,
    required this.pinch,
    required this.onStart,
    required this.scrollController,
    required this.child,
  });

  /// Whether a downward drag may dismiss.
  final bool pan;

  /// Whether a back swipe may dismiss.
  final bool backSwipe;

  /// Where the back swipe may start.
  final BackGestureRegion backGestureRegion;

  /// Whether a two-finger pinch may dismiss.
  final bool pinch;

  /// Starts a dismissal, or refuses it.
  final ZoomDismissStartCallback onStart;

  /// The route's scroll controller, whose positions hand drags across.
  final ZoomScrollController scrollController;

  /// The page.
  final Widget child;

  @override
  State<ZoomDismissGestureDetector> createState() =>
      _ZoomDismissGestureDetectorState();
}

class _ZoomDismissGestureDetectorState
    extends State<ZoomDismissGestureDetector> {
  ZoomDismissController? _controller;
  late final VerticalDragGestureRecognizer _panRecognizer;
  late final HorizontalDragGestureRecognizer _swipeRecognizer;

  /// How far the live back swipe has travelled, for the dead zone, and
  /// where it went down.
  double _swipeDragged = 0;
  Offset _swipeDown = Offset.zero;

  /// A back swipe from anywhere begins only once its first move is known
  /// to run toward the trailing edge; one that opens the other way is left
  /// alone for the rest of the touch.
  bool _swipeAwaitingDirection = false;

  /// Where the swipe's touch went down — the edge strip, or the page — and
  /// which pointer the swipe recognizer was given, so the layer around
  /// the page does not hand it the one the strip already has.
  BackGestureRegion _swipeRegion = BackGestureRegion.leadingEdge;
  int? _swipePointer;

  /// The finger a pan may start from: which it is, where it went down and
  /// where it is now, and how far the live pan has travelled, for its dead
  /// zone. The card shrinks about the touch point, not about where the
  /// dead zone ends. A second finger is the pinch's and leaves these
  /// alone, so a pan whose pinch never begins carries on from where it is.
  int? _panPointer;

  /// The finger's own motion, which a drag recognizer's estimate cannot be
  /// relied on for ([ReleaseVelocity]).
  final ReleaseVelocity _release = ReleaseVelocity();
  Offset _released = Offset.zero;
  Offset _panDown = Offset.zero;
  Offset _lastPointer = Offset.zero;
  double _panDragged = 0;

  /// Every finger on the page, by pointer id, in navigator coordinates.
  final Map<int, Offset> _pointers = <int, Offset>{};

  /// The two fingers of a pinch, or null, and their distance when the
  /// second landed: the pinch waits out its dead zone before it begins.
  (int, int)? _pinchPointers;
  double _pinchDistanceAtDown = 0;
  bool _pinchBegun = false;

  /// The window's size when last built, and whether the fingers down now
  /// were let go of: a held card is released when the size changes, as
  /// iOS lets go when the device turns, and the rest of that touch is not
  /// a new grab.
  Size? _size;
  bool _letGo = false;

  @override
  void initState() {
    super.initState();
    // Started from the pointer-down position: the dead zone is counted
    // from the touch, and the scroll handoff's slop is its own.
    _panRecognizer = VerticalDragGestureRecognizer(debugOwner: this)
      ..dragStartBehavior = DragStartBehavior.down
      ..velocityTrackerBuilder = _iosVelocityTracker
      ..onStart = _handlePanStart
      ..onUpdate = _handlePanUpdate
      ..onEnd = _handlePanEnd
      ..onCancel = _handleCancel;
    _swipeRecognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..dragStartBehavior = DragStartBehavior.down
      ..velocityTrackerBuilder = _iosVelocityTracker
      ..onStart = _handleSwipeStart
      ..onUpdate = _handleSwipeUpdate
      ..onEnd = _handleSwipeEnd
      ..onCancel = _handleCancel;
    _attachScrollController(widget.scrollController);
  }

  void _attachScrollController(ZoomScrollController controller) {
    controller
      ..onDragUpdate = _handleScrollDragUpdate
      ..onDragEnd = _handleScrollDragEnd
      ..isCardDragged = () => _controller?.isDragged ?? false;
  }

  void _detachScrollController(ZoomScrollController controller) {
    controller
      ..onDragUpdate = null
      ..onDragEnd = null
      ..isCardDragged = () => false;
  }

  /// Feeds the pan past its dead zone. Travel back up through the dead
  /// zone counts against it again, so a card dragged down and back up
  /// returns to rest where the finger started.
  void _handlePanUpdate(DragUpdateDetails details) {
    if (_letGo) {
      return;
    }
    final before = _panDragged;
    // From the global positions: the recognizer's delta is in the page's
    // own coordinates, which a card in flight scales.
    _panDragged = details.globalPosition.dy - _panDown.dy;
    if (_panDragged <= _kPanDeadZone && before <= _kPanDeadZone) {
      return;
    }
    if (_controller == null && !_begin(ZoomGesture.pan, _panDown)) {
      return;
    }
    _controller?.dragUpdate(
      math.max(_panDragged, _kPanDeadZone) - math.max(before, _kPanDeadZone),
    );
  }

  void _handlePanEnd(DragEndDetails details) {
    _endDrag(
      _release.reported(details.velocity.pixelsPerSecond.dy, _released.dy),
      cross: _released.dx,
    );
  }

  /// A back swipe's controller is fed from here rather than from the raw
  /// pointer stream, which runs ahead of the recognizer and would see the
  /// dead zone a move late.
  void _handleSwipeUpdate(DragUpdateDetails details) {
    if (_letGo) {
      return;
    }
    final before = _swipeDragged;
    _swipeDragged = _toLogical(details.globalPosition.dx - _swipeDown.dx);
    if (_swipeAwaitingDirection) {
      _swipeAwaitingDirection = false;
      if (_swipeDragged > 0) {
        _begin(ZoomGesture.backSwipe, _swipeDown);
      }
    }
    final deadZone = _swipeDeadZone(_swipeRegion);
    if (_swipeDragged <= deadZone) {
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (before <= deadZone) {
      // Leaving the dead zone: the chase anchors where it ends, not at the
      // first move seen past it.
      controller.pointerMoved(
        _toNavigator(_swipeDown + Offset(_toLogical(deadZone), 0)),
      );
    }
    // The part of this delta past the dead zone.
    controller
      ..dragUpdate(_swipeDragged - math.max(before, deadZone))
      ..pointerMoved(_toNavigator(details.globalPosition));
  }

  void _handleSwipeEnd(DragEndDetails details) {
    _endDrag(
      _toLogical(
        _release.reported(details.velocity.pixelsPerSecond.dx, _released.dx),
      ),
      cross: _released.dy,
    );
  }

  void _handleCancel() {
    _endDrag(0);
  }

  /// A one-finger recognizer letting go of the gesture. Nothing to a pinch,
  /// whose fingers' lift ends it: a scroll view winning the first finger's
  /// arena cancels the pan recognizer just as the second finger lands.
  void _endDrag(double velocity, {double cross = 0}) {
    if (_pinchPointers != null) {
      return;
    }
    _end(velocity, cross);
  }

  /// A scroll view at its top edge is handing a downward drag across. The
  /// dismissal begins on the first such delta, not when the drag started,
  /// so an ordinary scroll never counts as a navigator gesture.
  void _handleScrollDragUpdate(double delta) {
    if (_controller == null) {
      if (!_begin(ZoomGesture.pan, _panDown)) {
        return;
      }
      // The scroll view kept its slop, and its physics' motion threshold
      // the first few pixels after it; the card counts its dead zone from
      // the touch, as the pan does, so the first delta catches up.
      final travelled = _lastPointer.dy - _panDown.dy;
      _controller?.dragUpdate(math.max(0, travelled - _kPanDeadZone - delta));
    }
    _controller?.dragUpdate(delta);
  }

  void _handleScrollDragEnd(double velocity) {
    _endDrag(-velocity);
  }

  @override
  void didUpdateWidget(covariant ZoomDismissGestureDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      _detachScrollController(oldWidget.scrollController);
      _attachScrollController(widget.scrollController);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    if (_controller != null && _size != null && size != _size) {
      // A release at rest: the card lands or returns from where it is.
      // After this build, since the release publishes a frame.
      _letGo = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _letGo) {
          _end(0);
        }
      });
    }
    _size = size;
  }

  @override
  void dispose() {
    _panRecognizer.dispose();
    _swipeRecognizer.dispose();
    _detachScrollController(widget.scrollController);
    final controller = _controller;
    if (controller != null) {
      _controller = null;
      // The page is going away under a live gesture: let the route settle
      // itself, and tell the navigator once the frame is over — unless the
      // navigator went with it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (controller.navigator.mounted) {
          controller.dragEnd(0);
        }
        controller.dispose();
      });
    }
    super.dispose();
  }

  Offset _toNavigator(Offset global) {
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    return overlay.globalToLocal(global);
  }

  double _toLogical(double dx) => switch (Directionality.of(context)) {
    TextDirection.rtl => -dx,
    TextDirection.ltr => dx,
  };

  bool _begin(ZoomGesture gesture, Offset global) {
    if (_controller != null) {
      return true;
    }
    final controller = widget.onStart(
      gesture,
      _toNavigator(global),
      swipeRegion: _swipeRegion,
    );
    if (controller == null) {
      return false;
    }
    _controller = controller;
    return true;
  }

  /// Nothing begins here: a lone recognizer wins the arena on the pointer
  /// down, and a finger that has not dragged is no gesture to the navigator
  /// or to a card in flight. The pan begins as it leaves its dead zone.
  /// iOS's own estimate of the speed a finger left at, which the back
  /// swipe and a `Scrollable` on iOS use for the same reason: the default
  /// least-squares tracker reads a flick at a third to a half of the speed
  /// the finger was really moving (parity stage 2).
  static VelocityTracker _iosVelocityTracker(PointerEvent event) =>
      IOSScrollViewFlingVelocityTracker(event.kind);

  void _handlePanStart(DragStartDetails details) {
    _panDragged = 0;
  }

  void _handleSwipeStart(DragStartDetails details) {
    _swipeDragged = 0;
    _swipeDown = details.globalPosition;
    switch (_swipeRegion) {
      case BackGestureRegion.leadingEdge:
        _begin(ZoomGesture.backSwipe, details.globalPosition);
      case BackGestureRegion.anywhere:
        _swipeAwaitingDirection = true;
    }
  }

  void _end(double velocity, [double cross = 0]) {
    final controller = _controller;
    _controller = null;
    _pinchPointers = null;
    _pinchBegun = false;
    _swipeAwaitingDirection = false;
    controller?.dragEnd(velocity, crossVelocity: cross);
    if (controller != null) {
      // Disposed after the settle: the ticker only drives the sideways
      // chase, which has already been retargeted home by dragEnd.
      controller.dispose();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_pointers.isEmpty) {
      _panPointer = event.pointer;
      _panDown = event.position;
      _lastPointer = event.position;
      _release.reset();
      _released = Offset.zero;
    }
    _pointers[event.pointer] = _toNavigator(event.position);
    if (widget.pinch && _pointers.length == 2 && _pinchPointers == null) {
      final ids = _pointers.keys.toList();
      _pinchPointers = (ids[0], ids[1]);
      _pinchDistanceAtDown = _pinchDistance;
      return;
    }
    // A finger on a flying card is nothing until a recognizer resolves: the
    // native card flies on under a touch, and a drag begun on the way takes
    // it as it flies.
    if (widget.pan) {
      _panRecognizer.addPointer(event);
    }
    if (widget.backSwipe &&
        widget.backGestureRegion == BackGestureRegion.anywhere &&
        event.pointer != _swipePointer) {
      _swipePointer = event.pointer;
      _swipeRegion = BackGestureRegion.anywhere;
      _swipeRecognizer.addPointer(event);
    }
  }

  /// The strip is hit before the layer around the page, so a touch on it
  /// is the edge swipe by the time the layer sees it.
  void _handleEdgePointerDown(PointerDownEvent event) {
    if (widget.backSwipe) {
      _swipePointer = event.pointer;
      _swipeRegion = BackGestureRegion.leadingEdge;
      _swipeRecognizer.addPointer(event);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (event.pointer == _panPointer) {
      _lastPointer = event.position;
      _release.add(event.timeStamp, event.position);
    }
    final position = _toNavigator(event.position);
    _pointers[event.pointer] = position;
    final pinch = _pinchPointers;
    if (pinch != null && _pinchBegun) {
      if (event.pointer == pinch.$1 || event.pointer == pinch.$2) {
        _controller?.pinchUpdate(
          _pointers[pinch.$1]!,
          _pointers[pinch.$2]!,
          event.timeStamp,
        );
      }
      return;
    }
    if (pinch != null &&
        !_letGo &&
        (_pinchDistance - _pinchDistanceAtDown).abs() >= _kPinchDeadZone) {
      // Out of the dead zone: whatever the first finger was doing gives way.
      _beginPinch(event.timeStamp);
      return;
    }
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (controller.gesture == ZoomGesture.backSwipe) {
      return;
    }
    controller.pointerMoved(position);
  }

  void _handlePointerUp(PointerEvent event) {
    if (event.pointer == _panPointer) {
      // Before the recognizers' own callbacks, so a release has the
      // finger's motion by the time the gesture ends.
      _released = _release.at(event.timeStamp);
    }
    _pointers.remove(event.pointer);
    if (event.pointer == _panPointer) {
      _panPointer = null;
    }
    if (event.pointer == _swipePointer) {
      _swipePointer = null;
    }
    if (_pointers.isEmpty) {
      _letGo = false;
    }
    final pinch = _pinchPointers;
    if (pinch != null) {
      if (event.pointer == pinch.$1 || event.pointer == pinch.$2) {
        if (_pinchBegun) {
          _end(_controller?.pinchReleaseVelocity ?? 0);
        } else {
          // A finger lifted inside the dead zone: no pinch after all.
          _pinchPointers = null;
        }
      }
      return;
    }
  }

  /// The fingers of a waiting pinch, apart.
  double get _pinchDistance {
    final (a, b) = _pinchPointers!;
    return (_pointers[b]! - _pointers[a]!).distance;
  }

  /// The pinch is out of its dead zone: the live gesture, or a new one,
  /// becomes a pinch anchored on the fingers as they are now, and any
  /// scroll view drag lets go of its finger.
  void _beginPinch(Duration timeStamp) {
    final (a, b) = _pinchPointers!;
    final first = _pointers[a]!;
    final second = _pointers[b]!;
    if (_controller == null) {
      final controller = widget.onStart(
        ZoomGesture.pinch,
        (first + second) / 2,
        swipeRegion: _swipeRegion,
      );
      if (controller == null) {
        _pinchPointers = null;
        return;
      }
      _controller = controller;
    }
    _pinchBegun = true;
    widget.scrollController.cancelDrag();
    // Anchored where the dead zone ends, not at the first move seen past
    // it, so the card scales from there.
    final distance = (second - first).distance;
    final anchored =
        _pinchDistanceAtDown +
        (distance < _pinchDistanceAtDown ? -_kPinchDeadZone : _kPinchDeadZone);
    final focal = (first + second) / 2;
    final half = (second - first) * (anchored / distance / 2);
    _controller!
      ..beginPinch(focal - half, focal + half, timeStamp)
      ..pinchUpdate(first, second, timeStamp);
  }

  @override
  Widget build(BuildContext context) {
    assert(
      debugCheckHasDirectionality(context),
      'ZoomDismissGestureDetector needs a Directionality',
    );
    final edgeWidth = switch (Directionality.of(context)) {
      TextDirection.rtl => MediaQuery.paddingOf(context).right,
      TextDirection.ltr => MediaQuery.paddingOf(context).left,
    };
    // Opaque: the page absorbs pointers within its bounds, as a scaffold
    // would, so a tap on empty page area does not fall through to the modal
    // barrier and put its tap recognizer into the arena.
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerUp,
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          widget.child,
          PositionedDirectional(
            start: 0,
            width: math.max(edgeWidth, _kEdgeSwipeWidth),
            top: 0,
            bottom: 0,
            child: Listener(
              onPointerDown: _handleEdgePointerDown,
              behavior: HitTestBehavior.translucent,
            ),
          ),
        ],
      ),
    );
  }
}

/// The scroll controller a zoom route installs as its page's
/// [PrimaryScrollController], so a vertical scroll view on the page hands a
/// downward drag at its top edge to the dismissal — and hands the release
/// velocity across too — without any change to the page.
///
/// The mechanism is the SDK's `CupertinoSheetRoute` one: the position
/// diverts `applyUserOffset` to the dismissal while the list is at its top
/// (or the card is already dragged) and scrolls otherwise — but only for a
/// drag that began at the top. A drag that begins on a scrolled list
/// scrolls it to the top and over-scrolls there, as the native page does
/// (parity stage 4); it never becomes a dismissal.
class ZoomScrollController extends ScrollController {
  /// Creates the scroll controller for a zoom route's page.
  ZoomScrollController({super.initialScrollOffset, super.debugLabel});

  /// Called with each drag delta the scroll view hands across: downward
  /// deltas at its top edge, and every delta while the card is dragged.
  ValueChanged<double>? onDragUpdate;

  /// Called with the scroll velocity (negative for a downward fling) when a
  /// drag the scroll view handed across is released; zero when the scroll
  /// view kept the release for itself.
  ValueChanged<double>? onDragEnd;

  /// Whether the card has been dragged away from rest, so the drag keeps
  /// feeding the dismissal (an upward delta grows the card back) instead of
  /// scrolling the list.
  ValueGetter<bool> isCardDragged = () => false;

  /// Makes every attached scroll view let go of a drag in progress, so a
  /// pinch can take its finger over. The scroll view keeps receiving the
  /// drag's updates but no longer applies them.
  void cancelDrag() {
    for (final position in positions) {
      if (position is _ZoomScrollPosition) {
        position.cancelDrag();
      }
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _ZoomScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      controller: this,
    );
  }
}

/// Ported from the SDK's private `_CupertinoSheetScrollPosition`
/// (`cupertino/sheet.dart`), itself a modified
/// `_DraggableScrollableSheetScrollPosition`.
class _ZoomScrollPosition extends ScrollPositionWithSingleContext {
  _ZoomScrollPosition({
    required super.physics,
    required super.context,
    super.oldPosition,
    required this.controller,
  });

  final ZoomScrollController controller;
  VoidCallback? _dragCancelCallback;

  /// Whether the live drag began with the list at its top, the only kind
  /// that can hand across.
  bool _dragFromTop = false;

  bool get _listShouldScroll => pixels > 0.0;

  @override
  void absorb(ScrollPosition other) {
    super.absorb(other);
    assert(_dragCancelCallback == null, 'absorbed mid-drag');
    if (other is _ZoomScrollPosition && other._dragCancelCallback != null) {
      _dragCancelCallback = other._dragCancelCallback;
      other._dragCancelCallback = null;
    }
  }

  @override
  void applyUserOffset(double delta) {
    if (_dragFromTop &&
        !_listShouldScroll &&
        (delta > 0 || controller.isCardDragged())) {
      controller.onDragUpdate?.call(delta);
    } else {
      super.applyUserOffset(delta);
    }
  }

  @override
  void goBallistic(double velocity) {
    if (velocity == 0.0 ||
        (velocity < 0.0 && _listShouldScroll) ||
        (velocity > 0.0 && pixels != maxScrollExtent)) {
      controller.onDragEnd?.call(0);
      super.goBallistic(velocity);
      return;
    }
    _dragCancelCallback?.call();
    _dragCancelCallback = null;
    if (velocity < 0.0 && !_listShouldScroll) {
      controller.onDragEnd?.call(velocity);
      super.goBallistic(0);
      return;
    }
    controller.onDragEnd?.call(0);
    super.goBallistic(velocity);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    _dragCancelCallback = dragCancelCallback;
    _dragFromTop = !_listShouldScroll;
    return super.drag(details, dragCancelCallback);
  }

  /// Ends the drag activity without handing anything to the dismissal.
  void cancelDrag() {
    if (_dragCancelCallback == null) {
      return;
    }
    _dragCancelCallback?.call();
    _dragCancelCallback = null;
    super.goBallistic(0);
  }
}
