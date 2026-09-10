/// iOS's navigation transitions for Flutter.
///
/// [ZoomPageRoute] is the zoom transition introduced in iOS 18, where a
/// destination page grows out of a [ZoomTransitionSource] and shrinks back
/// into it through a pan, an edge swipe or a pinch; SwiftUI spells it
/// `matchedTransitionSource` and `navigationTransition(.zoom)`.
/// [SwiftPageRoute] is the ordinary push, with the same curve, the same back
/// swipe and the display's own corner radius, and
/// [SwiftPageTransitionsBuilder] applies it to every route on iOS.
///
/// Both are fitted frame by frame against a native reference app; the
/// measurements and the deviations that remain are in the repository's
/// `docs/design.md`.
library;

export 'src/corners/display_corner_radii.dart';
export 'src/page/back_gesture.dart' show BackGestureRegion;
export 'src/page/swift_page_route.dart'
    show SwiftPage, SwiftPageRoute, SwiftPageTransitionMixin;
export 'src/page/swift_page_transition.dart' show SwiftPageTransition;
export 'src/page/swift_page_transitions_builder.dart';
export 'src/physics/curves.dart';
export 'src/physics/springs.dart';
export 'src/zoom/zoom_dismiss_physics.dart';
export 'src/zoom/zoom_gestures.dart' show ZoomScrollController;
export 'src/zoom/zoom_interaction.dart'
    show ZoomGesture, ZoomInteractionContext, ZoomInteractiveDismissPredicate;
export 'src/zoom/zoom_page_route.dart'
    show ZoomPage, ZoomPageRoute, ZoomRouteTransitionMixin;
export 'src/zoom/zoom_transition_options.dart'
    show
        ZoomAlignmentRectContext,
        ZoomAlignmentRectProvider,
        ZoomDismissGestures,
        ZoomFlightDirection,
        ZoomTransitionOptions;
export 'src/zoom/zoom_transition_source.dart' show ZoomTransitionSource;
