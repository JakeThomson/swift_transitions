import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/swift_transitions.dart';

/// A `MediaQuery` shaped like a real device's `MediaQueryData`, for the
/// three fields the heuristic reads.
Widget deviceQuery({
  required Size size,
  required double devicePixelRatio,
  required EdgeInsets viewPadding,
  required Widget child,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      devicePixelRatio: devicePixelRatio,
      viewPadding: viewPadding,
    ),
    child: child,
  );
}

void main() {
  testWidgets('an enclosing override wins over everything else', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      deviceQuery(
        size: const Size(390, 844),
        devicePixelRatio: 3,
        viewPadding: const EdgeInsets.only(top: 47),
        child: DisplayCornerRadii(
          radii: BorderRadius.circular(99),
          child: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    expect(DisplayCornerRadii.of(capturedContext), BorderRadius.circular(99));
  });

  testWidgets('the iOS table resolves the iPhone 14 row', (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      deviceQuery(
        size: const Size(390, 844),
        devicePixelRatio: 3,
        viewPadding: const EdgeInsets.only(top: 47),
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(
      DisplayCornerRadii.of(capturedContext),
      BorderRadius.circular(47.33),
    );
  });

  testWidgets('the X-class and the 12/13 mini share a size but not an inset', (
    tester,
  ) async {
    BorderRadius? xClassRadii;
    await tester.pumpWidget(
      deviceQuery(
        size: const Size(375, 812),
        devicePixelRatio: 3,
        viewPadding: const EdgeInsets.only(top: 44),
        child: Builder(
          builder: (context) {
            xClassRadii = DisplayCornerRadii.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    BorderRadius? miniRadii;
    await tester.pumpWidget(
      deviceQuery(
        size: const Size(375, 812),
        devicePixelRatio: 3,
        viewPadding: const EdgeInsets.only(top: 50),
        child: Builder(
          builder: (context) {
            miniRadii = DisplayCornerRadii.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(xClassRadii, BorderRadius.circular(39));
    expect(miniRadii, BorderRadius.circular(44));
  });

  testWidgets('a landscape inset on the side still resolves the same row', (
    tester,
  ) async {
    BorderRadius? portraitRadii;
    await tester.pumpWidget(
      deviceQuery(
        size: const Size(390, 844),
        devicePixelRatio: 3,
        viewPadding: const EdgeInsets.only(top: 47),
        child: Builder(
          builder: (context) {
            portraitRadii = DisplayCornerRadii.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    BorderRadius? landscapeRadii;
    await tester.pumpWidget(
      deviceQuery(
        size: const Size(844, 390),
        devicePixelRatio: 3,
        viewPadding: const EdgeInsets.only(left: 47),
        child: Builder(
          builder: (context) {
            landscapeRadii = DisplayCornerRadii.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(landscapeRadii, portraitRadii);
  });

  testWidgets('the heuristic table maps each known inset', (tester) async {
    // One representative device per row of the iOS table in
    // display_corner_radii.dart, keeping this test and that table in sync.
    const devices = <(Size, double, EdgeInsets, double)>[
      (Size(375, 812), 3, EdgeInsets.only(top: 44), 39), // X, Xs, 11 Pro
      (Size(414, 896), 3, EdgeInsets.only(top: 44), 39), // Xs Max, 11 Pro Max
      (Size(414, 896), 2, EdgeInsets.only(top: 48), 41.5), // Xr, 11
      (Size(375, 812), 3, EdgeInsets.only(top: 50), 44), // 12 mini, 13 mini
      (Size(390, 844), 3, EdgeInsets.only(top: 47), 47.33), // 12, 13, 14
      (Size(428, 926), 3, EdgeInsets.only(top: 47), 53.33), // 12/13/14 Max/Plus
      (Size(393, 852), 3, EdgeInsets.only(top: 59), 55), // 14 Pro, 15, 16
      (
        Size(430, 932),
        3,
        EdgeInsets.only(top: 59),
        55,
      ), // 14/15/16 Pro Max/Plus
      (Size(402, 874), 3, EdgeInsets.only(top: 62), 62), // 16 Pro, 17, 17 Pro
      (Size(440, 956), 3, EdgeInsets.only(top: 62), 62), // 16/17 Pro Max
      (Size(420, 912), 3, EdgeInsets.only(top: 62), 62), // iPhone Air
      (Size(820, 1180), 2, EdgeInsets.only(top: 24), 18), // iPad Air 11"
      (Size(834, 1194), 2, EdgeInsets.only(top: 24), 18), // iPad Pro 11"
      (Size(1024, 1366), 2, EdgeInsets.only(top: 24), 18), // iPad Air/Pro 13"
    ];
    for (final (size, devicePixelRatio, viewPadding, radius) in devices) {
      BorderRadius? resolved;
      await tester.pumpWidget(
        deviceQuery(
          size: size,
          devicePixelRatio: devicePixelRatio,
          viewPadding: viewPadding,
          child: Builder(
            builder: (context) {
              resolved = DisplayCornerRadii.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        resolved,
        BorderRadius.circular(radius),
        reason: 'size $size at ${devicePixelRatio}x with $viewPadding',
      );
    }
  });

  testWidgets('an unknown device falls back to zero', (tester) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      deviceQuery(
        size: const Size(1234, 5678),
        devicePixelRatio: 2.75,
        viewPadding: EdgeInsets.zero,
        child: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(DisplayCornerRadii.of(capturedContext), BorderRadius.zero);
    expect(DisplayCornerRadii.maybeOf(capturedContext), isNull);
  });

  testWidgets('with no MediaQuery ancestor, of falls back to zero', (
    tester,
  ) async {
    late BuildContext capturedContext;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox();
        },
      ),
    );
    expect(DisplayCornerRadii.of(capturedContext), BorderRadius.zero);
  });
}
