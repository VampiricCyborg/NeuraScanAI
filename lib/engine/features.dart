/// The eighteen behavioural features and the four domains that group them.
///
/// A feature is described by a handful of things: which domain it belongs to, which
/// direction counts as worse, what it is called, and whether the baseline tests measure
/// it. Keeping that description in one place means the scoring code never has to
/// special-case a feature, and adding a nineteenth is a one-line change here plus a weight
/// review.
///
/// The app has two kinds of test. A *baseline* test has three steps -- words, speech and a
/// precision (spiral) tracing -- so those steps yield the five **core** features, which get
/// their baseline from the four baseline tests. A full (*actual*) test has eight steps,
/// five of which (reaction time, typing rhythm, trail-making, finger tapping, verbal
/// fluency) the baseline tests never ran. Those thirteen **extended** features get their
/// baseline from the user's first few full tests instead (see `ScreeningEngine`); until
/// then they are reported as raw values and do not feed the deviation index.
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

  /// The domain for [key], or null for one that does not exist.
  ///
  /// Tests stored by an earlier version of the app can carry keys this version does not
  /// know. Reading them must not fail, so decoders use this and skip what they do not
  /// recognise.
  static Domain? tryFromKey(String key) {
    for (final domain in Domain.values) {
      if (domain.key == key) return domain;
    }
    return null;
  }
}

/// Weight of each domain in the deviation index.
///
/// These are the project report's weights (35 / 25 / 25 / 15). Cognition carries the most
/// weight because delayed recall is the best-established early signal in the literature;
/// typing is passive and noisier, so it carries the least. They sum to one, and
/// `normalisedWeights` re-normalises them over whichever domains have data in a given
/// test, so a test in which a domain could not be measured is not dragged towards zero by
/// it.
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
    required this.typicalDaySd,
    this.unit = '',
    this.core = false,
    this.provisional = false,
  });

  final String key;
  final Domain domain;
  final Direction direction;
  final String label;
  final String unit;

  /// How much this feature typically varies from one day to the next within a single
  /// healthy person, in the feature's own units.
  ///
  /// Used for one thing only: to stop a baseline's spread being estimated as implausibly
  /// small. With only a few baseline sessions the MAD can come out near zero by luck, and
  /// every ordinary day then looks like a large deviation. A floor tied to typical
  /// variation prevents that without pulling the *centre* of anyone's baseline towards a
  /// population value -- the baseline stays personal.
  final double typicalDaySd;

  /// True when the baseline tests measure this feature, so its baseline comes from them.
  /// False for the features only a full test measures.
  final bool core;

  /// True when [typicalDaySd] is a provisional estimate rather than a figure from the
  /// report's Table A.2. The floor it sets is a safeguard, not a finding, but it should be
  /// replaced with measured values once pilot data exists.
  final bool provisional;

  /// Flips [z] if needed so that a positive result always means worse.
  ///
  /// The rest of the engine relies on this: once a z-score is oriented,
  /// `max(0, z)` is exactly "the part of the change that is a decline", with no
  /// per-feature knowledge required.
  double orient(double z) => direction == Direction.higherIsWorse ? z : -z;
}

