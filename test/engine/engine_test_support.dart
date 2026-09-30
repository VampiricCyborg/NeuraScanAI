/// Shared helpers for the screening-engine tests.
///
/// The helpers here build sessions from the same nominal feature values used as
/// the population means in the report's simulation parameters, so a "typical"
/// session in these tests looks like a typical session in the evaluation. Mirrors
/// `engine_lab/tests/conftest.py`.
library;

import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';

/// Nominal core feature values for an average user having an average day.
///
/// Tests perturb individual features away from these to create a targeted deviation.
const Map<String, double> kNominalCore = {
  'delayed_recall': 0.75,
  'speaking_rate': 140.0,
  'pause_ratio': 0.22,
  'spiral_rmse': 6.0,
  'tremor_index': 0.10,
};

/// Nominal values for the features only a full test measures.
///
/// Illustrative figures for an unimpaired adult, used to exercise the engine; they are not
/// population norms and are not used by the app.
const Map<String, double> kNominalExtended = {
  'immediate_recall': 0.85,
  'reaction_median': 320.0,
  'reaction_cv': 0.15,
  'inter_key_interval': 260.0,
  'inter_key_cv': 0.35,
  'completion_time': 11.0,
  'error_count': 1.0,
  'switch_cost': 0.35,
  'tap_rate': 4.5,
  'tap_interval_cv': 0.10,
  'fatigue_decay': 0.08,
  'valid_word_count': 16.0,
  'fluency_half_ratio': 0.8,
};

/// Every feature's nominal value.
const Map<String, double> kNominal = {...kNominalCore, ...kNominalExtended};

/// Within-person day-to-day spread of each feature. The core ones and the first reaction and
/// typing figures are from Table A.2 of the report; the rest are the provisional estimates in
/// `features.dart`. Used to express a perturbation in units the engine will recognise.
const Map<String, double> kWithinSd = {
  'delayed_recall': 0.06,
  'speaking_rate': 8.0,
  'pause_ratio': 0.025,
  'spiral_rmse': 0.6,
  'tremor_index': 0.012,
  'immediate_recall': 0.05,
  'reaction_median': 18.0,
  'reaction_cv': 0.02,
  'inter_key_interval': 15.0,
  'inter_key_cv': 0.035,
  'completion_time': 1.5,
  'error_count': 0.8,
  'switch_cost': 0.15,
  'tap_rate': 0.25,
  'tap_interval_cv': 0.04,
  'fatigue_decay': 0.05,
  'valid_word_count': 2.0,
  'fluency_half_ratio': 0.15,
};

/// A deviation large enough to push the index above the threshold on its own.
const Map<String, double> kSevere = {
  'delayed_recall': -9.0,
  'speaking_rate': -9.0,
  'pause_ratio': 9.0,
  'spiral_rmse': 9.0,
  'tremor_index': 9.0,
};

/// Builds a session from the nominal values.
///
/// By default this is a *baseline-style* session with the five core features; pass
/// `full: true` for a full test with all eighteen.
///
/// [overrides] sets a feature to an absolute value; [jitter] nudges a feature by
/// a number of within-person SDs, which is usually the more readable way to say
/// "this user is a bit slower today".
EngineSession makeSession({
  bool valid = true,
  bool confounded = false,
  String? sessionId,
  Map<String, double>? jitter,
  Map<String, double>? overrides,
  bool full = false,
}) {
  final features = Map<String, double>.of(full ? kNominal : kNominalCore);
  if (jitter != null) {
    jitter.forEach((key, sds) {
      features[key] = features[key]! + sds * kWithinSd[key]!;
    });
  }
  if (overrides != null) {
    features.addAll(overrides);
  }
  return EngineSession(
    features: features,
    valid: valid,
    confounded: confounded,
    sessionId: sessionId,
  );
}

/// A full test: every feature, at its nominal value unless changed.
EngineSession makeFullSession({
  bool valid = true,
  bool confounded = false,
  String? sessionId,
  Map<String, double>? jitter,
  Map<String, double>? overrides,
}) => makeSession(
  valid: valid,
  confounded: confounded,
  sessionId: sessionId,
  jitter: jitter,
  overrides: overrides,
  full: true,
);

/// Full tests that differ slightly, for calibrating the extended features.
///
/// Offsets follow [variedBaselineSessions], so the first three are symmetric about zero and
/// the calibrated centre is the nominal value.
List<EngineSession> variedFullSessions(int count) {
  const offsets = [-1.0, 1.0, 0.0, 0.5, -0.5, 0.25, -0.25, 0.75, -0.75, 1.25];
  return [
    for (var i = 0; i < count; i++)
      makeFullSession(
        sessionId: 'full-${i + 1}',
        jitter: {
          for (final key in kWithinSd.keys) key: offsets[i % offsets.length],
        },
      ),
  ];
}

/// Baseline-style sessions that differ slightly, so every feature has a non-zero spread.
///
/// A baseline fitted from identical sessions would have a MAD of zero on every
/// feature and rely entirely on the scale floor, which is not what most tests
/// want to exercise.
///
/// The default is exactly the number the engine pools. A larger default would leave the
/// extra sessions to be *scored* after the baseline froze, quietly giving every test an
/// engine with history and a non-zero EWMA.
///
/// The first three offsets are symmetric about zero, so the baseline centre is the nominal
/// value whatever the pool size -- a typical session then reads as typical rather than as
/// slightly off.
List<EngineSession> variedBaselineSessions([int count = kBaselineSessions]) {
  const offsets = [-1.0, 1.0, 0.0, 0.5, -0.5, 0.25, -0.25, 0.75, -0.75, 1.25];
  return [
    for (var i = 0; i < count; i++)
      makeSession(
        sessionId: 'baseline-${i + 1}',
        jitter: {
          for (final key in kCoreFeatureKeys) key: offsets[i % offsets.length],
        },
      ),
  ];
}

/// Drives [engine] through familiarisation and baseline building.
///
/// Sends the practice run first, because the engine discards that many tests before it
/// starts pooling, then the baseline tests themselves.
void feedBaseline(ScreeningEngine engine, [List<EngineSession>? sessions]) {
  for (var i = 0; i < kFamiliarisationSessions; i++) {
    engine.update(makeSession(sessionId: 'familiarisation-${i + 1}'));
  }
  for (final session in sessions ?? variedBaselineSessions()) {
    engine.update(session);
  }
}

/// Sends the practice run alone, for tests that go on to build a baseline themselves.
///
/// [overrides] lets a test make the practice run unlike the tests that follow, to show
/// that it is discarded.
void practise(ScreeningEngine engine, {Map<String, double>? overrides}) {
  for (var i = 0; i < kFamiliarisationSessions; i++) {
    engine.update(makeSession(overrides: overrides));
  }
}

/// An engine with a frozen baseline, ready to score.
ScreeningEngine readyEngine({
  bool useContext = true,
  bool useEwma = true,
  int persistence = 3,
}) {
  final engine = ScreeningEngine(
    useContext: useContext,
    useEwma: useEwma,
    persistence: persistence,
  );
  feedBaseline(engine);
  return engine;
}

/// Every feature key, for iterating in tests.
Iterable<String> get allFeatureKeys => kFeatureKeys;
