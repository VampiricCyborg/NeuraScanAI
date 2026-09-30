/// Scoring the trail-making step.
///
/// Part A is the user's own reference speed and part B adds switching, so the cost of switching
/// is the difference between them. These tests pin that arithmetic, and that errors are counted
/// in both parts without stopping the clock.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/trail_extractor.dart';

/// [targets] correct taps, one every [gapMs], starting [firstMs] in.
TrailPartLog part({
  required int targets,
  int gapMs = 1000,
  int firstMs = 1000,
  List<TrailTapEvent> extra = const [],
}) {
  final taps = [
    for (var i = 0; i < targets; i++)
      TrailTapEvent(timestampMs: firstMs + i * gapMs, correct: true),
    ...extra,
  ]..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
  return TrailPartLog(targets: targets, taps: taps);
}

void main() {
  group('times', () {
    test('completion time is the time to the last correct tap of part B', () {
      final result = extractTrailFeatures(
        partA: part(targets: 5),
        partB: part(targets: 8, gapMs: 1500),
      );
      // 1000 ms to the first circle, then seven more at 1500 ms.
      expect(result.completionTimeS, closeTo(11.5, 1e-9));
    });

    test('a part is timed per circle from when it appeared', () {
      final result = extractTrailFeatures(
        partA: part(targets: 5),
        partB: part(targets: 8),
      );
      expect(result.partAMeanS, closeTo(5.0 / 5, 1e-9));
    });
  });

  group('switch cost', () {
    test('equal speed in both parts costs nothing', () {
      final result = extractTrailFeatures(
        partA: part(targets: 5),
        partB: part(targets: 8),
      );
      expect(result.switchCostS, closeTo(0.0, 0.2));
    });

    test('slower per circle in part B is a positive cost', () {
      final result = extractTrailFeatures(
        partA: part(targets: 5, gapMs: 800, firstMs: 800),
        partB: part(targets: 8, gapMs: 1600, firstMs: 1600),
      );
      // Part A: 4.0 s over 5 circles is 0.8 s each; part B: 12.8 s over 8 is 1.6 s each.
      expect(result.switchCostS, closeTo(0.8, 1e-9));
    });

    test('faster in part B gives a negative cost', () {
      final result = extractTrailFeatures(
        partA: part(targets: 5, gapMs: 1500, firstMs: 1500),
        partB: part(targets: 8, gapMs: 800, firstMs: 800),
      );
      expect(result.switchCostS, lessThan(0.0));
    });

    test('the cost is per tap, so different part lengths are comparable', () {
      // Same per-circle speed, different numbers of circles.
      final result = extractTrailFeatures(
        partA: part(targets: 5),
        partB: part(targets: 8),
      );
      expect(result.partBMeanS, closeTo(1.0, 1e-9));
      expect(result.partAMeanS, closeTo(1.0, 1e-9));
      expect(result.switchCostS, closeTo(0.0, 1e-9));
    });
  });

  group('errors', () {
    test('wrong taps are counted in both parts', () {
      final result = extractTrailFeatures(
        partA: part(
          targets: 5,
          extra: const [TrailTapEvent(timestampMs: 1500, correct: false)],
        ),
        partB: part(
          targets: 8,
          extra: const [
            TrailTapEvent(timestampMs: 2500, correct: false),
            TrailTapEvent(timestampMs: 3500, correct: false),
          ],
        ),
      );
      expect(result.errorCount, 3);
    });

    test('no errors is zero', () {
      final result = extractTrailFeatures(
        partA: part(targets: 5),
        partB: part(targets: 8),
      );
      expect(result.errorCount, 0);
    });

    test('an error does not stop the clock', () {
      // A wrong tap late in the part does not move the finish time.
      final clean = extractTrailFeatures(
        partA: part(targets: 5),
        partB: part(targets: 8),
      );
      final withError = extractTrailFeatures(
        partA: part(targets: 5),
        partB: part(
          targets: 8,
          extra: const [TrailTapEvent(timestampMs: 99999, correct: false)],
        ),
      );
      expect(withError.completionTimeS, clean.completionTimeS);
    });
  });

  group('completion', () {
    test('both parts finished is complete', () {
      expect(
        extractTrailFeatures(
          partA: part(targets: 5),
          partB: part(targets: 8),
        ).completed,
        isTrue,
      );
    });

    test('a part short of its circles is not complete', () {
      expect(
        extractTrailFeatures(
          partA: part(targets: 5),
          partB: const TrailPartLog(targets: 8, taps: []),
        ).completed,
        isFalse,
      );
    });

    test('a part with no taps at all is timed as zero, not a failure', () {
      final result = extractTrailFeatures(
        partA: const TrailPartLog(targets: 5, taps: []),
        partB: const TrailPartLog(targets: 8, taps: []),
      );
      expect(result.completionTimeS, 0.0);
      expect(result.switchCostS, 0.0);
    });

    test('a part with no circles does not divide by zero', () {
      final result = extractTrailFeatures(
        partA: const TrailPartLog(targets: 0, taps: []),
        partB: part(targets: 8),
      );
      expect(result.partAMeanS, 0.0);
    });
  });
}
