import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'zoom_interaction.dart';

/// Called when a gesture wants to begin a dismissal at [grabPoint] (in
/// navigator coordinates); returns the controller driving it, or null if the
/// dismissal may not begin.
typedef ZoomDismissStartCallback =
    ZoomDismissController? Function(ZoomGesture gesture, Offset grabPoint);

const double _kEdgeSwipeWidth = 20.0;

/// Installs the pan and edge-swipe dismissal gestures over a zoom route's
/// page.
///
/// Three inputs feed one [ZoomDismissController]: a vertical drag
/// recognizer for pages without a vertical scroll view, the route's
/// [ZoomScrollController] for pages with one (the scroll view wins the
/// arena and hands a top-edge drag across, see [ZoomScrollController]), and
/// a horizontal drag recognizer on the leading edge for the swipe. A
/// translucent [Listener] underneath tracks the raw pointer for the pivot
/// and the sideways chase, and grabs a page that is still being pushed.
class ZoomDismissGestureDetector extends StatefulWidget {
  /// Creates the dismissal gesture layer.
  const ZoomDismissGestureDetector({
    super.key,
    required this.pan,
    required this.edgeSwipe,
    required this.isPushing,
    required this.onStart,
    required this.scrollController,
    required this.child,
  });

  /// Whether a downward drag may dismiss.
  final bool pan;

  /// Whether a drag from the leading edge may dismiss.
  final bool edgeSwipe;

  /// Whether the route's push is still running, so that a pointer down
  /// grabs the card in flight.
  final ValueGetter<bool> isPushing;

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
  late final HorizontalDragGestureRecognizer _edgeRecognizer;

  /// Whether the live gesture is being driven by raw pointer movement,
  /// which is how an interrupted push is grabbed before any recognizer has
  /// resolved.
  bool _pointerDriven = false;
  Offset? _lastPointer;

  @override
  void initState() {
    super.initState();
    // Started from the pointer-down position, so the card takes up the
    // slop distance rather than losing it: direct manipulation from the
    // first pixel.
    _panRecognizer = VerticalDragGestureRecognizer(debugOwner: this)
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = _handlePanStart
      ..onUpdate = _handlePanUpdate
      ..onEnd = _handlePanEnd
      ..onCancel = _handleCancel;
    _edgeRecognizer = HorizontalDragGestureRecognizer(debugOwner: this)
      ..dragStartBehavior = DragStartBehavior.down
      ..onStart = _handleEdgeStart
      ..onUpdate = _handleEdgeUpdate
      ..onEnd = _handleEdgeEnd
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

  void _handlePanUpdate(DragUpdateDetails details) {
    _controller?.dragUpdate(details.primaryDelta!);
  }

  void _handlePanEnd(DragEndDetails details) {
    _end(details.velocity.pixelsPerSecond.dy);
  }

  void _handleEdgeUpdate(DragUpdateDetails details) {
    _controller?.dragUpdate(_toLogical(details.primaryDelta!));
  }

  void _handleEdgeEnd(DragEndDetails details) {
    _end(_toLogical(details.velocity.pixelsPerSecond.dx));
  }

  void _handleCancel() {
    _end(0);
  }

  /// A scroll view at its top edge is handing a downward drag across. The
  /// dismissal begins on the first such delta, not when the drag started,
  /// so an ordinary scroll never counts as a navigator gesture.
  void _handleScrollDragUpdate(double delta) {
    if (_controller == null && !_pointerDriven) {
      final pointer = _lastPointer;
      if (pointer == null || !_begin(ZoomGesture.pan, pointer)) {
        return;
      }
    }
    _controller?.dragUpdate(delta);
  }

  void _handleScrollDragEnd(double velocity) {
    _end(-velocity);
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
  void dispose() {
    _panRecognizer.dispose();
    _edgeRecognizer.dispose();
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
    final controller = widget.onStart(gesture, _toNavigator(global));
    if (controller == null) {
      return false;
    }
    _controller = controller;
    return true;
  }

  void _handlePanStart(DragStartDetails details) {
    if (_pointerDriven) {
      return;
    }
    _begin(ZoomGesture.pan, details.globalPosition);
  }

  void _handleEdgeStart(DragStartDetails details) {
    if (_pointerDriven) {
      return;
    }
    _begin(ZoomGesture.edgeSwipe, details.globalPosition);
  }

  void _end(double velocity) {
    final controller = _controller;
    _controller = null;
    _pointerDriven = false;
    controller?.dragEnd(velocity);
    if (controller != null) {
      // Disposed after the settle: the ticker only drives the sideways
      // chase, which has already been retargeted home by dragEnd.
      controller.dispose();
    }
  }

  void _handlePointerDown(PointerDownEvent event) {
    _lastPointer = event.position;
    if (widget.pan) {
      _panRecognizer.addPointer(event);
    }
    if (widget.isPushing() && widget.pan && _controller == null) {
      // Grab the card in flight: the push completes into a gesture rather
      // than being cancelled. Driven from raw pointer movement, since no
      // recognizer has resolved yet.
      if (_begin(ZoomGesture.pan, event.position)) {
        _pointerDriven = true;
      }
    }
  }

  void _handleEdgePointerDown(PointerDownEvent event) {
    _lastPointer = event.position;
    if (widget.edgeSwipe) {
      _edgeRecognizer.addPointer(event);
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _lastPointer = event.position;
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (_pointerDriven) {
      controller.dragUpdate(event.delta.dy);
    }
    controller.pointerMoved(_toNavigator(event.position));
  }

  void _handlePointerUp(PointerEvent event) {
    if (_pointerDriven) {
      _end(0);
    }
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
/// (or the card is already dragged) and scrolls otherwise.
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
    if (!_listShouldScroll && (delta > 0 || controller.isCardDragged())) {
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
    return super.drag(details, dragCancelCallback);
  }
}