/// The eighteen features, in the order the tests measure them.
const List<FeatureSpec> kFeatureSpecs = [
  // 1. Word memory
  FeatureSpec(
    key: 'immediate_recall',
    typicalDaySd: 0.05,
    domain: Domain.cognitive,
    direction: Direction.lowerIsWorse,
    label: 'Immediate recall',
    unit: 'fraction',
    provisional: true,
  ),
  FeatureSpec(
    key: 'delayed_recall',
    typicalDaySd: 0.06,
    domain: Domain.cognitive,
    direction: Direction.lowerIsWorse,
    label: 'Delayed recall',
    unit: 'fraction',
    core: true,
  ),
  // 2. Reaction time
  FeatureSpec(
    key: 'reaction_median',
    typicalDaySd: 18.0,
    domain: Domain.cognitive,
    direction: Direction.higherIsWorse,
    label: 'Reaction time (median)',
    unit: 'ms',
  ),
  FeatureSpec(
    key: 'reaction_cv',
    typicalDaySd: 0.02,
    domain: Domain.cognitive,
    direction: Direction.higherIsWorse,
    label: 'Reaction consistency (CV)',
  ),
  // 3. Speech description
  FeatureSpec(
    key: 'speaking_rate',
    typicalDaySd: 8.0,
    domain: Domain.speech,
    direction: Direction.lowerIsWorse,
    label: 'Speaking rate',
    unit: 'syllables/min',
    core: true,
  ),
  FeatureSpec(
    key: 'pause_ratio',
    typicalDaySd: 0.025,
    domain: Domain.speech,
    direction: Direction.higherIsWorse,
    label: 'Pause ratio',
    core: true,
  ),
  // 4. Spiral tracing
  FeatureSpec(
    key: 'spiral_rmse',
    typicalDaySd: 0.6,
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Spiral tracing error',
    unit: 'dp',
    core: true,
  ),
  FeatureSpec(
    key: 'tremor_index',
    typicalDaySd: 0.012,
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Tremor index',
    core: true,
  ),
  // 5. Typing rhythm (passive)
  FeatureSpec(
    key: 'inter_key_interval',
    typicalDaySd: 15.0,
    domain: Domain.interaction,
    direction: Direction.higherIsWorse,
    label: 'Typing interval',
    unit: 'ms',
  ),
  FeatureSpec(
    key: 'inter_key_cv',
    typicalDaySd: 0.035,
    domain: Domain.interaction,
    direction: Direction.higherIsWorse,
    label: 'Typing rhythm (CV)',
  ),
  // 6. Trail-making lite
  FeatureSpec(
    key: 'completion_time',
    typicalDaySd: 1.5,
    domain: Domain.cognitive,
    direction: Direction.higherIsWorse,
    label: 'Trail-making time',
    unit: 's',
    provisional: true,
  ),
  FeatureSpec(
    key: 'error_count',
    typicalDaySd: 0.8,
    domain: Domain.cognitive,
    direction: Direction.higherIsWorse,
    label: 'Trail-making errors',
    unit: 'taps',
    provisional: true,
  ),
  FeatureSpec(
    key: 'switch_cost',
    typicalDaySd: 0.15,
    domain: Domain.cognitive,
    direction: Direction.higherIsWorse,
    label: 'Attention-switching cost',
    unit: 's/tap',
    provisional: true,
  ),
  // 7. Finger tapping
  FeatureSpec(
    key: 'tap_rate',
    typicalDaySd: 0.25,
    domain: Domain.motor,
    direction: Direction.lowerIsWorse,
    label: 'Tapping speed',
    unit: 'taps/s',
    provisional: true,
  ),
  FeatureSpec(
    key: 'tap_interval_cv',
    typicalDaySd: 0.04,
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Tapping regularity (CV)',
    provisional: true,
  ),
  FeatureSpec(
    key: 'fatigue_decay',
    typicalDaySd: 0.05,
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Tapping fatigue decay',
    unit: 'fraction',
    provisional: true,
  ),
  // 8. Verbal fluency
  FeatureSpec(
    key: 'valid_word_count',
    typicalDaySd: 2.0,
    domain: Domain.cognitive,
    direction: Direction.lowerIsWorse,
    label: 'Animals named',
    unit: 'words',
    provisional: true,
  ),
  FeatureSpec(
    key: 'fluency_half_ratio',
    typicalDaySd: 0.15,
    domain: Domain.cognitive,
    direction: Direction.lowerIsWorse,
    label: 'Fluency, last 15 s vs first 15 s',
    provisional: true,
  ),
];

/// Lookup by feature key.
final Map<String, FeatureSpec> kSpecByKey = {
  for (final spec in kFeatureSpecs) spec.key: spec,
};

/// Feature keys, in measurement order.
final List<String> kFeatureKeys = [for (final spec in kFeatureSpecs) spec.key];

/// The features the baseline tests measure.
final List<String> kCoreFeatureKeys = [
  for (final spec in kFeatureSpecs)
    if (spec.core) spec.key,
];

/// The features only a full test measures, which calibrate from full tests.
final List<String> kExtendedFeatureKeys = [
  for (final spec in kFeatureSpecs)
    if (!spec.core) spec.key,
];

/// The features belonging to [domain], in measurement order.
List<FeatureSpec> specsFor(Domain domain) => kFeatureSpecs
    .where((spec) => spec.domain == domain)
    .toList(growable: false);

/// One test as the engine sees it.
///
/// The engine deals only in extracted features. Raw touch coordinates and audio never reach
/// it -- they are reduced to these numbers on the device and then discarded, which is what
/// lets the app claim that raw signals never leave the phone.
///
/// A baseline test supplies the core features; a full test supplies those and the extended
/// ones. A feature a test could not measure -- typing, when the user typed almost nothing --
/// is simply absent.
class EngineSession {
  const EngineSession({
    required this.features,
    this.valid = true,
    this.confounded = false,
    this.sessionId,
  });

  /// Feature key to value. A baseline test must supply every core feature.
  final Map<String, double> features;

  /// False when the test could not be scored.
  final bool valid;

  /// True when the context check-in reported poor sleep, heavy fatigue, or
  /// illness or a medication change. Confounded sessions are stored and shown
  /// to the user but kept out of the baseline and the trend.
  final bool confounded;

  /// Optional identifier, carried through for storage and display.
  final String? sessionId;

  /// Core feature keys this session does not supply.
  List<String> missingFeatures() =>
      kCoreFeatureKeys.where((key) => !features.containsKey(key)).toList();
}
