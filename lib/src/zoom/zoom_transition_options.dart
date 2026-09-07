import 'package:flutter/widgets.dart';

/// Options for a zoom route, mirroring `UIZoomTransitionOptions`.
@immutable
class ZoomTransitionOptions {
  /// Creates zoom transition options.
  const ZoomTransitionOptions({
    this.dimmingColor = const Color(0x33000000),
    this.dimmingBlurSigma = 0.0,
    this.pushSpring = kZoomPushSpring,
  });

  /// The colour the covered page is dimmed with at the end of the push.
  ///
  /// The dim eases in with the flight and tracks an interactive dismissal.
  /// It is painted as the route's modal barrier, so a transparent colour
  /// leaves the covered page undimmed but still shielded from pointers.
  final Color dimmingColor;

  /// The blur applied to the covered page under the dim, the counterpart of
  /// `UIZoomTransitionOptions.dimmingVisualEffect`. Zero for no blur.
  final double dimmingBlurSigma;

  /// The spring that drives the push and the non-interactive pop.
  final SpringDescription pushSpring;

  @override
  bool operator ==(Object other) =>
      other is ZoomTransitionOptions &&
      other.dimmingColor == dimmingColor &&
      other.dimmingBlurSigma == dimmingBlurSigma &&
      other.pushSpring == pushSpring;

  @override
  int get hashCode => Object.hash(dimmingColor, dimmingBlurSigma, pushSpring);
}

/// The default zoom flight spring: [SpringDescription.withDurationAndBounce]
/// for 500 ms with no bounce, written out because that constructor is not
/// const. Calibration against the 60 fps push strip is pending; see
/// design.md section 3.9.
const SpringDescription kZoomPushSpring = SpringDescription(
  mass: 1,
  stiffness: 157.91367041742973, // (2π / 0.5 s)²
  damping: 25.132741228718345, // 4π / 0.5 s
);
