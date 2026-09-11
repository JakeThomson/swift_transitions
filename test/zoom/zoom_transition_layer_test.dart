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
  const picture = Key('picture');

  Future<void> pumpLayer(
    WidgetTester tester, {
    required Rect rect,
    Rect? alignmentRect,
    Rect? pageRect,
    double sourceOpacity = 0,
    double pageOpacity = 1,
  }) {
    return tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ZoomTransitionLayer(
          frame: ZoomFrame(
            rect: rect,
            rotation: 0,
            radii: BorderRadius.zero,
            sourceOpacity: sourceOpacity,
          ),
          pageSize: pageSize,
          atRest: false,
          flightChild: const SizedBox(key: picture),
          sourceSize: source.size,
          alignmentRect: alignmentRect,
          pageRect: pageRect,
          pageOpacity: pageOpacity,
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

  testWidgets('an aligned page is drawn at its pageRect, clipped by the card', (
    tester,
  ) async {
    // The page at the source end: scaled by 0.4 so the alignment rect
    // covers the source, the card being the source itself.
    final landing = zoomAlignedLandingRect(
      source: source,
      alignment: alignment,
      pageSize: pageSize,
    );
    expect(landing.width, closeTo(pageSize.width * 0.4, 1e-6));
    await pumpLayer(
      tester,
      rect: source,
      alignmentRect: alignment,
      pageRect: landing,
    );
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

  testWidgets("the source's picture is drawn over the alignment rect", (
    tester,
  ) async {
    await pumpLayer(
      tester,
      rect: Rect.lerp(source, Offset.zero & pageSize, 0.5)!,
      alignmentRect: alignment,
      pageRect: zoomAlignedPageRect(
        t: 0.5,
        source: source,
        alignment: alignment,
        pageSize: pageSize,
      ),
      sourceOpacity: 0.5,
    );
    // Wherever the page's transform puts the art, the picture sits on it —
    // both copies, the solid one under the page and the fading one over.
    expect(find.byKey(picture), findsNWidgets(2));
    expect(tester.getRect(find.byKey(picture).first), markerRect(tester));
    expect(tester.getRect(find.byKey(picture).last), markerRect(tester));
    // An art of another aspect: the picture keeps the source's, at the
    // art's top left, scaled as the page is.
    const wide = Rect.fromLTWH(80, 60, 300, 300);
    await pumpLayer(
      tester,
      rect: source,
      alignmentRect: wide,
      pageRect: zoomAlignedLandingRect(
        source: source,
        alignment: wide,
        pageSize: pageSize,
      ),
      sourceOpacity: 0.5,
    );
    final shown = tester.getRect(find.byKey(picture).first);
    expect(shown.topLeft, source.topLeft);
    expect(shown.size, source.size);
    // Without an alignment rect one fills the card.
    await pumpLayer(tester, rect: source, sourceOpacity: 0.5);
    expect(tester.getRect(find.byKey(picture)), source);
  });

  testWidgets(
    'the stack always has the picture under, the page, the picture over',
    (tester) async {
      // The same three children at rest and in flight, aligned or not, so
      // the page keeps its element and state: an empty slot is a slot.
      List<Widget> stack() => tester
          .widget<Stack>(
            find
                .ancestor(of: find.byKey(marker), matching: find.byType(Stack))
                .at(1),
          )
          .children;
      double? opacityOf(Widget positioned) {
        final finder = find.descendant(
          of: find.byWidget(positioned),
          matching: find.byType(Opacity),
        );
        return finder.evaluate().isEmpty
            ? null
            : tester.widget<Opacity>(finder).opacity;
      }

      await pumpLayer(
        tester,
        rect: source,
        alignmentRect: alignment,
        pageRect: zoomAlignedLandingRect(
          source: source,
          alignment: alignment,
          pageSize: pageSize,
        ),
        sourceOpacity: 0.4,
      );
      var children = stack();
      expect(children, hasLength(3));
      expect(children.first, isA<Positioned>());
      expect(opacityOf(children.first), 1);
      expect(children[1], isA<Opacity>());
      expect(children.last, isA<Positioned>());
      expect(opacityOf(children.last), 0.4);

      await pumpLayer(tester, rect: source, sourceOpacity: 0.4);
      children = stack();
      expect(children, hasLength(3));
      expect(opacityOf(children.first), isNull);
      expect(opacityOf(children.last), 0.4);

      await pumpLayer(tester, rect: source);
      children = stack();
      expect(children, hasLength(3));
      expect(opacityOf(children.first), isNull);
      expect(opacityOf(children.last), isNull);
    },
  );

  testWidgets('the page fades with pageOpacity, the picture does not', (
    tester,
  ) async {
    await pumpLayer(
      tester,
      rect: source,
      alignmentRect: alignment,
      sourceOpacity: 0.7,
      pageOpacity: 0.3,
    );
    final page = tester.widget<Opacity>(
      find.ancestor(of: find.byKey(marker), matching: find.byType(Opacity)),
    );
    expect(page.opacity, 0.3);
    final copy = tester.widget<Opacity>(
      find
          .ancestor(of: find.byKey(picture), matching: find.byType(Opacity))
          .first,
    );
    expect(copy.opacity, 0.7);
  });

  testWidgets('the card sheds its shadow as it reaches the source', (
    tester,
  ) async {
    await pumpLayer(tester, rect: Offset.zero & pageSize);
    ShapeDecoration decoration() =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(ZoomTransitionLayer),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as ShapeDecoration;
    expect(decoration().shadows, hasLength(1));
    expect(decoration().shadows!.single.blurRadius, 30);
    expect(decoration().shadows!.single.color.a, closeTo(0.24, 0.01));
    // Half of the fade window from the source, half of the shadow is left.
    await pumpLayer(
      tester,
      rect: Rect.fromLTWH(100, 200, 80 + (800 - 80) * 0.05, 120),
    );
    expect(decoration().shadows!.single.color.a, closeTo(0.12, 0.01));
    await pumpLayer(tester, rect: source);
    expect(decoration().shadows, isEmpty);
  });
}
