import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swift_transitions/swift_transitions.dart';

// Ported with the model from liquid_glass_widgets'
// glass_modal_sheet_morph_test.dart, restated in card heights.
void main() {
  const physics = ZoomDismissPhysics.ios26;
  const resting = Rect.fromLTRB(0, 0, 390, 844);

  group('scale', () {
    test('falls linearly at the measured iOS gain', () {
      expect(physics.scaleFor(0), 1);
      expect(physics.scaleFor(0.2), closeTo(1 - physics.scaleGain * 0.2, 1e-9));
      final half = 1 - physics.scaleFor(0.1);
      final full = 1 - physics.scaleFor(0.2);
      expect(half * 2, closeTo(full, 1e-9));
    });

    test('the measured linear region is untouched by the easing', () {
      expect(
        physics.scaleFor(0.48),
        closeTo(1 - physics.scaleGain * 0.48, 1e-9),
      );
    });

    test('eases toward the floor without reaching it', () {
      final far = physics.scaleFor(2);
      expect(far, greaterThan(physics.minimumScale));
      expect(far, lessThan(0.5));
      expect(physics.scaleFor(1), greaterThan(far));
    });

    test('the fall eases instead of sliding off under the finger', () {
      expect(physics.dampedTravel(0.1), closeTo(0.1, 1e-9));
      expect(physics.dampedTravel(0.48), closeTo(0.48, 1e-9));
      final long = physics.dampedTravel(2);
      expect(long, greaterThan(0.48));
      expect(long, lessThan(physics.maximumTravel));
      expect(long, lessThan(0.48 * 2));
    });
  });

  group('rubberBand', () {
    test('starts at 1:1 and never reaches the limit', () {
      expect(ZoomDismissPhysics.rubberBand(0, limit: 200), 0);
      expect(ZoomDismissPhysics.rubberBand(2, limit: 200), closeTo(2, 0.05));
      expect(ZoomDismissPhysics.rubberBand(1e6, limit: 200), lessThan(200));
      expect(ZoomDismissPhysics.rubberBand(1e6, limit: 200), greaterThan(199));
    });

    test('resists more the further it goes and is symmetric', () {
      final first = ZoomDismissPhysics.rubberBand(50, limit: 200);
      final second = ZoomDismissPhysics.rubberBand(100, limit: 200) - first;
      expect(second, lessThan(first));
      expect(
        ZoomDismissPhysics.rubberBand(-60, limit: 200),
        -ZoomDismissPhysics.rubberBand(60, limit: 200),
      );
      expect(ZoomDismissPhysics.rubberBand(80, limit: 0), 0);
    });
  });

  group('horizontalOffsetFor', () {
    // A card against the left edge of a 400-wide screen: room to its right,
    // none to its left.
    const card = Rect.fromLTRB(0, 500, 200, 800);

    test('free travel until the card reaches the edge it is heading for', () {
      expect(
        physics.horizontalOffsetFor(
          rawOffset: 150,
          cardRect: card,
          screenWidth: 400,
        ),
        150,
      );
    });

    test('resists immediately when there is nowhere to go', () {
      final damped = physics.horizontalOffsetFor(
        rawOffset: -150,
        cardRect: card,
        screenWidth: 400,
      );
      expect(damped, greaterThan(-150));
      expect(damped, lessThan(0));
    });

    test('past the edge it rubber-bands rather than stopping', () {
      final justPast = physics.horizontalOffsetFor(
        rawOffset: 260,
        cardRect: card,
        screenWidth: 400,
      );
      final wellPast = physics.horizontalOffsetFor(
        rawOffset: 600,
        cardRect: card,
        screenWidth: 400,
      );
      expect(justPast, greaterThan(200));
      expect(wellPast, greaterThan(justPast));
      expect(wellPast - justPast, lessThan(340));
    });

    test('mirrors exactly, so RTL needs no flip', () {
      const mirrored = Rect.fromLTRB(200, 500, 400, 800);
      for (final offset in <double>[40, 150, 260, 600]) {
        expect(
          physics.horizontalOffsetFor(
            rawOffset: -offset,
            cardRect: mirrored,
            screenWidth: 400,
          ),
          -physics.horizontalOffsetFor(
            rawOffset: offset,
            cardRect: card,
            screenWidth: 400,
          ),
        );
      }
    });
  });

  group('dismissedRect', () {
    test('an untouched card rests on its resting frame', () {
      expect(physics.dismissedRect(restingRect: resting, travel: 0), resting);
    });

    test('a sideways offset translates without touching the shrink', () {
      final straight = physics.dismissedRect(
        restingRect: resting,
        travel: 0.15,
      );
      final swept = physics.dismissedRect(
        restingRect: resting,
        travel: 0.15,
        horizontalOffset: 120,
      );
      expect(swept.size, straight.size);
      expect(swept.center.dx, closeTo(straight.center.dx + 120, 1e-9));
      expect(swept.center.dy, closeTo(straight.center.dy, 1e-9));
    });

    test('the grabbed point stays exactly under the finger', () {
      const grab = Offset(100, 300);
      const travel = 0.15;
      final swiped = physics.dismissedRect(
        restingRect: resting,
        travel: travel,
        anchor: grab,
      );
      final fx = (grab.dx - resting.left) / resting.width;
      final fy = (grab.dy - resting.top) / resting.height;
      expect(swiped.left + fx * swiped.width, closeTo(grab.dx, 1e-9));
      expect(
        swiped.top + fy * swiped.height,
        closeTo(grab.dy + travel * resting.height, 1e-9),
      );
      expect(
        swiped.width,
        closeTo(resting.width * physics.scaleFor(travel), 1e-9),
      );
    });

    test('the bottom edge never rises above its resting line', () {
      for (final grab in <Offset>[
        const Offset(100, 60),
        const Offset(200, 800),
        const Offset(200, -300),
      ]) {
        var previousBottom = -double.infinity;
        for (final travel in <double>[0, 0.05, 0.1, 0.2, 0.4, 1]) {
          final swiped = physics.dismissedRect(
            restingRect: resting,
            travel: travel,
            anchor: grab,
          );
          expect(swiped.bottom, greaterThanOrEqualTo(resting.bottom - 1e-9));
          expect(swiped.bottom, greaterThanOrEqualTo(previousBottom));
          previousBottom = swiped.bottom;
        }
      }
    });

    test('shrink and fall ease together off one curve', () {
      for (final travel in <double>[0.05, 0.2, 0.3, 0.6]) {
        final rect = physics.dismissedRect(
          restingRect: resting,
          travel: travel,
        );
        expect(
          rect.width / resting.width,
          closeTo(1 - physics.scaleGain * physics.dampedTravel(travel), 1e-9),
        );
      }
    });
  });

  group('commitVelocityFor', () {
    test('a fling hands the landing the speed it was shrinking at', () {
      expect(
        physics.commitVelocityFor(velocity: 400, cardHeight: 400),
        closeTo(physics.scaleGain, 1e-9),
      );
      expect(
        physics.commitVelocityFor(velocity: 400, cardHeight: 200),
        closeTo(2 * physics.scaleGain, 1e-9),
      );
    });

    test('a flick is capped rather than trusted', () {
      expect(physics.commitVelocityFor(velocity: 20000, cardHeight: 400), 10);
    });

    test('nothing is handed over by a release that was not falling', () {
      expect(physics.commitVelocityFor(velocity: -900, cardHeight: 400), 0);
      expect(physics.commitVelocityFor(velocity: 900, cardHeight: 0), 0);
    });
  });
}
