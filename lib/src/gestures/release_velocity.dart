import 'dart:ui' show Offset;

/// The finger's velocity at a release, from the pointer stream's own
/// timestamps.
///
/// [DragEndDetails.velocity] cannot be relied on for this: its tracker
/// reports nothing at all once 40 ms of wall clock have passed since the
/// last move it was given, which a single dropped frame under a heavy
/// dismissal is enough to do, and a drag recognizer zeroes the axis it
/// does not own. The samples are weighted the way iOS weights its own
/// fling estimate — toward the pair before the last, since a finger slows
/// as it leaves the glass — but keyed on when the moves happened rather
/// than on when they were delivered. A pinch reads its fingers the same
/// way (`ZoomDismissController.pinchReleaseVelocity`).
class ReleaseVelocity {
  static const int _samples = 4;
  static const Duration _stopped = Duration(milliseconds: 40);
  static const List<double> _weights = <double>[0.6, 0.35, 0.05];

  final List<(Duration, Offset)> _moves = <(Duration, Offset)>[];

  /// Forgets the gesture so far.
  void reset() => _moves.clear();

  /// Records where the finger was at [time].
  void add(Duration time, Offset position) {
    _moves.add((time, position));
    if (_moves.length > _samples) {
      _moves.removeAt(0);
    }
  }

  /// [reported] unless a recognizer's tracker has given up on the release
  /// and called it still, in which case [ours].
  ///
  /// A tracker's estimate is the better one — it is iOS's own weighting
  /// over every move the recognizer saw — but it is thrown away whole once
  /// 40 ms of wall clock have passed since the last of them, which one
  /// dropped frame under a heavy transition is enough to do, and a card
  /// released at speed then lands as if it had been let go at rest.
  double reported(double reported, double ours) =>
      reported != 0 ? reported : ours;

  /// The finger's motion as it left at [now], or zero if it had already
  /// stopped moving by then.
  Offset at(Duration now) {
    if (_moves.length < 2 || now - _moves.last.$1 > _stopped) {
      return Offset.zero;
    }
    var velocity = Offset.zero;
    for (var i = 0; i < _weights.length; i++) {
      // The oldest pair first, as iOS weights them.
      final newer = _moves.length - _weights.length + i;
      if (newer < 1) {
        continue;
      }
      final (before, from) = _moves[newer - 1];
      final (after, to) = _moves[newer];
      final seconds =
          (after - before).inMicroseconds / Duration.microsecondsPerSecond;
      if (seconds > 0) {
        velocity += (to - from) / seconds * _weights[i];
      }
    }
    return velocity;
  }
}
