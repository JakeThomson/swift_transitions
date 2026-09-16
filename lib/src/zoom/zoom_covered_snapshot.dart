import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'zoom_transition_source.dart';

/// Paints its child from a snapshot while [enabled]: the child as it is
/// on the first frame the snapshot is asked for, a margin wider than the
/// child on every side so that whatever it paints past its bounds is kept.
///
/// The child is the page a zoom route covers. It is painted once, on the
/// first covered frame, into a layer of its own, the way [SnapshotWidget]
/// paints it, and not again for as long as it is covered: whatever the
/// page does in response to being covered a frame on — chrome it hides,
/// glass it lets go of, content it rebuilds — stays out of the picture,
/// and the page costs nothing to draw under the flight. UIKit shows a
/// snapshot of the zoomed-from view controller in the same way. The layer
/// is kept, not just the picture: a source hidden for the flight
/// ([ZoomTransitionSource]) after that frame — a route pushed by a pages
/// navigator hides its source at the end of the covering frame — has its
/// own layer ([RenderZoomSourceBoundary]) lifted out, and the picture is
/// rasterised again without it.
///
/// [SnapshotWidget] captures exactly the child's size, which would cut a
/// page off at its edge: the strip the covered page's scale uncovers is
/// filled natively by whatever the page draws past its bounds — an
/// unclipped `scaledToFill` image, a card row the scroll view lets overflow
/// (parity stage 9) — and a page scaled live does the same here, so the
/// snapshot has to as well. The margin is [bleed] of the child's size on
/// each side, and a point over so that rounding cannot leave a hairline at
/// the screen's edge. It is the cull rect of the paint, so what the page
/// draws past its bounds is kept; a repaint boundary under the page keeps
/// the frame it last drew, with whatever that reaches past its bounds.
///
/// The snapshot is rasterised twice: the whole of it, margin included,
/// and over that the page itself, from its own origin and at its own
/// size. One image would do but for a backdrop filter with a runtime
/// shader ([BackdropFilter], [ImageFilter.shader]), whose fragment
/// coordinate is the position in the render target it filters: a shader
/// that places its shape by the screen position it recorded — glass, in
/// an app that draws it that way — draws where it did on screen only in
/// a target with the page's origin and size, and in an image starting a
/// margin above and left of the page it drew that margin up and left of
/// its control. Within the strips such a shader is still off by the
/// margin; a control cut by the page's edge is the only thing that shows
/// it. The strips are not rendered on their own instead, because the
/// engine leaves out of a render every picture whose recorded bounds miss
/// it, and a picture's bounds are cut to its repaint boundary's whatever
/// it draws past them: a strip rendered alone lost the labels and chips
/// the page draws into it, which the whole image keeps.
///
/// A platform view cannot be rasterised, and its layer is lifted out of
/// the paint the same way as a hidden source's: a native view the page
/// shows — glass chrome — is hidden under a route regardless. Always in
/// the tree, so the child's element keeps its position and state. The
/// snapshot is kept until [enabled] is cleared, or the child is laid out
/// at another size.
class ZoomCoveredSnapshot extends SingleChildRenderObjectWidget {
  /// Creates a snapshot of [child] with a margin around it.
  const ZoomCoveredSnapshot({
    required this.enabled,
    required this.bleed,
    required super.child,
    super.key,
  });

  /// Whether the child is painted from a snapshot.
  final bool enabled;

  /// How far past each edge of the child the snapshot reaches, as a
  /// fraction of the child's size on that axis.
  final double bleed;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderZoomCoveredSnapshot(
      enabled: enabled,
      bleed: bleed,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderZoomCoveredSnapshot)
      ..enabled = enabled
      ..bleed = bleed
      ..devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
  }
}

