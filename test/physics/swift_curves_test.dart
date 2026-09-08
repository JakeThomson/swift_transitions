import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/swift_transitions.dart';

void main() {
  test('the push curve decays exponentially with a 61 ms time constant', () {
    const curve = SwiftCurves.push;
    expect(curve.transform(0), 0);
    expect(curve.transform(1), 1);
    // Remaining distance at 400 ms × t, against e^(−t·400/61).
    for (final t in <double>[0.05, 0.1, 0.25, 0.5, 0.75]) {
      final remaining = 1 - curve.transform(t);
      expect(remaining, closeTo(math.exp(-t * 400 / 61), 0.002));
    }
    // Native reached 15 pt of 402 at 200 ms.
    expect(1 - curve.transform(0.5), closeTo(15 / 402, 0.004));
  });

  test('the pop is the same decay toward the far side', () {
    final reverse = SwiftCurves.push.flipped;
    // Reversing the controller from 1 to 0 over 400 ms: after 100 ms of
    // pop (value 0.75) the page has covered 1 − e^(−100/61) of its way.
    expect(
      1 - reverse.transform(0.75),
      closeTo(1 - math.exp(-100 / 61), 0.002),
    );
  });
}
