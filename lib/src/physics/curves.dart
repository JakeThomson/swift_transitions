import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Curves measured from iOS's own navigation transitions.
abstract final class SwiftCurves {
  /// The push: the arriving page's remaining distance decays exponentially,
  /// falling by 1/e every 61 ms, and the pop is the same decay toward the
  /// far side (so the reverse of this curve is its [Curve.flipped]).
  /// Measured frame by frame from a `NavigationStack` push on the iOS 27.0
  /// simulator (parity stage 1: 402 pt in 24 frames, log-linear to a
  /// residual of 0.06). There is no ease-in at all: the first frame already
  /// moves a fifth of the width.
  ///
  /// The rate is the time constant over
  /// [SwiftPageTransitionMixin.kTransitionDuration]; at the end of the
  /// 400 ms the residual is half a point.
  static const Curve push = _ExponentialDecay(400 / 61);
}

/// `1 − e^(−rate·t)`, normalised to end at 1.
class _ExponentialDecay extends Curve {
  const _ExponentialDecay(this.rate);

  final double rate;

  @override
  double transformInternal(double t) =>
      (1 - math.exp(-rate * t)) / (1 - math.exp(-rate));

  @override
  String toString() => '${objectRuntimeType(this, '_ExponentialDecay')}($rate)';
}
