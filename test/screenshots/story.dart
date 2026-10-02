/// A plausible history to photograph.
///
/// `test/app/seed_history.dart` seeds identical sessions, which is what an assertion
/// wants and the worst possible thing to photograph: every chart is a flat line and
/// every measurement sits exactly on its baseline. These are the same records, with
/// the day-to-day variation a real person has.
///
/// Nothing here is data about anyone. It is the engine's own nominal values with a
/// pseudo-random wobble, which is how the simulation in `lib/engine/simulation.dart`
/// makes a cohort too.
library;

import 'dart:math' as math;

import 'package:neurascan_ai/engine/constants.dart';

import '../app/seed_history.dart';
import '../engine/engine_test_support.dart';

/// How a person's measurements move over a run of tests.
enum Story {
  /// Ordinary variation, never far from the baseline.
  steady,

  /// Thinking and movement drifting slowly worse, far enough and for long enough
  /// that the engine reports it.
  drifting,
}

/// A standard normal draw, from two uniforms.
double _gauss(math.Random rng) {
  final u = 1.0 - rng.nextDouble();
  final v = rng.nextDouble();
  return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * v);
}

/// Which way is worse for each measurement that carries the drift.
///
/// Remembering fewer words is worse; taking longer, wobbling more and tapping less
/// evenly are worse the other way up. Drifting the wrong way would quietly produce a
/// story of someone getting better.
const Map<String, double> _worse = {
  'delayed_recall': -1.0,
  'immediate_recall': -1.0,
  'reaction_median': 1.0,
  'reaction_cv': 1.0,
  'completion_time': 1.0,
  'switch_cost': 1.0,
  'spiral_rmse': 1.0,
  'tremor_index': 1.0,
  'tap_interval_cv': 1.0,
};

/// A history of [full] full tests, with the practice run and the baseline before them.
///
/// [setAside] names full tests (counting from zero) the user reported sleeping badly
/// for, which the app stores and keeps out of every average.
List<SeededTest> storyHistory({
  int full = 10,
  Story story = Story.steady,
  Set<int> setAside = const {},
  int seed = 6,
}) {
  final rng = math.Random(seed);
  return [
    for (var i = 0; i < kFamiliarisationSessions; i++)
      (session: makeSession(), setAside: false),
    for (final session in variedBaselineSessions())
      (session: session, setAside: false),
    for (var i = 0; i < full; i++)
      (
        session: makeFullSession(
          sessionId: 'full-$i',
          confounded: setAside.contains(i),
          jitter: {
            for (final key in kWithinSd.keys)
              key:
                  0.55 * _gauss(rng) +
                  (story == Story.drifting && i >= 3
                      ? (_worse[key] ?? 0.0) * 0.62 * (i - 2)
                      : 0.0),
          },
        ),
        setAside: setAside.contains(i),
      ),
  ];
}
