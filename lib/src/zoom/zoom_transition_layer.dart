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

  /// The size [flightChild] is laid out at before it is fitted to the card.
  final Size? sourceSize;

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final rect = frame.rect;
    final scale = pageSize.isEmpty
        ? 1.0
        : math.max(rect.width / pageSize.width, rect.height / pageSize.height);
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
                    alignment: Alignment.topCenter,
                    minWidth: 0,
                    maxWidth: double.infinity,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: Transform.scale(
                      scale: scale,
                      alignment: Alignment.topCenter,
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
