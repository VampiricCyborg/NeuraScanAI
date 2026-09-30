/// Motor feature extraction from the spiral trace.
///
/// The traces are synthesised: a perfect follow of the guide, the same with a
/// radial offset, and the same with a sinusoidal wobble at a known frequency. That
/// last one is what makes the tremor index testable at all -- a 6 Hz wobble must
/// land inside the band and a 1 Hz sway must not.
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/spiral_extractor.dart';

void main() {
  const guide = GuideSpiral(
    centre: (x: 180.0, y: 180.0),
    maxRadius: 150.0,
  );

  /// Samples the guide at [sampleRateHz] over [seconds], optionally adding a
  /// constant radial [offset] and a [wobbleHz] oscillation of [wobbleAmplitude].
  ///
  /// The trace starts at [startFraction] of the way along the guide rather than at
  /// the very centre. That is not a convenience: a displacement applied at the
  /// centre would drive the radius negative, which puts the point on the opposite
  /// side of the spiral. A finger cannot do that, so a fixture that did would be
  /// testing the extractor against input it will never see.
  List<TracePoint> traceGuide({
    double seconds = 6.0,
    double sampleRateHz = 100.0,
    double offset = 0.0,
    double wobbleHz = 0.0,
    double wobbleAmplitude = 0.0,
    double coverageFraction = 1.0,
    double startFraction = 0.15,
  }) {
    final count = (seconds * sampleRateHz).round();
    final totalAngle = guide.turns * 2 * math.pi;
    final points = <TracePoint>[];
    for (var i = 0; i < count; i++) {
      final progress = i / (count - 1);
      final theta =
          (startFraction + progress * (coverageFraction - startFraction)) *
              totalAngle;
      final t = i / sampleRateHz;

      var radius = guide.radiusAt(theta) + offset;
      if (wobbleHz > 0) {
        radius += wobbleAmplitude * math.sin(2 * math.pi * wobbleHz * t);
      }

      points.add(TracePoint(
        x: guide.centre.x + radius * math.cos(theta),
        y: guide.centre.y + radius * math.sin(theta),
        timestampMs: (t * 1000).round(),
      ));
    }
    return points;
  }

  group('the guide spiral', () {
    test('starts at the centre and ends at the maximum radius', () {
      expect(guide.radiusAt(0), 0.0);
      expect(guide.radiusAt(guide.turns * 2 * math.pi), closeTo(150.0, 1e-9));
    });

    test('turns are evenly spaced, so the task is equally hard throughout', () {
      final first = guide.radiusAt(2 * math.pi);
      final second = guide.radiusAt(4 * math.pi) - first;
      final third = guide.radiusAt(6 * math.pi) - guide.radiusAt(4 * math.pi);
      expect(second, closeTo(first, 1e-9));
      expect(third, closeTo(first, 1e-9));
    });

    test('a point on the guide is at the guide radius from the centre', () {
      final point = guide.pointAt(3.0);
      final dx = point.x - guide.centre.x;
      final dy = point.y - guide.centre.y;
      expect(math.sqrt(dx * dx + dy * dy), closeTo(guide.radiusAt(3.0), 1e-9));
    });

    test('angle unwrapping keeps a multi-turn trace monotonic', () {
      // atan2 wraps at pi, which would make a continuous trace look like it
      // jumped back several turns.
      var previous = 0.0;
      final unwrapped = <double>[];
      for (var i = 0; i < 200; i++) {
        final theta = i / 199 * guide.turns * 2 * math.pi;
        final radius = guide.radiusAt(theta);
        final point = TracePoint(
          x: guide.centre.x + radius * math.cos(theta),
          y: guide.centre.y + radius * math.sin(theta),
          timestampMs: i * 10,
        );
        previous = guide.unwrapAngle(point, previous);
        unwrapped.add(previous);
      }
      for (var i = 1; i < unwrapped.length; i++) {
        expect(unwrapped[i], greaterThanOrEqualTo(unwrapped[i - 1] - 1e-6));
      }
      expect(unwrapped.last, closeTo(guide.turns * 2 * math.pi, 0.2));
    });
  });

  group('RMS radial error', () {
    test('a perfect trace has almost no error', () {
      final result = extractSpiralFeatures(trace: traceGuide(), guide: guide);
      expect(result.rmse, lessThan(0.5));
    });

    test('a constant radial offset shows up as that offset', () {
      final result =
          extractSpiralFeatures(trace: traceGuide(offset: 8.0), guide: guide);
      expect(result.rmse, closeTo(8.0, 0.5));
    });

    test('a larger stray gives a larger error', () {
      final near =
          extractSpiralFeatures(trace: traceGuide(offset: 3.0), guide: guide);
      final far =
          extractSpiralFeatures(trace: traceGuide(offset: 15.0), guide: guide);
      expect(far.rmse, greaterThan(near.rmse));
    });

    test('the error is a magnitude, so an inward stray counts like an outward one',
        () {
      final inward =
          extractSpiralFeatures(trace: traceGuide(offset: -9.0), guide: guide);
      final outward =
          extractSpiralFeatures(trace: traceGuide(offset: 9.0), guide: guide);
      expect(inward.rmse, closeTo(outward.rmse, 0.6));
    });
  });

  group('tremor index', () {
    test('a smooth trace has almost no power in the tremor band', () {
      final result = extractSpiralFeatures(trace: traceGuide(), guide: guide);
      expect(result.tremorIndex, lessThan(0.25));
    });

    test('a 6 Hz wobble lands inside the band', () {
      final result = extractSpiralFeatures(
        trace: traceGuide(wobbleHz: 6.0, wobbleAmplitude: 5.0),
        guide: guide,
      );
      expect(result.tremorIndex, greaterThan(0.6));
    });

    test('a 1 Hz sway does not, being deliberate movement rather than tremor', () {
      final result = extractSpiralFeatures(
        trace: traceGuide(wobbleHz: 1.0, wobbleAmplitude: 5.0),
        guide: guide,
      );
      expect(result.tremorIndex, lessThan(0.3));
    });

    test('a wobble at the top of the band still counts', () {
      final result = extractSpiralFeatures(
        trace: traceGuide(wobbleHz: 11.0, wobbleAmplitude: 5.0),
        guide: guide,
      );
      expect(result.tremorIndex, greaterThan(0.5));
    });

    test('a wobble above the band does not', () {
      final result = extractSpiralFeatures(
        trace: traceGuide(wobbleHz: 20.0, wobbleAmplitude: 5.0),
        guide: guide,
      );
      expect(result.tremorIndex, lessThan(0.3));
    });

    test('it is a share, so wobble amplitude barely changes it', () {
      // The index says how much of the error is oscillation, not how big the
      // error is. That separation is the point: RMSE already measures size.
      final small = extractSpiralFeatures(
        trace: traceGuide(wobbleHz: 6.0, wobbleAmplitude: 2.0),
        guide: guide,
      );
      final large = extractSpiralFeatures(
        trace: traceGuide(wobbleHz: 6.0, wobbleAmplitude: 12.0),
        guide: guide,
      );
      expect(large.tremorIndex, closeTo(small.tremorIndex, 0.25));
    });

    test('a constant offset is not mistaken for tremor', () {
      // The mean is removed before the transform, so a trace drawn simply too
      // large does not put all its power at DC and dilute the band share.
      final result =
          extractSpiralFeatures(trace: traceGuide(offset: 20.0), guide: guide);
      expect(result.tremorIndex, lessThan(0.3));
    });

    test('the index stays within zero and one', () {
      for (final hz in [0.0, 1.0, 6.0, 11.0, 25.0]) {
        final result = extractSpiralFeatures(
          trace: traceGuide(wobbleHz: hz, wobbleAmplitude: 4.0),
          guide: guide,
        );
        expect(result.tremorIndex, inInclusiveRange(0.0, 1.0));
      }
    });

    test('an uneven touch sample rate still finds the wobble', () {
      // Real touch events are neither evenly spaced nor at a consistent rate, so
      // the series is resampled before the transform.
      final result = extractSpiralFeatures(
        trace: traceGuide(wobbleHz: 6.0, wobbleAmplitude: 5.0, sampleRateHz: 63.0),
        guide: guide,
      );
      expect(result.tremorIndex, greaterThan(0.5));
    });
  });

  group('coverage', () {
    test('a trace along the whole guide covers nearly all of it', () {
      // The fixture starts 15 % along, so the innermost bins are never visited.
      final result = extractSpiralFeatures(
        trace: traceGuide(startFraction: 0.0, offset: 4.0),
        guide: guide,
      );
      expect(result.coverage, greaterThan(0.95));
    });

    test('stopping half way covers about half', () {
      final result = extractSpiralFeatures(
        trace: traceGuide(startFraction: 0.0, coverageFraction: 0.5, offset: 4.0),
        guide: guide,
      );
      expect(result.coverage, closeTo(0.5, 0.08));
    });

    test('scribbling far from the guide covers nothing', () {
      // Coverage is judged over the guide, not over the trace, so a dense scribble
      // in one place cannot pass the gate.
      final result = extractSpiralFeatures(
        trace: traceGuide(offset: 90.0),
        guide: guide,
      );
      expect(result.coverage, lessThan(0.1));
    });

    test('a trace below the gate is reported as such', () {
      final result = extractSpiralFeatures(
        trace: traceGuide(startFraction: 0.0, coverageFraction: 0.4, offset: 4.0),
        guide: guide,
      );
      expect(result.coverage, lessThan(0.70));
    });
  });

  group('degenerate input', () {
    test('an empty trace yields zeroed features', () {
      final result = extractSpiralFeatures(trace: const [], guide: guide);
      expect(result.rmse, 0.0);
      expect(result.tremorIndex, 0.0);
      expect(result.coverage, 0.0);
      expect(result.sampleCount, 0);
    });

    test('a two-point trace yields zeroed features', () {
      final result = extractSpiralFeatures(
        trace: const [
          TracePoint(x: 180, y: 180, timestampMs: 0),
          TracePoint(x: 185, y: 185, timestampMs: 10),
        ],
        guide: guide,
      );
      expect(result.sampleCount, 0);
    });

    test('coincident timestamps do not divide by zero', () {
      // Two touch events can share a millisecond.
      final trace = [
        for (var i = 0; i < 40; i++)
          TracePoint(
            x: 180.0 + i,
            y: 180.0 + i,
            timestampMs: (i ~/ 2) * 10,
          ),
      ];
      final result = extractSpiralFeatures(trace: trace, guide: guide);
      expect(result.rmse.isFinite, isTrue);
      expect(result.tremorIndex.isFinite, isTrue);
    });

    test('a trace too short in time to resample yields a zero tremor index', () {
      final trace = [
        for (var i = 0; i < 20; i++)
          TracePoint(x: 180.0 + i, y: 180.0, timestampMs: i)
      ];
      final result = extractSpiralFeatures(trace: trace, guide: guide);
      expect(result.tremorIndex, 0.0);
      expect(result.rmse.isFinite, isTrue);
    });
  });
}
