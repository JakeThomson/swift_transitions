import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

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
  });

  /// The card's frame.
  final Rect rect;

  /// The card's rotation in radians, non-zero only during a pinch.
  final double rotation;

  /// The card's on-screen corner radii.
  final BorderRadius radii;

  /// The opacity of the source's pixels drawn inside the card, 0 to 1.
  final double sourceOpacity;

  @override
  bool operator ==(Object other) =>
      other is ZoomFrame &&
      other.rect == rect &&
      other.rotation == rotation &&
      other.radii == radii &&
      other.sourceOpacity == sourceOpacity;

  @override
  int get hashCode => Object.hash(rect, rotation, radii, sourceOpacity);
}

/// The fraction of a push (or a pop, from the other end) over which the
/// source's pixels cross-fade with the page's. Read off a native flight
/// where the copy sat over the page's light top strip: 0.58 at progress
/// 0.21, 0.39 at 0.33, gone by 0.63 — a straight fade over the first
/// 0.55 (parity stage 3).
const double kZoomCrossFadeWindow = 0.55;

/// How the covered route's dim follows the flight: in step with the route
/// animation. Native's dim, read from a patch of the covered page well away
/// from the card, was 0.15 × progress at every frame (parity stage 3).
/// Used as the route's barrier curve.
const Curve kZoomDimmingCurve = Curves.linear;

/// How far a pushed card's top and bottom edges have travelled when its
/// side edges have travelled [t]: on a native push the card widens first
/// and grows tall afterwards — at a third of the sideways travel the
/// vertical travel is a tenth, at 0.63 it is 0.56, at 0.85 it is 0.80 —
/// converging by the end (parity stage 3, read off the page's bar strip
/// inside the card at ten progresses). A pop grows both together.
double zoomPushVerticalProgress(double t) =>
    math.pow(((t - 0.25) / 0.75).clamp(0.0, 1.0), 0.8).toDouble();

/// The frame of a zoom flight (push, committed dismissal, or cancel) at
/// progress [t], where `t = 0` is [source] at rest and `t = 1` is [screen]
/// at rest. With [pushing], the vertical edges lag the horizontal ones by
/// [zoomPushVerticalProgress].
///
/// [sourceRadii] and [screenRadii] are interpolated in the card's own space
/// (against its interpolated size, not the navigator's), so the visible
/// radius scales with the card rather than the flight distance. The dim of
/// the covered route is not part of the frame: it is the route's modal
/// barrier, driven by the same animation through [kZoomDimmingCurve].
ZoomFrame zoomFlightFrame({
  required double t,
  required Rect source,
  required Rect screen,
  required BorderRadius sourceRadii,
  required BorderRadius screenRadii,
  bool pushing = false,
}) {
  assert(t >= 0 && t <= 1, 'flight progress must be normalised, got $t');
  final ty = pushing ? zoomPushVerticalProgress(t) : t;
  return ZoomFrame(
    rect: Rect.fromLTRB(
      lerpDouble(source.left, screen.left, t)!,
      lerpDouble(source.top, screen.top, ty)!,
      lerpDouble(source.right, screen.right, t)!,
      lerpDouble(source.bottom, screen.bottom, ty)!,
    ),
    rotation: 0,
    radii: BorderRadius.lerp(sourceRadii, screenRadii, t)!,
    sourceOpacity: 1 - (t / kZoomCrossFadeWindow).clamp(0, 1),
  );
}

/// The frame of a card leaving from [from] — the frame a gesture released it
/// at, or the frame a push was interrupted at — and flying to [to], at
/// progress [t] from 0 ([from]) to 1 ([to]).
///
/// When the destination is the source, [sourceOpacity] runs the cross-fade
/// over the last [kZoomCrossFadeWindow] of the flight as [zoomFlightFrame]
/// does; when it is the full screen (a cancelled dismissal) there is
/// nothing to fade to.
ZoomFrame zoomDepartureFrame({
  required double t,
  required ZoomFrame from,
  required Rect to,
  required BorderRadius toRadii,
  required bool toSource,
}) {
  assert(t >= 0 && t <= 1, 'flight progress must be normalised, got $t');
  return ZoomFrame(
    rect: Rect.lerp(from.rect, to, t)!,
    rotation: from.rotation * (1 - t),
    radii: BorderRadius.lerp(from.radii, toRadii, t)!,
    sourceOpacity: toSource
        ? ((t - (1 - kZoomCrossFadeWindow)) / kZoomCrossFadeWindow).clamp(0, 1)
        : 0,
  );
}
