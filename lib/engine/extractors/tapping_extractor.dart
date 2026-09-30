/// Scoring the finger-tapping step.
///
/// The user taps two buttons alternately, as fast as they can, for ten seconds. Three features
/// come out, all of them markers of the slowing and irregularity of repetitive movement:
///
/// * `tap_rate` -- correctly alternated taps per second.
/// * `tap_interval_cv` -- how uneven the gaps between those taps are (standard deviation over
///   mean). A steady tapper has a low one; a halting or festinating one does not.
/// * `fatigue_decay` -- how much slower the second half is than the first, as a fraction of
///   the first half's rate. Positive means slowing down; it can be negative for someone who
///   speeds up.
///
/// A tap counts only if it is on the *other* button from the last counted one. Hammering one
/// button is not the task, and counting it would reward the wrong thing. Taps that do not count
/// still tell us something (how many were wasted) and are kept in the total.
///
/// Times are milliseconds after the step started. Taps outside `[0, durationMs]` are ignored.
///
/// Mirrors nothing in `engine_lab`: extraction is on-device only, and the engine only ever sees
/// the three numbers.
library;

import 'dart:math' as math;

import '../constants.dart';

/// One tap, on button [side] (0 for left, 1 for right), [timestampMs] after the start.
class TapEvent {
  const TapEvent({required this.timestampMs, required this.side});

  final int timestampMs;
  final int side;
}

/// What the tapping step produced.
class TappingResult {
  const TappingResult({
    required this.tapRate,
    required this.intervalCv,
    required this.fatigueDecay,
    required this.validTaps,
    required this.totalTaps,
  });

  /// Correctly alternated taps per second. The `tap_rate` feature.
  final double tapRate;

  /// Standard deviation over mean of the intervals between counted taps. The
  /// `tap_interval_cv` feature.
  final double intervalCv;

  /// `(first-half rate - second-half rate) / first-half rate`. The `fatigue_decay` feature.
  final double fatigueDecay;

  /// Taps that alternated correctly.
  final int validTaps;

  /// Every tap in the window, counted or not.
  final int totalTaps;
}

/// Scores [taps] over a window of [durationMs].
TappingResult extractTappingFeatures(
  List<TapEvent> taps, {
  int durationMs = kTappingSeconds * 1000,
}) {
  final inWindow = [
    for (final tap in taps)
      if (tap.timestampMs >= 0 && tap.timestampMs <= durationMs) tap,
  ]..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

  final counted = <TapEvent>[];
  for (final tap in inWindow) {
    if (counted.isEmpty || counted.last.side != tap.side) counted.add(tap);
  }

  final seconds = durationMs / 1000.0;
  final tapRate = counted.length / seconds;

  final intervals = <double>[
    for (var i = 1; i < counted.length; i++)
      (counted[i].timestampMs - counted[i - 1].timestampMs).toDouble(),
  ];
  var cv = 0.0;
  if (intervals.length > 1) {
    final mean = intervals.reduce((a, b) => a + b) / intervals.length;
    if (mean > 0) {
      final sumSquares = intervals
          .map((value) => (value - mean) * (value - mean))
          .reduce((a, b) => a + b);
      cv = math.sqrt(sumSquares / (intervals.length - 1)) / mean;
    }
  }

  final half = durationMs / 2;
  final firstHalf = counted.where((tap) => tap.timestampMs < half).length;
  final secondHalf = counted.length - firstHalf;
  final halfSeconds = seconds / 2;
  final firstRate = firstHalf / halfSeconds;
  final secondRate = secondHalf / halfSeconds;
  final decay = firstRate > 0 ? (firstRate - secondRate) / firstRate : 0.0;

  return TappingResult(
    tapRate: tapRate,
    intervalCv: cv,
    fatigueDecay: decay,
    validTaps: counted.length,
    totalTaps: inWindow.length,
  );
}
