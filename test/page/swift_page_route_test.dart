import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/swift_transitions.dart';

/// A minimal app with a home page that pushes a [SwiftPageRoute] wrapping
/// [secondPage] when its button is tapped.
Widget testApp({
  required Widget secondPage,
  BackGestureRegion backGestureRegion = BackGestureRegion.leadingEdge,
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

ClipRSuperellipse findClip(WidgetTester tester) =>
    tester.widget<ClipRSuperellipse>(find.byType(ClipRSuperellipse).last);

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
    expect(midFlight.borderRadius, BorderRadius.circular(40));

    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    final atRest = findClip(tester);
    expect(atRest.clipBehavior, Clip.none);
    expect(atRest.borderRadius, BorderRadius.zero);
  });

  testWidgets(
    'the covered page is clipped while another SwiftPageRoute covers it',
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

      // Two clips are live: the covered ("push again") page receding, and the
      // incoming ("third") page arriving. Both must be actively clipping —
      // this is the canTransitionTo regression the design calls out: two
      // stacked SwiftPageRoutes share a delegatedTransition, so the covered
      // route keeps driving its own buildTransitions rather than handing off,
      // and its secondaryRouteAnimation must still reach this clip.
      final clips = tester
          .widgetList<ClipRSuperellipse>(find.byType(ClipRSuperellipse))
          .toList();
      expect(clips, hasLength(greaterThanOrEqualTo(2)));
      expect(
        clips.every((clip) => clip.clipBehavior == Clip.antiAlias),
        isTrue,
      );
    },
  );

  testWidgets(
    'a release past the midpoint on the leading edge commits the pop',
    (tester) async {
      await tester.pumpWidget(
        testApp(secondPage: const Center(child: Text('second'))),
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
      testApp(secondPage: const Center(child: Text('second'))),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    // 100px is well short of the 400px midpoint of the default 800px test
    // view; only the fling-velocity threshold (one screen width per second)
    // can be committing this.
    await tester.flingFrom(const Offset(5, 300), const Offset(100, 0), 1600);
    await tester.pumpAndSettle();

    expect(find.text('second'), findsNothing);
  });

  testWidgets('a short drag on the leading edge cancels the pop', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(secondPage: const Center(child: Text('second'))),
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
        testApp(secondPage: const Center(child: Text('second'))),
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

    expect(findClip(tester).borderRadius, BorderRadius.circular(20));
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

      // The regression this guards: SwiftPageTransition.delegatedTransition
      // and CupertinoPageTransition.delegatedTransition must be the same
      // function so the swift route underneath keeps driving its own
      // secondaryRouteAnimation (and this clip) rather than being handed a
      // frozen proxy animation.
      expect(find.byType(ClipRSuperellipse), findsWidgets);
      final clip = tester
          .widgetList<ClipRSuperellipse>(find.byType(ClipRSuperellipse))
          .first;
      expect(clip.clipBehavior, Clip.antiAlias);

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
      BorderRadius.circular(40),
    );
    expect(midFlight.shadows, isNotEmpty);

    await tester.pumpAndSettle();
    expect(shadowDecoration().shadows, isEmpty);
  });
}
