/// An iOS-style zoom navigation transition for Flutter.
///
/// Recreates the zoom transition introduced in iOS 18, where a destination
/// page grows out of a source view and shrinks back into it on dismissal.
/// The design draws on Flutter's [Hero] mechanics and on SwiftUI's
/// `matchedTransitionSource` / `navigationTransition(.zoom)` APIs.
///
/// The route classes have not landed yet. See the repository README for the
/// project goals and current status.
library;

export 'src/corners/display_corner_radii.dart' show DisplayCornerRadii;
export 'src/physics/springs.dart' show SwiftSprings;
