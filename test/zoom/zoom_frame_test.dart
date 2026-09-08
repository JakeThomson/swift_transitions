import 'dart:ui' show lerpDouble;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/src/zoom/zoom_frame.dart';

void main() {
  final source = const Rect.fromLTWH(20, 40, 80, 120);
  final screen = const Rect.fromLTWH(0, 0, 390, 844);
  final sourceRadii = BorderRadius.circular(12);
  final screenRadii = BorderRadius.circular(47.33);

  ZoomFrame frameAt(double t) => zoomFlightFrame(
    t: t,
    source: source,
    screen: screen,
    sourceRadii: sourceRadii,
    screenRadii: screenRadii,
  );

  test('t = 0 rests on the source', () {
    final frame = frameAt(0);
    expect(frame.rect, source);
    expect(frame.radii, sourceRadii);
    expect(frame.sourceOpacity, 1);
  });

  test('t = 1 rests on the screen', () {
    final frame = frameAt(1);
    expect(frame.rect, screen);
    expect(frame.radii, screenRadii);
    expect(frame.sourceOpacity, 0);
  });

  test('the source fades out within the cross-fade window', () {
    expect(frameAt(kZoomCrossFadeWindow).sourceOpacity, 0);
    expect(frameAt(kZoomCrossFadeWindow / 2).sourceOpacity, closeTo(0.5, 1e-9));
  });

  test('a push widens before it grows tall', () {
    expect(zoomPushVerticalProgress(0), 0);
    expect(zoomPushVerticalProgress(1), 1);
    expect(zoomPushVerticalProgress(0.2), 0);
    expect(zoomPushVerticalProgress(0.63), closeTo(0.58, 0.02));
    expect(zoomPushVerticalProgress(0.85), closeTo(0.84, 0.02));
    final frame = zoomFlightFrame(
      t: 0.63,
      source: source,
      screen: screen,
      sourceRadii: sourceRadii,
      screenRadii: screenRadii,
      pushing: true,
    );
    expect(frame.rect.left, lerpDouble(source.left, screen.left, 0.63));
    expect(
      frame.rect.top,
      lerpDouble(source.top, screen.top, zoomPushVerticalProgress(0.63)),
    );
  });

  test('the rect and radii are a plain lerp at the midpoint', () {
    final frame = frameAt(0.5);
    expect(frame.rect, Rect.lerp(source, screen, 0.5));
    expect(frame.radii, BorderRadius.lerp(sourceRadii, screenRadii, 0.5));
  });
}
