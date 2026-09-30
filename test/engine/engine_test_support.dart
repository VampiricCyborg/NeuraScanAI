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

/// Nominal feature values for an average user having an average day.
///
/// Tests perturb individual features away from these to create a targeted
/// deviation.
const Map<String, double> kNominal = {
  'delayed_recall': 0.75,
  'reaction_median': 320.0,
  'reaction_cv': 0.15,
  'speaking_rate': 140.0,
  'pause_ratio': 0.22,
  'spiral_rmse': 6.0,
  'tremor_index': 0.10,
  'inter_key_interval': 260.0,
  'inter_key_cv': 0.35,
};

/// Within-person day-to-day spread of each feature, from Table A.2 of the
/// report. Used to express a perturbation in units the engine will recognise.
const Map<String, double> kWithinSd = {
  'delayed_recall': 0.06,
  'reaction_median': 18.0,
  'reaction_cv': 0.02,
  'speaking_rate': 8.0,
  'pause_ratio': 0.025,
  'spiral_rmse': 0.6,
  'tremor_index': 0.012,
  'inter_key_interval': 15.0,
  'inter_key_cv': 0.035,
};

/// A deviation large enough to push the index above the threshold on its own.
const Map<String, double> kSevere = {
  'delayed_recall': -9.0,
  'reaction_median': 9.0,
  'reaction_cv': 9.0,
  'speaking_rate': -9.0,
  'pause_ratio': 9.0,
  'spiral_rmse': 9.0,
  'tremor_index': 9.0,
  'inter_key_interval': 9.0,
  'inter_key_cv': 9.0,
};

/// Builds a session from the nominal values.
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
}) {
  final features = Map<String, double>.of(kNominal);
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

/// Sessions that differ slightly, so every feature has a non-zero spread.
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
          for (final key in kWithinSd.keys) key: offsets[i % offsets.length],
        },
      ),
  ];
}

/// Drives [engine] through familiarisation and baseline building.
///
/// Sends two familiarisation sessions first, because the engine discards that
/// many before it starts pooling, then the baseline sessions themselves.
void feedBaseline(ScreeningEngine engine, [List<EngineSession>? sessions]) {
  engine.update(makeSession(sessionId: 'familiarisation-1'));
  engine.update(makeSession(sessionId: 'familiarisation-2'));
  for (final session in sessions ?? variedBaselineSessions()) {
    engine.update(session);
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
