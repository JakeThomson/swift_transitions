import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:swift_transitions/swift_transitions.dart';

/// Frame times for the transitions, in profile mode on a device or the
/// desktop (the simulator cannot build profile mode):
///
///     flutter drive --profile -d <device> \
///       --driver=test_driver/perf_driver.dart \
///       --target=integration_test/perf_test.dart
///
/// Two apps are measured: a light one of flat colour and text, as the
/// gallery is, and a heavy one of glass surfaces — `BackdropFilter` blurs
/// over a gradient — as a host app's pages are. Each scenario's timeline is
/// summarised to `build/perf/<key>.timeline_summary.json` by the driver; a
/// `#n` suffix on a key merges its runs into one summary.
/// The frame events — the framework's on the Dart stream, the engine's on
/// the embedder's — and no more: every stream of a scroll's worth of frames
/// is more than the service connection survives.
const List<String> _streams = <String>['Dart', 'Embedder'];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final heavy in <bool>[false, true]) {
    final prefix = heavy ? 'heavy' : 'light';

    testWidgets('$prefix: zoom push and pop', (tester) async {
      await _start(tester, heavy: heavy);
      for (var i = 0; i < 4; i++) {
        await binding.traceAction(
          () => _pushZoom(tester),
          reportKey: '${prefix}_zoom_push#$i',
          streams: _streams,
        );
        await binding.traceAction(
          () => _pop(tester),
          reportKey: '${prefix}_zoom_pop#$i',
          streams: _streams,
        );
      }
    });

    testWidgets('$prefix: push and pop', (tester) async {
      await _start(tester, heavy: heavy);
      for (var i = 0; i < 4; i++) {
        await binding.traceAction(
          () => _pushSwift(tester),
          reportKey: '${prefix}_push_push#$i',
          streams: _streams,
        );
        await binding.traceAction(
          () => _pop(tester),
          reportKey: '${prefix}_push_pop#$i',
          streams: _streams,
        );
      }
    });
  }

  testWidgets('heavy: scrolling a zoom page at rest', (tester) async {
    await _start(tester, heavy: true);
    await _pushZoom(tester);
    await binding.traceAction(
      () => _scroll(tester, depth: 1),
      reportKey: 'heavy_zoom_rest_scroll',
      streams: _streams,
    );
    await _pop(tester);
  });

  testWidgets('heavy: scrolling a pushed page at rest', (tester) async {
    await _start(tester, heavy: true);
    await _pushSwift(tester);
    await binding.traceAction(
      () => _scroll(tester, depth: 1),
      reportKey: 'heavy_push_rest_scroll',
      streams: _streams,
    );
    await _pop(tester);
  });

  testWidgets('heavy: scrolling the top of three zoom pages', (tester) async {
    await _start(tester, heavy: true);
    await _pushZoom(tester);
    await _pushNext(tester, depth: 1);
    await _pushNext(tester, depth: 2);
    await binding.traceAction(
      () => _scroll(tester, depth: 3),
      reportKey: 'heavy_zoom_stack3_rest_scroll',
      streams: _streams,
    );
    await _pop(tester);
    await _pop(tester);
    await _pop(tester);
  });

  testWidgets('heavy: pan to dismiss', (tester) async {
    await _start(tester, heavy: true);
    await binding.traceAction(
      () async {
        for (var i = 0; i < 3; i++) {
          await _pushZoom(tester);
          await _panDismiss(tester);
        }
      },
      reportKey: 'heavy_zoom_pan_dismiss',
      streams: _streams,
    );
  });
}

final GlobalKey<NavigatorState> _navigator = GlobalKey<NavigatorState>();

Future<void> _start(WidgetTester tester, {required bool heavy}) async {
  await tester.pumpWidget(_BenchApp(heavy: heavy));
  await tester.pumpAndSettle();
  // The first frames of a fresh app carry shader and font warm-up.
  await tester.pump(const Duration(milliseconds: 500));
}

/// The source itself, not the copy of it a card in flight draws.
Future<void> _pushZoom(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('card')).hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _pushSwift(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('tile')));
  await tester.pumpAndSettle();
}

Future<void> _pushNext(WidgetTester tester, {required int depth}) async {
  await tester.tap(find.byKey(ValueKey<String>('next:$depth')).hitTestable());
  await tester.pumpAndSettle();
}

Future<void> _pop(WidgetTester tester) async {
  _navigator.currentState!.pop();
  await tester.pumpAndSettle();
}

/// Six drags down the page and five back up, each a third of a second:
/// one short of home, since a drag down from the top is the pan.
Future<void> _scroll(WidgetTester tester, {required int depth}) async {
  final list = find.byKey(ValueKey<String>('detail:$depth'));
  const step = Duration(milliseconds: 300);
  for (var i = 0; i < 6; i++) {
    await tester.timedDrag(list, const Offset(0, -300), step);
    await tester.pumpAndSettle();
  }
  for (var i = 0; i < 5; i++) {
    await tester.timedDrag(list, const Offset(0, 300), step);
    await tester.pumpAndSettle();
  }
}

