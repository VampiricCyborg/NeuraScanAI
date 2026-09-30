/// Motor features from the spiral-tracing task.
///
/// The user traces a three-turn Archimedean spiral with a finger. Two features
/// come out of the trace, and they separate two different kinds of motor problem.
///
/// The RMS radial error is accuracy: how far the finger strayed from the guide.
/// It rises with anything that degrades fine motor control.
///
/// The tremor index is more specific. The radial error is resampled to a uniform
/// time grid and the share of its power sitting in the 4-12 Hz band is measured.
/// That band is where pathological tremor lives -- Parkinsonian rest tremor
/// around 4-6 Hz, essential tremor higher up -- while deliberate hand movement is
/// almost entirely below 4 Hz. So a shaky trace and a merely inaccurate one look
/// different here, which a single accuracy number could not show.
library;

import 'dart:math' as math;

/// Lower edge of the tremor band.
const double kTremorBandLowHz = 4.0;

/// Upper edge of the tremor band.
const double kTremorBandHighHz = 12.0;

/// Rate the error series is resampled to before the transform.
///
/// Touch sampling varies between 60 and 120 Hz across phones and is not evenly
/// spaced even on one device, so the series has to be put on a uniform grid
/// before a frequency estimate means anything. 100 Hz keeps the Nyquist limit
/// comfortably above the top of the tremor band.
const double kResampleHz = 100.0;

/// Arc-length bins used to measure how much of the guide was traced.
///
/// Coverage is judged over the guide rather than over the trace, so scribbling
/// densely in one corner cannot pass the gate.
const int kCoverageBins = 60;

/// How close a sample must be to the guide to count as covering its part of it,
/// as a fraction of the gap between neighbouring turns.
///
/// This was a fixed 24 dp, which turned out to be far too generous on a real phone:
/// there the turns are only about 55 dp apart, so 24 dp either side of the line meant
/// a finger anywhere in roughly 85 % of the space between turns still counted as
/// "on the spiral", and a trace well off the line reached the 70 % gate anyway.
///
/// Tying it to the turn spacing keeps it meaningful at any screen size. A quarter of
/// the spacing is about 14 dp on a phone, comfortably above the roughly 6 dp of
/// ordinary hand error in the report's simulation parameters, but tight enough that
/// straying half way to the next turn no longer counts.
const double kCoverageToleranceFraction = 0.25;

/// The largest step between consecutive samples, as a fraction of the turn spacing, that
/// still counts as the same continuous stroke. Beyond it the turn is re-resolved by radius.
const double kMaxContinuousStepFraction = 0.6;

/// Samples closer than this to the centre are left out of the error analysis.
///
/// The angle of a point at the centre is undefined, and just outside it a
/// movement of a single pixel swings the angle by a large fraction of a turn. The
/// radial error at those samples is therefore dominated by where the angle
/// happened to land rather than by the user's accuracy. The innermost few
/// millimetres of the guide are excluded rather than allowed to drown the signal
/// from the rest of the trace.
///
/// Coverage still counts these samples, because the user did trace that part.
const double kMinAnalysisRadiusDp = 10.0;

/// Radial-error variation, in dp RMS, below which there is no oscillation to
/// characterise.
///
/// Touch coordinates are quantised, and a near-perfect trace leaves an error
/// series that is floating-point residue. Measuring which frequency band that
/// residue sits in would return an essentially arbitrary number, so the tremor
/// index is reported as zero instead.
const double kMinTremorAmplitudeDp = 0.05;

/// One sampled touch point.
class TracePoint {
  const TracePoint({
    required this.x,
    required this.y,
    required this.timestampMs,
  });

  final double x;
  final double y;

  /// Milliseconds since the trace began.
  final int timestampMs;
}

/// The guide spiral the user is asked to follow.
///
/// An Archimedean spiral, r = a + b*theta, because its turns are evenly spaced --
/// so the task is equally hard throughout, and the radial error means the same
/// thing at the centre as at the edge.
class GuideSpiral {
  const GuideSpiral({
    required this.centre,
    required this.maxRadius,
    this.turns = 3,
  });

  /// Centre of the spiral, in the same coordinate space as the trace.
  final ({double x, double y}) centre;

  /// Radius at the outermost point.
  final double maxRadius;

  /// Complete turns from centre to edge.
  final int turns;

  double get _totalAngle => turns * 2 * math.pi;

  /// Radial distance between neighbouring turns.
  ///
  /// The natural unit for judging accuracy: how far off the line is only meaningful
  /// relative to how far away the next turn is.
  double get turnSpacing => maxRadius / turns;

