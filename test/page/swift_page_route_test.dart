import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/src/page/back_gesture.dart';
import 'package:swift_transitions/swift_transitions.dart';

/// A minimal app with a home page that pushes a [SwiftPageRoute] wrapping
/// [secondPage] when its button is tapped.
Widget testApp({
  required Widget secondPage,
  BackGestureRegion backGestureRegion = BackGestureRegion.anywhere,
}) {
  return CupertinoApp(
    home: Builder(
      builder: (context) => CupertinoPageScaffold(
        child: Center(
          child: CupertinoButton(
            onPressed: () => Navigator.of(context).push(
              SwiftPageRoute<void>(
                backGestureRegion: backGestureRegion,
                builder: (_) => secondPage,
              ),
            ),
            child: const Text('push'),
          ),
        ),
      ),
    ),
  );
}

/// What a 40pt display radius clips to: the leading (LTR: left) corners only.
const BorderRadius leadingCorners40 = BorderRadius.only(
  topLeft: Radius.circular(40),
  bottomLeft: Radius.circular(40),
);

ClipRSuperellipse findClip(WidgetTester tester) =>
    tester.widget<ClipRSuperellipse>(find.byType(ClipRSuperellipse).last);

/// The alpha of the dim painted over the covered (first clipped) page.
double coveredDim(WidgetTester tester) {
  final box = tester.widget<DecoratedBox>(
    find
        .descendant(
          of: find.byType(ClipRSuperellipse).first,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.position == DecorationPosition.foreground,
          ),
        )
        .first,
  );
  return (box.decoration as BoxDecoration).color?.a ?? 0;
}

