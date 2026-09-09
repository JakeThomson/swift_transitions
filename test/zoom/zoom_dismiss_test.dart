import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/src/zoom/zoom_transition_layer.dart';
import 'package:swift_transitions/swift_transitions.dart';

const Rect posterRect = Rect.fromLTWH(100, 200, 80, 120);
const Rect otherPosterRect = Rect.fromLTWH(600, 200, 80, 120);
const Rect screen = Rect.fromLTWH(0, 0, 800, 600);

/// A home page with a poster source and a button that pushes a zoom route
/// for [detail]. With [hero], both pages carry a [Hero] tagged 'bar', the
/// way a [CupertinoNavigationBar] does.
Widget testApp({
  required Widget detail,
  ZoomTransitionOptions options = const ZoomTransitionOptions(),
  bool hero = false,
}) {
  if (hero) {
    detail = Hero(tag: 'bar', child: detail);
  }
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
            Positioned.fromRect(
              rect: otherPosterRect,
              child: const ZoomTransitionSource(
                tag: 'other',
                child: ColoredBox(color: Color(0xFFFF0000)),
              ),
            ),
            if (hero)
              const Positioned(
                right: 0,
                top: 0,
                child: Hero(tag: 'bar', child: SizedBox(width: 20, height: 20)),
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

bool sourceHidden(WidgetTester tester) => !tester
    .widget<Visibility>(
      find.descendant(
        of: find.byWidgetPredicate(
          (widget) => widget is ZoomTransitionSource && widget.tag == 'poster',
        ),
        matching: find.byType(Visibility),
      ),
    )
    .visible;

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

      // The first 18px are the dead zone: the card holds still for them.
      final gesture = await tester.startGesture(const Offset(400, 300));
      await gesture.moveBy(const Offset(0, 18));
      await tester.pump();
      expect(cardRect(tester), screen);
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();

      // 300px down a 600px card is half a card height of travel.
      final scale = physics.scaleFor(0.5);
      expect(scale, lessThan(physics.panDismissThreshold));
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

  testWidgets('the grabbed content shrinks about the touch and trails it', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    const grab = Offset(200, 150);
    final gesture = await tester.startGesture(grab);
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();

    final rect = cardRect(tester);
    final fx = grab.dx / 800;
    final fy = grab.dy / 600;
    expect(rect.left + fx * rect.width, closeTo(grab.dx, 0.5));
    expect(
      rect.top + fy * rect.height,
      closeTo(grab.dy + physics.fallFor(120 / 600) * 600, 0.5),
    );
    expect(rect.top + fy * rect.height, lessThan(grab.dy + 120));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a short pan cancels and restores identity', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final navigator = navigatorOf(tester);

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(
      physics.scaleFor(60 / 600),
      greaterThan(physics.panDismissThreshold),
    );
    expect(cardRect(tester).width, lessThan(800));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(cardRect(tester), screen);
    expect(navigator.userGestureInProgress, isFalse);
    expect(sourceHidden(tester), isTrue);
  });

  testWidgets('a committed release pops and lands from where it was', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final navigator = navigatorOf(tester);
    final route = ModalRoute.of(tester.element(find.text('detail')))!;

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // Landing: the pop's own transition, from the departure frame.
    expect(route.isCurrent, isFalse);
    expect(route.animation!.status, AnimationStatus.reverse);
    // The gesture is over at the commit: a landing card is not grabbed
    // again, and a touch on it must reach the page underneath.
    expect(navigator.userGestureInProgress, isFalse);
    expect(cardRect(tester).width, lessThan(800 * physics.scaleFor(0.5)));

    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(route.isActive, isFalse);
    expect(navigator.userGestureInProgress, isFalse);
    expect(sourceHidden(tester), isFalse);
  });

  testWidgets('a committed release lands on the landing spring', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final route =
        ModalRoute.of(tester.element(find.text('detail')))!
            as TransitionRoute<void>;

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));

    // The pop's simulation is the landing spring from where the controller
    // is, not the push's.
    final value = route.animation!.value;
    final simulation = route.createSimulation(forward: false)!;
    expect(
      simulation.x(0.1),
      closeTo(
        SpringSimulation(physics.landingSpring, value, 0, 0).x(0.1),
        1e-6,
      ),
    );
    expect(
      simulation.x(0.1),
      isNot(
        closeTo(
          SpringSimulation(
            const ZoomTransitionOptions().pushSpring,
            value,
            0,
            0,
          ).x(0.1),
          1e-3,
        ),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a pinch released still closing lands sooner', (tester) async {
    await pushAndSettle(tester, staticDetail);
    // Closes the fingers from 200 apart to 90 slowly enough for the card to
    // follow, then either holds them still — the release rate is read from
    // the last hundred milliseconds of moves — or closes them 30 px more
    // in 12 ms before the lift, and returns how long the landing takes to
    // reach 98 % of the way to the source.
    Future<Duration> landingTime({required bool closing}) async {
      final first = await tester.startGesture(
        const Offset(300, 300),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(500, 300),
        pointer: 2,
      );
      Future<void> fingersAt(double gap, Duration at) async {
        await first.moveTo(Offset(400 - gap / 2, 300), timeStamp: at);
        await second.moveTo(Offset(400 + gap / 2, 300), timeStamp: at);
        await tester.pump();
      }

      for (var i = 1; i <= 3; i++) {
        await fingersAt(200 - 110 * i / 3, Duration(milliseconds: 100 * i));
        await tester.pump(const Duration(milliseconds: 100));
      }
      Duration lift;
      if (closing) {
        await fingersAt(75, const Duration(milliseconds: 306));
        await fingersAt(60, const Duration(milliseconds: 312));
        lift = const Duration(milliseconds: 314);
      } else {
        await fingersAt(90, const Duration(milliseconds: 500));
        await fingersAt(90, const Duration(milliseconds: 650));
        lift = const Duration(milliseconds: 700);
      }
      await first.up(timeStamp: lift);
      await second.up(timeStamp: lift);
      await tester.pump();
      final from = cardRect(tester).width;
      var elapsed = Duration.zero;
      while (cardRect(tester).width >
          posterRect.width + 0.02 * (from - posterRect.width)) {
        await tester.pump(const Duration(milliseconds: 16));
        elapsed += const Duration(milliseconds: 16);
        expect(elapsed, lessThan(const Duration(seconds: 1)));
      }
      await tester.pumpAndSettle();
      expect(find.text('detail'), findsNothing);
      return elapsed;
    }

    final atRest = await landingTime(closing: false);
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final closing = await landingTime(closing: true);
    expect(closing, lessThan(atRest - const Duration(milliseconds: 30)));
  });

  testWidgets('a size change while the card is held lets go', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final navigator = navigatorOf(tester);
    final route = ModalRoute.of(tester.element(find.text('detail')))!;
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    final held = route.animation!.value;
    expect(held, lessThan(1));

    // The window turns: a release at rest, short of the threshold here, so
    // the card returns, to the window as it is now; the finger still down
    // is not a new grab.
    tester.view.physicalSize = const Size(1800, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pump();
    // The release follows the frame the size change built; its ticker
    // starts on the next.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 50));
    final returning = route.animation!.value;
    expect(returning, greaterThan(held));
    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(route.animation!.value, greaterThan(returning));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(cardRect(tester), const Rect.fromLTWH(0, 0, 600, 800));
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('a touch during the landing lets it land', (tester) async {
    await pushAndSettle(tester, staticDetail);

    final first = await tester.startGesture(const Offset(400, 300));
    await first.moveBy(const Offset(0, 18));
    await first.moveBy(const Offset(0, 300));
    await tester.pump();
    await first.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final touchedAt = cardRect(tester);

    // Neither a finger nor a drag catches a landing card: the route is
    // popping, as on iOS, where the touch reaches the page underneath.
    final second = await tester.startGesture(touchedAt.center);
    await second.moveBy(const Offset(0, -40));
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      cardRect(tester).width,
      lessThan(touchedAt.width),
      reason: 'the landing flies on',
    );

    await second.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('a dismissal from rest lands on the current sourceTag', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final route = ModalRoute.of(tester.element(find.text('detail')))!;
    (route as ZoomPageRoute<void>).sourceTag = 'other';

    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final card = cardRect(tester);
    expect(
      (card.center - otherPosterRect.center).distance,
      lessThan((card.center - posterRect.center).distance),
    );
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('a downward fling short of the threshold still pops', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    // 120 ms at 1500 px/s is another 180px on top of the 60, which the
    // projection reads as past the boundary.
    expect(
      physics.scaleFor(60 / 600),
      greaterThan(physics.panDismissThreshold),
    );
    expect(
      physics.scaleFor((60 + 180) / 600),
      lessThan(physics.panDismissThreshold),
    );
    await tester.fling(find.text('detail'), const Offset(0, 60), 1500);
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('a pan follows the finger sideways at a fraction', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    final before = cardRect(tester);

    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final after = cardRect(tester);
    expect(after.size, before.size);
    expect(
      after.left - before.left,
      closeTo(physics.crossAxisOffsetFor(150, width: 800), 0.5),
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('a pan released moving back up springs back', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump();
    expect(physics.scaleFor(100 / 600), lessThan(physics.panDismissThreshold));
    // Three samples for the velocity tracker: 40px up in 20 ms is
    // 2000 px/s, which projects the card back above the boundary.
    for (var i = 1; i <= 3; i++) {
      await gesture.moveBy(
        const Offset(0, -13),
        timeStamp: Duration(milliseconds: 6 * i),
      );
      await tester.pump();
    }
    await gesture.up(timeStamp: const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('the release flies from where the card was', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final gesture = await tester.startGesture(const Offset(400, 300));
    await gesture.moveBy(const Offset(0, 18));
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

  testWidgets('a drag that begins on a scrolled list never hands off', (
    tester,
  ) async {
    await pushAndSettle(tester, listDetail());
    final list = tester.state<ScrollableState>(find.byType(Scrollable));
    await tester.drag(find.text('detail'), const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(list.position.pixels, closeTo(200, 1));

    // Down past the top: the list over-scrolls, as the native page does,
    // and the card stays put.
    final gesture = await tester.startGesture(const Offset(400, 400));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 200));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(list.position.pixels, lessThan(0));
    expect(cardRect(tester), screen);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(list.position.pixels, 0);
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('a drag that begins at the top of a list hands off', (
    tester,
  ) async {
    await pushAndSettle(tester, listDetail());
    final list = tester.state<ScrollableState>(find.byType(Scrollable));

    // The list's own recognizer wins the arena and, like any SDK drag, takes
    // the first move as slop; the dismissal counts its dead zone from the
    // touch all the same.
    final gesture = await tester.startGesture(const Offset(400, 400));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 300));
    await tester.pump();
    expect(list.position.pixels, 0);
    expect(
      cardRect(tester).width,
      closeTo(800 * physics.scaleFor((320 - 18) / 600), 0.5),
    );

    // Back up above where it was grabbed: the card grows back, the list
    // does not scroll.
    await gesture.moveBy(const Offset(0, -350));
    await tester.pump();
    expect(list.position.pixels, 0);
    expect(cardRect(tester), screen);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('a pan from the top of a list shrinks the card at once', (
    tester,
  ) async {
    await pushAndSettle(tester, listDetail());
    final gesture = await tester.startGesture(const Offset(400, 400));
    await gesture.moveBy(const Offset(0, 20));
    await gesture.moveBy(const Offset(0, 60));
    await tester.pump();
    expect(
      cardRect(tester).width,
      closeTo(800 * physics.scaleFor((80 - 18) / 600), 0.5),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('an edge swipe commits on where a flick would carry the card', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    // 163px past the dead zone leaves the card well above the threshold;
    // 120 ms at 2000 px/s is another 240px, which takes it below.
    expect(
      physics.edgeSwipeScaleFor(163 / 800),
      greaterThan(physics.dismissThreshold),
    );
    expect(
      physics.edgeSwipeScaleFor((163 + 240) / 800),
      lessThan(physics.dismissThreshold),
    );
    final gesture = await tester.startGesture(const Offset(5, 300));
    for (var i = 1; i <= 5; i++) {
      await gesture.moveBy(
        const Offset(35, 0),
        timeStamp: Duration(microseconds: 17500 * i),
      );
      await tester.pump();
    }
    await gesture.up(timeStamp: const Duration(microseconds: 95500));
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('an edge swipe follows a finger moving down at a fraction', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final gesture = await tester.startGesture(const Offset(5, 300));
    await gesture.moveBy(const Offset(112, 0));
    await tester.pump();
    final before = cardRect(tester);

    await gesture.moveBy(const Offset(0, 200));
    await tester.pump();
    final after = cardRect(tester);
    expect(after.width, closeTo(before.width, 0.001));
    expect(
      after.top - before.top,
      closeTo(physics.crossAxisOffsetFor(200, width: 800), 0.5),
    );
    expect(after.top - before.top, lessThan(200 * physics.crossAxisGain));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('an edge swipe shrinks the card by horizontal travel', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final gesture = await tester.startGesture(const Offset(5, 300));
    // The first 12px are the dead zone: the card stays put.
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();
    expect(cardRect(tester).width, 800);

    await gesture.moveBy(const Offset(190, 0));
    await tester.pump();
    // 188px past the dead zone across an 800px card, with no knee.
    expect(
      cardRect(tester).width,
      closeTo(800 * physics.edgeSwipeScaleFor(188 / 800), 0.5),
    );
    // The card's left edge follows the finger less the dead zone (the
    // grab point at 5 shrinks toward itself), off the right of the screen.
    // The sideways chase settles on the tracking spring.
    await tester.pump(const Duration(milliseconds: 300));
    final scale = physics.edgeSwipeScaleFor(188 / 800);
    expect(cardRect(tester).left, closeTo(5 * (1 - scale) + 188, 0.5));
    expect(cardRect(tester).right, greaterThan(800));

    await gesture.moveBy(const Offset(300, 0));
    await tester.pump();
    expect(
      physics.edgeSwipeScaleFor(488 / 800),
      lessThan(physics.dismissThreshold),
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('a touch during the push does not stop it', (tester) async {
    await tester.pumpWidget(testApp(detail: staticDetail));
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final route = ModalRoute.of(tester.element(find.text('detail')))!;
    final touched = route.animation!.value;
    expect(touched, inExclusiveRange(0, 1));

    // Inside the card at every point of the flight: the poster's centre.
    final gesture = await tester.startGesture(posterRect.center);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      route.animation!.value,
      greaterThan(touched),
      reason: 'the push flies on',
    );
    expect(navigatorOf(tester).userGestureInProgress, isFalse);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(route.animation!.isCompleted, isTrue);
  });

  testWidgets('a pan begun during the push takes the card as it flies', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(detail: staticDetail));
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final route = ModalRoute.of(tester.element(find.text('detail')))!;
    final navigator = navigatorOf(tester);

    final gesture = await tester.startGesture(posterRect.center);
    await gesture.moveBy(const Offset(0, 18));
    await gesture.moveBy(const Offset(0, 12));
    await tester.pump();
    expect(navigator.userGestureInProgress, isTrue);
    expect(route.animation!.status, AnimationStatus.reverse);
    final grabbed = cardRect(tester).width;
    expect(grabbed, lessThan(800));

    // The push completes underneath: the card grows past where the pan
    // took it, to the pan's scale of the full screen.
    await tester.pump(const Duration(milliseconds: 100));
    expect(cardRect(tester).width, greaterThan(grabbed));
    await tester.pump(const Duration(seconds: 1));
    final scale = physics.scaleFor(12 / 600);
    expect(cardRect(tester).width, closeTo(800 * scale, 0.5));
    expect(route.animation!.value, closeTo(scale, 0.001));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(route.animation!.isCompleted, isTrue);
    expect(navigator.userGestureInProgress, isFalse);
  });

  testWidgets('grabbing during the push diverts a hero flight', (tester) async {
    await tester.pumpWidget(testApp(detail: staticDetail, hero: true));
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // The hero in flight has a copy of the page's text in the overlay.
    final route = ModalRoute.of(
      tester.element(find.byType(ZoomTransitionLayer)),
    )!;

    final gesture = await tester.startGesture(posterRect.center);
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    expect(route.animation!.status, AnimationStatus.reverse);
    // A little, and slowly: the card is small this early in the push, so a
    // short drag is a long way in card heights, and a fast one is a fling.
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump(const Duration(milliseconds: 50));
    await gesture.moveBy(const Offset(0, 5));
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(navigatorOf(tester).userGestureInProgress, isFalse);
  });

  testWidgets('a drag while the card returns is the same gesture', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(detail: staticDetail, hero: true));
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final navigator = navigatorOf(tester);
    final route = ModalRoute.of(tester.element(find.text('detail')))!;

    final first = await tester.startGesture(const Offset(400, 300));
    await first.moveBy(const Offset(0, 18));
    await first.moveBy(const Offset(0, 50));
    await tester.pump();
    await first.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    expect(route.animation!.status, AnimationStatus.forward);
    expect(route.animation!.value, inExclusiveRange(0, 1));

    final second = await tester.startGesture(const Offset(400, 300));
    await second.moveBy(const Offset(0, 18));
    await second.moveBy(const Offset(0, 6));
    await tester.pump();
    final caughtAt = route.animation!.value;
    expect(navigator.userGestureInProgress, isTrue);
    await tester.pump(const Duration(milliseconds: 40));
    expect(
      route.animation!.value,
      greaterThan(caughtAt),
      reason: 'the return flies on under the drag',
    );
    expect(tester.takeException(), isNull);

    await second.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsOneWidget);
    expect(route.animation!.isCompleted, isTrue);
    expect(navigator.userGestureInProgress, isFalse);
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
    await first.moveTo(const Offset(304, 300));
    await second.moveTo(const Offset(496, 300));
    await tester.pump();

    // The first 9 pt of closing are the pinch's dead zone.
    expect(cardRect(tester), screen);

    await first.moveTo(const Offset(305, 300));
    await second.moveTo(const Offset(495, 300));
    await first.moveTo(const Offset(355, 300));
    await second.moveTo(const Offset(445, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The fingers closed from 191 apart, where the pinch took hold, to 90:
    // under half, which a release lands.
    expect(cardRect(tester).width, closeTo(800 * 90 / 191, 0.5));
    expect(cardRect(tester).height, closeTo(600 * 90 / 191, 0.5));
    expect(cardRect(tester).center.dx, closeTo(400, 0.5));
    expect(navigatorOf(tester).userGestureInProgress, isTrue);

    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    await second.up();
  });

  testWidgets('a pinch trails the fingers through the tracking spring', (
    tester,
  ) async {
    await pushAndSettle(tester, staticDetail);
    final first = await tester.startGesture(const Offset(300, 300), pointer: 1);
    final second = await tester.startGesture(
      const Offset(500, 300),
      pointer: 2,
    );
    await first.moveTo(const Offset(305, 300));
    await second.moveTo(const Offset(495, 300));
    await first.moveTo(const Offset(355, 300));
    await second.moveTo(const Offset(445, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // A frame in, the card is on its way to 90/191 of its size, not there.
    expect(cardRect(tester).width, lessThan(800));
    expect(cardRect(tester).width, greaterThan(800 * 90 / 191 + 20));

    await tester.pump(const Duration(milliseconds: 300));
    expect(cardRect(tester).width, closeTo(800 * 90 / 191, 0.5));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
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
    // A turn alone does nothing: the pinch takes hold on distance.
    await second.moveTo(
      Offset(300 + 200 * math.cos(angle), 300 + 200 * math.sin(angle)),
    );
    await tester.pump();
    expect(cardRotation(tester), 0);
    expect(cardRect(tester), screen);

    await second.moveTo(const Offset(500, 300));
    await second.moveTo(const Offset(491, 300));
    await second.moveTo(
      Offset(300 + 191 * math.cos(angle), 300 + 191 * math.sin(angle)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(cardRotation(tester), closeTo(angle, 1e-6));
    // The fingers are as far apart as when the pinch took hold, so the card
    // keeps its size (its bounding rect is wider, being rotated).
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
    await second.moveTo(const Offset(400, 380));
    await first.moveTo(const Offset(400, 230));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The fingers closed from 300 to 150 apart, the pinch taking hold 9 pt
    // in; the list did not scroll with either of them once it had.
    expect(cardRect(tester).width, closeTo(800 * 150 / 291, 0.5));
    expect(list.position.pixels, closeTo(200, 1));

    await first.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    await second.up();
  });

  testWidgets('a pinch begun with both fingers on a list outlives the pan', (
    tester,
  ) async {
    await pushAndSettle(tester, listDetail());
    final first = await tester.startGesture(const Offset(400, 150), pointer: 1);
    final second = await tester.startGesture(
      const Offset(400, 450),
      pointer: 2,
    );
    // The list wins the first finger's arena on these moves and cancels
    // the pan recognizer under the pinch.
    for (var i = 0; i < 18; i++) {
      await first.moveBy(const Offset(0, 5));
      await second.moveBy(const Offset(0, -5));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    // 300 apart to 120, the pinch taking hold 9 pt in.
    expect(cardRect(tester).width, closeTo(800 * 120 / 291, 0.5));

    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
  });

  testWidgets('a second finger turns a pan into a pinch', (tester) async {
    await pushAndSettle(tester, staticDetail);
    final first = await tester.startGesture(const Offset(400, 200), pointer: 1);
    await first.moveBy(const Offset(0, 18));
    await first.moveBy(const Offset(0, 100));
    await tester.pump();
    final panned = cardRect(tester);
    expect(panned.width, closeTo(800 * physics.scaleFor(100 / 600), 0.5));

    final second = await tester.startGesture(
      const Offset(400, 568),
      pointer: 2,
    );
    await second.moveTo(const Offset(400, 428));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 250 apart to 110, the pinch taking hold 9 pt in: 110/241 of the size
    // the pan left the card at, under half of it.
    expect(cardRect(tester).width, closeTo(panned.width * 110 / 241, 0.5));

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
    await gesture.moveBy(const Offset(0, 18));
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
