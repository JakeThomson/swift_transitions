import 'package:flutter/physics.dart';

/// Spring descriptions matching the SDK's Cupertino motion, for apps that
/// want the exact SDK feel rather than the package defaults.
abstract final class SwiftSprings {
  /// The critically damped spring iOS dialogs and action sheets use,
  /// reproduced from `cupertino/route.dart`'s private `_kStandardSpring`
  /// (stiffness 522.35, damping derived for a damping ratio of 1).
  static const SpringDescription standard = SpringDescription(
    mass: 1,
    stiffness: 522.35,
    damping: 45.7099552,
  );
}
