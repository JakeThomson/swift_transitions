import 'package:flutter/cupertino.dart';
import 'package:swift_transitions/swift_transitions.dart';

void main() {
  runApp(const ExampleApp());
}

/// Demo app for `swift_transitions`.
///
/// A gallery of source views that open destination pages. Currently just
/// the push transition; the zoom transition arrives with its milestone.
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
          ],
        ),
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