class _RenderZoomCoveredSnapshot extends RenderProxyBox
    implements ZoomSourceHiddenListener {
  _RenderZoomCoveredSnapshot({
    required this._enabled,
    required this._bleed,
    required this._devicePixelRatio,
  });

  bool get enabled => _enabled;
  bool _enabled;
  set enabled(bool value) {
    if (value == _enabled) {
      return;
    }
    _enabled = value;
    _live = false;
    _drop();
    markNeedsPaint();
  }

  double get bleed => _bleed;
  double _bleed;
  set bleed(double value) {
    if (value == _bleed) {
      return;
    }
    _bleed = value;
    _drop();
    markNeedsPaint();
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
    _drop();
    markNeedsPaint();
  }

  /// The paint of the child the snapshot is rasterised from, kept so that
  /// it can be rasterised again.
  OffsetLayer? _layer;
  List<_Piece>? _pieces;
  Size? _imageSize;

  /// Whether the child is painted live because something in it cannot be
  /// rasterised.
  bool _live = false;

  /// The snapshot's margin past each edge of the child, in points.
  Offset get _margin =>
      Offset(size.width * _bleed + 1, size.height * _bleed + 1);

  /// The snapshot's bounds in the child's coordinates.
  Rect get _bounds {
    final margin = _margin;
    return Rect.fromLTRB(
      -margin.dx,
      -margin.dy,
      size.width + margin.dx,
      size.height + margin.dy,
    );
  }

  /// The pieces the snapshot is rasterised in, in the child's coordinates:
  /// the whole of it, margin included, and over that the page itself,
  /// from its own origin and at its own size, so that a backdrop filter's
  /// shader sees the fragment coordinates it saw on screen.
  List<Rect> get _pieceRects => <Rect>[_bounds, Offset.zero & size];

  void _dropPieces() {
    if (_pieces case final pieces?) {
      for (final piece in pieces) {
        piece.image.dispose();
      }
    }
    _pieces = null;
  }

  void _drop() {
    _dropPieces();
    _layer?.dispose();
    _layer = null;
    _imageSize = null;
  }

  @override
  void detach() {
    _live = false;
    _drop();
    super.detach();
  }

  @override
  void dispose() {
    _drop();
    super.dispose();
  }

  /// A source under the page was hidden after the snapshot was taken:
  /// rasterise the paint again, without the source, when this paints.
  /// Only a paint can be asked for here — the source is hidden from a
  /// build, which under a [LayoutBuilder] runs during layout, where
  /// nothing outside the builder may be marked for layout.
  @override
  void sourceHidden() {
    if (_pieces != null) {
      _dropPieces();
      markNeedsPaint();
    }
  }

  /// Paints the child into a layer of its own, the margin as the cull
  /// rect, and keeps it: what the child paints past its own size is in
  /// the picture only because the cull rect reaches that far.
  void _capture() {
    final layer = OffsetLayer();
    final context = PaintingContext(layer, _bounds);
    super.paint(context, Offset.zero);
    // ignore: invalid_use_of_protected_member, as SnapshotWidget does
    context.stopRecordingIfNeeded();
    _layer = layer;
  }

  /// Rasterises the kept paint, one image per piece, with the layers of
  /// the sources hidden under the page left out, and any platform view's:
  /// a platform view cannot be rasterised, and one the page shows natively
  /// — glass chrome — is hidden under a route anyway. Null, and the child
  /// is painted live from then on, if something else in it cannot be.
  List<_Piece>? _rasterise() {
    final layer = _layer!;
    // Each lifted layer is put back among its siblings after, in the same
    // order, so the paint stays as the page left it. The siblings are
    // held while they are out of the tree: a layer nothing holds is
    // disposed.
    final lifted = <(ContainerLayer, List<LayerHandle<Layer>>)>[];
    void lift(Layer child) {
      final parent = child.parent;
      if (parent == null) {
        return;
      }
      final siblings = <LayerHandle<Layer>>[];
      for (var sibling = parent.firstChild; sibling != null;) {
        siblings.add(LayerHandle<Layer>(sibling));
        sibling = sibling.nextSibling;
      }
      lifted.add((parent, siblings));
      child.remove();
    }

    void visitSources(RenderObject node) {
      if (node is RenderZoomSourceBoundary && node.hidden) {
        if (node.layer case final source?) {
          lift(source);
        }
        return;
      }
      node.visitChildren(visitSources);
    }

    void visitPlatformViews(Layer node) {
      if (node is PlatformViewLayer) {
        lift(node);
      } else if (node is ContainerLayer) {
        final children = <Layer>[];
        for (var child = node.firstChild; child != null;) {
          children.add(child);
          child = child.nextSibling;
        }
        children.forEach(visitPlatformViews);
      }
    }

    visitChildren(visitSources);
    visitPlatformViews(layer);
    try {
      if (!layer.supportsRasterization()) {
        _live = true;
        return null;
      }
      return <_Piece>[
        for (final rect in _pieceRects)
          (
            image: layer.toImageSync(rect, pixelRatio: _devicePixelRatio),
            rect: rect,
          ),
      ];
    } finally {
      for (final (parent, siblings) in lifted.reversed) {
        parent.removeAllChildren();
        for (final sibling in siblings) {
          parent.append(sibling.layer!);
          sibling.layer = null;
        }
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_enabled || _live || size.isEmpty) {
      _drop();
      super.paint(context, offset);
      return;
    }
    if (_layer == null || _imageSize != size) {
      _drop();
      _capture();
      _imageSize = size;
    }
    _pieces ??= _rasterise();
    final pieces = _pieces;
    if (pieces == null) {
      _drop();
      super.paint(context, offset);
      return;
    }
    final paint = Paint()..filterQuality = FilterQuality.low;
    for (final (:image, :rect) in pieces) {
      final width = image.width.toDouble();
      final height = image.height.toDouble();
      // Drawn at the image's own size — a piece is rounded up to whole
      // pixels — rather than fitted to its rect, so that nothing is scaled
      // and the pieces meet at a pixel.
      context.canvas.drawImageRect(
        image,
        Offset.zero & Size(width, height),
        Rect.fromLTWH(
          rect.left,
          rect.top,
          width / _devicePixelRatio,
          height / _devicePixelRatio,
        ).shift(offset),
        paint,
      );
    }
  }
}

/// One rasterised part of the snapshot, and where it goes in the child's
/// coordinates.
typedef _Piece = ({ui.Image image, Rect rect});
