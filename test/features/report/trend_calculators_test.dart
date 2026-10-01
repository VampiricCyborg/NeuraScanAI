/// The Theil-Sen slope, the smoothing and run counts, the rolling average, the minimum-data rule
/// and the ranges.
///
/// These are the numbers behind every trend statement, so the tests are about the ways they
/// could quietly say something untrue: a trend from too few tests, noise called a trend, one
/// odd test dragging a slope, a range that includes the wrong tests.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/features/report/calculators/theil_sen.dart';
import 'package:neurascan_ai/features/report/calculators/trend_stats.dart';
import 'package:neurascan_ai/features/report/models.dart';
import 'package:neurascan_ai/features/report/report_constants.dart';

void main() {
  group('Theil-Sen slope', () {
    test('a straight line has its own slope', () {
      expect(theilSenSlope([1, 3, 5, 7, 9]), closeTo(2.0, 1e-12));
    });

    test('a falling line has a negative slope', () {
      expect(theilSenSlope([10, 8, 6, 4]), closeTo(-2.0, 1e-12));
    });

    test('a flat series has none', () {
      expect(theilSenSlope([4, 4, 4, 4]), 0.0);
    });

    test('fewer than two values have no slope', () {
      expect(theilSenSlope([]), isNull);
      expect(theilSenSlope([5]), isNull);
    });

    test('two values have the slope between them', () {
      expect(theilSenSlope([1, 4]), 3.0);
    });

    test('one wild value does not move it', () {
      // A line of slope 1 with one point thrown far off: the median of the pairwise slopes
      // ignores it where a least-squares fit would not.
      final clean = theilSenSlope([0, 1, 2, 3, 4, 5, 6, 7])!;
      final dirty = theilSenSlope([0, 1, 2, 3, 40, 5, 6, 7])!;
      expect(dirty, closeTo(clean, 0.25));
    });

    test('an ordinary least-squares line would have moved a long way', () {
      // Stated as a comparison, because it is the reason for the choice.
      const ys = [0.0, 1.0, 2.0, 3.0, 40.0, 5.0, 6.0, 7.0];
      final n = ys.length;
      final xs = List<double>.generate(n, (i) => i.toDouble());
      final meanX = xs.reduce((a, b) => a + b) / n;
      final meanY = ys.reduce((a, b) => a + b) / n;
      var num = 0.0;
      var den = 0.0;
      for (var i = 0; i < n; i++) {
        num += (xs[i] - meanX) * (ys[i] - meanY);
        den += (xs[i] - meanX) * (xs[i] - meanX);
      }
      final ols = num / den;
      expect((ols - 1.0).abs(), greaterThan(0.3));
      expect((theilSenSlope(ys)! - 1.0).abs(), lessThan(0.05));
    });

    test('uneven spacing is handled by the x-aware form', () {
      expect(
        theilSenSlopeAt([0, 2, 4, 10], [0, 4, 8, 20]),
        closeTo(2.0, 1e-12),
      );
    });

    test('points with the same x are skipped, not divided by zero', () {
      expect(theilSenSlopeAt([1, 1, 3], [0, 5, 4]), isNotNull);
      expect(theilSenSlopeAt([1, 1], [0, 5]), isNull);
    });
  });

  group('the smoothed series', () {
    test('starts from zero, as the engine does', () {
      expect(ewmaSeries([1.0]).first, closeTo(kEwmaLambda, 1e-12));
    });

    test('follows the engine\'s formula', () {
      final series = ewmaSeries([1.0, 2.0, 0.0]);
      expect(series[0], closeTo(0.3, 1e-12));
      expect(series[1], closeTo(0.3 * 2.0 + 0.7 * 0.3, 1e-12));
      expect(series[2], closeTo(0.7 * series[1], 1e-12));
    });

    test('has one entry per value', () {
      expect(ewmaSeries([1, 2, 3, 4]), hasLength(4));
      expect(ewmaSeries([]), isEmpty);
    });

    test('a sustained level approaches that level', () {
      final series = ewmaSeries(List.filled(40, 2.0));
      expect(series.last, closeTo(2.0, 0.01));
    });

    test('one spike is damped to a third of its size', () {
      expect(ewmaSeries([3.0, 0.0]).first, closeTo(0.9, 1e-12));
    });
  });

  group('runs above a level', () {
    test('counts the unbroken latest entries at or above it', () {
      expect(trailingRunAtOrAbove([0.1, 0.9, 1.1, 1.2], 1.0), 2);
    });

    test('is zero when the latest is below', () {
      expect(trailingRunAtOrAbove([1.5, 1.4, 0.5], 1.0), 0);
    });

    test('a dip breaks the run', () {
      expect(trailingRunAtOrAbove([1.5, 0.5, 1.5, 1.5], 1.0), 2);
    });

    test('counts an entry exactly at the level', () {
      expect(trailingRunAtOrAbove([1.0, 1.0], 1.0), 2);
    });

    test('an empty series has none', () {
      expect(trailingRunAtOrAbove([], 1.0), 0);
    });

    test('the whole series can be the run', () {
      expect(trailingRunAtOrAbove([2, 2, 2], 1.0), 3);
    });
  });

  group('the rolling average', () {
    test('averages the four tests before the one in question', () {
      final values = [10.0, 20.0, 30.0, 40.0, 50.0, 100.0];
      // The tests before the sixth are 20, 30, 40, 50.
      expect(priorMean(values, 5), closeTo(35.0, 1e-12));
    });

    test('never includes the test itself', () {
      expect(priorMean([1.0, 1000.0], 1), 1.0);
    });

    test('uses fewer than four when fewer exist', () {
      expect(priorMean([2.0, 4.0, 9.0], 2), 3.0);
    });

    test('has nothing before the first test', () {
      expect(priorMean([5.0, 6.0], 0), isNull);
    });

    test('is four tests by default', () {
      expect(kRollingWindow, 4);
    });

    test('a window can be chosen', () {
      expect(priorMean([1.0, 2.0, 3.0, 4.0], 3, window: 2), 2.5);
    });
  });

  group('the minimum-data rule', () {
    List<double> rising(int n, double step) => [
      for (var i = 0; i < n; i++) step * i,
    ];

    test('is six tests', () {
      expect(kMinSessionsForTrend, 6);
    });

    test('five tests are not enough for a trend', () {
      final stats = computeTrendStats(oriented: rising(5, 1.0));
      expect(stats.enough, isFalse);
      expect(stats.n, 5);
    });

    test('no direction and no slope are given below the minimum', () {
      final stats = computeTrendStats(
        oriented: rising(5, 1.0),
        raw: rising(5, 1.0),
      );
      expect(stats.direction, isNull);
      expect(stats.slopeSds, isNull);
      expect(stats.slopeRaw, isNull);
    });

    test('the smoothed value is still given below the minimum', () {
      // It is the engine's own number, not a trend claim.
      final stats = computeTrendStats(oriented: rising(3, 1.0));
      expect(stats.ewma, isNotNull);
    });

    test('six tests are enough', () {
      final stats = computeTrendStats(oriented: rising(6, 1.0));
      expect(stats.enough, isTrue);
      expect(stats.direction, isNotNull);
    });

    test('no tests at all is handled', () {
      final stats = computeTrendStats(oriented: const []);
      expect(stats.n, 0);
      expect(stats.enough, isFalse);
      expect(stats.ewma, isNull);
      expect(stats.runMild, 0);
    });

    test('the minimum can be changed', () {
      final stats = computeTrendStats(oriented: rising(3, 1.0), minSessions: 3);
      expect(stats.enough, isTrue);
    });
  });

  group('the direction', () {
    test('a steady rise in the bad direction is declining', () {
      final stats = computeTrendStats(
        oriented: [for (var i = 0; i < 8; i++) 0.3 * i],
      );
      expect(stats.direction, TrendDirection.declining);
    });

    test('a steady fall is improving', () {
      final stats = computeTrendStats(
        oriented: [for (var i = 0; i < 8; i++) -0.3 * i],
      );
      expect(stats.direction, TrendDirection.improving);
    });

    test('a flat series is stable', () {
      final stats = computeTrendStats(oriented: List.filled(8, 0.2));
      expect(stats.direction, TrendDirection.stable);
    });

    test('a tiny drift is not called a trend', () {
      // Total change 0.2 of a spread across the period: below the minimum.
      final stats = computeTrendStats(
        oriented: [for (var i = 0; i < 8; i++) 0.2 / 7 * i],
      );
      expect(stats.direction, TrendDirection.stable);
    });

    test('a change of exactly the minimum counts', () {
      final stats = computeTrendStats(
        oriented: [for (var i = 0; i < 6; i++) kTrendMinChangeSds / 5 * i],
      );
      expect(stats.direction, TrendDirection.declining);
    });

    test('noise around zero is stable', () {
      final random = math.Random(3);
      var stable = 0;
      for (var trial = 0; trial < 50; trial++) {
        final noise = [for (var i = 0; i < 10; i++) random.nextDouble() - 0.5];
        if (computeTrendStats(oriented: noise).direction ==
            TrendDirection.stable) {
          stable++;
        }
      }
      // Uniform noise of half a spread either side, ten tests: almost always stable.
      expect(stable, greaterThan(40));
    });

    test('one odd test does not turn a steady series into a trend', () {
      final stats = computeTrendStats(
        oriented: [0.1, 0.0, 0.1, 6.0, 0.0, 0.1, 0.0, 0.1],
      );
      expect(stats.direction, TrendDirection.stable);
    });

    test(
      'the slope is reported in spreads and in the measurement\'s units',
      () {
        final stats = computeTrendStats(
          oriented: [for (var i = 0; i < 6; i++) 0.5 * i],
          raw: [for (var i = 0; i < 6; i++) 10.0 + 4.0 * i],
        );
        expect(stats.slopeSds, closeTo(0.5, 1e-12));
        expect(stats.slopeRaw, closeTo(4.0, 1e-12));
      },
    );
  });

  group('runs above the mild and notable levels', () {
    test('a sustained deviation gives a notable run', () {
      final stats = computeTrendStats(oriented: List.filled(12, 3.0));
      expect(stats.runNotable, greaterThan(0));
      expect(stats.runMild, greaterThanOrEqualTo(stats.runNotable));
    });

    test('a steady series has neither', () {
      final stats = computeTrendStats(oriented: List.filled(8, 0.0));
      expect(stats.runMild, 0);
      expect(stats.runNotable, 0);
    });

    test('the mild level is lower than the notable one', () {
      // A deviation that settles at 0.8 smoothed: above mild (0.6), below notable (1.0).
      final stats = computeTrendStats(oriented: List.filled(40, 0.8));
      // The smoothed value takes a few tests to climb from zero to the mild level.
      expect(stats.runMild, greaterThan(30));
      expect(stats.runNotable, 0);
    });

    test('uses the engine\'s thresholds', () {
      expect(kMildFraction * kDefaultThreshold, closeTo(0.6, 1e-12));
    });

    test('the run is of the smoothed value, not the raw test', () {
      // One large spike then calm: the raw value was high once, the smoothed value dips back.
      final stats = computeTrendStats(oriented: [0, 0, 0, 0, 0, 5.0, 0, 0]);
      expect(stats.runNotable, 0);
    });
  });

  group('ranges', () {
    final now = DateTime(2026, 6, 30);
    // Tests every five days for forty days, oldest first.
    final tests = [
      for (var i = 0; i < 9; i++) now.subtract(Duration(days: 40 - i * 5)),
    ];
    List<DateTime> pick(TrendRange range) =>
        applyRange(tests, range, at: (d) => d, now: now);

    test('all keeps everything', () {
      expect(pick(TrendRange.all), tests);
    });

    test('the last seven are the last seven, however long ago', () {
      expect(pick(TrendRange.last7), tests.sublist(2));
    });

    test('fewer than seven keeps them all', () {
      final few = tests.take(3).toList();
      expect(applyRange(few, TrendRange.last7, at: (d) => d, now: now), few);
    });

    test('thirty days is by date', () {
      final result = pick(TrendRange.days30);
      expect(result, isNotEmpty);
      for (final at in result) {
        expect(now.difference(at).inDays, lessThanOrEqualTo(30));
      }
      expect(result.length, lessThan(tests.length));
    });

    test('ninety days keeps all of forty', () {
      expect(pick(TrendRange.days90), tests);
    });

    test('a test exactly on the cutoff is kept', () {
      final edge = [now.subtract(const Duration(days: 30))];
      expect(applyRange(edge, TrendRange.days30, at: (d) => d, now: now), edge);
    });

    test('a test just past it is not', () {
      final past = [now.subtract(const Duration(days: 30, seconds: 1))];
      expect(
        applyRange(past, TrendRange.days30, at: (d) => d, now: now),
        isEmpty,
      );
    });

    test('order is kept', () {
      final result = pick(TrendRange.days30);
      for (var i = 1; i < result.length; i++) {
        expect(result[i].isAfter(result[i - 1]), isTrue);
      }
    });

    test('an empty list stays empty for every range', () {
      for (final range in TrendRange.values) {
        expect(
          applyRange(<DateTime>[], range, at: (d) => d, now: now),
          isEmpty,
        );
      }
    });
  });
}
