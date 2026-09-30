/// A stored history of tests, for widget tests that start part-way through a user's journey.
///
/// Driving the whole baseline through the screens would make every test minutes long. This
/// stores the same records the app would have, using a real engine so the stored statuses are
/// the ones it would have produced, and lets the test start from there.
library;

import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart' show EngineSession;
import 'package:neurascan_ai/engine/screening_engine.dart';

import '../engine/engine_test_support.dart';
import 'test_harness.dart';

/// One test in a seeded history.
typedef SeededTest = ({EngineSession session, bool setAside});

/// Tests that make up a user's history, in order: the practice test, the baseline, then
/// [actual] full tests. Entries in [setAside] are reported as tired on the check-in.
List<SeededTest> history({required int actual, Set<int> setAside = const {}}) =>
    [
      for (var i = 0; i < kFamiliarisationSessions; i++)
        (session: makeSession(), setAside: false),
      for (final s in variedBaselineSessions()) (session: s, setAside: false),
      for (var i = 0; i < actual; i++)
        (
          session: makeSession(confounded: setAside.contains(i)),
          setAside: setAside.contains(i),
        ),
    ];

/// Stores [plan] for the signed-in user.
///
/// Ids are `seed-0`, `seed-1` and so on, oldest first.
Future<void> seed(TestApp app, List<SeededTest> plan) async {
  final engine = ScreeningEngine();
  for (var i = 0; i < plan.length; i++) {
    final at = DateTime.now().subtract(Duration(days: (plan.length - i) * 2));
    final result = engine.update(plan[i].session);
    await app.repository.saveSession(
      session: SessionRecord(
        id: 'seed-$i',
        userId: 'user-1',
        startedAt: at,
        completedAt: at.add(const Duration(minutes: 4)),
        checkIn: plan[i].setAside
            ? CheckIn(
                sleep: SleepQuality.poor,
                fatigue: FatigueLevel.none,
                illnessOrMedicationChange: false,
                answeredAt: at,
              )
            : CheckIn.unremarkable(at),
        features: plan[i].session.features,
        valid: true,
        status: result.status,
        index: result.index,
        ewma: result.ewma,
        run: result.run,
        domainScores: result.domains,
        contributions: result.contributions,
      ),
      engine: engine,
    );
  }
}
