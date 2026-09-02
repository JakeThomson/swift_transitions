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
