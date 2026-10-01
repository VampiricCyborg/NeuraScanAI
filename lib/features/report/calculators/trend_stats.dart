/// The statistics behind the trend screens and the report.
///
/// Everything here is a plain function of numbers, so it can be tested without a screen and
/// used unchanged by the PDF. Values are taken *oriented* wherever a direction matters: in units
/// of the user's own usual spread, positive meaning worse, the same convention the engine uses.
/// That is what lets one rule judge a reaction time (worse when it rises) and a recall score
/// (worse when it falls).
///
/// Nothing here re-implements the engine. The smoothing is the engine's (`kEwmaLambda`), the
/// thresholds are the engine's (`kDefaultThreshold`, `kMildFraction`), and a status is never
/// derived here; these are the supporting numbers shown beside it.
library;

import '../../../engine/constants.dart';
import '../models.dart';
import '../report_constants.dart';
import 'theil_sen.dart';

/// An exponentially weighted moving average of [values], starting from [start].
///
/// Starts from zero by default because that is where the engine starts: a deviation of zero
/// spreads is "as usual". One entry per value.
List<double> ewmaSeries(
  List<double> values, {
  double lambda = kEwmaLambda,
  double start = 0.0,
}) {
  final result = <double>[];
  var current = start;
  for (final value in values) {
    current = lambda * value + (1 - lambda) * current;
    result.add(current);
  }
  return result;
}

/// How many of the most recent entries of [series], unbroken, are at or above [threshold].
///
/// Zero if the last one is below it. This is the persistence count the engine's rule is about:
/// a notable change needs it to reach the persistence length.
int trailingRunAtOrAbove(List<double> series, double threshold) {
  var run = 0;
  for (var i = series.length - 1; i >= 0; i--) {
    if (series[i] >= threshold) {
      run++;
    } else {
      break;
    }
  }
  return run;
}

/// The mean of the (up to) [window] values before [index], or null if there are none.
///
/// "Before" so that a test is compared with what came earlier and not with itself.
double? priorMean(
  List<double> values,
  int index, {
  int window = kRollingWindow,
}) {
  if (index <= 0) return null;
  final start = index - window < 0 ? 0 : index - window;
  final slice = values.sublist(start, index);
  if (slice.isEmpty) return null;
  return slice.reduce((a, b) => a + b) / slice.length;
}

/// The statistics of one series of valid tests.
class TrendStats {
  const TrendStats({
    required this.n,
    required this.enough,
    this.slopeRaw,
    this.slopeSds,
    this.direction,
    this.ewma,
    this.runMild = 0,
    this.runNotable = 0,
  });

  /// Valid tests in the series.
  final int n;

  /// True when there are enough of them ([kMinSessionsForTrend]) for a trend to be stated.
  final bool enough;

  /// The Theil-Sen slope in the measurement's own units per test. Null unless [enough].
  final double? slopeRaw;

  /// The same slope in spreads per test, oriented so that positive is worse. Null unless
  /// [enough].
  final double? slopeSds;

  /// Improving, stable or declining. Null unless [enough].
  final TrendDirection? direction;

  /// The smoothed deviation after the latest test, in spreads, positive worse. Null if there
  /// are no tests.
  final double? ewma;

  /// Consecutive latest tests with the smoothed deviation at or above the mild level.
  final int runMild;

  /// Consecutive latest tests with the smoothed deviation at or above the notable level.
  final int runNotable;
}

/// Computes [TrendStats] from [oriented], one deviation per valid test, oldest first, in
/// spreads with positive meaning worse.
///
/// [raw] are the same tests' values in the measurement's own units, for the slope to be shown
/// in them. The direction is judged on the total change across the series in spreads, which is
/// [minChange] or more before it is called improving or declining.
TrendStats computeTrendStats({
  required List<double> oriented,
  List<double>? raw,
  int minSessions = kMinSessionsForTrend,
  double minChange = kTrendMinChangeSds,
  double threshold = kDefaultThreshold,
}) {
  final n = oriented.length;
  final smoothed = ewmaSeries(oriented);
  final mildLevel = kMildFraction * threshold;

  final runMild = trailingRunAtOrAbove(smoothed, mildLevel);
  final runNotable = trailingRunAtOrAbove(smoothed, threshold);
  final ewma = smoothed.isEmpty ? null : smoothed.last;

  if (n < minSessions) {
    return TrendStats(
      n: n,
      enough: false,
      ewma: ewma,
      runMild: runMild,
      runNotable: runNotable,
    );
  }

  final slopeSds = theilSenSlope(oriented)!;
  final change = slopeSds * (n - 1);
  final direction = change >= minChange
      ? TrendDirection.declining
      : change <= -minChange
      ? TrendDirection.improving
      : TrendDirection.stable;

  return TrendStats(
    n: n,
    enough: true,
    slopeRaw: raw == null ? null : theilSenSlope(raw),
    slopeSds: slopeSds,
    direction: direction,
    ewma: ewma,
    runMild: runMild,
    runNotable: runNotable,
  );
}

/// The items of [items] inside [range], measured back from [now].
///
/// Items must be oldest first. "Last 7" is the last seven items whenever they were; the day
/// ranges are by date.
List<T> applyRange<T>(
  List<T> items,
  TrendRange range, {
  required DateTime Function(T item) at,
  required DateTime now,
}) {
  switch (range) {
    case TrendRange.all:
      return List<T>.of(items);
    case TrendRange.last7:
      final start = items.length - kRangeSessions;
      return items.sublist(start < 0 ? 0 : start);
    case TrendRange.days30:
      final cutoff = now.subtract(const Duration(days: kRangeShortDays));
      return [
        for (final item in items)
          if (!at(item).isBefore(cutoff)) item,
      ];
    case TrendRange.days90:
      final cutoff = now.subtract(const Duration(days: kRangeLongDays));
      return [
        for (final item in items)
          if (!at(item).isBefore(cutoff)) item,
      ];
  }
}
