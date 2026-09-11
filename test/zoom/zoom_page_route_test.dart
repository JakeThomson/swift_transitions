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

  testWidgets('the strip the covered page uncovers is painted', (tester) async {
    await tester.pumpWidget(testApp());
    final backdrop = find.ancestor(
      of: find.text('home'),
      matching: find.byType(ColoredBox),
    );

    // Nothing to cover while the page is still full screen.
    expect(backdrop, findsNothing);

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();

    // The scale leaves a strip at the screen's edges. Natively that strip
    // is the window behind the page and carries the system background; a
    // zoom route is not opaque, so the strip is painted here instead of
    // falling through to the window's black.
    expect(backdrop, findsOneWidget);
    expect(tester.getRect(backdrop), const Rect.fromLTWH(0, 0, 800, 600));
    expect(
      tester.widget<ColoredBox>(backdrop).color,
      isSameColorAs(CupertinoColors.systemBackground.color),
    );
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

  testWidgets('the pop lands on a source whose page took no scale', (
    tester,
  ) async {
    // A route underneath that declines the transition is not scaled
    // ([_CoveredPage] never wraps it), so the source rests where it is
    // measured; the flight must not read it back through a scale the
    // page was never drawn at.
    await tester.pumpWidget(
      CupertinoApp(
        onGenerateRoute: (settings) => _DecliningRoute<void>(
          builder: (context) => Stack(
            children: <Widget>[
              const Positioned.fill(child: Text('home')),
              Positioned.fromRect(
                rect: posterRect,
                child: ZoomTransitionSource(
                  tag: 'poster',
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      ZoomPageRoute<void>(
                        sourceTag: 'poster',
                        builder: (_) => const Center(child: Text('detail')),
                      ),
                    ),
                    child: const Text('poster'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final homeBefore = tester.getRect(find.text('home'));
    await tester.tap(find.text('poster'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('home')), homeBefore);

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
    final art = GlobalKey();
    final measured = <Rect?>[];
    await tester.pumpWidget(
      testApp(
        options: ZoomTransitionOptions(
          alignmentRect: (context) {
            asked.add(context);
            measured.add(context.rectOf(art.currentContext!));
            return const Rect.fromLTWH(0, 0, 400, 300);
          },
        ),
        detail: Stack(
          children: <Widget>[
            const Center(child: Text('detail')),
            Positioned.fromRect(
              rect: const Rect.fromLTWH(40, 160, 300, 200),
              child: SizedBox(key: art),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('push'));
    // The push came from a tap handler, before its page was built: the
    // provider is asked at the end of the first frame, with the page laid
    // out; that frame drew the card as the source's picture regardless.
    await tester.pump();
    expect(asked, hasLength(1));
    await tester.pumpAndSettle();
    expect(asked, hasLength(1));
    expect(asked.single.direction, ZoomFlightDirection.push);
    expect(asked.single.sourceRect, posterRect);
    expect(asked.single.pageSize, screen.size);
    expect(
      (asked.single.pageContext.findRenderObject()! as RenderBox).size,
      screen.size,
    );
    expect(measured.single, const Rect.fromLTWH(40, 160, 300, 200));

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

  testWidgets(
    'an aligned page flies as the whole page scaled onto its source',
    (tester) async {
      const art = Rect.fromLTWH(40, 160, 300, 200);
      await tester.pumpWidget(
        testApp(options: ZoomTransitionOptions(alignmentRect: (_) => art)),
      );
      await tester.tap(find.text('push'));
      await tester.pump();
      ZoomTransitionLayer layer() =>
          tester.widget<ZoomTransitionLayer>(find.byType(ZoomTransitionLayer));
      final landing = zoomAlignedLandingRect(
        source: posterRect,
        alignment: art,
        pageSize: screen.size,
      );
      // The poster is 80 by 120 and the art 300 by 200: the page lands at
      // 0.6, 480 by 360, the art covering the poster from its top left
      // and overhanging it to the right.
      expect(landing.size, const Size(480, 360));
      final artAtLanding = Rect.fromLTWH(
        landing.left + art.left * 0.6,
        landing.top + art.top * 0.6,
        art.width * 0.6,
        art.height * 0.6,
      );
      expect(artAtLanding.topLeft, posterRect.topLeft);
      expect(artAtLanding.height, posterRect.height);
      expect(artAtLanding.width, greaterThan(posterRect.width));
      await tester.pump(const Duration(milliseconds: 80));
      final route = detailRoute(tester);
      final t = route.animation!.value;
      expect(t, inExclusiveRange(0.1, 0.9));
      // The card is the ordinary one, on the line from the poster to the
      // screen; the page behind it scales from its landing to itself, and
      // fades in with the flight over the source's picture.
      expect(
        layer().frame.rect.width,
        closeTo(lerpDouble(posterRect.width, 800, t)!, 1),
      );
      expect(layer().pageRect!.width, closeTo(lerpDouble(480, 800, t)!, 1));
      expect(layer().pageOpacity, closeTo(t, 1e-9));
      expect(
        layer().frame.sourceOpacity,
        closeTo(zoomAlignedPictureOpacity(t), 1e-9),
      );
      expect(layer().alignmentRect, art);
      await tester.pumpAndSettle();
      expect(layer().pageOpacity, 1);
    },
  );

  testWidgets('the page keeps its element through a flight', (tester) async {
    // An aligned flight changes what the card's stack holds around the
    // page; the page must not be rebuilt for it, or a scroll view loses
    // its position and the dismissal its hand-off.
    const art = Rect.fromLTWH(40, 160, 300, 200);
    await tester.pumpWidget(
      testApp(
        options: ZoomTransitionOptions(alignmentRect: (_) => art),
        detail: const _Stateful(),
      ),
    );
    await tester.tap(find.text('push'));
    await tester.pump();
    await tester.pump();
    final first = tester.state<_StatefulState>(find.byType(_Stateful));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.state<_StatefulState>(find.byType(_Stateful)), same(first));
    await tester.pumpAndSettle();
    expect(tester.state<_StatefulState>(find.byType(_Stateful)), same(first));
    Navigator.of(tester.element(find.text('detail'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.state<_StatefulState>(find.byType(_Stateful)), same(first));
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

  /// A home with the same tag on two tabs of an [IndexedStack], the visible
  /// tab's source at [posterRect] and the hidden tab's at [otherPosterRect],
  /// plus a third copy under a disabled [HeroMode] at [otherPosterRect].
  Widget tabbedApp() {
    return DisplayCornerRadii(
      radii: BorderRadius.circular(40),
      child: CupertinoApp(
        home: Builder(
          builder: (context) => Stack(
            children: <Widget>[
              IndexedStack(
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      Positioned.fromRect(
                        rect: posterRect,
                        child: const ZoomTransitionSource(
                          tag: 'poster',
                          child: Text('visible'),
                        ),
                      ),
                    ],
                  ),
                  Stack(
                    children: <Widget>[
                      Positioned.fromRect(
                        rect: otherPosterRect,
                        child: const ZoomTransitionSource(
                          tag: 'poster',
                          child: Text('offstage'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Positioned.fromRect(
                rect: otherPosterRect,
                child: const HeroMode(
                  enabled: false,
                  child: ZoomTransitionSource(
                    tag: 'poster',
                    child: Text('hero mode off'),
                  ),
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
    );
  }

  testWidgets(
    'a source on a non-selected IndexedStack tab or under a disabled HeroMode '
    'is not matched',
    (tester) async {
      await tester.pumpWidget(tabbedApp());
      // Two sources share the tag with the visible one; only the visible one
      // is a candidate, so this does not trip the duplicate-tag assertion
      // and the flight leaves from the tab the user can see.
      await tester.tap(find.text('push'));
      await tester.pump();
      await tester.pump();
      expect(cardRect(tester), rectCloseTo(posterRect));
      final hidden = find.byWidgetPredicate(
        (widget) => widget is Visibility && !widget.visible,
      );
      expect(
        tester
            .widget<Text>(
              find.descendant(of: hidden, matching: find.byType(Text)),
            )
            .data,
        'visible',
      );

      await tester.pumpAndSettle();
      Navigator.of(tester.element(find.text('detail'))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final t = detailRoute(tester).animation!.value;
      expect(cardRect(tester), rectCloseTo(popRect(posterRect, t)));
    },
  );

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

class _Stateful extends StatefulWidget {
  const _Stateful();

  @override
  State<_Stateful> createState() => _StatefulState();
}

class _StatefulState extends State<_Stateful> {
  @override
  Widget build(BuildContext context) => const Center(child: Text('detail'));
}

/// A page route that declines every transition, so a zoom route pushed on
/// top of it neither scales nor dims it.
class _DecliningRoute<T> extends PageRoute<T> {
  _DecliningRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Duration.zero;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);
}