  /// Guide radius at angle [theta], measured from the centre outwards.
  double radiusAt(double theta) => maxRadius * (theta / _totalAngle);

  /// The point on the guide at angle [theta].
  ({double x, double y}) pointAt(double theta) {
    final r = radiusAt(theta);
    return (
      x: centre.x + r * math.cos(theta),
      y: centre.y + r * math.sin(theta),
    );
  }

  /// The unwrapped angle to start tracking from, given the first recorded point.
  ///
  /// `atan2` only says where a point is *round* the circle, in -pi..pi. Which *turn* of
  /// the spiral the finger is on is invisible in that: a point 3.5 rad round the third
  /// turn and a point -2.8 rad round the zeroth turn look identical. Taking the raw angle
  /// silently assumed the first turn, and every later sample was then compared with the
  /// guide one full turn out, so a perfectly accurate trace scored as a poor one.
  ///
  /// It matters in practice, not just in theory. A touchscreen only starts reporting a drag
  /// after the finger has moved past the touch slop, roughly 18 px, so the first recorded
  /// point is already well out from the centre and often more than half a turn round.
  ///
  /// So the turn is chosen by radius: of the angles that fit the point's direction, the one
  /// whose guide radius is nearest the point's actual distance from the centre. Nearer the
  /// centre than one turn there is only one sensible answer, and the search reduces to the
  /// raw angle, as before.
  double initialAngle(TracePoint first) {
    final dx = first.x - centre.x;
    final dy = first.y - centre.y;
    final distance = math.sqrt(dx * dx + dy * dy);
    final raw = math.atan2(dy, dx);

    var best = raw;
    var bestError = double.infinity;
    for (var turn = 0; turn <= turns; turn++) {
      final candidate = raw + 2 * math.pi * turn;
      final error = (distance - radiusAt(math.max(0.0, candidate))).abs();
      // Strictly better, so a tie keeps the earlier turn.
      if (error < bestError - 1e-9) {
        bestError = error;
        best = candidate;
      }
    }
    return best;
  }

  /// Unwrapped angle of a trace point, given the angle of the previous point.
  ///
  /// `atan2` wraps at pi, which would make a continuous trace look like it jumped
  /// backwards several turns. Unwrapping relative to the previous angle keeps the
  /// progression monotonic so that a point can be matched to the right turn of
  /// the guide.
  double unwrapAngle(TracePoint point, double previousAngle) {
    final raw = math.atan2(point.y - centre.y, point.x - centre.x);
    var candidate = raw;
    while (candidate < previousAngle - math.pi) {
      candidate += 2 * math.pi;
    }
    while (candidate > previousAngle + math.pi) {
      candidate -= 2 * math.pi;
    }
    return candidate;
  }
}

/// Motor features and the quality numbers that go with them.
class SpiralResult {
  const SpiralResult({
    required this.rmse,
    required this.tremorIndex,
    required this.coverage,
    required this.sampleCount,
    required this.durationSeconds,
  });

  /// RMS radial distance of the trace from the guide, in dp. This is the
  /// `spiral_rmse` feature.
  final double rmse;

  /// Share of the radial-error power in the 4-12 Hz band, in 0..1. This is the
  /// `tremor_index` feature.
  final double tremorIndex;

  /// Share of the guide the trace came close to, in 0..1. A quality signal.
  final double coverage;

  final int sampleCount;
  final double durationSeconds;
}

