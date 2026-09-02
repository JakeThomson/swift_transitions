import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Resolves the physical display corner radius for a subtree.
///
/// Resolution order:
///
///  1. an enclosing [DisplayCornerRadii] override,
///  2. [MediaQuery.maybeDisplayCornerRadiiOf], populated by the engine on
///     Android 12 and later; not yet reported on iOS,
///  3. the iOS device table below, keyed by the size and view padding
///     [MediaQuery] does report,
///  4. [BorderRadius.zero].
///
/// Wrap the app (or a subtree under a fixed-size test device) in this widget
/// to override every step below the first with a known value.
class DisplayCornerRadii extends InheritedWidget {
  /// Creates an override of the resolved display corner radius for [child].
  const DisplayCornerRadii({
    super.key,
    required this.radii,
    required super.child,
  });

  /// The radius applied to every corner of the display.
  final BorderRadius radii;

  /// The resolved display corner radius, or [BorderRadius.zero] if none of
  /// the steps in the class documentation apply.
  ///
  /// Unlike most `of` methods, this never throws for a missing [MediaQuery]
  /// ancestor: the heuristic step is simply skipped. Use [maybeOf] to tell
  /// "no radius was found" apart from "the radius is zero".
  static BorderRadius of(BuildContext context) =>
      maybeOf(context) ?? BorderRadius.zero;

  /// The resolved display corner radius, or null if no override, reported
  /// value, or table entry applies.
  static BorderRadius? maybeOf(BuildContext context) {
    final override = context
        .dependOnInheritedWidgetOfExactType<DisplayCornerRadii>();
    if (override != null) {
      return override.radii;
    }
    final reported = MediaQuery.maybeDisplayCornerRadiiOf(context);
    if (reported != null) {
      return reported;
    }
    return _iosDisplayCornerRadii(
      size: MediaQuery.maybeSizeOf(context),
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context),
      viewPadding: MediaQuery.maybeViewPaddingOf(context),
    );
  }

  @override
  bool updateShouldNotify(DisplayCornerRadii oldWidget) =>
      radii != oldWidget.radii;
}

/// One row of [_iosCornerRadiusTable], keyed by what [MediaQuery] reports.
///
/// [shortestSide] and [longestSide] replace width/height so portrait and
/// landscape key the same row. [notchInset] is the largest of the four
/// [EdgeInsets] on [MediaQuery.viewPadding]: in portrait the sensor housing
/// inset lands on `top`, in landscape it rotates onto `left` or `right`, so
/// taking the maximum reads the same value in both orientations. It is also
/// what tells apart devices that otherwise share a size and pixel ratio,
/// such as the iPhone X-class (39pt radius, 44pt inset) and the iPhone 12
/// and 13 mini (44pt radius, 50pt inset), both 375x812 at 3x.
class _DeviceKey {
  const _DeviceKey({
    required this.shortestSide,
    required this.longestSide,
    required this.devicePixelRatio,
    required this.notchInset,
  });

  factory _DeviceKey.from({
    required Size size,
    required double devicePixelRatio,
    required EdgeInsets viewPadding,
  }) {
    return _DeviceKey(
      shortestSide: size.shortestSide,
      longestSide: size.longestSide,
      devicePixelRatio: devicePixelRatio,
      notchInset: <double>[
        viewPadding.top,
        viewPadding.bottom,
        viewPadding.left,
        viewPadding.right,
      ].reduce(math.max),
    );
  }

  final double shortestSide;
  final double longestSide;
  final double devicePixelRatio;
  final double notchInset;

  bool matches(_DeviceKey other) =>
      shortestSide == other.shortestSide &&
      longestSide == other.longestSide &&
      devicePixelRatio == other.devicePixelRatio &&
      notchInset == other.notchInset;
}

class _DeviceRow {
  const _DeviceRow(this.key, this.radius);

  final _DeviceKey key;
  final double radius;
}

/// Display corner radii for iOS devices, read from `UIScreen`'s private
/// `_displayCornerRadius` by the kylebshr/ScreenCorners project
/// (https://github.com/kylebshr/ScreenCorners), reproduced here because pure
/// Dart cannot call into `UIScreen`. Sizes and view paddings are the public
/// values Apple documents for each device's safe area in portrait; a device
/// missing from this table has no rounding.
final List<_DeviceRow> _iosCornerRadiusTable = <_DeviceRow>[
  // iPhone X, Xs, 11 Pro.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 375,
      longestSide: 812,
      devicePixelRatio: 3,
      notchInset: 44,
    ),
    39,
  ),
  // iPhone Xs Max, 11 Pro Max.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 414,
      longestSide: 896,
      devicePixelRatio: 3,
      notchInset: 44,
    ),
    39,
  ),
  // iPhone Xr, 11.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 414,
      longestSide: 896,
      devicePixelRatio: 2,
      notchInset: 48,
    ),
    41.5,
  ),
  // iPhone 12 mini, 13 mini.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 375,
      longestSide: 812,
      devicePixelRatio: 3,
      notchInset: 50,
    ),
    44,
  ),
  // iPhone 12, 12 Pro, 13, 13 Pro, 14, 16e.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 390,
      longestSide: 844,
      devicePixelRatio: 3,
      notchInset: 47,
    ),
    47.33,
  ),
  // iPhone 12 Pro Max, 13 Pro Max, 14 Plus.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 428,
      longestSide: 926,
      devicePixelRatio: 3,
      notchInset: 47,
    ),
    53.33,
  ),
  // iPhone 14 Pro, 15, 15 Pro, 16.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 393,
      longestSide: 852,
      devicePixelRatio: 3,
      notchInset: 59,
    ),
    55,
  ),
  // iPhone 14 Pro Max, 15 Plus, 15 Pro Max, 16 Plus.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 430,
      longestSide: 932,
      devicePixelRatio: 3,
      notchInset: 59,
    ),
    55,
  ),
  // iPhone 16 Pro, 17, 17 Pro.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 402,
      longestSide: 874,
      devicePixelRatio: 3,
      notchInset: 62,
    ),
    62,
  ),
  // iPhone 16 Pro Max, 17 Pro Max.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 440,
      longestSide: 956,
      devicePixelRatio: 3,
      notchInset: 62,
    ),
    62,
  ),
  // iPhone Air.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 420,
      longestSide: 912,
      devicePixelRatio: 3,
      notchInset: 62,
    ),
    62,
  ),
  // iPad Air 11-inch, iPad Pro 11-inch.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 820,
      longestSide: 1180,
      devicePixelRatio: 2,
      notchInset: 24,
    ),
    18,
  ),
  // iPad Air 13-inch, iPad Pro 13-inch.
  const _DeviceRow(
    _DeviceKey(
      shortestSide: 1024,
      longestSide: 1366,
      devicePixelRatio: 2,
      notchInset: 24,
    ),
    18,
  ),
];

BorderRadius? _iosDisplayCornerRadii({
  required Size? size,
  required double? devicePixelRatio,
  required EdgeInsets? viewPadding,
}) {
  if (size == null || devicePixelRatio == null || viewPadding == null) {
    return null;
  }
  final key = _DeviceKey.from(
    size: size,
    devicePixelRatio: devicePixelRatio,
    viewPadding: viewPadding,
  );
  for (final row in _iosCornerRadiusTable) {
    if (row.key.matches(key)) {
      return BorderRadius.all(Radius.circular(row.radius));
    }
  }
  return null;
}
