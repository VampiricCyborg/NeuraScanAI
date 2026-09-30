/// Scoring the trail-making step.
///
/// A lite version of the classic trail-making test, in two parts. Part A is the numbers 1 to 5,
/// tapped in order: the user's own reference speed for finding and tapping circles. Part B
/// alternates numbers and letters -- 1, A, 2, B, 3, C, 4, D -- which adds the demand of holding
/// two sequences in mind and switching between them. Three features come out:
///
/// * `completion_time` -- seconds to finish part B.
/// * `error_count` -- wrong circles tapped, across both parts.
/// * `switch_cost` -- how much longer each tap takes in part B than in part A, in seconds per
///   tap. It is the part of the slowing that is about switching, not about motor speed, which
///   is why part A is there.
///
/// Times are measured from the moment each part's circles appeared. A part is timed to its
/// last correct tap; a wrong tap does not stop the clock, so errors cost time as they do in
/// the paper test.
///
/// Mirrors nothing in `engine_lab`: extraction is on-device only, and the engine only sees
/// the three numbers.
library;

/// One tap on a circle.
class TrailTapEvent {
  const TrailTapEvent({required this.timestampMs, required this.correct});

  /// Milliseconds after the part's circles appeared.
  final int timestampMs;

  /// True if it was the next circle in the sequence.
  final bool correct;
}

/// Everything that happened in one part.
class TrailPartLog {
  const TrailPartLog({required this.targets, required this.taps});

  /// Circles in the part.
  final int targets;

  /// Every tap, in order, right or wrong.
  final List<TrailTapEvent> taps;

  int get errors => taps.where((tap) => !tap.correct).length;

  int get correctTaps => taps.where((tap) => tap.correct).length;

  /// True if every circle was reached.
  bool get completed => correctTaps >= targets;

  /// Milliseconds to the last correct tap, or to the last tap of any kind if none was right.
  int get durationMs {
    final correct = [
      for (final tap in taps)
        if (tap.correct) tap.timestampMs,
    ];
    if (correct.isNotEmpty) return correct.last;
    return taps.isEmpty ? 0 : taps.last.timestampMs;
  }
}

/// What the trail-making step produced.
class TrailResult {
  const TrailResult({
    required this.completionTimeS,
    required this.errorCount,
    required this.switchCostS,
    required this.partAMeanS,
    required this.partBMeanS,
    required this.completed,
  });

  /// Seconds to finish part B. The `completion_time` feature.
  final double completionTimeS;

  /// Wrong taps in both parts. The `error_count` feature.
  final int errorCount;

  /// Extra seconds per tap in part B over part A. The `switch_cost` feature.
  final double switchCostS;

  /// Mean seconds per circle in part A.
  final double partAMeanS;

  /// Mean seconds per circle in part B.
  final double partBMeanS;

  /// True if both parts were finished.
  final bool completed;
}

/// Scores the two parts.
TrailResult extractTrailFeatures({
  required TrailPartLog partA,
  required TrailPartLog partB,
}) {
  double meanPerTap(TrailPartLog part) =>
      part.targets == 0 ? 0.0 : part.durationMs / 1000.0 / part.targets;

  final aMean = meanPerTap(partA);
  final bMean = meanPerTap(partB);

  return TrailResult(
    completionTimeS: partB.durationMs / 1000.0,
    errorCount: partA.errors + partB.errors,
    switchCostS: bMean - aMean,
    partAMeanS: aMean,
    partBMeanS: bMean,
    completed: partA.completed && partB.completed,
  );
}