/// Extracts the motor features from [trace] against [guide].
SpiralResult extractSpiralFeatures({
  required List<TracePoint> trace,
  required GuideSpiral guide,
}) {
  if (trace.length < 3) {
    return const SpiralResult(
      rmse: 0.0,
      tremorIndex: 0.0,
      coverage: 0.0,
      sampleCount: 0,
      durationSeconds: 0.0,
    );
  }

  // Radial error at each sample: how far from the guide radius the finger was at
  // the angle it had reached. Radial rather than nearest-point distance, because
  // it is cheap, stable, and the quantity whose oscillation is the tremor.
  //
  // Every sample gets an error and an angle, because coverage is judged over the
  // whole trace. Only samples far enough from the centre go on to the error
  // analysis, for the reason given at [kMinAnalysisRadiusDp].
  final allErrors = <double>[];
  final allAngles = <double>[];
  final allTimes = <double>[];
  final analysableErrors = <double>[];
  final analysableTimes = <double>[];

  var previousAngle = 0.0;
  TracePoint? previous;

  for (final point in trace) {
    // Continuity picks the turn while consecutive points are close together. It cannot
    // across a gap: the touchscreen reports nothing until the finger passes the pan slop
    // (about 36 px), so the point after the touch-down sample can be a long way on, and
    // "the nearest angle to the last one" then lands a whole turn out for the rest of the
    // trace. After a gap, and for the first point, the turn is chosen by radius instead.
    final theta = previous == null || _isGap(previous, point, guide)
        ? guide.initialAngle(point)
        : guide.unwrapAngle(point, previousAngle);
    previousAngle = theta;
    previous = point;

    final dx = point.x - guide.centre.x;
    final dy = point.y - guide.centre.y;
    final actualRadius = math.sqrt(dx * dx + dy * dy);
    // Angles behind the start of the guide have no meaningful target radius, so
    // they are clamped to the start rather than producing a negative one.
    final expectedRadius = guide.radiusAt(math.max(0.0, theta));
    final error = actualRadius - expectedRadius;
    final seconds = point.timestampMs / 1000.0;

    allErrors.add(error);
    allAngles.add(theta);
    allTimes.add(seconds);

    if (actualRadius >= kMinAnalysisRadiusDp) {
      analysableErrors.add(error);
      analysableTimes.add(seconds);
    }
  }

  final coverage = _coverage(
    angles: allAngles,
    errors: allErrors,
    guide: guide,
  );
  final durationSeconds = allTimes.last - allTimes.first;

  if (analysableErrors.isEmpty) {
    // The whole trace sat on the centre point. There is nothing to compare
    // against the guide, and the coverage gate will reject the session.
    return SpiralResult(
      rmse: 0.0,
      tremorIndex: 0.0,
      coverage: coverage,
      sampleCount: trace.length,
      durationSeconds: durationSeconds,
    );
  }

  final sumSquares =
      analysableErrors.map((error) => error * error).reduce((a, b) => a + b) /
      analysableErrors.length;
  final rmse = math.sqrt(sumSquares);

  final resampled = _resampleUniform(
    times: analysableTimes,
    values: analysableErrors,
    rateHz: kResampleHz,
  );
  final tremorIndex = _bandPowerShare(
    series: resampled,
    sampleRateHz: kResampleHz,
    lowHz: kTremorBandLowHz,
    highHz: kTremorBandHighHz,
  );

  return SpiralResult(
    rmse: rmse,
    tremorIndex: tremorIndex,
    coverage: coverage,
    sampleCount: trace.length,
    durationSeconds: durationSeconds,
  );
}

/// Whether [to] is too far from [from] to trust that it is the same turn of the spiral.
///
/// A fraction of the turn spacing, because that is the scale on which the turns are
/// distinguishable at all. A finger moving fast enough to cover this in one touch sample
/// (about 30 dp between samples on a phone, roughly 1800 dp/s at 60 Hz) is far quicker than
/// anyone traces a spiral.
bool _isGap(TracePoint from, TracePoint to, GuideSpiral guide) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;
  return math.sqrt(dx * dx + dy * dy) >
      guide.turnSpacing * kMaxContinuousStepFraction;
}

/// Share of the guide the trace came close to.
///
/// The guide's angular range is split into bins and a bin counts as covered when
/// some sample fell in it within [kCoverageToleranceFraction] of a turn's spacing of
/// the guide radius.
double _coverage({
  required List<double> angles,
  required List<double> errors,
  required GuideSpiral guide,
}) {
  final totalAngle = guide.turns * 2 * math.pi;
  final tolerance = guide.turnSpacing * kCoverageToleranceFraction;
  final covered = List<bool>.filled(kCoverageBins, false);

  for (var i = 0; i < angles.length; i++) {
    final theta = angles[i];
    if (theta < 0 || theta > totalAngle) continue;
    if (errors[i].abs() > tolerance) continue;

    final bin = ((theta / totalAngle) * kCoverageBins).floor();
    if (bin >= 0 && bin < kCoverageBins) covered[bin] = true;
  }

  return covered.where((isCovered) => isCovered).length / kCoverageBins;
}

