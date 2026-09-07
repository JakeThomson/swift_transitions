import 'package:flutter/widgets.dart';

/// Marks the widget a zoom route grows out of and shrinks back into.
///
/// The counterpart of SwiftUI's `matchedTransitionSource`. A `ZoomPageRoute`
/// pushed with a matching [tag] measures this widget's frame, draws
/// [flightChild] inside the card as it grows, and hides this widget for as
/// long as the route is on the stack. The slot keeps its size while hidden,
/// so the row or grid around it does not reflow — the same placeholder
/// [Hero] leaves behind during a flight.
///
/// Like [Hero], the tag must be unique among the sources in one route's
/// subtree, and a source inside a nested [Navigator] only takes part when
/// its own route is the current [PageRoute] there.
class ZoomTransitionSource extends StatefulWidget {
  /// Creates a source for a zoom route to grow out of.
  const ZoomTransitionSource({
    super.key,
    required this.tag,
    this.borderRadius = BorderRadius.zero,
    this.flightChild,
    this.enabled = true,
    required this.child,
  });

  /// The identifier a zoom route's `sourceTag` matches against.
  final Object tag;

  /// The corner radius of the source's shape, which the card's corners
  /// interpolate from as it grows and land on as it shrinks back.
  ///
  /// The corners are drawn as a superellipse, matching the display's own
  /// corners at the other end of the flight.
  final BorderRadiusGeometry borderRadius;

  /// What to draw for the source inside the card while it is in flight,
  /// cross-fading with the page. Defaults to [child].
  final Widget? flightChild;

  /// Whether a zoom route may match this source. A disabled source is
  /// skipped as if it were not there, and its route falls back to the
  /// centred scale-and-fade.
  final bool enabled;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  State<ZoomTransitionSource> createState() => ZoomTransitionSourceState();

  /// The enabled source tagged [tag] in the subtree under [context], or null
  /// if there is none.
  ///
  /// Walks the tree the way [Hero] discovers its participants: every source
  /// whose nearest navigator is [navigator] is a candidate, and a source
  /// inside a nested navigator is a candidate only if its own route is the
  /// current [PageRoute] of that navigator.
  static ZoomTransitionSourceState? sourceFor(
    BuildContext context,
    Object tag,
    NavigatorState navigator,
  ) {
    ZoomTransitionSourceState? result;

    void visitor(Element element) {
      final widget = element.widget;
      if (widget is ZoomTransitionSource) {
        if (widget.enabled && widget.tag == tag) {
          final route = ModalRoute.of(element);
          final inScope =
              Navigator.of(element) == navigator ||
              (route != null && route is PageRoute && route.isCurrent);
          if (inScope) {
            assert(
              result == null,
              'There are multiple ZoomTransitionSources that share the tag '
              '$tag within a route subtree. Each tag must be unique within '
              'the subtree of one PageRoute.',
            );
            result =
                (element as StatefulElement).state as ZoomTransitionSourceState;
          }
        }
      }
      element.visitChildren(visitor);
    }

    context.visitChildElements(visitor);
    return result;
  }
}

/// The state of a [ZoomTransitionSource], which a zoom route uses to measure
/// the source and to hide it while the route is on the stack.
class ZoomTransitionSourceState extends State<ZoomTransitionSource> {
  final GlobalKey _key = GlobalKey();
  Size? _placeholderSize;

  /// Whether the source is currently replaced by its placeholder.
  bool get hidden => _placeholderSize != null;

  /// What a zoom route draws for this source inside its card.
  Widget get flightChild => widget.flightChild ?? widget.child;

  /// The source's corner radius resolved for [context]'s text direction.
  BorderRadius get borderRadius =>
      widget.borderRadius.resolve(Directionality.maybeOf(context));

  /// The source's bounding box in the coordinate space of [ancestor]'s
  /// render object, or null if the source has not been laid out.
  Rect? boundsIn(RenderObject ancestor) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) {
      return null;
    }
    return MatrixUtils.transformRect(
      box.getTransformTo(ancestor),
      Offset.zero & box.size,
    );
  }

  /// Replaces the source with a placeholder of its current size, keeping the
  /// child mounted (with its tickers muted) so it resumes where it left off.
  ///
  /// Has no effect if the source is already hidden or not yet laid out.
  void hide() {
    if (hidden || !mounted) {
      return;
    }
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) {
      return;
    }
    setState(() {
      _placeholderSize = box.size;
    });
  }

  /// Shows the source again. Has no effect if it is not hidden.
  void show() {
    if (!hidden) {
      return;
    }
    _placeholderSize = null;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _placeholderSize?.width,
      height: _placeholderSize?.height,
      child: Offstage(
        offstage: hidden,
        child: TickerMode(
          enabled: !hidden,
          child: KeyedSubtree(key: _key, child: widget.child),
        ),
      ),
    );
  }
}
