import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/src/zoom/zoom_transition_layer.dart';
import 'package:swift_transitions/swift_transitions.dart';

const Rect posterRect = Rect.fromLTWH(100, 200, 80, 120);
const Rect screen = Rect.fromLTWH(0, 0, 800, 600);

/// A home page with a poster source and a button that pushes a zoom route
/// for [detail].
Widget testApp({
  required Widget detail,
  ZoomTransitionOptions options = const ZoomTransitionOptions(),
}) {
  return DisplayCornerRadii(
    radii: BorderRadius.circular(40),
    child: CupertinoApp(
      home: Builder(
        builder: (context) => Stack(
          children: <Widget>[
            Positioned.fromRect(
              rect: posterRect,
              child: const ZoomTransitionSource(
                tag: 'poster',
                child: ColoredBox(color: Color(0xFF0000FF)),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              child: CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  ZoomPageRoute<void>(
                    sourceTag: 'poster',
                    options: options,
                    builder: (_) => detail,
                  ),
                ),
                child: const Text('push'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A page with nothing to scroll.
const Widget staticDetail = Center(child: Text('detail'));

/// A page whose primary scroll view is a long list.
Widget listDetail() => ListView.builder(
  itemCount: 60,
  itemExtent: 50,
  itemBuilder: (context, index) => Text(index == 0 ? 'detail' : 'item $index'),
);

Rect cardRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(ZoomTransitionLayer),
    matching: find.byType(ClipRSuperellipse),
  ),
);

NavigatorState navigatorOf(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

bool sourceHidden(WidgetTester tester) => tester
    .widget<Offstage>(
      find.descendant(
        of: find.byType(ZoomTransitionSource),
        matching: find.byType(Offstage),
      ),
    )
    .offstage;

Future<void> pushAndSettle(
  WidgetTester tester,
  Widget detail, {
  ZoomTransitionOptions options = const ZoomTransitionOptions(),
}) async {
  await tester.pumpWidget(testApp(detail: detail, options: options));
  await tester.tap(find.text('push'));
  await tester.pumpAndSettle();
  expect(find.text('detail'), findsOneWidget);
}

void main() {
  const physics = ZoomDismissPhysics.ios26;

  testWidgets(
    'a pan shrinks the card and pops when released past the threshold',
    (tester) async {
      await pushAndSettle(tester, staticDetail);
      final navigator = navigatorOf(tester);

      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();

      // 300px down a 600px card is half a card height of travel.
      final scale = physics.scaleFor(0.5);
      expect(scale, lessThan(physics.dismissThreshold));
      expect(cardRect(tester).width, closeTo(800 * scale, 0.5));
      expect(cardRect(tester).height, closeTo(600 * scale, 0.5));
      expect(navigator.userGestureInProgress, isTrue);
      final route = ModalRoute.of(tester.element(find.text('detail')))!;
      expect(route.animation!.value, closeTo(scale, 1e-6));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      expect(navigator.userGestureInProgress, isFalse);
      expect(sourceHidden(tester), isFalse);
    },
  );

  testWidgets('the grabbed content stays under the finger', (tester) async {
    await pushAndSettle(tester, staticDetail);
    const grab = Offset(200, 150);
    final gesture = await tester.startGesture(grab);
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();

    final rect = cardRect(tester);
    final fx = grab.dx / 800;
    final fy = grab.dy / 600;
    expect(rect.left + fx * rect.width, closeTo(grab.dx, 0.5));
    expect(rect.top + fy * rect.height, closeTo(grab.dy + 120, 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a short pan cancels and restores identity', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final navigator = navigatorOf(tester);

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(physics.scaleFor(100 / 600), greaterThan(physics.dismissThreshold));
    expect(cardRect(tester).width, lessThan(800));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(cardRect(tester), screen);
    expect(navigator.userGestureInProgress, isFalse);
    expect(sourceHidden(tester), isTrue);
  });

  testWidgets('a downward fling short of the threshold still pops', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    await tester.fling(find.text('detail'), const Offset(0, 60), 1500);
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('the release flies from where the card was', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    final released = cardRect(tester);

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final justAfter = cardRect(tester);
    // One frame into the landing the card is still close to where it was
    // let go, not snapped onto the flight line (which at this progress is a
    // much larger, top-left-anchored rect).
    expect((justAfter.center - released.center).distance, lessThan(40));
    expect(justAfter.width, lessThan(released.width + 1));
    await tester.pumpAndSettle();
  });

  testWidgets('a scrolled list scrolls until its top, then hands off', (
    tester,
  ) async {
    await pushAndSettle(tester, listDetail());
    final list = tester.state<ScrollableState>(find.byType(Scrollable));

    // The list's own recognizer wins the arena and, like any SDK drag, takes
    // the first move as slop; the moves after it scroll exactly.
    final gesture = await tester.startGesture(const Offset(400, 400));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(list.position.pixels, closeTo(200, 1));
    expect(cardRect(tester), screen);

    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    expect(list.position.pixels, closeTo(0, 1));
    expect(cardRect(tester), screen);

    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(list.position.pixels, 0);
    expect(cardRect(tester).width, closeTo(800 * physics.scaleFor(0.5), 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('a pan from the top of a list shrinks the card at once', (
    tester,
  ) async {
    await pushAndSettle(tester, listDetail());
    final gesture = await tester.startGesture(const Offset(400, 400));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(cardRect(tester).width, closeTo(800 * physics.scaleFor(0.2), 0.5));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('an edge swipe shrinks the card by horizontal travel', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(200, 0));
    await tester.pump();
    // 200px across an 800px card is a quarter of a card width of travel.
    expect(cardRect(tester).width, closeTo(800 * physics.scaleFor(0.25), 0.5));

    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    expect(physics.scaleFor(500 / 800), lessThan(physics.dismissThreshold));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('a pointer down during the push grabs the card', (tester) async {
    await tester.pumpWidget(testApp(detail: staticDetail));
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final route = ModalRoute.of(tester.element(find.text('detail')))!;
    final grabbed = route.animation!.value;
    expect(grabbed, inExclusiveRange(0, 1));

    // Inside the card at every point of the flight: the poster's centre.
    final gesture = await tester.startGesture(posterRect.center);
    await tester.pump(const Duration(milliseconds: 100));
    expect(route.animation!.value, grabbed, reason: 'the push stops');
    expect(navigatorOf(tester).userGestureInProgress, isTrue);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(route.animation!.isCompleted, isTrue);
    expect(navigatorOf(tester).userGestureInProgress, isFalse);
  });

  /// The angle the card is drawn at, from the layer's rotate transform.
  double cardRotation(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find
          .descendant(
            of: find.byType(ZoomTransitionLayer),
            matching: find.byType(Transform),
          )
          .first,
    );
    final m = transform.transform;
    return math.atan2(m.entry(1, 0), m.entry(0, 0));
  }

  testWidgets('a pinch scales the card with the fingers and pops', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final first = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final second = await tester.startGesture(
      const Offset(500, 300),
      pointer: 2,
    );
    await first.moveTo(const Offset(350, 300));
    await second.moveTo(const Offset(450, 300));
    await tester.pump();

    // The fingers closed from 200 to 100 apart.
    expect(cardRect(tester).width, closeTo(400, 0.5));
    expect(cardRect(tester).height, closeTo(300, 0.5));
    expect(cardRect(tester).center.dx, closeTo(400, 0.5));
    expect(navigatorOf(tester).userGestureInProgress, isTrue);

    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    await second.up();
  });

  testWidgets('a pinch rotates the card and it un-rotates on release', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final first = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final second = await tester.startGesture(
      const Offset(500, 300),
      pointer: 2,
    );
    const angle = math.pi / 6;
    await second.moveTo(
      Offset(300 + 200 * math.cos(angle), 300 + 200 * math.sin(angle)),
    );
    await tester.pump();

    expect(cardRotation(tester), closeTo(angle, 1e-6));
    // The fingers are the same distance apart, so the card keeps its size
    // (its bounding rect is wider, being rotated).
    expect(
      tester.getSize(
        find.descendant(
          of: find.byType(ZoomTransitionLayer),
          matching: find.byType(ClipRSuperellipse),
        ),
      ),
      const Size(800, 600),
    );

    await first.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(cardRotation(tester), inExclusiveRange(0, angle));

    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(cardRotation(tester), closeTo(0, 1e-6));
    expect(cardRect(tester), screen);
    await second.up();
  });

  testWidgets('a pinch over a scrolled list takes the finger from the list', (
    tester,
  ) async {
    await pushAndSettle(tester, listDetail());
    final list = tester.state<ScrollableState>(find.byType(Scrollable));
    final first = await tester.startGesture(const Offset(400, 400), pointer: 1);
    await first.moveBy(const Offset(0, -20));
    await first.moveBy(const Offset(0, -200));
    await tester.pump();
    expect(list.position.pixels, closeTo(200, 1));

    final second = await tester.startGesture(
      const Offset(400, 480),
      pointer: 2,
    );
    await second.moveTo(const Offset(400, 330));
    await first.moveTo(const Offset(400, 230));
    await tester.pump();

    // The fingers closed from 300 to 100 apart; the list did not scroll
    // with either of them.
    expect(cardRect(tester).width, closeTo(800 / 3, 0.5));
    expect(list.position.pixels, closeTo(200, 1));

    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    await second.up();
  });

  testWidgets('a second finger turns a pan into a pinch', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final first = await tester.startGesture(const Offset(400, 200), pointer: 1);
    await first.moveBy(const Offset(0, 100));
    await tester.pump();
    final panned = cardRect(tester);
    expect(panned.width, closeTo(800 * physics.scaleFor(100 / 600), 0.5));

    final second = await tester.startGesture(
      const Offset(400, 550),
      pointer: 2,
    );
    await second.moveTo(const Offset(400, 425));
    await tester.pump();

    // 250 apart to 125 apart: half the size the pan left the card at.
    expect(cardRect(tester).width, closeTo(panned.width / 2, 0.5));

    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    await second.up();
  });

  testWidgets('interactiveDismissShouldBegin can refuse', (tester) async {
    ZoomInteractionContext? asked;
    await pushAndSettle(
      tester,
      staticDetail,
      options: ZoomTransitionOptions(
        interactiveDismissShouldBegin: (context) {
          asked = context;
          return false;
        },
      ),
    );
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(asked?.gesture, ZoomGesture.pan);
    expect(cardRect(tester), screen);
    expect(navigatorOf(tester).userGestureInProgress, isFalse);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('ZoomDismissGestures.none installs no gesture', (tester) async {
    await pushAndSettle(
      tester,
      staticDetail,
      options: const ZoomTransitionOptions(
        dismissGestures: ZoomDismissGestures.none,
      ),
    );
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(300, 200));
    await tester.pump();
    expect(cardRect(tester), screen);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });
}