void main() {
  testWidgets('the pushed page is clipped mid-transition and not at rest', (
    tester,
  ) async {
    await tester.pumpWidget(
      DisplayCornerRadii(
        radii: BorderRadius.circular(40),
        child: testApp(secondPage: const Center(child: Text('second'))),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final midFlight = findClip(tester);
    expect(midFlight.clipBehavior, Clip.antiAlias);
    expect(midFlight.borderRadius, leadingCorners40);

    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    final atRest = findClip(tester);
    expect(atRest.clipBehavior, Clip.none);
    expect(atRest.borderRadius, BorderRadius.zero);
  });

  testWidgets(
    'a covered SwiftPageRoute keeps square corners and still recedes',
    (tester) async {
      await tester.pumpWidget(
        DisplayCornerRadii(
          radii: BorderRadius.circular(40),
          child: testApp(
            secondPage: Builder(
              builder: (context) => CupertinoPageScaffold(
                child: Center(
                  child: CupertinoButton(
                    onPressed: () => Navigator.of(context).push(
                      SwiftPageRoute<void>(builder: (_) => const Text('third')),
                    ),
                    child: const Text('push again'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('push again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final clips = tester
          .widgetList<ClipRSuperellipse>(find.byType(ClipRSuperellipse))
          .toList();
      expect(clips, hasLength(greaterThanOrEqualTo(2)));
      // The arriving ("third") page is clipped. The covered ("push again")
      // page is not: it still spans the screen, so rounding its leading
      // corners would cut the display's own corners out of it and leave the
      // window showing through them.
      expect(clips.last.clipBehavior, Clip.antiAlias);
      expect(clips.last.borderRadius, leadingCorners40);
      expect(clips.first.clipBehavior, Clip.none);
      expect(clips.first.borderRadius, BorderRadius.zero);
      // It still recedes, which is the canTransitionTo regression the design
      // calls out: two stacked SwiftPageRoutes share a delegatedTransition,
      // so the covered route keeps driving its own buildTransitions rather
      // than handing off, and its secondaryRouteAnimation must still reach
      // this transition.
      expect(
        tester.getTopLeft(find.byType(ClipRSuperellipse).first).dx,
        lessThan(0),
      );
    },
  );

  testWidgets(
    'a release past the midpoint on the leading edge commits the pop',
    (tester) async {
      await tester.pumpWidget(
        testApp(
          secondPage: const Center(child: Text('second')),
          backGestureRegion: BackGestureRegion.leadingEdge,
        ),
      );
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);

      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(700, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('second'), findsNothing);
    },
  );

  testWidgets('a fast fling short of the midpoint still commits the pop', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        secondPage: const Center(child: Text('second')),
        backGestureRegion: BackGestureRegion.leadingEdge,
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    // 100px is well short of the 400px midpoint of the default 800px test
    // view; only the release velocity can be committing this: 4 widths/s
    // projected over 120 ms is another 0.48.
    await tester.flingFrom(const Offset(5, 300), const Offset(100, 0), 3200);
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
  });

  testWidgets('a short flick commits when its coast would pass the midpoint', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        secondPage: const Center(child: Text('second')),
        backGestureRegion: BackGestureRegion.leadingEdge,
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    // 260px at 1600px/s: 0.31 widths beyond the dead zone, and 2 widths/s
    // projected over 120 ms is another 0.24. Past the 53 % line together,
    // and past neither of the SDK's tests alone.
    expect(BackGestureController.projectedTravel(2), closeTo(0.24, 1e-9));
    await tester.flingFrom(const Offset(5, 300), const Offset(260, 0), 1600);
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
  });

  testWidgets('a page pulled back at the release still pops past midpoint', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        secondPage: const Center(child: Text('second')),
        backGestureRegion: BackGestureRegion.leadingEdge,
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    // Dragged 70% across, then moving back at 500px/s when let go: the
    // projection only takes 0.075 off, so it pops, as native does from 66%
    // moving back at that speed.
    // Stamped by hand: the velocity tracker reads event times, and a pause
    // before the pull back keeps the drag out of its window.
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(560, 0));
    await tester.pump(const Duration(milliseconds: 150));
    var at = const Duration(milliseconds: 150);
    for (var i = 0; i < 4; i++) {
      at += const Duration(milliseconds: 20);
      await gesture.moveBy(const Offset(-10, 0), timeStamp: at);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await gesture.up(timeStamp: at);
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
  });

  testWidgets('a short drag on the leading edge cancels the pop', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        secondPage: const Center(child: Text('second')),
        backGestureRegion: BackGestureRegion.leadingEdge,
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(20, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('second'), findsOneWidget);
  });

  testWidgets(
    'userGestureInProgress is set for the drag and cleared after it settles',
    (tester) async {
      await tester.pumpWidget(
        testApp(
          secondPage: const Center(child: Text('second')),
          backGestureRegion: BackGestureRegion.leadingEdge,
        ),
      );
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      expect(navigator.userGestureInProgress, isFalse);

      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(20, 0));
      expect(navigator.userGestureInProgress, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(navigator.userGestureInProgress, isFalse);
    },
  );

  testWidgets('a drag starting anywhere pops when the region is anywhere', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        secondPage: const Center(child: Text('second')),
        backGestureRegion: BackGestureRegion.anywhere,
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(700, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
  });

  testWidgets(
    'a drag opening the wrong way is not claimed when the region is anywhere',
    (tester) async {
      await tester.pumpWidget(
        testApp(
          secondPage: const Center(child: Text('second')),
          backGestureRegion: BackGestureRegion.anywhere,
        ),
      );
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(-700, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('second'), findsOneWidget);
    },
  );

  testWidgets('a swipe from anywhere waits out 27px and commits from 42 %', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(secondPage: const Center(child: Text('second'))),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('second')))!;

    // Native's page held still for the first 27 pt of a mid-page drag
    // (parity stage 10), 15 more than an edge swipe's.
    final gesture = await tester.startGesture(const Offset(200, 300));
    await gesture.moveBy(const Offset(27, 0));
    await tester.pump();
    expect(route.animation!.value, 1);
    // Then followed 1:1: 320px past the dead zone is 0.40 of the 800px
    // view, short of the 42 % line.
    await gesture.moveBy(const Offset(320, 0));
    await tester.pump();
    expect(route.animation!.value, closeTo(0.6, 1e-9));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);

    // 0.43 at rest pops, where an edge swipe would spring back.
    final again = await tester.startGesture(const Offset(200, 300));
    await again.moveBy(const Offset(27 + 344, 0));
    await tester.pump(const Duration(milliseconds: 100));
    await again.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('a horizontal scrollable on the page wins over the swipe', (
    tester,
  ) async {
    final pageController = PageController(initialPage: 1);
    addTearDown(pageController.dispose);
    await tester.pumpWidget(
      testApp(
        secondPage: PageView(
          controller: pageController,
          children: const <Widget>[Text('first'), Text('second')],
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('second')))!;

    // A trailing drag over the pager scrolls it back a page, as it would
    // natively; the route stays put. (The scrollable's own recognizer only
    // starts on the first move; the second scrolls.)
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(500, 0));
    await tester.pump();
    expect(route.animation!.value, 1);
    expect(pageController.page, lessThan(1));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(route.isCurrent, isTrue);
    expect(pageController.page, 0);
    expect(find.text('first'), findsOneWidget);
  });

  testWidgets('from the leading edge the swipe wins over the scrollable', (
    tester,
  ) async {
    final pageController = PageController(initialPage: 1);
    addTearDown(pageController.dispose);
    await tester.pumpWidget(
      testApp(
        secondPage: PageView(
          controller: pageController,
          children: const <Widget>[Text('first'), Text('second')],
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('second')))!;

    // The strip lies over the page, as the SDK's does: its swipe is the
    // edge swipe, with the edge's 12px dead zone, and the pager stays put.
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(212, 0));
    await tester.pump();
    expect(route.animation!.value, closeTo(0.75, 1e-9));
    expect(pageController.page, 1);
    await gesture.moveBy(const Offset(300, 0));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsNothing);
  });

  testWidgets('a pan on the page wins over the swipe from anywhere', (
    tester,
  ) async {
    // A pan recognizer waits for the pan slop, twice a horizontal drag's,
    // so an eager swipe would take the finger from a card that pans — a
    // swipe deck — before the card had a say.
    var panned = Offset.zero;
    await tester.pumpWidget(
      testApp(
        secondPage: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => panned += details.delta,
          child: const Center(child: Text('second')),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final route = ModalRoute.of(tester.element(find.text('second')))!;

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(500, 0));
    await tester.pump();
    expect(route.animation!.value, 1);
    expect(panned.dx, 600);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('a drag opening the wrong way is left to a pan on the page', (
    tester,
  ) async {
    // Refused, not merely ignored: a swipe that won the arena and then
    // did nothing would still have taken the finger from the card.
    var panned = Offset.zero;
    await tester.pumpWidget(
      testApp(
        secondPage: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (details) => panned += details.delta,
          child: const Center(child: Text('second')),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(-100, 0));
    await tester.pump();
    // Nor does turning round make it a swipe.
    await gesture.moveBy(const Offset(400, 0));
    await tester.pump();
    expect(panned.dx, 300);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
  });

  testWidgets('the covered page keeps pace at 0.30 of the width and dims', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(secondPage: const Center(child: Text('second'))),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // The home CupertinoPageRoute receives SwiftPageTransition's delegate, so
    // both pages are clipped pages: the covered one first, the arriving one
    // last. The covered page's travel is a fixed fraction of the arriving
    // page's, whatever the curve, because they share one curve.
    final arrivingX = tester.getTopLeft(find.byType(ClipRSuperellipse).last).dx;
    final coveredX = tester.getTopLeft(find.byType(ClipRSuperellipse).first).dx;
    expect(arrivingX, inExclusiveRange(0, 800));
    expect(coveredX, closeTo(-0.30 * (800 - arrivingX), 1));
    expect(coveredDim(tester), closeTo(0.10 * (800 - arrivingX) / 800, 0.005));

    await tester.pumpAndSettle();
    expect(coveredDim(tester), 0);
  });

  testWidgets('the covered page tracks the finger linearly', (tester) async {
    await tester.pumpWidget(
      testApp(
        secondPage: const Center(child: Text('second')),
        backGestureRegion: BackGestureRegion.leadingEdge,
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    // The first 12px of the drag are the dead zone; the page follows the
    // remaining 200.
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(212, 0));
    await tester.pump();

    expect(tester.getTopLeft(find.byType(ClipRSuperellipse).last).dx, 200);
    // 200px of an 800px drag leaves the controller at 0.75.
    expect(
      tester.getTopLeft(find.byType(ClipRSuperellipse).first).dx,
      closeTo(-0.30 * 800 * 0.75, 1),
    );
    expect(coveredDim(tester), closeTo(0.10 * 600 / 800, 0.005));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a SwiftPageRoute has no barrier colour', (tester) async {
    await tester.pumpWidget(
      testApp(secondPage: const Center(child: Text('second'))),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    expect(
      ModalRoute.of(tester.element(find.text('second')))!.barrierColor,
      isNull,
    );
  });

  testWidgets('an override wins over the resolved display corner radii', (
    tester,
  ) async {
    await tester.pumpWidget(
      DisplayCornerRadii(
        radii: BorderRadius.circular(20),
        child: testApp(secondPage: const Center(child: Text('second'))),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      findClip(tester).borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(20),
        bottomLeft: Radius.circular(20),
      ),
    );
  });

  testWidgets(
    'a SwiftPageRoute pushed over a CupertinoPageRoute clips and swipes back',
    (tester) async {
      await tester.pumpWidget(
        DisplayCornerRadii(
          radii: BorderRadius.circular(40),
          child: CupertinoApp(
            home: Builder(
              builder: (context) => CupertinoPageScaffold(
                child: Center(
                  child: CupertinoButton(
                    onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (context) => CupertinoPageScaffold(
                          child: Center(
                            child: CupertinoButton(
                              onPressed: () => Navigator.of(context).push(
                                SwiftPageRoute<void>(
                                  builder: (_) => const Text('swift'),
                                ),
                              ),
                              child: const Text('push swift'),
                            ),
                          ),
                        ),
                      ),
                    ),
                    child: const Text('push cupertino'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('push cupertino'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('push swift'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(ClipRSuperellipse), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('swift'), findsOneWidget);

      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(700, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('swift'), findsNothing);
      expect(find.text('push swift'), findsOneWidget);
    },
  );

  testWidgets(
    'a CupertinoPageRoute pushed over a SwiftPageRoute clips and slides the swift page',
    (tester) async {
      await tester.pumpWidget(
        DisplayCornerRadii(
          radii: BorderRadius.circular(40),
          child: testApp(
            secondPage: Builder(
              builder: (context) => CupertinoPageScaffold(
                child: Center(
                  child: CupertinoButton(
                    onPressed: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const Text('cupertino'),
                      ),
                    ),
                    child: const Text('push cupertino'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('push'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('push cupertino'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      // The documented trade-off of owning the delegated transition: under a
      // stock CupertinoPageRoute the swift page receives the SDK's delegate,
      // so it slides as the SDK does and its own clip stays inactive.
      final clip = findClip(tester);
      expect(clip.clipBehavior, Clip.none);
      expect(tester.getTopLeft(find.byType(ClipRSuperellipse)).dx, lessThan(0));

      await tester.pumpAndSettle();
      expect(find.text('cupertino'), findsOneWidget);
    },
  );

  testWidgets(
    'SwiftPage pushes with the swift transition through a declarative Navigator',
    (tester) async {
      var removed = false;
      var showSecond = true;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return CupertinoApp(
              home: Navigator(
                pages: <Page<void>>[
                  const SwiftPage<void>(
                    key: ValueKey('first'),
                    child: Text('first'),
                  ),
                  if (showSecond)
                    const SwiftPage<void>(
                      key: ValueKey('second'),
                      child: Text('second'),
                    ),
                ],
                onDidRemovePage: (page) {
                  removed = true;
                  setState(() => showSecond = false);
                },
              ),
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);

      final gesture = await tester.startGesture(const Offset(5, 300));
      await gesture.moveBy(const Offset(700, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(removed, isTrue);
      expect(find.text('second'), findsNothing);
      expect(find.text('first'), findsOneWidget);
    },
  );

  testWidgets('the leading-edge shadow is cast from the clipped shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      DisplayCornerRadii(
        radii: BorderRadius.circular(40),
        child: testApp(secondPage: const Center(child: Text('second'))),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    ShapeDecoration shadowDecoration() => tester
        .widgetList<DecoratedBox>(find.byType(DecoratedBox))
        .map((box) => box.decoration)
        .whereType<ShapeDecoration>()
        .lastWhere(
          (decoration) => decoration.shape is RoundedSuperellipseBorder,
        );

    // Mid-flight the shadow's shape carries the same radii as the clip, so
    // it wraps the corner instead of filling the notch as a rectangle would.
    final midFlight = shadowDecoration();
    expect(
      (midFlight.shape as RoundedSuperellipseBorder).borderRadius,
      leadingCorners40,
    );
    expect(midFlight.shadows, isNotEmpty);

    await tester.pumpAndSettle();
    expect(shadowDecoration().shadows, isEmpty);
  });
}
