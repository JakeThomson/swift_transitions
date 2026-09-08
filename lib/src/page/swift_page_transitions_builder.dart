import 'package:flutter/cupertino.dart';

import 'back_gesture.dart';
import 'swift_page_route.dart';
import 'swift_page_transition.dart';

/// A [PageTransitionsBuilder] that provides the iOS push transition,
/// including the display-radius corner clip, for any [PageRoute] — a
/// [MaterialPageRoute] included.
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     pageTransitionsTheme: const PageTransitionsTheme(builders: {
///       TargetPlatform.iOS: SwiftPageTransitionsBuilder(),
///     }),
///   ),
/// )
/// ```
class SwiftPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Creates a page transition builder for the iOS push transition.
  const SwiftPageTransitionsBuilder({
    this.backGestureRegion = BackGestureRegion.leadingEdge,
    this.cornerRadii,
  });

  /// Where the interactive back swipe may start.
  final BackGestureRegion backGestureRegion;

  /// Overrides [DisplayCornerRadii.of] for the incoming page's clip.
  final BorderRadius? cornerRadii;

  @override
  Duration get transitionDuration =>
      SwiftPageTransitionMixin.kTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      SwiftPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SwiftPageTransitionMixin.buildPageTransitions<T>(
      route,
      animation,
      secondaryAnimation,
      child,
      region: backGestureRegion,
      cornerRadii: cornerRadii,
    );
  }
}