/// A finger dragged 300 pt down the page from its top edge over about a
/// third of a second, then let go: past the pan's commit line.
Future<void> _panDismiss(WidgetTester tester) async {
  final size = tester.getSize(find.byType(CupertinoApp));
  final gesture = await tester.startGesture(Offset(size.width / 2, 200));
  for (var i = 0; i < 30; i++) {
    await gesture.moveBy(const Offset(0, 10));
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

class _BenchApp extends StatelessWidget {
  const _BenchApp({required this.heavy});

  final bool heavy;

  @override
  Widget build(BuildContext context) {
    // The clip and the card's corners as on an iPhone, whatever the host.
    return DisplayCornerRadii(
      radii: BorderRadius.circular(62),
      child: CupertinoApp(
        navigatorKey: _navigator,
        debugShowCheckedModeBanner: false,
        home: _HomePage(heavy: heavy),
      ),
    );
  }
}

class _HomePage extends StatelessWidget {
  const _HomePage({required this.heavy});

  final bool heavy;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Benchmark')),
      child: _Backdrop(
        heavy: heavy,
        child: ListView(
          children: <Widget>[
            const SizedBox(height: 100),
            CupertinoListTile(
              key: const ValueKey<String>('tile'),
              title: const Text('Push'),
              onTap: () => Navigator.of(context).push(
                SwiftPageRoute<void>(
                  builder: (_) => _DetailPage(heavy: heavy, depth: 1),
                ),
              ),
            ),
            for (var section = 0; section < 8; section++)
              _CardRow(heavy: heavy, section: section),
          ],
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.heavy, required this.section});

  final bool heavy;
  final int section;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (context, index) {
          final tag = 'card:$section:$index';
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ZoomTransitionSource(
              tag: tag,
              borderRadius: _Surface.radius,
              child: GestureDetector(
                key: section == 0 && index == 0
                    ? const ValueKey<String>('card')
                    : null,
                onTap: () => Navigator.of(context).push(
                  ZoomPageRoute<void>(
                    sourceTag: tag,
                    builder: (_) => _DetailPage(heavy: heavy, depth: 1),
                  ),
                ),
                child: _Surface(
                  heavy: heavy,
                  width: 140,
                  child: Text('Card $section.$index'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DetailPage extends StatelessWidget {
  const _DetailPage({required this.heavy, required this.depth});

  final bool heavy;
  final int depth;

  @override
  Widget build(BuildContext context) {
    final tag = 'next:$depth';
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text('Detail $depth')),
      child: _Backdrop(
        heavy: heavy,
        child: ListView(
          key: ValueKey<String>('detail:$depth'),
          primary: true,
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
          children: <Widget>[
            _Surface(
              heavy: heavy,
              height: 220,
              child: Text(
                'Detail $depth',
                style: const TextStyle(fontSize: 34),
              ),
            ),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.all(16),
                child: _Surface(
                  heavy: heavy,
                  height: 120,
                  child: Text('Surface $i\n$_paragraph'),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: ZoomTransitionSource(
                  tag: tag,
                  borderRadius: _Surface.radius,
                  child: GestureDetector(
                    key: ValueKey<String>(tag),
                    onTap: () => Navigator.of(context).push(
                      ZoomPageRoute<void>(
                        sourceTag: tag,
                        builder: (_) =>
                            _DetailPage(heavy: heavy, depth: depth + 1),
                      ),
                    ),
                    child: _Surface(
                      heavy: heavy,
                      width: 140,
                      height: 200,
                      child: const Text('Next'),
                    ),
                  ),
                ),
              ),
            ),
            for (var i = 0; i < 30; i++)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text('$i. $_paragraph'),
              ),
          ],
        ),
      ),
    );
  }
}

/// A page's ground: a gradient with a few shapes for the glass to blur, or
/// white.
class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.heavy, required this.child});

  final bool heavy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!heavy) {
      return ColoredBox(color: CupertinoColors.white, child: child);
    }
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF2B1055), Color(0xFF7597DE)],
            ),
          ),
        ),
        for (var i = 0; i < 5; i++)
          Positioned(
            left: 60.0 * i - 40,
            top: 150.0 * i,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(
                  const Color(0xFFFF8C42),
                  const Color(0xFF3AD7C5),
                  i / 4,
                )!.withValues(alpha: 0.7),
              ),
            ),
          ),
        child,
      ],
    );
  }
}

/// A glass surface — a blur of what is behind it under a tinted fill —
/// or a flat one.
class _Surface extends StatelessWidget {
  const _Surface({
    required this.heavy,
    this.width,
    this.height,
    required this.child,
  });

  static const BorderRadius radius = BorderRadius.all(Radius.circular(16));

  final bool heavy;
  final double? width;
  final double? height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: width,
      height: height,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: CupertinoColors.white),
          child: child,
        ),
      ),
    );
    if (!heavy) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF3A7BD5),
          borderRadius: radius,
        ),
        child: content,
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0x66FFFFFF)),
            gradient: const LinearGradient(
              colors: <Color>[Color(0x55FFFFFF), Color(0x22FFFFFF)],
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}

const String _paragraph =
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
    'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
    'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip.';
