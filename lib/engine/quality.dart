/// Step-level quality gates.
///
/// A step that was not performed properly is worse than no step at all: it enters a
/// baseline as if it were normal behaviour, or it produces a deviation that has nothing to
/// do with the user's neurology. These gates catch the failure modes we can detect
/// mechanically -- saying almost nothing during the speech step, abandoning the spiral
/// part-way, guessing through the reaction trials, tapping too few times to measure a
/// rhythm.
///
/// The gates apply to a single step, not to a whole test. A step that fails is simply done
/// again, so one quiet room or one slipped finger does not throw away a test the user has
/// spent minutes on. (Earlier the gates invalidated the whole session; with eight steps to a
/// test that would have been far too costly.)
///
/// The gates deliberately do not try to detect a user who is simply not trying. That is what
/// the context check-in is for, and it is handled separately as a confound rather than as
/// invalidity.
///
/// Mirrors `engine_lab/neurascan_engine/quality.py`.
library;

import 'constants.dart';

/// The few raw numbers the gates need, per step.
///
/// Everything else about the steps -- the actual trace, the audio -- has already been
/// reduced to features by the time the gates run. The defaults sit exactly on each limit, so
/// the default instance is the boundary case.
class TaskMetrics {
  const TaskMetrics({
    this.voicedSeconds = kMinVoicedSeconds,
    this.spiralCoverage = kMinSpiralCoverage,
    this.anticipations = kMaxAnticipations,
    this.validReactionTrials = kMinValidReactionTrials,
    this.validTaps = kMinValidTaps,
  });

  /// Seconds of voiced speech detected in the picture description.
  final double voicedSeconds;

  /// Share of the guide spiral covered by the trace, in 0..1.
  final double spiralCoverage;

  /// Taps that landed before the reaction stimulus appeared.
  final int anticipations;

  /// Reaction trials that produced a usable time.
  final int validReactionTrials;

  /// Correctly alternated taps in the finger-tapping step.
  final int validTaps;

  TaskMetrics copyWith({
    double? voicedSeconds,
    double? spiralCoverage,
    int? anticipations,
    int? validReactionTrials,
    int? validTaps,
  }) => TaskMetrics(
    voicedSeconds: voicedSeconds ?? this.voicedSeconds,
    spiralCoverage: spiralCoverage ?? this.spiralCoverage,
    anticipations: anticipations ?? this.anticipations,
    validReactionTrials: validReactionTrials ?? this.validReactionTrials,
    validTaps: validTaps ?? this.validTaps,
  );
}

/// Outcome of the gates: whether the step counts, and why not.
class QualityReport {
  const QualityReport({required this.valid, this.failures = const []});

  final bool valid;
  final List<String> failures;

  /// Human-readable summary, for the retry prompt shown to the user.
  String reason() =>
      valid ? 'The step met the quality checks.' : failures.join('; ');
}

/// Applies every gate to [metrics] and reports the combined result.
QualityReport evaluateQuality(TaskMetrics metrics) {
  final failures = <String>[];

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

  if (metrics.validTaps < kMinValidTaps) {
    failures.add(
      'only ${metrics.validTaps} alternating taps '
      '(at least $kMinValidTaps needed)',
    );
  }

  return QualityReport(valid: failures.isEmpty, failures: failures);
}
