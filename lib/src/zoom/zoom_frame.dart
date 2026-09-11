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

/// The fraction of a push over which the source's pixels cross-fade with
/// the page's. Read off a native flight where the copy sat over the
/// page's light top strip: 0.58 at progress 0.21, 0.39 at 0.33, gone by
/// 0.63 — a straight fade over the first 0.55 (parity stage 3).
const double kZoomCrossFadeWindow = 0.55;

/// Where on the flight line a pop's cross-fade begins, the source's
/// picture then coming in over the page across [kZoomCrossFadeWindow]:
/// solid from 0.31 of the way, with most of the flight still to go. On a
/// native pop of a page that is not its poster — a film's, leading with
/// a backdrop — the poster read 0.07, 0.19, 0.39 and 0.55 solid over the
/// backdrop at 0.84, 0.75, 0.66 and 0.56 of the way, a straight line from
/// 0.86 (parity, the film page), where the aligned pop's picture reads
/// much the same ([zoomAlignedPictureOpacity]). A fade over the last part of
/// the flight, the push's mirrored, is invisible on a page that is its
/// own poster and a double exposure on one that is not: the page shows
/// through the poster until the card has all but landed.
const double kZoomPopCrossFadeStart = 0.86;

/// The fraction of a landing — the flight of a card let go of — over
/// which the source's picture comes in over the page, from the release.
/// A native pan flung at 0.64 of the way read 0.04, 0.28 and 0.79 solid
/// at 0.09, 0.28 and 0.39 of the landing, and 0.9 by 0.42 (parity, the
/// film page): the fade is a beat of the landing, not of the flight line,
/// and a card held shows none of it ([ZoomFrame.sourceOpacity] is 0 while
/// a finger has the card).
const double kZoomLandingCrossFadeWindow = 0.45;

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

/// The covered page's scale at [progress] of a zoom flight.
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
/// a push and a little ahead on a pop, per [zoomVerticalProgress]. The
/// source's picture fades out over the first [kZoomCrossFadeWindow] of a
/// push and in over the same length of a pop from
/// [kZoomPopCrossFadeStart], the start of either flight.
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
    sourceOpacity: pushing
        ? 1 - (t / kZoomCrossFadeWindow).clamp(0, 1)
        : ((kZoomPopCrossFadeStart - t) / kZoomCrossFadeWindow).clamp(0, 1),
  );
}

/// How far along its line an aligned page's art is when the page's scale
/// is [t] along, per axis.
///
/// Natively an aligned page's position runs behind its scale. On a pop the
/// art starts a beat late and catches up — behind by 0.14 of what is left,
/// on both axes; on a push it trails most at mid-flight, by 0.25 · f(1 − f)
/// vertically and 0.1 · f(1 − f) across, f being the scale's progress from
/// the source (parity stage 3, aligned, from the art's centre against its
/// width; both fit within 0.01). Both converge by the end.
Offset zoomAlignedCentreProgress(double t, {required bool pushing}) {
  if (pushing) {
    final bump = t * (1 - t);
    return Offset(t - 0.1 * bump, t - 0.25 * bump);
  }
  final behind = math.min(1.0, 1.14 * t);
  return Offset(behind, behind);
}

/// How much of the source's picture is over an aligned page at progress
/// [t]: none at rest, all of it from a little before the flight's last
/// quarter, fading in over the middle of the flight — the still's label
/// read 0.10, 0.30, 0.72, 0.88 and 0.99 white at 0.13, 0.34, 0.55, 0.63
/// and 0.71 of the way to the source (parity stage 3, aligned). Under it
/// the page's own art stays solid: natively the page fades everywhere but
/// there.
double zoomAlignedPictureOpacity(double t) =>
    ((0.78 - t) / 0.5).clamp(0.0, 1.0);

/// The scale of an aligned page at the source end of its flight: the
/// larger of the two ratios between [source] and [alignment], so the art
/// covers the source.
double zoomAlignedLandingScale({
  required Rect source,
  required Rect alignment,
}) =>
    math.max(source.width / alignment.width, source.height / alignment.height);

/// The page's bounds at the source end of an aligned flight: scaled by
/// [zoomAlignedLandingScale] with the art's top left on the source's.
///
/// An art of another aspect than its source overhangs it, natively, below
/// or to the right — the page scaled by the larger ratio and the art's top
/// left put on the source's, not its centre (parity stage 3, aligned, a
/// 4:3 art on a 16:9 still: the art's top left flies the line it flies
/// with a 16:9 art, to the point, and lands 30 pt too tall).
Rect zoomAlignedLandingRect({
  required Rect source,
  required Rect alignment,
  required Size pageSize,
}) {
  final scale = zoomAlignedLandingScale(source: source, alignment: alignment);
  return (source.topLeft - alignment.topLeft * scale) & (pageSize * scale);
}

/// Where an aligned page is at progress [t] of a flight between its
/// source end ([zoomAlignedLandingRect]) and [from] — the page's bounds at
/// the far end: at rest when null, or where a card let go of it — scaled
/// as one picture, straight from the one to the other, with its art's
/// centre behind per [zoomAlignedCentreProgress]. The card clipping it is
/// [zoomFlightFrame]'s, flying the same line as any other (parity stage 3,
/// aligned: the card's edges at mid-flight are the plain card's to a few
/// points, while the art inside reads its own scale).
Rect zoomAlignedPageRect({
  required double t,
  required Rect source,
  required Rect alignment,
  required Size pageSize,
  Rect? from,
  bool pushing = false,
}) {
  final landing = zoomAlignedLandingRect(
    source: source,
    alignment: alignment,
    pageSize: pageSize,
  );
  final far = from ?? (Offset.zero & pageSize);
  final scale = lerpDouble(landing.width, far.width, t)! / pageSize.width;
  final centre = zoomAlignedCentreProgress(t, pushing: pushing);
  // The art's centre on the line between its two ends, and the page
  // around it.
  Offset artIn(Rect page) =>
      page.topLeft + alignment.center * (page.width / pageSize.width);
  final near = artIn(landing);
  final away = artIn(far);
  final art = Offset(
    lerpDouble(near.dx, away.dx, centre.dx)!,
    lerpDouble(near.dy, away.dy, centre.dy)!,
  );
  return (art - alignment.center * scale) & (pageSize * scale);
}

/// Where the source's picture is over an aligned page at [pageRect]: at
/// the top left of the art, at the source's own aspect, scaled as the
/// page is against its landing scale — the source itself at the source
/// end.
Rect zoomAlignedPictureRect({
  required Rect pageRect,
  required Rect alignment,
  required Size pageSize,
  required Size sourceSize,
}) {
  final scale = pageRect.width / pageSize.width;
  final landing = zoomAlignedLandingScale(
    source: Offset.zero & sourceSize,
    alignment: alignment,
  );
  return (pageRect.topLeft + alignment.topLeft * scale) &
      (sourceSize * (scale / landing));
}

/// The frame of a card leaving from [from] — the frame a gesture released it
/// at, or the frame a push was interrupted at — and flying to [to], at
/// progress [t] from 0 ([from]) to 1 ([to]).
///
/// When the destination is the source, the source's picture comes in over
/// the first [kZoomLandingCrossFadeWindow] of the landing; when it is the
/// full screen (a cancelled dismissal) there is nothing to fade to. A
/// landing whose spring overshoots the source carries on past it, [t]
/// above 1: the card is the source by then, so its corners shrink with it
/// rather than carrying on past the source's own.
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
    sourceOpacity: toSource ? (t / kZoomLandingCrossFadeWindow).clamp(0, 1) : 0,
  );
}
