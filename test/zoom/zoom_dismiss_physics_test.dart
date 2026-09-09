import 'dart:math' as math;

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
        physics.scaleFor(0.49),
        closeTo(1 - physics.scaleGain * 0.49, 1e-9),
      );
    });

    test('the native page held at 0.8 of its height', () {
      // 0.545 natively; the knee and floor were fitted to this point.
      expect(physics.scaleFor(0.78), closeTo(0.545, 0.01));
    });

    test('eases toward the floor without reaching it', () {
      final far = physics.scaleFor(2);
      expect(far, greaterThan(physics.minimumScale));
      expect(far, lessThan(0.5));
      expect(physics.scaleFor(1), greaterThan(far));
    });

    test('the shrink eases instead of sliding off under the finger', () {
      expect(physics.dampedTravel(0.1), closeTo(0.1, 1e-9));
      expect(physics.dampedTravel(0.52), closeTo(0.52, 1e-9));
      final long = physics.dampedTravel(2);
      expect(long, greaterThan(0.52));
      expect(long, lessThan(physics.maximumTravel));
      expect(long, lessThan(0.52 * 2));
    });

    test('the fall trails the finger hardly at all, then more and more', () {
      // The native page's top sat 0.99 of the finger's travel past the
      // dead zone down at a tenth of the height, 0.89 at half, 0.73 at 0.8.
      expect(physics.fallFor(0.1) / 0.1, closeTo(1.0, 0.01));
      expect(physics.fallFor(0.5) / 0.5, closeTo(0.89, 0.01));
      expect(physics.fallFor(0.8) / 0.8, closeTo(0.73, 0.02));
      expect(physics.fallFor(3), greaterThanOrEqualTo(physics.fallFor(1)));
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

  group('crossAxisOffsetFor', () {
    test('follows at the gain at first and trails more as it goes', () {
      // The native card on a 402 pt page: 26 pt for a 50 pt sweep, 85 for
      // 195; 86 for a 200 pt drop during an edge swipe.
      expect(physics.crossAxisOffsetFor(50, width: 402), closeTo(26, 1.5));
      expect(physics.crossAxisOffsetFor(195, width: 402), closeTo(85, 1.5));
      expect(physics.crossAxisOffsetFor(200, width: 402), closeTo(86, 1.5));
      expect(
        physics.crossAxisOffsetFor(-100, width: 402),
        -physics.crossAxisOffsetFor(100, width: 402),
      );
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

    test('the grabbed point rides just behind the finger', () {
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
        closeTo(grab.dy + physics.fallFor(travel) * resting.height, 1e-9),
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
        for (final travel in <double>[0, 0.05, 0.1, 0.2, 0.4, 1]) {
          final swiped = physics.dismissedRect(
            restingRect: resting,
            travel: travel,
            anchor: grab,
          );
          expect(swiped.bottom, greaterThanOrEqualTo(resting.bottom - 1e-9));
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
    test('a release hands the landing its rate over what is left', () {
      expect(
        physics.commitVelocityFor(rate: 1, remainingScale: 0.5),
        closeTo(2, 1e-9),
      );
      expect(
        physics.commitVelocityFor(rate: 0.6, remainingScale: 0.3),
        closeTo(2, 1e-9),
      );
    });

    test('a flick is capped rather than trusted', () {
      expect(
        physics.commitVelocityFor(rate: 100, remainingScale: 0.5),
        physics.maxCommitVelocity,
      );
    });

    test('nothing is handed over by a release that was not shrinking', () {
      expect(physics.commitVelocityFor(rate: -1, remainingScale: 0.5), 0);
      expect(physics.commitVelocityFor(rate: 1, remainingScale: 0), 0);
    });
  });

  group('landingSpringFor', () {
    test('a release at rest lands on the landing spring itself', () {
      expect(physics.landingSpringFor(0), physics.landingSpring);
      expect(physics.landingSpringFor(-1), physics.landingSpring);
    });

    test(
      'a release on the move lands on a quicker spring, damped the same',
      () {
        final quick = physics.landingSpringFor(2);
        final ratio =
            physics.landingSpring.damping /
            (2 * math.sqrt(physics.landingSpring.stiffness));
        expect(
          quick.damping / (2 * math.sqrt(quick.stiffness)),
          closeTo(ratio, 1e-9),
        );
        expect(
          math.sqrt(quick.stiffness / physics.landingSpring.stiffness),
          closeTo(1 + 2 * physics.landingQuickening, 1e-9),
        );
      },
    );
  });
}
