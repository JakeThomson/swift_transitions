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

/// How far the covered page is scaled down while a zoom route is open.
///
/// Read from the grid the covered page carries: the poster row's outer
/// edges, 384 pt apart at rest, close to 0.914 of that with the card at
/// full screen, and the point they close about is the screen's centre.
/// The scale runs straight with the flight's progress — 0.989 at 0.12 of
/// it, 0.968 at 0.36, 0.944 at 0.65, within 0.003 of the line everywhere
/// (parity stage 9).
const double kZoomCoveredPageScale = 0.086;

/// The spring the covered page comes back to rest on when the route above
/// it pops, from wherever the flight left it.
///
/// It does not follow the card home: a native landing settles the card in
/// about 215 ms and the page behind it keeps growing for 270 ms more,
/// a critically damped ω 15 — 98 % of the way in 370 ms — where the card's
/// own landing spring is seeded and underdamped (parity stage 9).
const SpringDescription kZoomCoveredPageReturn = SpringDescription(
  mass: 1,
  stiffness: 225, // ω²
  damping: 30, // 2ζω
);

/// The covered page's scale at [progress] of a zoom flight, and the
/// factor a source measured through it has to be divided by to read as it
/// will at rest.
double zoomCoveredPageScale(double progress) =>
    1 - kZoomCoveredPageScale * progress.clamp(0.0, 1.0);

/// How the covered route's dim follows the flight: in step with the route
/// animation. Native's dim, read from a patch of the covered page well away
/// from the card, was 0.15 × progress at every frame (parity stage 3).
/// Used as the route's barrier curve.
const Curve kZoomDimmingCurve = Curves.linear;

/// How long the cross-fade takes with Reduce Motion on: a native page
/// fades in over about 140 ms on the push and out over the same on the
/// pop, the bar switching with it (parity stage 8).
const Duration kZoomReduceMotionDuration = Duration(milliseconds: 140);

/// How far a card's top and bottom edges have travelled when its side
/// edges have travelled [t]. On a native push the card widens a little
/// ahead of growing tall — its bottom edge reads 0.29 at a third of the
/// sideways travel, 0.58 at 0.63, 0.73 at 0.76, 0.83 at 0.85 — and on a
/// pop it shrinks a little ahead of narrowing, by about half as much
/// (parity stage 3, from the card's outline against the covered page);
/// both converge by the end.
double zoomVerticalProgress(double t, {required bool pushing}) {
  final lead = pushing ? -0.05 : 0.03;
  return (t + lead * math.sin(math.pi * t)).clamp(0.0, 1.0);
}

/// [zoomVerticalProgress] for a push.
double zoomPushVerticalProgress(double t) =>
    zoomVerticalProgress(t, pushing: true);

/// The frame of a zoom flight (push, committed dismissal, or cancel) at
/// progress [t], where `t = 0` is [source] at rest and `t = 1` is [screen]
/// at rest. The vertical edges run a little behind the horizontal ones on
/// a push and a little ahead on a pop, per [zoomVerticalProgress].
///
/// The corners run straight from [sourceRadii] to [screenRadii] with the
/// progress: a native card's top-left corner reads 13 pt at the source,
/// 22 at a quarter of the way, 33 at half and 44 at three quarters, within
/// 3 pt of this line at every point (parity stage 8). The dim of the
/// covered route is not part of the frame: it is the route's modal
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
  final ty = zoomVerticalProgress(t, pushing: pushing);
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
/// nothing to fade to. A landing whose spring overshoots the source carries
/// on past it, [t] above 1: the card is the source by then, so its corners
/// shrink with it rather than carrying on past the source's own.
ZoomFrame zoomDepartureFrame({
  required double t,
  required ZoomFrame from,
  required Rect to,
  required BorderRadius toRadii,
  required bool toSource,
}) {
  assert(
    t >= 0 && (t <= 1 || toSource),
    'flight progress must be normalised, got $t',
  );
  final rect = Rect.lerp(from.rect, to, t)!;
  return ZoomFrame(
    rect: rect,
    rotation: from.rotation * (1 - math.min(t, 1)),
    radii: t <= 1
        ? BorderRadius.lerp(from.radii, toRadii, t)!
        : toRadii * (rect.width / to.width),
    sourceOpacity: toSource
        ? ((t - (1 - kZoomCrossFadeWindow)) / kZoomCrossFadeWindow).clamp(0, 1)
        : 0,
  );
}
