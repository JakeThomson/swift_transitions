/// An iOS-style zoom navigation transition for Flutter.
///
/// Recreates the zoom transition introduced in iOS 18, where a destination
/// page grows out of a source view and shrinks back into it on dismissal.
/// The design draws on Flutter's [Hero] mechanics and on SwiftUI's
/// `matchedTransitionSource` / `navigationTransition(.zoom)` APIs.
///
/// The zoom route has not landed yet. See the repository README for the
/// project goals and current status.
library;

export 'src/corners/display_corner_radii.dart';
export 'src/page/back_gesture.dart' show BackGestureRegion;
export 'src/page/swift_page_route.dart' show SwiftPage, SwiftPageRoute;
export 'src/page/swift_page_transition.dart' show SwiftPageTransition;
export 'src/page/swift_page_transitions_builder.dart';
export 'src/physics/springs.dart';
