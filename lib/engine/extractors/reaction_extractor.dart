/// Reaction-time features from the ten-trial tapping task.
///
/// Two features come out of this task and they say different things. The median
/// is how fast the user is; the coefficient of variation is how *consistently*
/// fast they are, and inconsistency is the more interesting early signal --
/// attention lapses widen the spread before they slow the middle.
///
/// The task also produces the anticipation count, which is a quality signal
/// rather than a feature: a user tapping to a rhythm instead of to the stimulus
/// would produce beautifully fast, beautifully consistent numbers that mean
/// nothing.
library;

import 'dart:math' as math;

/// Times below this are physiologically implausible as genuine reactions and are
/// treated as a lucky guess at the foreperiod rather than a real response.
///
/// Simple visual reaction time bottoms out around 150 ms in young adults; 120 ms
/// leaves headroom without admitting pre-emptive taps.
const int kMinPlausibleReactionMs = 120;

/// Times above this are treated as a lapse of attention -- the user looked away,
/// or was interrupted -- rather than as a reaction.
///
/// Discarding them rather than keeping them is a deliberate trade-off: lapses are
/// clinically interesting, but one three-second outlier would dominate a
/// ten-trial coefficient of variation and swamp the signal we can measure
/// reliably.
const int kMaxPlausibleReactionMs = 2000;

/// One reaction trial.
class ReactionTrial {
  const ReactionTrial({required this.responseMs, required this.anticipated});

  /// Milliseconds from stimulus to tap, or null when the user tapped early or
  /// never tapped at all.
  final int? responseMs;

  /// True when the tap landed before the stimulus appeared.
  final bool anticipated;

  /// A trial the user reacted to.
  const ReactionTrial.responded(int ms)
      : responseMs = ms,
        anticipated = false;

  /// A trial the user tapped ahead of.
  const ReactionTrial.anticipation()
      : responseMs = null,
        anticipated = true;

  /// A trial the user never responded to.
  const ReactionTrial.timedOut()
      : responseMs = null,
        anticipated = false;

  /// True when the time is present and physiologically plausible.
  bool get isUsable =>
      !anticipated &&
      responseMs != null &&
      responseMs! >= kMinPlausibleReactionMs &&
      responseMs! <= kMaxPlausibleReactionMs;
}

/// Reaction features and the quality numbers that go with them.
class ReactionResult {
  const ReactionResult({
    required this.medianMs,
    required this.coefficientOfVariation,
    required this.anticipations,
    required this.usableTrials,
    required this.totalTrials,
  });

  /// Median of the usable trials. This is the `reaction_median` feature.
  ///
  /// The median rather than the mean, for the same reason the baseline uses one:
  /// a single slow trial should not define the session.
  final double medianMs;

  /// Standard deviation over the mean of the usable trials. This is the
  /// `reaction_cv` feature.
  ///
  /// Dimensionless, so it is comparable between a fast user and a slow one --
  /// which matters, because the baseline is personal but the feature definition
  /// is shared.
  final double coefficientOfVariation;

  /// Taps that landed before the stimulus.
  final int anticipations;

  /// Trials that survived the plausibility window.
  final int usableTrials;

  /// Trials presented.
  final int totalTrials;
}

/// Extracts the reaction features from [trials].
///
/// Returns zeroed features when nothing usable survived; the caller's quality
/// gate is what turns that into an invalid session, so this function does not
/// throw.
ReactionResult extractReactionFeatures(List<ReactionTrial> trials) {
  final usable = <double>[
    for (final trial in trials)
      if (trial.isUsable) trial.responseMs!.toDouble(),
  ]..sort();

  final anticipations = trials.where((trial) => trial.anticipated).length;

  if (usable.isEmpty) {
    return ReactionResult(
      medianMs: 0.0,
      coefficientOfVariation: 0.0,
      anticipations: anticipations,
      usableTrials: 0,
      totalTrials: trials.length,
    );
  }

  final middle = usable.length ~/ 2;
  final medianMs = usable.length.isOdd
      ? usable[middle]
      : (usable[middle - 1] + usable[middle]) / 2.0;

  final mean = usable.reduce((a, b) => a + b) / usable.length;

  // The sample standard deviation, with Bessel's correction, because ten trials
  // is a sample of the user's reaction behaviour rather than the whole of it.
  // A single usable trial has no spread to estimate, so the CV is zero there.
  var cv = 0.0;
  if (usable.length > 1 && mean > 0) {
    final sumSquares = usable
        .map((value) => (value - mean) * (value - mean))
        .reduce((a, b) => a + b);
    cv = math.sqrt(sumSquares / (usable.length - 1)) / mean;
  }

  return ReactionResult(
    medianMs: medianMs,
    coefficientOfVariation: cv,
    anticipations: anticipations,
    usableTrials: usable.length,
    totalTrials: trials.length,
  );
}
