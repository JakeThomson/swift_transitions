import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:swift_transitions/swift_transitions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Parity.load();
  runApp(const ExampleApp());
}

/// Launch-environment switches shared with the native reference app, so
/// the parity driver (docs/parity-plan.md) configures both the same way:
/// `PARITY_SHOW_TOUCHES` draws a ring under every pointer and
/// `PARITY_FLAT` swaps the poster gradients for flat colour. Dart cannot
/// read the launch environment on iOS, so the Runner hands it over.
abstract final class Parity {
  static const MethodChannel _channel = MethodChannel(
    'swift_transitions.example/parity',
  );

  /// Whether to draw a ring under every pointer.
  static bool showTouches = false;

  /// Whether to draw the posters and pages in flat colour.
  static bool flat = false;

  /// Reads the switches from the launch environment.
  static Future<void> load() async {
    var environment = Platform.environment;
    if (Platform.isIOS) {
      try {
        final handed = await _channel.invokeMapMethod<String, String>(
          'environment',
        );
        if (handed != null) {
          environment = handed;
        }
      } on MissingPluginException {
        // Not running in the example's own Runner.
      }
    }
    showTouches = environment['PARITY_SHOW_TOUCHES'] == '1';
    flat = environment['PARITY_FLAT'] == '1';
  }
}

/// Demo app for `swift_transitions`.
///
/// A gallery of source views that open destination pages: the push
/// transition from list tiles, and the zoom transition from a row of
/// posters.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoApp(
      home: const GalleryPage(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          Parity.showTouches ? TouchRings(child: child!) : child!,
    );
  }
}

/// Draws a ring under every pointer, above the app, so a recording of a
/// gesture carries the finger's position. A [Listener] in the tree above
/// the navigator sees every pointer without taking part in any arena.
class TouchRings extends StatefulWidget {
  /// Creates the overlay.
  const TouchRings({super.key, required this.child});

  /// The app.
  final Widget child;

  @override
  State<TouchRings> createState() => _TouchRingsState();
}

class _TouchRingsState extends State<TouchRings> {
  final Map<int, Offset> _pointers = <int, Offset>{};

