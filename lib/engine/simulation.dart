/// Illustrative trends, built from a user's own baseline.
///
/// After the baseline is set the user has no results yet, and a screen of numbers they have
/// never seen is hard to trust. This produces two made-up runs of tests -- a steady pattern
/// and a gradual change -- scored by the *real* engine against the user's *real* baseline, so
/// they can see what the measurements do before they have any of their own.
///
/// Everything here is invented and must be presented as such. It never reads a stored
/// session, never touches the engine that holds the user's state, and is deterministic: the
/// same baseline and seed always give the same picture, so the example does not change every
/// time the screen is opened and a test can pin what it shows.
library;

import 'dart:math' as math;

import 'baseline.dart';
import 'constants.dart';
import 'features.dart';
import 'screening_engine.dart';

/// The two pictures the example shows.
enum SimulationScenario {
  /// Ordinary day-to-day variation around the baseline, and nothing else.
  steady,

  /// A drift for the worse that begins after a few tests and keeps growing.
  gradualChange,
}

/// One simulated test and what the engine made of it.
class SimulatedPoint {
  const SimulatedPoint({
    required this.test,
    required this.index,
    required this.ewma,
    required this.status,
    required this.run,
    required this.domains,
  });

  /// One-based position in the run.
  final int test;

  /// Raw weighted deviation for this test.
  final double index;

  /// Smoothed deviation, which is what the status is judged on.
  final double ewma;

  final ScreeningStatus status;

  /// Consecutive tests at or above the threshold, including this one.
  final int run;

  /// Oriented per-area scores. Negative means better than the baseline.
  final Map<Domain, double> domains;
}

/// A simulated run.
class SimulatedTrend {
  const SimulatedTrend({required this.scenario, required this.points});

  final SimulationScenario scenario;
  final List<SimulatedPoint> points;

  /// The first test at which a notable change would have been reported, or null.
  int? get notableAt {
    for (final point in points) {
      if (point.status == ScreeningStatus.notableDeviation) return point.test;
    }
    return null;
  }

  double get finalEwma => points.isEmpty ? 0.0 : points.last.ewma;
}

/// Tests in a simulated run. Long enough for a change to build and be reported.
const int kSimulatedTests = 24;

/// The test after which the gradual change begins.
const int kSimulatedOnset = 6;

/// The seed the app uses, chosen so both pictures show what they are meant to.
///
/// A steady run drawn at random can wander over the line by chance -- that is exactly the
/// false-alert rate the report discusses -- and an example that did so would teach the wrong
/// lesson. The tests pin that this seed gives a clean steady run and a change that is caught.
const int kExampleSeed = 12;

/// The size of the change, in the user's own units of spread, by the end of the run, per
/// area. Cognitive changes most and speech follows more gently, as in the report: a change
/// in thinking tends to show up in speech too. Movement is left alone.
const Map<Domain, double> kSimulatedChangeSds = {
  Domain.cognitive: 3.0,
  Domain.speech: 1.5,
};

/// Runs [scenario] against [baseline] and scores it with the real engine.
///
/// Each feature is drawn around the baseline's own median with the baseline's own spread, so
/// a steady run looks like ordinary days *for this person*: a slow, steady mover and a quick,
/// variable one get different pictures from different baselines, which is the point of a
/// personal baseline.
SimulatedTrend simulateTrend({
  required Baseline baseline,
  required SimulationScenario scenario,
  int tests = kSimulatedTests,
  int seed = kExampleSeed,
}) {
  final random = math.Random(seed);
  // A fresh engine seeded with the baseline. It is not the user's engine and shares no state
  // with it.
  final engine = ScreeningEngine(baseline: baseline);
  final points = <SimulatedPoint>[];

  for (var i = 0; i < tests; i++) {
    final progress = scenario == SimulationScenario.gradualChange
        ? ((i - kSimulatedOnset + 1) / (tests - kSimulatedOnset)).clamp(
            0.0,
            1.0,
          )
        : 0.0;

    final features = <String, double>{};
    for (final spec in kFeatureSpecs) {
      // A measurement still calibrating has no baseline to simulate around.
      final centre = baseline.median[spec.key];
      if (centre == null) continue;
      final spread = baseline.scale[spec.key]!;
      var value = centre + _gaussian(random) * spread;

      final change = kSimulatedChangeSds[spec.domain];
      if (change != null && progress > 0) {
        // Pushed in the direction that is worse for this feature.
        final worse = spec.direction == Direction.higherIsWorse ? 1.0 : -1.0;
        value += worse * spread * change * progress;
      }
      features[spec.key] = value;
    }

    final result = engine.update(EngineSession(features: features));
    points.add(
      SimulatedPoint(
        test: i + 1,
        index: result.index ?? 0.0,
        ewma: result.ewma ?? 0.0,
        status: result.status,
        run: result.run ?? 0,
        domains: result.domains ?? const {},
      ),
    );
  }

  return SimulatedTrend(scenario: scenario, points: points);
}

/// A standard normal draw (Box-Muller).
double _gaussian(math.Random random) {
  // 1 - nextDouble() is in (0, 1], so the log never sees zero.
  final u = 1.0 - random.nextDouble();
  final v = random.nextDouble();
  return math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
}

/// The threshold and persistence the simulated charts are judged against, exposed so the
/// screen draws the same line the engine used.
const double kSimulatedThreshold = kDefaultThreshold;
const int kSimulatedPersistence = kDefaultPersistence;
