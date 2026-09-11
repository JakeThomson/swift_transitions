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
/// With a [pageRect] the page is not fitted to the card but drawn at that
/// rect — an aligned flight's page, scaled as one picture behind the card
/// and carried so that its art lands on the source ([zoomAlignedPageRect]);
/// the card clips it as it clips any page.
///
/// [flightChild] is the source's own content, laid out at [sourceSize] and
/// drawn over the page inside the card at [ZoomFrame.sourceOpacity], so the
/// two cross-fade as one picture. It fills the card, or with an
/// [alignmentRect] sits at the top left of that part of the page, carried
/// by the page's own transform and scaled with it, at the source's own
/// aspect — natively the picture of a 16:9 still over a 4:3 art is 16:9,
/// neither stretched nor cropped — so it lands on the source exactly.
///
/// [pageOpacity] fades the page the way an aligned page fades natively:
/// out, linearly with the flight, as the card shrinks to its source —
/// everywhere but over its art, which natively stays solid while the
/// source's picture fades in on top of it and covers it well before the
/// landing. With an [alignmentRect] and a [pageRect] the picture is drawn
/// twice: opaque under the page, so the art never thins to the page
/// underneath, and over it at [ZoomFrame.sourceOpacity] (parity stage 3,
/// aligned: the art reads its own colour at every frame while the
/// paragraph beside it is half gone, and the still's label is white by
/// 0.7 of the way).
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
    this.pageRect,
    this.pageOpacity = 1,
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

  /// The part of the page, in its own coordinates, that [flightChild] is
  /// drawn over. Null for the whole page.
  final Rect? alignmentRect;

  /// Where the page is drawn, in the card's parent's coordinates, or null
  /// for the page fitted to the card.
  final Rect? pageRect;

  /// The page's opacity, 1.0 at rest.
  final double pageOpacity;

  /// The page.
  final Widget child;

  // The card's shadow, from the luminance beside and below a native card at
  // mid-flight (parity stage 3): about 10 % darker 4 pt out, 3 % at 20 pt,
  // gone by 40 pt, a little stronger below than beside. A Gaussian of
  // σ ≈ 18 pt at this alpha, offset 4 pt down, reproduces that profile.
  static const double _shadowAlpha = 0.24;
  static const Offset _shadowOffset = Offset(0, 4);
  static const double _shadowBlurRadius = 30;
  // The last of the flight over which the shadow fades away. A native card
  // landing on its source casts none: the page 12 and 20 pt beside it reads
  // its own colour from a twentieth of the flight in, where ours was 5.3 %
  // and 2.8 % darker until the pop took the card away (parity stage 9).
  static const double _shadowFadeWindow = 0.1;

  /// How much of the shadow the card carries this frame: all of it for
  /// most of the flight, fading out over [_shadowFadeWindow], and with the
  /// page when that fades. 1.0 without a source, whose fallback card never
  /// reaches one.
  double get _shadowFade {
    final source = sourceSize;
    if (source == null || pageSize.width - source.width <= 0) {
      return pageOpacity;
    }
    final along =
        (frame.rect.width - source.width) / (pageSize.width - source.width);
    return (along / _shadowFadeWindow).clamp(0.0, 1.0) * pageOpacity;
  }

  @override
  Widget build(BuildContext context) {
    final rect = frame.rect;
    final page = pageRect;
    final double scale;
    final Offset shift;
    if (page != null && !pageSize.isEmpty) {
      scale = page.width / pageSize.width;
      shift = page.topLeft - rect.topLeft;
    } else {
      scale = pageSize.isEmpty
          ? 1.0
          : math.max(
              rect.width / pageSize.width,
              rect.height / pageSize.height,
            );
      // The page's top centre on the card's top centre.
      shift = Offset(rect.width / 2 - pageSize.width / 2 * scale, 0);
    }
    final showSource =
        flightChild != null && sourceSize != null && frame.sourceOpacity > 0;
    // An aligned page in flight keeps its art solid: the picture under it.
    final solidArt =
        alignmentRect != null &&
        pageRect != null &&
        flightChild != null &&
        sourceSize != null &&
        !atRest;
    // Where the source's picture goes: over the art it is a preview of,
    // carried by the page's own transform, or over the whole card.
    final alignment = alignmentRect;
    final source = sourceSize;
    final Rect picture;
    if (alignment == null || source == null) {
      picture = Offset.zero & rect.size;
    } else {
      // The source's own size, scaled as the page is relative to its
      // landing scale: at the source end the picture is the source.
      picture = zoomAlignedPictureRect(
        pageRect: (shift + rect.topLeft) & (pageSize * scale),
        alignment: alignment,
        pageSize: pageSize,
        sourceSize: source,
      ).shift(-rect.topLeft);
    }
    // A picture of the source, not the source: it neither takes pointers
    // (a grab mid-flight must reach the page) nor ticks. Its slot is
    // always in the stack, empty when there is nothing to show, so the
    // stack has the same children at rest and in flight and the page
    // between them keeps its element and state.
    Widget copy(double opacity, {required bool shown}) => Positioned.fromRect(
      rect: picture,
      child: !shown
          ? const SizedBox.shrink()
          : IgnorePointer(
              child: Opacity(
                opacity: opacity,
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
    );
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned.fromRect(
          rect: rect,
          child: Transform.rotate(
            angle: frame.rotation,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: RoundedSuperellipseBorder(
                  borderRadius: atRest ? BorderRadius.zero : frame.radii,
                ),
                shadows: <BoxShadow>[
                  if (!atRest && _shadowFade > 0)
                    BoxShadow(
                      color: const Color(
                        0xFF000000,
                      ).withValues(alpha: _shadowAlpha * _shadowFade),
                      offset: _shadowOffset,
                      blurRadius: _shadowBlurRadius,
                    ),
                ],
              ),
              child: ClipRSuperellipse(
                borderRadius: atRest ? BorderRadius.zero : frame.radii,
                clipBehavior: atRest ? Clip.none : Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    copy(1, shown: solidArt),
                    Opacity(
                      opacity: pageOpacity,
                      child: OverflowBox(
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
                          child: SizedBox.fromSize(
                            size: pageSize,
                            child: child,
                          ),
                        ),
                      ),
                    ),
                    copy(frame.sourceOpacity, shown: showSource),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
