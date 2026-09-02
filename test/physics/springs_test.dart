import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/swift_transitions.dart';

void main() {
  test('SwiftSprings.standard is critically damped', () {
    // damping = 2 * sqrt(mass * stiffness), the SDK's own derivation for
    // _kStandardSpring in cupertino/route.dart.
    final spring = SwiftSprings.standard;
    final criticalDamping = 2 * math.sqrt(spring.mass * spring.stiffness);
    expect(spring.damping, closeTo(criticalDamping, 1e-6));
  });
}
