import 'package:flutter/cupertino.dart';
import 'package:swift_transitions/swift_transitions.dart';

import 'parity.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Parity.load();
  runApp(const ExampleApp());
}

/// Demo app for `swift_transitions`.
///
/// A gallery of source views that open destination pages: the push
/// transition from list tiles, and the zoom transition from a row of
/// posters, and from a row of stills whose pages keep the art below a
/// title and align the flight to it.
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
                  backGestureRegion: BackGestureRegion.leadingEdge,
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
            CupertinoListSection(
              header: const Text('Zoom — tap a still, aligned to its art'),
              children: const <Widget>[StillRow()],
            ),
            CupertinoListSection(
              header: const Text(
                'Zoom — tap a film, its page leads with a backdrop',
              ),
              children: const <Widget>[FilmRow()],
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

/// A horizontally scrolling row of stills — the posters' art cut wide —
/// each a [ZoomTransitionSource] that opens its [StillPage].
///
/// A still's page does not open with the art: a title and a paragraph
/// come first. Left to itself the zoom would fit the whole page into the
/// card, top first, so the card would read as a double exposure on its
/// way — the still's picture over the page's shrunken title — as it does
/// natively. The route's `alignmentRect` says where the art is instead,
/// measured through a [GlobalKey] once the page is laid out, and the card
/// grows out of the still showing the art and shrinks back onto it.
class StillRow extends StatelessWidget {
  /// Creates the still row.
  const StillRow({super.key});

  static const double _height = 90;
  static const BorderRadius _radius = BorderRadius.all(Radius.circular(10));

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
          // Tags are unique within a route, and the posters have the titles.
          final tag = 'still:${poster.title}';
          return ZoomTransitionSource(
            tag: tag,
            borderRadius: _radius,
            child: GestureDetector(
              onTap: () {
                final art = GlobalKey();
                Navigator.of(context).push(
                  ZoomPageRoute<void>(
                    sourceTag: tag,
                    title: poster.title,
                    options: ZoomTransitionOptions(
                      alignmentRect: (flight) {
                        // Scrolled far enough for the list to have let go
                        // of the art: the whole page aligns instead.
                        final context = art.currentContext;
                        return context == null ? null : flight.rectOf(context);
                      },
                    ),
                    builder: (_) => StillPage(poster: poster, artKey: art),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: _radius,
                child: PosterArt(poster: poster, width: 160, height: _height),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A horizontally scrolling row of the posters again, each a
/// [ZoomTransitionSource] that opens its [FilmPage].
///
/// A film's page does not open with its poster: it leads with a backdrop —
/// another picture, wide where the poster is tall, across the top of the
/// page under a title. Nothing on the page is the poster, so there is
/// nothing to align the flight to; the whole page shrinks into the poster
/// and the poster's picture cross-fades in over it, as it does natively.
class FilmRow extends StatelessWidget {
  /// Creates the film row.
  const FilmRow({super.key});

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
          final tag = 'film:${poster.title}';
          return ZoomTransitionSource(
            tag: tag,
            borderRadius: _radius,
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  ZoomPageRoute<void>(
                    sourceTag: tag,
                    title: poster.title,
                    builder: (_) => FilmPage(poster: poster),
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

/// A film's backdrop: a wide still in the poster's colours, its title set
/// large across it — another picture than the poster, not a crop of it.
class BackdropArt extends StatelessWidget {
  /// Creates the backdrop for [poster].
  const BackdropArt({super.key, required this.poster});

  /// The film whose backdrop this is.
  final Poster poster;

  @override
  Widget build(BuildContext context) {
    final lighter = Color.lerp(poster.color, const Color(0xFFFFFFFF), 0.35)!;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        // Flat: one colour, and not the poster's, so a measurement can
        // tell the two pictures apart.
        color: Parity.flat ? lighter : null,
        gradient: Parity.flat
            ? null
            : LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: <Color>[
                  Color.lerp(poster.color, const Color(0xFF000000), 0.45)!,
                  lighter,
                ],
              ),
      ),
      child: Parity.flat
          ? null
          : Text(
              poster.title.toUpperCase(),
              style: const TextStyle(
                color: CupertinoColors.white,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
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

/// The page a still zooms open into: its art under a title and a paragraph,
/// keyed with [artKey] so the route can align the flight to it.
class StillPage extends StatelessWidget {
  /// Creates the detail page for [poster].
  const StillPage({super.key, required this.poster, required this.artKey});

  /// The poster whose still was tapped.
  final Poster poster;

  /// The key on the art, for the route's `alignmentRect` to measure.
  final GlobalKey artKey;

  @override
  Widget build(BuildContext context) {
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(poster.title)),
      child: ListView(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 44),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              poster.title,
              style: CupertinoTheme.of(
                context,
              ).textTheme.navLargeTitleTextStyle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'The still is a preview of this art, not of this page: the '
              'title and this paragraph come first. The route aligns the '
              'flight to the art instead, so the card grows out of the '
              'still showing it and shrinks back onto it.',
              style: textStyle,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AspectRatio(
              key: artKey,
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: const BorderRadius.all(Radius.circular(12)),
                child: PosterArt(
                  poster: poster,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Drag down, swipe in from the leading edge, or pinch to shrink '
              'the page into its still. Tap back to zoom home.',
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}

/// The page a film zooms open into: its backdrop across the top, under the
/// bar, then its title and a paragraph. The poster is nowhere on it.
class FilmPage extends StatelessWidget {
  /// Creates the detail page for [poster].
  const FilmPage({super.key, required this.poster});

  /// The film whose poster was tapped.
  final Poster poster;

  @override
  Widget build(BuildContext context) {
    final textTheme = CupertinoTheme.of(context).textTheme;
    return CupertinoPageScaffold(
      backgroundColor: Parity.flat ? const Color(0xFFE0F0FF) : null,
      navigationBar: CupertinoNavigationBar(
        middle: Text(poster.title),
        // Parity: as PosterPage's bar.
        backgroundColor: Parity.flat ? const Color(0xFEFFFFFF) : null,
        automaticBackgroundVisibility: false,
        border: Parity.flat
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0x4D000000), width: 0),
              ),
      ),
      child: ListView(
        // The backdrop where PosterPage puts its art.
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 40),
        children: <Widget>[
          AspectRatio(
            aspectRatio: 16 / 9,
            child: BackdropArt(poster: poster),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(poster.title, style: textTheme.navLargeTitleTextStyle),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'The poster is not on this page: it leads with a backdrop, '
              'another picture at another size. The whole page shrinks into '
              'the poster and the poster fades in over it. Drag down, swipe '
              'in from the leading edge, or pinch to dismiss; tap back to '
              'zoom home.',
              style: textTheme.textStyle,
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
                    backGestureRegion: region,
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
