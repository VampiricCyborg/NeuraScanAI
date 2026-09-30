/// The example trends shown before the user has results of their own.
///
/// They are invented, so the tests are about honesty as much as behaviour: they must be
/// deterministic, built from the user's own baseline, and never able to reach real data.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';
import 'package:neurascan_ai/engine/simulation.dart';

import 'engine_test_support.dart';

void main() {
  late Baseline baseline;

  setUp(() => baseline = Baseline.fit(variedBaselineSessions()));

  SimulatedTrend run(
    SimulationScenario scenario, {
    Baseline? using,
    int seed = kExampleSeed,
    int tests = kSimulatedTests,
  }) => simulateTrend(
    baseline: using ?? baseline,
    scenario: scenario,
    seed: seed,
    tests: tests,
  );

  group('what the example is meant to show', () {
    test('the steady pattern is never reported as a notable change', () {
      // A steady run that crossed the line would teach the wrong lesson.
      final steady = run(SimulationScenario.steady);
      expect(steady.notableAt, isNull);
      expect(steady.points.every((p) => p.ewma < kSimulatedThreshold), isTrue);
    });

    test('the gradual change is caught before the run ends', () {
      final change = run(SimulationScenario.gradualChange);
      expect(change.notableAt, isNotNull);
      expect(change.notableAt, lessThanOrEqualTo(kSimulatedTests));
    });

    test('and only after it has actually begun', () {
      final change = run(SimulationScenario.gradualChange);
      expect(change.notableAt, greaterThan(kSimulatedOnset));
    });

    test('the change ends well above the steady run', () {
      final steady = run(SimulationScenario.steady);
      final change = run(SimulationScenario.gradualChange);
      expect(change.finalEwma, greaterThan(steady.finalEwma + 0.5));
    });

    test('a notable change needs the persistence rule, not one bad test', () {
      final change = run(SimulationScenario.gradualChange);
      final at = change.notableAt!;
      expect(
        change.points[at - 1].run,
        greaterThanOrEqualTo(kSimulatedPersistence),
      );
    });

    test('the change shows up in thinking first and most', () {
      final change = run(SimulationScenario.gradualChange);
      final last = change.points.last.domains;
      expect(last[Domain.cognitive]!, greaterThan(last[Domain.motor]!));
      expect(last[Domain.cognitive]!, greaterThan(last[Domain.speech]!));
    });

    test('the untouched area stays near the baseline', () {
      // Movement is not part of the simulated change.
      final change = run(SimulationScenario.gradualChange);
      final motor = change.points.map((p) => p.domains[Domain.motor]!);
      expect(motor.every((score) => score.abs() < 2.5), isTrue);
    });
  });

  group('determinism', () {
    test('the same baseline and seed give the same picture', () {
      final a = run(SimulationScenario.gradualChange);
      final b = run(SimulationScenario.gradualChange);
      expect(
        [for (final p in a.points) p.ewma],
        [for (final p in b.points) p.ewma],
      );
    });

    test('a different seed gives a different picture', () {
      final a = run(SimulationScenario.steady);
      final b = run(SimulationScenario.steady, seed: kExampleSeed + 1);
      expect([
        for (final p in a.points) p.ewma,
      ], isNot([for (final p in b.points) p.ewma]));
    });

    test('the two scenarios are drawn from the same random noise', () {
      // Before the change begins they must look the same, so the eye can see where they part.
      final steady = run(SimulationScenario.steady);
      final change = run(SimulationScenario.gradualChange);
      for (var i = 0; i < kSimulatedOnset - 1; i++) {
        expect(change.points[i].ewma, closeTo(steady.points[i].ewma, 1e-9));
      }
    });
  });

  group('it is built from the user\'s own baseline', () {
    test('a different baseline gives a different picture', () {
      final slower = Baseline.fit([
        for (var i = 0; i < kBaselineSessions; i++)
          makeSession(
            sessionId: '$i',
            overrides: {'speaking_rate': 100.0 - i * 10},
          ),
      ]);
      final mine = run(SimulationScenario.steady);
      final theirs = run(SimulationScenario.steady, using: slower);
      expect([
        for (final p in mine.points) p.ewma,
      ], isNot([for (final p in theirs.points) p.ewma]));
    });

    test('a steady run stays inside this person\'s own spread', () {
      // Scored against the baseline it came from, ordinary days read as ordinary.
      final steady = run(SimulationScenario.steady);
      for (final point in steady.points) {
        for (final score in point.domains.values) {
          expect(score.abs(), lessThan(3.0));
        }
      }
    });

    test('every test has all four areas scored', () {
      for (final point in run(SimulationScenario.steady).points) {
        expect(point.domains.keys.toSet(), Domain.values.toSet());
      }
    });
  });

  group('it cannot touch anything real', () {
    test('it does not alter the baseline it is given', () {
      final medianBefore = Map<String, double>.of(baseline.median);
      final scaleBefore = Map<String, double>.of(baseline.scale);
      run(SimulationScenario.gradualChange);
      expect(baseline.median, medianBefore);
      expect(baseline.scale, scaleBefore);
    });

    test('it runs on its own engine, leaving the caller\'s untouched', () {
      final users = ScreeningEngine(baseline: baseline);
      run(SimulationScenario.gradualChange);
      expect(users.ewma, 0.0);
      expect(users.run, 0);
      expect(users.sessionsSeen, 0);
    });

    test(
      'every point is a scored result, never a baseline or excluded one',
      () {
        for (final point in run(SimulationScenario.gradualChange).points) {
          expect(point.status.isScored, isTrue);
        }
      },
    );
  });

  group('shape', () {
    test('the run has the requested number of tests, numbered from one', () {
      final trend = run(SimulationScenario.steady, tests: 10);
      expect(trend.points, hasLength(10));
      expect(
        [for (final p in trend.points) p.test],
        [for (var i = 1; i <= 10; i++) i],
      );
    });

    test('a run of zero tests is empty rather than an error', () {
      final trend = run(SimulationScenario.steady, tests: 0);
      expect(trend.points, isEmpty);
      expect(trend.notableAt, isNull);
      expect(trend.finalEwma, 0.0);
    });

    test('every value is finite', () {
      for (final scenario in SimulationScenario.values) {
        for (final point in run(scenario).points) {
          expect(point.ewma.isFinite, isTrue);
          expect(point.index.isFinite, isTrue);
        }
      }
    });
  });
}
