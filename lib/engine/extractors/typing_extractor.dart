/// Typing-rhythm features from the app's own text fields.
///
/// This is the one passive signal in the session. It is collected only inside
/// NeuraScan's own fields -- the delayed-recall box, the sign-up form -- and never
/// through a system-wide keyboard service. That boundary is the whole reason the
/// feature is defensible: a keyboard that watched everything the user typed would
/// be a far more sensitive data store than anything else in the app, and the
/// screening value would not justify it.
///
/// What is recorded is timing only. The interval between two key presses is kept;
/// which keys they were is not, so the raw signal cannot reconstruct the text.
library;

import 'dart:math' as math;

/// Gaps longer than this are a pause for thought, not a typing rhythm.
///
/// Recall typing in particular is bursty: the user remembers a word, types it
/// quickly, then stops to think. Keeping the thinking gaps would measure
/// hesitation, which is what the speech pause ratio already measures, and would
/// swamp the motor signal this feature is for.
const int kMaxInterKeyIntervalMs = 2000;

/// Gaps shorter than this are not two deliberate presses.
///
/// A key repeat, a two-finger roll or an autocomplete insertion can land two
/// characters within a few milliseconds of each other.
const int kMinInterKeyIntervalMs = 20;

/// Intervals needed before the features mean anything.
///
/// Below this the median and the coefficient of variation are dominated by
/// whichever few gaps happened to be recorded.
const int kMinInterKeyIntervals = 8;

/// A single character insertion, recorded by timestamp only.
class KeystrokeEvent {
  const KeystrokeEvent({required this.timestampMs});

  /// Milliseconds on a monotonic clock. No key identity is stored.
  final int timestampMs;
}

/// Typing features and the quality numbers that go with them.
class TypingResult {
  const TypingResult({
    required this.medianIntervalMs,
    required this.coefficientOfVariation,
    required this.usableIntervals,
    required this.totalIntervals,
  });

  /// Median gap between character inserts, in ms. This is the
  /// `inter_key_interval` feature.
  final double medianIntervalMs;

  /// Standard deviation over the mean of the usable gaps. This is the
  /// `inter_key_cv` feature.
  ///
  /// Rhythm irregularity is the more interesting of the two: the keystroke
  /// literature on early Parkinson's finds the variability of hold and flight
  /// times separating patients from controls better than their average speed.
  final double coefficientOfVariation;

  /// Gaps that survived the plausibility window.
  final int usableIntervals;

  /// Gaps observed, before filtering.
  final int totalIntervals;

  /// True when enough intervals survived for the features to be meaningful.
  bool get hasEnoughData => usableIntervals >= kMinInterKeyIntervals;
}

/// Extracts the typing features from [events].
///
/// Events are expected in the order they occurred; they are sorted defensively
/// because they may have been merged from more than one field within a session.
TypingResult extractTypingFeatures(List<KeystrokeEvent> events) {
  if (events.length < 2) {
    return const TypingResult(
      medianIntervalMs: 0.0,
      coefficientOfVariation: 0.0,
      usableIntervals: 0,
      totalIntervals: 0,
    );
  }

  final timestamps = [for (final event in events) event.timestampMs]..sort();

  final all = <double>[];
  final usable = <double>[];
  for (var i = 1; i < timestamps.length; i++) {
    final gap = (timestamps[i] - timestamps[i - 1]).toDouble();
    all.add(gap);
    if (gap >= kMinInterKeyIntervalMs && gap <= kMaxInterKeyIntervalMs) {
      usable.add(gap);
    }
  }

  if (usable.isEmpty) {
    return TypingResult(
      medianIntervalMs: 0.0,
      coefficientOfVariation: 0.0,
      usableIntervals: 0,
      totalIntervals: all.length,
    );
  }

  usable.sort();
  final middle = usable.length ~/ 2;
  final medianMs = usable.length.isOdd
      ? usable[middle]
      : (usable[middle - 1] + usable[middle]) / 2.0;

  final mean = usable.reduce((a, b) => a + b) / usable.length;
  var cv = 0.0;
  if (usable.length > 1 && mean > 0) {
    final sumSquares = usable
        .map((value) => (value - mean) * (value - mean))
        .reduce((a, b) => a + b);
    cv = math.sqrt(sumSquares / (usable.length - 1)) / mean;
  }

  return TypingResult(
    medianIntervalMs: medianMs,
    coefficientOfVariation: cv,
    usableIntervals: usable.length,
    totalIntervals: all.length,
  );
}
