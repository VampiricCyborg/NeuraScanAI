/// Task-level quality gates.
///
/// A session that was not performed properly is worse than no session at all: it
/// enters the baseline as if it were normal behaviour, or it produces a deviation
/// that has nothing to do with the user's neurology. These gates catch the
/// failure modes we can detect mechanically -- tapping ahead of the stimulus,
/// saying almost nothing during the speech task, abandoning the spiral part-way
/// -- and mark the session invalid so the engine ignores it entirely.
///
/// The gates deliberately do not try to detect a user who is simply not trying.
/// That is what the context check-in is for, and it is handled separately as a
/// confound rather than as invalidity.
///
/// Mirrors `engine_lab/neurascan_engine/quality.py`.
library;

import 'constants.dart';

/// The few raw numbers the gates need, per session.
///
/// Everything else about the tasks -- the actual trace, the audio, the trial
/// times -- has already been reduced to features by the time the gates run.
class TaskMetrics {
  const TaskMetrics({
    this.anticipations = 0,
    this.validReactionTrials = kMinValidReactionTrials,
    this.voicedSeconds = kMinVoicedSeconds,
    this.spiralCoverage = kMinSpiralCoverage,
  });

  /// Taps that landed before the reaction stimulus appeared.
  final int anticipations;

  /// Reaction trials that produced a usable time.
  final int validReactionTrials;

  /// Seconds of voiced speech detected in the picture description.
  final double voicedSeconds;

  /// Share of the guide spiral covered by the trace, in 0..1.
  final double spiralCoverage;

  TaskMetrics copyWith({
    int? anticipations,
    int? validReactionTrials,
    double? voicedSeconds,
    double? spiralCoverage,
  }) => TaskMetrics(
    anticipations: anticipations ?? this.anticipations,
    validReactionTrials: validReactionTrials ?? this.validReactionTrials,
    voicedSeconds: voicedSeconds ?? this.voicedSeconds,
    spiralCoverage: spiralCoverage ?? this.spiralCoverage,
  );
}

/// Outcome of the gates: whether the session counts, and why not.
class QualityReport {
  const QualityReport({required this.valid, this.failures = const []});

  final bool valid;
  final List<String> failures;

  /// Human-readable summary, for the retry prompt shown to the user.
  String reason() =>
      valid ? 'All tasks met the quality checks.' : failures.join('; ');
}

/// Applies every gate to [metrics] and reports the combined result.
QualityReport evaluateQuality(TaskMetrics metrics) {
  final failures = <String>[];

  if (metrics.anticipations > kMaxAnticipations) {
    failures.add(
      '${metrics.anticipations} taps came before the stimulus '
      '(at most $kMaxAnticipations allowed)',
    );
  }

  if (metrics.validReactionTrials < kMinValidReactionTrials) {
    failures.add(
      'only ${metrics.validReactionTrials} usable reaction trials '
      '(at least $kMinValidReactionTrials needed)',
    );
  }

  if (metrics.voicedSeconds < kMinVoicedSeconds) {
    failures.add(
      'only ${metrics.voicedSeconds.toStringAsFixed(1)} s of speech detected '
      '(at least ${kMinVoicedSeconds.toStringAsFixed(0)} s needed)',
    );
  }

  if (metrics.spiralCoverage < kMinSpiralCoverage) {
    failures.add(
      'spiral only ${(metrics.spiralCoverage * 100).toStringAsFixed(0)} % traced '
      '(at least ${(kMinSpiralCoverage * 100).toStringAsFixed(0)} % needed)',
    );
  }

  return QualityReport(valid: failures.isEmpty, failures: failures);
}
