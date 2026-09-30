/// The nine behavioural features and the four domains that group them.
///
/// A feature is described by three things: which domain it belongs to, which
/// direction counts as worse, and what it is called. Keeping that description
/// in one place means the scoring code never has to special-case a feature, and
/// adding a tenth feature is a one-line change here plus a weight review.
///
/// Mirrors `engine_lab/neurascan_engine/features.py`.
library;

/// The four behavioural domains fused into a single deviation index.
enum Domain {
  cognitive('cognitive', 'Cognitive'),
  speech('speech', 'Speech'),
  motor('motor', 'Motor'),
  interaction('interaction', 'Interaction');

  const Domain(this.key, this.label);

  /// Stable identifier used in the database and in synced documents.
  final String key;

  /// Human-readable name shown on the report and trend screens.
  final String label;

  static Domain fromKey(String key) =>
      Domain.values.firstWhere((domain) => domain.key == key);
}

/// Weight of each domain in the deviation index.
///
/// Cognition carries the most weight because delayed recall is the
/// best-established early signal in the literature; interaction carries the
/// least because passive typing is the noisiest and the most confounded by what
/// the user happens to be typing.
const Map<Domain, double> kDomainWeights = {
  Domain.cognitive: 0.35,
  Domain.speech: 0.25,
  Domain.motor: 0.25,
  Domain.interaction: 0.15,
};

/// Which way a feature moves when the user is doing worse.
enum Direction {
  /// Worse when the value rises, e.g. reaction time.
  higherIsWorse,

  /// Worse when the value falls, e.g. words recalled.
  lowerIsWorse,
}

/// Static description of one behavioural feature.
class FeatureSpec {
  const FeatureSpec({
    required this.key,
    required this.domain,
    required this.direction,
    required this.label,
    this.unit = '',
  });

  final String key;
  final Domain domain;
  final Direction direction;
  final String label;
  final String unit;

  /// Flips [z] if needed so that a positive result always means worse.
  ///
  /// The rest of the engine relies on this: once a z-score is oriented,
  /// `max(0, z)` is exactly "the part of the change that is a decline", with no
  /// per-feature knowledge required.
  double orient(double z) => direction == Direction.higherIsWorse ? z : -z;
}

/// The nine features, in the order they appear in the project report.
const List<FeatureSpec> kFeatureSpecs = [
  FeatureSpec(
    key: 'delayed_recall',
    domain: Domain.cognitive,
    direction: Direction.lowerIsWorse,
    label: 'Delayed recall',
    unit: 'fraction',
  ),
  FeatureSpec(
    key: 'reaction_median',
    domain: Domain.cognitive,
    direction: Direction.higherIsWorse,
    label: 'Reaction median',
    unit: 'ms',
  ),
  FeatureSpec(
    key: 'reaction_cv',
    domain: Domain.cognitive,
    direction: Direction.higherIsWorse,
    label: 'Reaction variability',
  ),
  FeatureSpec(
    key: 'speaking_rate',
    domain: Domain.speech,
    direction: Direction.lowerIsWorse,
    label: 'Speaking rate',
    unit: 'syllables/min',
  ),
  FeatureSpec(
    key: 'pause_ratio',
    domain: Domain.speech,
    direction: Direction.higherIsWorse,
    label: 'Pause ratio',
  ),
  FeatureSpec(
    key: 'spiral_rmse',
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Spiral tracing error',
    unit: 'dp',
  ),
  FeatureSpec(
    key: 'tremor_index',
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Tremor index',
  ),
  FeatureSpec(
    key: 'inter_key_interval',
    domain: Domain.interaction,
    direction: Direction.higherIsWorse,
    label: 'Inter-key interval',
    unit: 'ms',
  ),
  FeatureSpec(
    key: 'inter_key_cv',
    domain: Domain.interaction,
    direction: Direction.higherIsWorse,
    label: 'Inter-key variability',
  ),
];

/// Lookup by feature key.
final Map<String, FeatureSpec> kSpecByKey = {
  for (final spec in kFeatureSpecs) spec.key: spec,
};

/// Feature keys, in report order.
final List<String> kFeatureKeys = [for (final spec in kFeatureSpecs) spec.key];

/// The features belonging to [domain], in report order.
List<FeatureSpec> specsFor(Domain domain) => kFeatureSpecs
    .where((spec) => spec.domain == domain)
    .toList(growable: false);

/// One screening session as the engine sees it.
///
/// The engine deals only in extracted features. Raw touch coordinates, audio
/// and keystroke timings never reach it -- they are reduced to these nine
/// numbers on the device and then discarded, which is what lets the app claim
/// that raw signals never leave the phone.
class EngineSession {
  const EngineSession({
    required this.features,
    this.valid = true,
    this.confounded = false,
    this.sessionId,
  });

  /// Feature key to value. Missing keys make the session unusable.
  final Map<String, double> features;

  /// False when a quality gate rejected one of the tasks.
  final bool valid;

  /// True when the context check-in reported poor sleep, heavy fatigue, or
  /// illness or a medication change. Confounded sessions are stored and shown
  /// to the user but kept out of the baseline and the trend.
  final bool confounded;

  /// Optional identifier, carried through for storage and display.
  final String? sessionId;

  /// Feature keys this session does not supply.
  List<String> missingFeatures() =>
      kFeatureKeys.where((key) => !features.containsKey(key)).toList();
}
