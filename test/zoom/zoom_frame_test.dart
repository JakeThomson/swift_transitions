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
    expect(zoomPushVerticalProgress(0.33), closeTo(0.29, 0.01));
    expect(zoomPushVerticalProgress(0.63), closeTo(0.58, 0.01));
    expect(zoomPushVerticalProgress(0.85), closeTo(0.83, 0.01));
    // A pop runs the other way, by less.
    expect(zoomVerticalProgress(0.64, pushing: false), closeTo(0.667, 0.01));
    expect(zoomVerticalProgress(0, pushing: false), 0);
    expect(zoomVerticalProgress(1, pushing: false), 1);
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

  test('the side edges and radii are a plain lerp at the midpoint', () {
    final frame = frameAt(0.5);
    expect(frame.rect.left, lerpDouble(source.left, screen.left, 0.5));
    expect(frame.rect.right, lerpDouble(source.right, screen.right, 0.5));
    expect(frame.radii, BorderRadius.lerp(sourceRadii, screenRadii, 0.5));
  });

  test('a landing past the source keeps going, corners and all', () {
    final from = ZoomFrame(
      rect: screen,
      rotation: 0.1,
      radii: screenRadii,
      sourceOpacity: 0,
    );
    final frame = zoomDepartureFrame(
      t: 1.1,
      from: from,
      to: source,
      toRadii: sourceRadii,
      toSource: true,
    );
    expect(frame.rect, Rect.lerp(screen, source, 1.1));
    expect(frame.rect.width, lessThan(source.width));
    expect(frame.radii.topLeft.x, closeTo(12 * frame.rect.width / 80, 1e-9));
    expect(frame.rotation, 0);
    expect(frame.sourceOpacity, 1);
  });
}
