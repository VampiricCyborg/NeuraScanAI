/// How one full test compares with the baseline and with the test before it.
///
/// This is the answer to "did I do better or worse, and by how much?" for each measurement and
/// each area. It is display logic built on the same numbers the engine uses -- the baseline's
/// median and its spread -- and it changes nothing the engine decides. The status still comes
/// from the smoothed score and the persistence rule; this only lays the test out against what
/// the user usually does and against what they did last time.
///
/// Everything is judged in units of the user's own spread, the same as the engine. A change
/// counts as *better* or *worse* only when it is at least [kSimilarBandSds] of that spread;
/// anything smaller is *about the same*, because a change inside a person's ordinary
/// day-to-day variation says nothing either way.
library;

import 'baseline.dart';
import 'features.dart';
import 'scoring.dart';

/// Which way something moved, from the user's point of view.
enum Change { better, similar, worse }

/// How far, in units of the user's own spread, a measurement has to move to count as better
/// or worse rather than about the same.
///
/// One spread is also the engine's own alert threshold for a single test, so "worse" here
/// means "far enough that, if it kept up, it would start to matter".
const double kSimilarBandSds = 1.0;

Change _classify(double orientedSds) {
  if (orientedSds >= kSimilarBandSds) return Change.worse;
  if (orientedSds <= -kSimilarBandSds) return Change.better;
  return Change.similar;
}

/// One measurement in one test, set against the baseline and the previous test.
class MeasurementComparison {
  const MeasurementComparison({
    required this.spec,
    required this.value,
    required this.baselineMedian,
    required this.baselineScale,
    this.previous,
  });

  final FeatureSpec spec;

  /// This test's value.
  final double value;

  /// The user's usual value and how much it usually varies.
  final double baselineMedian;
  final double baselineScale;

  /// The previous full test's value, or null when there is no earlier one.
  final double? previous;

  /// How far this test is from the usual value, in spreads. Positive means worse.
  double get sdsFromBaseline =>
      spec.orient((value - baselineMedian) / baselineScale);

  Change get vsBaseline => _classify(sdsFromBaseline);

  /// How far this test moved from the previous one, in spreads. Positive means worse.
  double? get sdsFromPrevious => previous == null
      ? null
      : spec.orient((value - previous!) / baselineScale);

  Change? get vsPrevious =>
      sdsFromPrevious == null ? null : _classify(sdsFromPrevious!);
}

/// One area in one test: the mean of its measurements' oriented scores.
class AreaComparison {
  const AreaComparison({
    required this.domain,
    required this.score,
    required this.measurements,
    this.previousScore,
  });

  final Domain domain;

  /// The area's score against the baseline, in spreads. Positive means worse.
  final double score;

  /// The area's score in the previous test, or null when there is no earlier one.
  final double? previousScore;

  final List<MeasurementComparison> measurements;

  Change get vsBaseline => _classify(score);

  /// How the area moved since the previous test. Positive means worse.
  double? get changeFromPrevious =>
      previousScore == null ? null : score - previousScore!;

  Change? get vsPrevious =>
      changeFromPrevious == null ? null : _classify(changeFromPrevious!);
}

/// A whole test laid out against the baseline and the previous test.
class TestComparison {
  const TestComparison({required this.areas, required this.hasPrevious});

  final List<AreaComparison> areas;

  /// False for the first full test, which has nothing earlier to be compared with.
  final bool hasPrevious;

  /// Every measurement, in the order they are measured.
  List<MeasurementComparison> get measurements => [
    for (final area in areas) ...area.measurements,
  ];
}

/// Compares [latest] with [baseline] and, when given, with [previous].
///
/// [latest] and [previous] are the features of two full tests. Measurements missing from
/// either are left out rather than guessed.
TestComparison compareTests({
  required Map<String, double> latest,
  required Baseline baseline,
  Map<String, double>? previous,
}) {
  final scores = domainScores(latest, baseline.median, baseline.scale);
  final previousScores = previous == null
      ? null
      : domainScores(previous, baseline.median, baseline.scale);

  final areas = <AreaComparison>[];
  for (final domain in Domain.values) {
    final measurements = <MeasurementComparison>[
      for (final spec in specsFor(domain))
        if (latest.containsKey(spec.key) &&
            baseline.median.containsKey(spec.key))
          MeasurementComparison(
            spec: spec,
            value: latest[spec.key]!,
            baselineMedian: baseline.median[spec.key]!,
            baselineScale: baseline.scale[spec.key]!,
            previous: previous?[spec.key],
          ),
    ];
    if (measurements.isEmpty) continue;
    areas.add(
      AreaComparison(
        domain: domain,
        score: scores[domain] ?? 0.0,
        previousScore: previousScores?[domain],
        measurements: measurements,
      ),
    );
  }

  return TestComparison(areas: areas, hasPrevious: previous != null);
}
