import 'package:flutter/cupertino.dart';

void main() {
  runApp(const ExampleApp());
}

/// Demo app for `swift_transitions`.
///
/// Placeholder until the package exposes its first API. It will grow into a
/// gallery of source views (grid cells, list rows, buttons) that open
/// destination pages with the zoom transition.
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const CupertinoApp(
      home: CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text('swift_transitions'),
        ),
        child: Center(child: Text('Demos arrive with the first API.')),
      ),
    );
  }
}
