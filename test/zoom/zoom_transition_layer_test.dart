import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/src/zoom/zoom_frame.dart';
import 'package:swift_transitions/src/zoom/zoom_transition_layer.dart';

void main() {
  const pageSize = Size(800, 600);
  const source = Rect.fromLTWH(100, 200, 80, 120);
  // A part of the page with the source's aspect, off centre.
  const alignment = Rect.fromLTWH(80, 60, 200, 300);
  const marker = Key('marker');

  Future<void> pumpLayer(
    WidgetTester tester, {
    required Rect rect,
    Rect? alignmentRect,
  }) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ZoomTransitionLayer(
          frame: ZoomFrame(
            rect: rect,
            rotation: 0,
            radii: BorderRadius.zero,
            sourceOpacity: 0,
          ),
          pageSize: pageSize,
          atRest: false,
          sourceSize: source.size,
          alignmentRect: alignmentRect,
          child: Stack(
            children: <Widget>[
              Positioned.fromRect(
                rect: alignment,
                child: const SizedBox(key: marker),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Rect markerRect(WidgetTester tester) => tester.getRect(find.byKey(marker));

  testWidgets(
    'without an alignment rect the page fills the card from the top',
    (tester) async {
      await pumpLayer(tester, rect: source);
      // Aspect fill: 120/600 = 0.2 wins over 80/800 = 0.1, anchored at the
      // card's top centre.
      final rect = markerRect(tester);
      expect(rect.width, closeTo(alignment.width * 0.2, 1e-6));
      expect(rect.top, closeTo(source.top + alignment.top * 0.2, 1e-6));
      expect(
        rect.left,
        closeTo(source.center.dx + (alignment.left - 400) * 0.2, 1e-6),
      );
    },
  );

  testWidgets('the alignment rect sits on the card at the source end', (
    tester,
  ) async {
    await pumpLayer(tester, rect: source, alignmentRect: alignment);
    final rect = markerRect(tester);
    expect(rect.left, closeTo(source.left, 1e-6));
    expect(rect.top, closeTo(source.top, 1e-6));
    expect(rect.width, closeTo(source.width, 1e-6));
    expect(rect.height, closeTo(source.height, 1e-6));
  });

  testWidgets('the page is itself at the screen end', (tester) async {
    await pumpLayer(
      tester,
      rect: Offset.zero & pageSize,
      alignmentRect: alignment,
    );
    expect(markerRect(tester), alignment);
  });

  testWidgets('the window widens with the card', (tester) async {
    await pumpLayer(
      tester,
      rect: Rect.lerp(source, Offset.zero & pageSize, 0.5)!,
      alignmentRect: alignment,
    );
    final rect = markerRect(tester);
    // Bigger than at the source end, smaller than itself.
    expect(rect.width, greaterThan(source.width));
    expect(rect.width, lessThan(alignment.width));
    // The window has grown past the alignment rect on every side, so the
    // rect now sits inside the card rather than on its edges.
    final card = Rect.lerp(source, Offset.zero & pageSize, 0.5)!;
    expect(rect.left, greaterThan(card.left));
    expect(rect.top, greaterThan(card.top));
    expect(rect.right, lessThan(card.right));
  });
}
