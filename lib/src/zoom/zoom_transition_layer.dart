import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'zoom_frame.dart';

/// Draws a page as the card described by a [ZoomFrame].
///
/// The page is laid out once at [pageSize] — the size it has at rest — and
/// scaled to fill the card, so it never reflows during a flight; this is
/// what iOS does. The scale is the larger of the two ratios between the
/// card and the page (aspect fill), anchored at the top centre, so a card
/// narrower than it is tall shows the top of the page at the card's width
/// and a wide, short card shows the page's top strip at full scale.
///
/// With an [alignmentRect], that part of the page is what fills the card
/// at the source end of the flight, and the window widens to the whole page
/// as the card grows to the screen: the window is the rect interpolated
/// toward the page's bounds by how far the card's size is from the source's
/// ([sourceSize]) to the page's.
///
/// [flightChild] is the source's own content, drawn over the page inside the
/// card at [ZoomFrame.sourceOpacity] and fitted to the card the same way, so
/// the two cross-fade as one picture. [sourceSize] is the size it is drawn
/// at before fitting.
///
/// The tree has the same shape at rest and in flight — the clip and the
/// transforms become identities rather than being removed — so the page's
/// element subtree keeps its position and state.
class ZoomTransitionLayer extends StatelessWidget {
  /// Creates a layer drawing [child] inside [frame].
  const ZoomTransitionLayer({
    super.key,
    required this.frame,
    required this.pageSize,
    required this.atRest,
    this.flightChild,
    this.sourceSize,
    this.alignmentRect,
    required this.child,
  });

  /// The card's geometry for this frame.
  final ZoomFrame frame;

  /// The size the page is laid out at, which is its size at rest.
  final Size pageSize;

  /// Whether the route has settled, so the clip can be switched off.
  final bool atRest;

  /// The source's content, drawn over the page while
  /// [ZoomFrame.sourceOpacity] is above zero.
  final Widget? flightChild;

  /// The size [flightChild] is laid out at before it is fitted to the card,
  /// and the card's size at the source end of the flight.
  final Size? sourceSize;

  /// The part of the page, in its own coordinates, that fills the card at
  /// the source end of the flight. Null for the whole page.
  final Rect? alignmentRect;

  /// The page.
  final Widget child;

  /// How far the card's size is from [sourceSize] toward [pageSize], by
  /// the square root of area so a card halfway along a linear flight reads
  /// as about halfway; 1.0 without a source or an [alignmentRect].
  double get _growth {
    final source = sourceSize;
    if (alignmentRect == null || source == null) {
      return 1;
    }
    final from = math.sqrt(source.width * source.height);
    final to = math.sqrt(pageSize.width * pageSize.height);
    if (to - from <= 0) {
      return 1;
    }
    final now = math.sqrt(frame.rect.width * frame.rect.height);
    return ((now - from) / (to - from)).clamp(0.0, 1.0);
  }

  /// The part of the page the card shows this frame.
  Rect get _window {
    final page = Offset.zero & pageSize;
    final alignment = alignmentRect;
    if (alignment == null) {
      return page;
    }
    return Rect.lerp(alignment, page, _growth)!;
  }

  @override
  Widget build(BuildContext context) {
    final rect = frame.rect;
    final window = _window;
    final scale = window.isEmpty
        ? 1.0
        : math.max(rect.width / window.width, rect.height / window.height);
    // The window's top centre on the card's top centre.
    final shift = Offset(
      rect.width / 2 - window.center.dx * scale,
      -window.top * scale,
    );
    final showSource =
        flightChild != null && sourceSize != null && frame.sourceOpacity > 0;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fromRect(
          rect: rect,
          child: Transform.rotate(
            angle: frame.rotation,
            child: ClipRSuperellipse(
              borderRadius: atRest ? BorderRadius.zero : frame.radii,
              clipBehavior: atRest ? Clip.none : Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                clipBehavior: Clip.none,
                children: <Widget>[
                  OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Transform(
                      transform: Matrix4.translationValues(
                        shift.dx,
                        shift.dy,
                        0,
                      )..scaleByDouble(scale, scale, 1, 1),
                      child: SizedBox.fromSize(size: pageSize, child: child),
                    ),
                  ),
                  // A picture of the source, not the source: it neither
                  // takes pointers (a grab mid-flight must reach the page)
                  // nor ticks.
                  if (showSource)
                    IgnorePointer(
                      child: Opacity(
                        opacity: frame.sourceOpacity,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          clipBehavior: Clip.hardEdge,
                          child: SizedBox.fromSize(
                            size: sourceSize,
                            child: flightChild,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
