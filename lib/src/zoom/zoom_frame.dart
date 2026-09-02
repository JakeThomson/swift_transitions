import 'package:flutter/widgets.dart';

/// The card geometry for one frame of a zoom transition, computed once per
/// frame and shared by rendering and by the gesture-driven interaction.
///
/// See design.md section 3.4. This is a pure value object; how it is
/// produced (a route animation during a flight, or a gesture during an
/// interactive dismissal) is not its concern.
@immutable
class ZoomFrame {
  /// Creates a zoom frame. All fields are in navigator coordinates.
  const ZoomFrame({
    required this.rect,
    required this.rotation,
    required this.radii,
    required this.sourceOpacity,
    required this.dimming,
  });

  /// The card's frame.
  final Rect rect;

  /// The card's rotation in radians, non-zero only during a pinch.
  final double rotation;

  /// The card's on-screen corner radii.
  final BorderRadius radii;

  /// The opacity of the source's pixels drawn inside the card, 0 to 1.
  final double sourceOpacity;

  /// The dimming applied to the covered route, 0 to 1.
  final double dimming;

  @override
  bool operator ==(Object other) =>
      other is ZoomFrame &&
      other.rect == rect &&
      other.rotation == rotation &&
      other.radii == radii &&
      other.sourceOpacity == sourceOpacity &&
      other.dimming == dimming;

  @override
  int get hashCode =>
      Object.hash(rect, rotation, radii, sourceOpacity, dimming);
}

/// The fraction of a push (or a pop, from the other end) over which the
/// source's pixels cross-fade with the page's, per design.md section 3.4.
const double kZoomCrossFadeWindow = 0.4;

/// The frame of a zoom flight (push, committed dismissal, or cancel) at
/// progress [t], where `t = 0` is [source] at rest and `t = 1` is [screen]
/// at rest.
///
/// [sourceRadii] and [screenRadii] are interpolated in the card's own space
/// (against its interpolated size, not the navigator's), so the visible
/// radius scales with the card rather than the flight distance.
ZoomFrame zoomFlightFrame({
  required double t,
  required Rect source,
  required Rect screen,
  required BorderRadius sourceRadii,
  required BorderRadius screenRadii,
}) {
  assert(t >= 0 && t <= 1, 'flight progress must be normalised, got $t');
  return ZoomFrame(
    rect: Rect.lerp(source, screen, t)!,
    rotation: 0,
    radii: BorderRadius.lerp(sourceRadii, screenRadii, t)!,
    sourceOpacity: 1 - (t / kZoomCrossFadeWindow).clamp(0, 1),
    dimming: Curves.easeIn.transform(t),
  );
}
