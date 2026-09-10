import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/src/zoom/zoom_frame.dart';
import 'package:swift_transitions/src/zoom/zoom_transition_layer.dart';
import 'package:swift_transitions/swift_transitions.dart';

/// Where the test app lays out its poster: a known rect in an 800x600 view.
const Rect posterRect = Rect.fromLTWH(100, 200, 80, 120);
const Rect otherPosterRect = Rect.fromLTWH(300, 200, 80, 120);

/// A home page with two posters at fixed positions, each a source, and a
/// button that pushes a [ZoomPageRoute] for [pushTag].
Widget testApp({
  Object pushTag = 'poster',
  ZoomTransitionOptions options = const ZoomTransitionOptions(),
  bool disableAnimations = false,
  Widget detail = const Center(child: Text('detail')),
  VoidCallback? onPosterTap,
  VoidCallback? onOtherTap,
}) {
  return DisplayCornerRadii(
    radii: BorderRadius.circular(40),
    child: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: CupertinoApp(
        home: Builder(
          builder: (context) => Stack(
            children: <Widget>[
              const Positioned.fill(child: Text('home')),
              Positioned.fromRect(
                rect: posterRect,
                child: ZoomTransitionSource(
                  tag: 'poster',
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    onTap: onPosterTap,
                    child: const ColoredBox(
                      color: Color(0xFF0000FF),
                      child: Text('poster'),
                    ),
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: otherPosterRect,
                child: ZoomTransitionSource(
                  tag: 'other',
                  child: GestureDetector(
                    onTap: onOtherTap,
                    child: const ColoredBox(
                      color: Color(0xFFFF0000),
                      child: Text('other'),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    ZoomPageRoute<void>(
                      sourceTag: pushTag,
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
    ),
  );
}

Rect cardRect(WidgetTester tester) => tester.getRect(
  find.descendant(
    of: find.byType(ZoomTransitionLayer),
    matching: find.byType(ClipRSuperellipse),
  ),
);

ClipRSuperellipse cardClip(WidgetTester tester) =>
    tester.widget<ClipRSuperellipse>(
      find.descendant(
        of: find.byType(ZoomTransitionLayer),
        matching: find.byType(ClipRSuperellipse),
      ),
    );

ModalRoute<Object?> detailRoute(WidgetTester tester) =>
    ModalRoute.of(tester.element(find.text('detail')))!;

/// The offstage state of the source tagged [tag].
bool sourceHidden(WidgetTester tester, String tag) {
  final source = find.byWidgetPredicate(
    (widget) => widget is ZoomTransitionSource && widget.tag == tag,
  );
  return !tester
      .widget<Visibility>(
        find.descendant(of: source, matching: find.byType(Visibility)),
      )
      .visible;
}

Rect sourceRect(WidgetTester tester, String tag) => tester.getRect(
  find.byWidgetPredicate(
    (widget) => widget is ZoomTransitionSource && widget.tag == tag,
  ),
);

Matcher rectCloseTo(Rect expected, {double distance = 0.5}) => predicate<Rect>(
  (rect) =>
      (rect.left - expected.left).abs() < distance &&
      (rect.top - expected.top).abs() < distance &&
      (rect.right - expected.right).abs() < distance &&
      (rect.bottom - expected.bottom).abs() < distance,
  'a rect within $distance of $expected',
);

void main() {
  const screen = Rect.fromLTWH(0, 0, 800, 600);

  /// Where a popping card is at progress [t]: a lerp whose vertical edges
  /// run a little ahead.
  Rect popRect(Rect source, double t) {
    final ty = zoomVerticalProgress(t, pushing: false);
    return Rect.fromLTRB(
      lerpDouble(source.left, screen.left, t)!,
      lerpDouble(source.top, screen.top, ty)!,
      lerpDouble(source.right, screen.right, t)!,
      lerpDouble(source.bottom, screen.bottom, ty)!,
    );
  }

  testWidgets('the card starts on the source and lands on the screen', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('push'));
    await tester.pump();
    // The source is found at the end of the first frame; the card is drawn
    // from the second.
    await tester.pump();

    expect(cardRect(tester), posterRect);
    expect(cardClip(tester).borderRadius, BorderRadius.circular(12));

    await tester.pumpAndSettle();
    expect(cardRect(tester), rectCloseTo(screen));
    expect(cardClip(tester).clipBehavior, Clip.none);
    expect(cardClip(tester).borderRadius, BorderRadius.zero);
  });

  testWidgets('mid-flight the card is the lerp of the source and the screen', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final t = detailRoute(tester).animation!.value;
    expect(t, inExclusiveRange(0, 1));
    final ty = zoomPushVerticalProgress(t);
    expect(
      cardRect(tester),
      rectCloseTo(
        Rect.fromLTRB(
          lerpDouble(posterRect.left, screen.left, t)!,
          lerpDouble(posterRect.top, screen.top, ty)!,
          lerpDouble(posterRect.right, screen.right, t)!,
          lerpDouble(posterRect.bottom, screen.bottom, ty)!,
        ),
      ),
    );
    expect(
      cardClip(tester).borderRadius,
      BorderRadius.lerp(
        BorderRadius.circular(12),
        BorderRadius.circular(40),
        t,
      ),
    );
    expect(cardClip(tester).clipBehavior, Clip.antiAlias);
  });

  testWidgets('the covered page is scaled down and dimmed', (tester) async {
    await tester.pumpWidget(testApp());
    final homeBefore = tester.getRect(find.text('home'));
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(tester.getRect(find.text('home')).width, lessThan(homeBefore.width));
    // The home CupertinoPageRoute has a barrier of its own; the zoom
    // route's is the topmost.
    Color barrierColor() => tester
        .widget<AnimatedModalBarrier>(find.byType(AnimatedModalBarrier).last)
        .color
        .value!;
    expect(barrierColor().a, greaterThan(0));
    expect(barrierColor().a, lessThan(0x26 / 0xFF));

    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.text('home')).width,
      closeTo(homeBefore.width * zoomCoveredPageScale(1), 0.5),
    );
    // Scaled about the screen's centre, so the page keeps its middle.
    expect(
      tester.getRect(find.text('home')).center.dx,
      closeTo(
        400 + (homeBefore.center.dx - 400) * zoomCoveredPageScale(1),
        0.5,
      ),
    );
    expect(barrierColor().a, closeTo(0x26 / 0xFF, 0.01));
  });

  testWidgets('the source is hidden while the route is up and shown after', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    final slot = sourceRect(tester, 'poster');
    await tester.tap(find.text('push'));
    await tester.pump();
    // Pushed from a tap, the source is found before the first frame and
    // its placeholder is already in.
    expect(sourceHidden(tester, 'poster'), isTrue);
    expect(sourceRect(tester, 'poster'), slot);

    await tester.pumpAndSettle();
    expect(sourceHidden(tester, 'poster'), isTrue);
    expect(sourceHidden(tester, 'other'), isFalse);

    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(sourceHidden(tester, 'poster'), isTrue);

    await tester.pumpAndSettle();
    expect(find.text('detail'), findsNothing);
    expect(sourceHidden(tester, 'poster'), isFalse);
    expect(sourceRect(tester, 'poster'), slot);
  });

  testWidgets('the source takes no tap until the landing is over', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(testApp(onPosterTap: () => taps++));
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(sourceHidden(tester, 'poster'), isTrue);

    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // Natively this tap would reach the poster and push again; the page
    // behind a flying card takes nothing here (design.md section 1.7).
    await tester.tapAt(posterRect.center);
    await tester.pumpAndSettle();
    expect(taps, 0);
    expect(find.text('detail'), findsNothing);

    await tester.tapAt(posterRect.center);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('the page behind takes no touches until the pop finishes', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(testApp(onOtherTap: () => taps++));
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(otherPosterRect.center);
    await tester.pump(const Duration(milliseconds: 60));
    expect(taps, 0);

    await tester.pumpAndSettle();
    await tester.tapAt(otherPosterRect.center);
    await tester.pumpAndSettle();
    expect(taps, 1);
  });

  testWidgets('the pop shrinks the card back onto the source', (tester) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final t = detailRoute(tester).animation!.value;
    expect(t, inExclusiveRange(0, 1));
    expect(cardRect(tester), rectCloseTo(popRect(posterRect, t)));
  });

  testWidgets('a changed sourceTag lands the pop on the new source', (
    tester,
  ) async {
    await tester.pumpWidget(testApp());
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    final route = detailRoute(tester) as ZoomPageRoute<void>;
    route.sourceTag = 'other';
    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final t = route.animation!.value;
    expect(cardRect(tester), rectCloseTo(popRect(otherPosterRect, t)));
    expect(sourceHidden(tester, 'other'), isTrue);
    expect(sourceHidden(tester, 'poster'), isFalse);

    await tester.pumpAndSettle();
    expect(sourceHidden(tester, 'other'), isFalse);
  });

  testWidgets('alignmentRect is asked on the push and again on the pop', (
    tester,
  ) async {
    final asked = <ZoomAlignmentRectContext>[];
    await tester.pumpWidget(
      testApp(
        options: ZoomTransitionOptions(
          alignmentRect: (context) {
            asked.add(context);
            return const Rect.fromLTWH(0, 0, 400, 300);
          },
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(asked, hasLength(1));
    expect(asked.single.direction, ZoomFlightDirection.push);
    expect(asked.single.sourceRect, posterRect);
    expect(asked.single.pageSize, screen.size);

    final route = detailRoute(tester) as ZoomPageRoute<void>;
    route.sourceTag = 'other';
    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump();
    expect(asked, hasLength(2));
    expect(asked.last.direction, ZoomFlightDirection.pop);
    expect(asked.last.sourceRect, otherPosterRect);
    await tester.pumpAndSettle();
  });

  testWidgets('snapshotDuringTransition rasterises the page only in flight', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        options: const ZoomTransitionOptions(snapshotDuringTransition: true),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    SnapshotWidget snapshot() => tester.widget<SnapshotWidget>(
      find.descendant(
        of: find.byType(ZoomTransitionLayer),
        matching: find.byType(SnapshotWidget),
      ),
    );
    expect(snapshot().controller.allowSnapshotting, isTrue);
    expect(snapshot().mode, SnapshotMode.permissive);

    await tester.pumpAndSettle();
    expect(snapshot().controller.allowSnapshotting, isFalse);
  });

  testWidgets('a missing source falls back to a centred scale-and-fade', (
    tester,
  ) async {
    await tester.pumpWidget(testApp(pushTag: 'nowhere'));
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump();

    final start = cardRect(tester);
    expect(start.center, screen.center);
    expect(start.width, lessThan(screen.width));
    expect(start.height, lessThan(screen.height));
    expect(
      tester
          .widget<Opacity>(
            find.ancestor(
              of: find.byType(ZoomTransitionLayer),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      0,
    );
    expect(sourceHidden(tester, 'poster'), isFalse);

    await tester.pumpAndSettle();
    expect(cardRect(tester), rectCloseTo(screen));
    expect(sourceHidden(tester, 'poster'), isFalse);
  });

  testWidgets('a disabled source is not matched', (tester) async {
    await tester.pumpWidget(
      DisplayCornerRadii(
        radii: BorderRadius.circular(40),
        child: CupertinoApp(
          home: Builder(
            builder: (context) => Stack(
              children: <Widget>[
                Positioned.fromRect(
                  rect: posterRect,
                  child: const ZoomTransitionSource(
                    tag: 'poster',
                    enabled: false,
                    child: Text('poster'),
                  ),
                ),
                CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    ZoomPageRoute<void>(
                      sourceTag: 'poster',
                      builder: (_) => const Text('detail'),
                    ),
                  ),
                  child: const Text('push'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump();

    expect(cardRect(tester).center, screen.center);
    expect(sourceHidden(tester, 'poster'), isFalse);
  });

  testWidgets('Reduce Motion fades the page in with no card', (tester) async {
    await tester.pumpWidget(testApp(disableAnimations: true));
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));

    expect(find.byType(ZoomTransitionLayer), findsNothing);
    final fade = tester.widget<FadeTransition>(
      find.ancestor(
        of: find.text('detail'),
        matching: find.byType(FadeTransition),
      ),
    );
    // Half way through the native 140 ms.
    expect(fade.opacity.value, closeTo(0.5, 0.01));
    expect(sourceHidden(tester, 'poster'), isFalse);
    await tester.pump(const Duration(milliseconds: 70));
    expect(fade.opacity.value, 1);
  });

  testWidgets('a SwiftPageRoute pushed on top slides the zoomed page', (
    tester,
  ) async {
    await tester.pumpWidget(
      testApp(
        detail: Builder(
          builder: (context) => Center(
            child: CupertinoButton(
              onPressed: () => Navigator.of(
                context,
              ).push(SwiftPageRoute<void>(builder: (_) => const Text('third'))),
              child: const Text('detail'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.text('detail'));

    await tester.tap(find.text('detail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.getTopLeft(find.text('detail')).dx, lessThan(before.dx));
    expect(sourceHidden(tester, 'poster'), isTrue);

    await tester.pumpAndSettle();
    expect(find.text('third'), findsOneWidget);
  });

  testWidgets('ZoomPage builds the same transition for a pages navigator', (
    tester,
  ) async {
    var showDetail = false;
    late StateSetter setState;
    await tester.pumpWidget(
      DisplayCornerRadii(
        radii: BorderRadius.circular(40),
        child: CupertinoApp(
          home: StatefulBuilder(
            builder: (context, setter) {
              setState = setter;
              return Navigator(
                onDidRemovePage: (page) => showDetail = false,
                pages: <Page<void>>[
                  CupertinoPage<void>(
                    child: Stack(
                      children: <Widget>[
                        Positioned.fromRect(
                          rect: posterRect,
                          child: const ZoomTransitionSource(
                            tag: 'poster',
                            child: Text('poster'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (showDetail)
                    const ZoomPage<void>(
                      sourceTag: 'poster',
                      child: Center(child: Text('detail')),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    setState(() => showDetail = true);
    await tester.pump();
    await tester.pump();

    expect(cardRect(tester), posterRect);
    await tester.pumpAndSettle();
    expect(cardRect(tester), rectCloseTo(screen));
    expect(sourceHidden(tester, 'poster'), isTrue);
  });
}
