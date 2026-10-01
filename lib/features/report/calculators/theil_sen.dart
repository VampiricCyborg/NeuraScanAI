/// The Theil-Sen slope: the median of the slopes between every pair of points.
///
/// Used instead of a least-squares line because a trend through a handful of tests has to
/// survive one unusual test. A single outlier moves an ordinary regression line a long way; it
/// changes only a few of the pairwise slopes, and the median ignores them. The estimator
/// tolerates nearly a third of the points being outliers.
///
/// The x-axis is the order of the tests, one unit per test, not calendar time: tests are not
/// evenly spaced, and the question the screens answer is "across these tests, which way did it
/// go", not "how fast per day".
library;

import '../../../engine/robust_stats.dart' as stats;

/// Slope of [values] per step, taking them as evenly spaced.
///
/// Null with fewer than two values, where there is no slope to speak of. Equal x-values cannot
/// occur, so no pair is skipped.
double? theilSenSlope(List<double> values) {
  if (values.length < 2) return null;
  final slopes = <double>[];
  for (var i = 0; i < values.length; i++) {
    for (var j = i + 1; j < values.length; j++) {
      slopes.add((values[j] - values[i]) / (j - i));
    }
  }
  return stats.median(slopes);
}

/// Slope of [values] against [xs], for points that are not evenly spaced.
///
/// Pairs with equal x are skipped. Null when no pair is left.
double? theilSenSlopeAt(List<double> xs, List<double> values) {
  assert(xs.length == values.length, 'one x for every value');
  final slopes = <double>[];
  for (var i = 0; i < values.length; i++) {
    for (var j = i + 1; j < values.length; j++) {
      final dx = xs[j] - xs[i];
      if (dx == 0) continue;
      slopes.add((values[j] - values[i]) / dx);
    }
  }
  return slopes.isEmpty ? null : stats.median(slopes);
}
