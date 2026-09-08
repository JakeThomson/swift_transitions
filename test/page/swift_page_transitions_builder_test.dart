import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/swift_transitions.dart';

void main() {
  testWidgets(
    'applies the iOS push transition and clip to a MaterialPageRoute',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            platform: TargetPlatform.iOS,
            pageTransitionsTheme: const PageTransitionsTheme(
              builders: <TargetPlatform, PageTransitionsBuilder>{
                TargetPlatform.iOS: SwiftPageTransitionsBuilder(),
              },
            ),
          ),
          home: Builder(
            builder: (context) => CupertinoPageScaffold(
              child: Center(
                child: CupertinoButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Text('second'),
                    ),
                  ),
                  child: const Text('push'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('push'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(ClipRSuperellipse), findsWidgets);
      // Two Material routes share their delegated transition, so the covered
      // one runs the theme's transition itself and keeps pace with the
      // arriving page.
      final arrivingX = tester
          .getTopLeft(find.byType(ClipRSuperellipse).last)
          .dx;
      final coveredX = tester
          .getTopLeft(find.byType(ClipRSuperellipse).first)
          .dx;
      expect(arrivingX, inExclusiveRange(0, 800));
      expect(coveredX, closeTo(-0.30 * (800 - arrivingX), 1));

      await tester.pumpAndSettle();
      expect(find.text('second'), findsOneWidget);
    },
  );
}
