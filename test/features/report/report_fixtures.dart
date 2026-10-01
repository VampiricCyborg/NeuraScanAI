/// A stored history built with the real engine, for the results module's tests.
///
/// The records are what the app would have stored: a practice test, the baseline tests, then
/// full tests, scored by a real [ScreeningEngine] so every status, index and contribution is the
/// one the engine produces. The noise is seeded, so a fixture is the same every run.
library;

import 'dart:math' as math;

import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/engine/baseline.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';

import '../../engine/engine_test_support.dart';

/// A history and the engine that produced it.
class Fixture {
  Fixture({required this.sessions, required this.engine});

  /// Oldest first.
  final List<SessionRecord> sessions;

  final ScreeningEngine engine;

  Baseline get baseline => engine.baseline!;

  /// The full tests only.
  List<SessionRecord> get fullTests => [
    for (final s in sessions)
      if (s.status.isScored || s.status == ScreeningStatus.excludedContext) s,
  ];

  /// The scored full tests.
  List<SessionRecord> get counted => [
    for (final s in sessions)
      if (s.status.isScored) s,
  ];
}

/// The day the first test was taken.
final DateTime kFixtureStart = DateTime(2026, 1, 5, 9);

/// Builds a history with [fullTests] full tests after the baseline.
///
/// [setAside] are indexes (among the full tests) reported as tired on the check-in.
/// [declineSds] is how many of the user's own spreads each measurement worsens by per full
/// test, so a positive number gives a steady decline. [noiseSds] is the day-to-day noise.
/// [omit] are measurements left out of every full test, as typing is when nobody typed.
/// [jitterFor], if given, replaces the noise and the decline: it returns, for full test `i`,
/// each measurement's offset from nominal in units of its within-person spread.
Fixture buildFixture({
  Map<String, double> Function(int index)? jitterFor,
  int fullTests = 10,
  Set<int> setAside = const {},
  double declineSds = 0.0,
  double noiseSds = 0.6,
  Set<String> omit = const {},
  int seed = 7,
  int daysBetween = 2,
  DateTime? start,
  int epoch = 0,
}) {
  final random = math.Random(seed);
  final first = start ?? kFixtureStart;
  double gaussian() {
    final u = 1.0 - random.nextDouble();
    final v = random.nextDouble();
    return math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * v);
  }

  final engine = ScreeningEngine();
  final sessions = <SessionRecord>[];
  var clockIndex = 0;

  SessionRecord record(EngineSession session, {required bool confounded}) {
    final at = first.add(Duration(days: clockIndex * daysBetween));
    final id = 'fx-${clockIndex++}';
    final result = engine.update(session);
    return SessionRecord(
      id: id,
      userId: 'user-1',
      startedAt: at,
      completedAt: at.add(const Duration(minutes: 8)),
      checkIn: confounded
          ? CheckIn(
              sleep: SleepQuality.poor,
              fatigue: FatigueLevel.none,
              illnessOrMedicationChange: false,
              answeredAt: at,
            )
          : CheckIn.unremarkable(at),
      features: session.features,
      valid: true,
      status: result.status,
      index: result.index,
      ewma: result.ewma,
      run: result.run,
      domainScores: result.domains,
      contributions: result.contributions,
      epoch: epoch,
    );
  }

  // The practice test, then the baseline tests, with a little spread so the baseline has width.
  final baselineSessions = [
    if (kFamiliarisationSessions > 0)
      for (var i = 0; i < kFamiliarisationSessions; i++) makeSession(),
    ...variedBaselineSessions(),
  ];
  for (final session in baselineSessions) {
    sessions.add(record(session, confounded: false));
  }

  for (var i = 0; i < fullTests; i++) {
    final jitter = <String, double>{};
    for (final spec in kFeatureSpecs) {
      // A move in the bad direction for this measurement, plus noise.
      final worse = spec.direction == Direction.higherIsWorse ? 1.0 : -1.0;
      jitter[spec.key] = gaussian() * noiseSds + worse * declineSds * i;
    }
    if (jitterFor != null) {
      jitter
        ..updateAll((key, _) => 0.0)
        ..addAll(jitterFor(i));
    }
    final base = makeFullSession(jitter: jitter);
    final features = Map<String, double>.of(base.features)
      ..removeWhere((key, _) => omit.contains(key))
      // Counts and ratios stay in a sensible range whatever the noise did.
      ..['error_count'] = math.max(
        0,
        (base.features['error_count'] ?? 1).roundToDouble(),
      )
      ..['valid_word_count'] = math.max(
        0,
        (base.features['valid_word_count'] ?? 12).roundToDouble(),
      );
    if (omit.contains('error_count')) features.remove('error_count');
    if (omit.contains('valid_word_count')) features.remove('valid_word_count');

    final tired = setAside.contains(i);
    sessions.add(
      record(
        EngineSession(features: features, confounded: tired),
        confounded: tired,
      ),
    );
  }

  return Fixture(sessions: sessions, engine: engine);
}