  void _update(PointerEvent event) {
    setState(() {
      if (event is PointerUpEvent || event is PointerCancelEvent) {
        _pointers.remove(event.pointer);
      } else {
        _pointers[event.pointer] = event.position;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _update,
      onPointerMove: _update,
      onPointerUp: _update,
      onPointerCancel: _update,
      child: Stack(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          widget.child,
          for (final position in _pointers.values)
            Positioned(
              left: position.dx - 12,
              top: position.dy - 12,
              child: const IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.fromBorderSide(
                      BorderSide(color: Color(0xFF33FF33), width: 3),
                    ),
                  ),
                  child: SizedBox(width: 24, height: 24),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The gallery's home page.
class GalleryPage extends StatelessWidget {
  /// Creates the gallery's home page.
  const GalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(
        middle: Text('swift_transitions'),
      ),
      child: SafeArea(
        child: ListView(
          children: <Widget>[
            CupertinoListTile(
              title: const Text('Push — leading edge back swipe'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => Navigator.of(context).push(
                SwiftPageRoute<void>(
                  builder: (_) =>
                      const PushDemoPage(region: BackGestureRegion.leadingEdge),
                ),
              ),
            ),
            CupertinoListTile(
              title: const Text('Push — back swipe anywhere'),
              trailing: const CupertinoListTileChevron(),
              onTap: () => Navigator.of(context).push(
                SwiftPageRoute<void>(
                  builder: (_) =>
                      const PushDemoPage(region: BackGestureRegion.anywhere),
                ),
              ),
            ),
            CupertinoListSection(
              header: const Text('Zoom — tap a poster'),
              children: const <Widget>[PosterRow()],
            ),
          ],
        ),
      ),
    );
  }
}

/// A poster in the zoom demo's row.
class Poster {
  /// Creates a poster.
  const Poster(this.title, this.color);

  /// The poster's title, also its source tag.
  final String title;

  /// The poster's colour.
  final Color color;
}

/// The posters in the zoom demo's row.
const List<Poster> posters = <Poster>[
  Poster('Aurora', Color(0xFF3A7BD5)),
  Poster('Dunes', Color(0xFFD58B3A)),
  Poster('Kelp', Color(0xFF2E8B57)),
  Poster('Magma', Color(0xFFC0392B)),
  Poster('Nimbus', Color(0xFF6C5CE7)),
  Poster('Quartz', Color(0xFF8E44AD)),
];

/// A horizontally scrolling row of posters, each a [ZoomTransitionSource]
/// that opens its [PosterPage] with a [ZoomPageRoute].
class PosterRow extends StatelessWidget {
  /// Creates the poster row.
  const PosterRow({super.key});

  static const double _height = 180;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(12));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height + 24,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: posters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final poster = posters[index];
          return ZoomTransitionSource(
            tag: poster.title,
            borderRadius: _radius,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  ZoomPageRoute<void>(
                    sourceTag: poster.title,
                    title: poster.title,
                    builder: (_) => PosterPager(initial: index),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: _radius,
                child: PosterArt(poster: poster, width: 120, height: _height),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A poster's artwork: a coloured card with its title.
class PosterArt extends StatelessWidget {
  /// Creates the artwork for [poster] at [width] by [height].
  const PosterArt({
    super.key,
    required this.poster,
    required this.width,
    required this.height,
  });

  /// The poster drawn.
  final Poster poster;

  /// The artwork's width.
  final double width;

  /// The artwork's height.
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      alignment: Alignment.bottomLeft,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Parity.flat ? poster.color : null,
        gradient: Parity.flat
            ? null
            : LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  poster.color,
                  Color.lerp(poster.color, const Color(0xFF000000), 0.45)!,
                ],
              ),
      ),
      // Text blends into the colour it sits on, so the flat palette, which
      // exists to be measured, carries none.
      child: Parity.flat
          ? null
          : Text(
              poster.title,
              style: const TextStyle(
                color: CupertinoColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }
}

/// The poster pages, swiped through sideways.
///
/// Whichever poster is showing is the one the page shrinks back onto: each
/// swipe sets the route's `sourceTag`, the counterpart of UIKit calling the
/// source view provider again on dismiss.
class PosterPager extends StatefulWidget {
  /// Creates the pager, opened on the poster at [initial].
  const PosterPager({super.key, required this.initial});

  /// The index of the poster that was tapped.
  final int initial;

  @override
  State<PosterPager> createState() => _PosterPagerState();
}

class _PosterPagerState extends State<PosterPager> {
  late final PageController _controller = PageController(
    initialPage: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _controller,
      itemCount: posters.length,
      onPageChanged: (index) {
        ZoomRouteTransitionMixin.of(context)?.sourceTag = posters[index].title;
      },
      itemBuilder: (context, index) => PosterPage(poster: posters[index]),
    );
  }
}

/// The page a poster zooms open into.
class PosterPage extends StatelessWidget {
  /// Creates the detail page for [poster].
  const PosterPage({super.key, required this.poster});

  /// The poster shown.
  final Poster poster;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Parity.flat ? const Color(0xFFE0F0FF) : null,
      navigationBar: CupertinoNavigationBar(
        middle: Text(poster.title),
        // Parity: SwiftUI's bar is opaque white over this page, scrolled
        // to the top or not. A hair short of opaque, so the scaffold still
        // lays the page out under the bar, where SwiftUI's scroll view
        // starts.
        backgroundColor: Parity.flat ? const Color(0xFEFFFFFF) : null,
        automaticBackgroundVisibility: false,
        border: Parity.flat
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0x4D000000), width: 0),
              ),
      ),
      child: ListView(
        // Where SwiftUI's scroll view puts the art: 40 pt below the status
        // bar, the first 17 pt of it under the bar. This context is above
        // the page's own scaffold, so its padding is the status bar alone.
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 40),
        children: <Widget>[
          AspectRatio(
            aspectRatio: 2 / 3,
            child: PosterArt(
              poster: poster,
              width: double.infinity,
              height: double.infinity,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Drag down from the top of this page, swipe in from the '
              'leading edge, or pinch with two fingers to shrink it into its '
              'poster; let go early and it springs back, and a card on its '
              'way anywhere can be caught. Swipe sideways for the next '
              'poster, which is then the one this page lands on. Tap back '
              'to zoom home.',
              style: CupertinoTheme.of(context).textTheme.textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// The pushed page for the push-transition demos.
///
/// On a device with a rounded display, its leading corners clip to the
/// display's physical corner radius while it slides in and while it recedes
/// under another pushed page.
class PushDemoPage extends StatelessWidget {
  /// Creates a push-transition demo page for [region].
  const PushDemoPage({super.key, required this.region});

  /// The back-gesture region the demo was pushed with.
  final BackGestureRegion region;

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: Parity.flat ? const Color(0xFFD8FFE0) : null,
      navigationBar: const CupertinoNavigationBar(middle: Text('Detail')),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                region == BackGestureRegion.leadingEdge
                    ? 'Swipe from the leading edge to go back.'
                    : 'Swipe anywhere on this page to go back.',
              ),
              const SizedBox(height: 24),
              CupertinoButton.filled(
                onPressed: () => Navigator.of(context).push(
                  SwiftPageRoute<void>(
                    builder: (_) => PushDemoPage(region: region),
                  ),
                ),
                child: const Text('Push another'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