/// Linearly resamples an irregular series onto a uniform grid at [rateHz].
///
/// Touch events do not arrive evenly, and a frequency estimate from unevenly
/// spaced samples would attribute power to the wrong band.
List<double> _resampleUniform({
  required List<double> times,
  required List<double> values,
  required double rateHz,
}) {
  if (times.length < 2) return const [];

  final duration = times.last - times.first;
  final count = (duration * rateHz).floor();
  if (count < 4) return const [];

  final resampled = List<double>.filled(count, 0.0);
  var cursor = 0;
  for (var i = 0; i < count; i++) {
    final t = times.first + i / rateHz;
    while (cursor < times.length - 2 && times[cursor + 1] < t) {
      cursor++;
    }
    final t0 = times[cursor];
    final t1 = times[cursor + 1];
    final span = t1 - t0;
    // Coincident timestamps happen when two touch events share a millisecond;
    // interpolating across a zero span would divide by zero.
    final weight = span <= 0 ? 0.0 : ((t - t0) / span).clamp(0.0, 1.0);
    resampled[i] =
        values[cursor] + weight * (values[cursor + 1] - values[cursor]);
  }
  return resampled;
}

/// Share of the total power of [series] falling between [lowHz] and [highHz].
///
/// The mean is removed first, so a trace that was simply drawn too large does not
/// put all its power at DC and dilute the band share.
double _bandPowerShare({
  required List<double> series,
  required double sampleRateHz,
  required double lowHz,
  required double highHz,
}) {
  if (series.length < 8) return 0.0;

  final mean = series.reduce((a, b) => a + b) / series.length;
  final centred = [for (final value in series) value - mean];

  // A trace that followed the guide almost exactly leaves an error series that is
  // numerical residue rather than movement. Asking which band that residue sits in
  // would return an arbitrary number, so report no tremor instead.
  final variation = math.sqrt(
    centred.map((value) => value * value).reduce((a, b) => a + b) /
        centred.length,
  );
  if (variation < kMinTremorAmplitudeDp) return 0.0;

  // Zero-padded to a power of two for the radix-2 transform. Padding spreads a
  // little energy between neighbouring bins, which is acceptable here because
  // the result is a ratio over a wide band rather than a precise peak frequency.
  var size = 1;
  while (size < centred.length) {
    size *= 2;
  }
  final real = List<double>.filled(size, 0.0);
  final imaginary = List<double>.filled(size, 0.0);
  for (var i = 0; i < centred.length; i++) {
    real[i] = centred[i];
  }

  _fftInPlace(real, imaginary);

  final binHz = sampleRateHz / size;
  var bandPower = 0.0;
  var totalPower = 0.0;
  // Only the first half of the spectrum: the second half mirrors it for a real
  // input and would double-count.
  for (var bin = 1; bin < size ~/ 2; bin++) {
    final power = real[bin] * real[bin] + imaginary[bin] * imaginary[bin];
    totalPower += power;
    final frequency = bin * binHz;
    if (frequency >= lowHz && frequency <= highHz) {
      bandPower += power;
    }
  }

  return totalPower <= 0 ? 0.0 : bandPower / totalPower;
}

/// In-place iterative radix-2 Cooley-Tukey FFT.
///
/// Written out rather than taken from a package because it is the only transform
/// the app needs, it runs on a few hundred points once per session, and a
/// dependency here would have to be audited for the same reason everything else
/// in the engine is: this code decides what a user is told.
void _fftInPlace(List<double> real, List<double> imaginary) {
  final n = real.length;
  if (n <= 1) return;

  // Bit-reversal permutation.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tempReal = real[i];
      real[i] = real[j];
      real[j] = tempReal;
      final tempImaginary = imaginary[i];
      imaginary[i] = imaginary[j];
      imaginary[j] = tempImaginary;
    }
  }

  // Butterflies, doubling the block length each pass.
  for (var length = 2; length <= n; length <<= 1) {
    final angle = -2 * math.pi / length;
    final wReal = math.cos(angle);
    final wImaginary = math.sin(angle);
    for (var start = 0; start < n; start += length) {
      var currentReal = 1.0;
      var currentImaginary = 0.0;
      for (var k = 0; k < length ~/ 2; k++) {
        final a = start + k;
        final b = a + length ~/ 2;

        final evenReal = real[a];
        final evenImaginary = imaginary[a];
        final oddReal = real[b] * currentReal - imaginary[b] * currentImaginary;
        final oddImaginary =
            real[b] * currentImaginary + imaginary[b] * currentReal;

        real[a] = evenReal + oddReal;
        imaginary[a] = evenImaginary + oddImaginary;
        real[b] = evenReal - oddReal;
        imaginary[b] = evenImaginary - oddImaginary;

        final nextReal = currentReal * wReal - currentImaginary * wImaginary;
        currentImaginary = currentReal * wImaginary + currentImaginary * wReal;
        currentReal = nextReal;
      }
    }
  }
}
