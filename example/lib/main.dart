import 'package:flutter/cupertino.dart';
import 'package:swift_transitions/swift_transitions.dart';

void main() {
  runApp(const ExampleApp());
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
    return const CupertinoApp(home: GalleryPage());
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
              onTap: () => Navigator.of(context).push(
                ZoomPageRoute<void>(
                  sourceTag: poster.title,
                  title: poster.title,
                  builder: (_) => PosterPage(poster: poster),
                ),
              ),
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
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            poster.color,
            Color.lerp(poster.color, const Color(0xFF000000), 0.45)!,
          ],
        ),
      ),
      child: Text(
        poster.title,
        style: const TextStyle(
          color: CupertinoColors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
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
      navigationBar: CupertinoNavigationBar(middle: Text(poster.title)),
      child: ListView(
        padding: EdgeInsets.zero,
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
              'poster; let go early and it springs back. Tap back to zoom '
              'home.',
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
