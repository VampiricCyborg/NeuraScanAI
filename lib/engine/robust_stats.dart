/// Robust summary statistics used to build a personal baseline.
///
/// These live in their own library rather than alongside [Baseline] for two
/// reasons. The practical one is that `Baseline` has a field called `median`,
/// which would shadow a top-level function of the same name anywhere inside the
/// class body. The better one is that these are general-purpose and worth reading
/// on their own: the choice of median and MAD over mean and standard deviation is
/// the single decision that makes a baseline built from a handful of sessions usable at all.
library;

import 'dart:math' as math;

import 'constants.dart';

/// Median of [values].
///
/// Throws [ArgumentError] on an empty list, because a baseline with no sessions
/// is a programming error rather than a state the UI should ever reach.
double median(List<double> values) {
  if (values.isEmpty) {
    throw ArgumentError('median of an empty list');
  }
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2.0;
}

/// Median of the absolute deviations from the median.
///
/// Preferred over a standard deviation here because it has a breakdown point of
/// 50 %: half the baseline sessions would have to be unusual before the estimate
/// is affected, whereas one extreme session is enough to inflate an SD
/// noticeably at n = 6.
double medianAbsoluteDeviation(List<double> values) {
  final centre = median(values);
  return median([for (final value in values) (value - centre).abs()]);
}

/// Spread of [values] as a floored, sigma-equivalent robust scale.
///
/// The MAD is rescaled by [kMadToSigma] so that a resulting z-score reads on the
/// familiar standard-deviation scale, then floored so that a user whose baseline
/// happens to be perfectly consistent does not get infinite z-scores forever
/// after.
double robustScale(List<double> values) {
  final centre = median(values);
  final scale = kMadToSigma * medianAbsoluteDeviation(values);
  final floor = math.max(
    kScaleFloorFraction * centre.abs(),
    kScaleFloorAbsolute,
  );
  return math.max(scale, floor);
}
