/// The five behavioural features and the three domains that group them.
///
/// A feature is described by three things: which domain it belongs to, which
/// direction counts as worse, and what it is called. Keeping that description
/// in one place means the scoring code never has to special-case a feature, and
/// adding a sixth feature is a one-line change here plus a weight review.
///
/// The app measures three things -- words, speech and a precision (spiral) tracing --
/// and each yields one or two features. An earlier design also had a reaction-time task and
/// a typing-rhythm measurement (nine features, four domains). Both were dropped when the
/// tests were restructured around the three steps, because a step in an actual test has to
/// be something the baseline also measured, or there is nothing to compare it with.
///
/// Mirrors `engine_lab/neurascan_engine/features.py`.
library;

/// The three behavioural domains fused into a single deviation index.
enum Domain {
  cognitive('cognitive', 'Cognitive'),
  speech('speech', 'Speech'),
  motor('motor', 'Motor');

  const Domain(this.key, this.label);

  /// Stable identifier used in the database and in synced documents.
  final String key;

  /// Human-readable name shown on the report and trend screens.
  final String label;

  static Domain fromKey(String key) =>
      Domain.values.firstWhere((domain) => domain.key == key);

  /// The domain for [key], or null for one that no longer exists.
  ///
  /// Records stored before the typing area was dropped still carry an "interaction" score.
  /// Reading them must not fail, so decoders use this and skip what they do not recognise.
  static Domain? tryFromKey(String key) {
    for (final domain in Domain.values) {
      if (domain.key == key) return domain;
    }
    return null;
  }
}

/// Weight of each domain in the deviation index.
///
/// Cognition carries the most weight because delayed recall is the best-established early
/// signal in the literature. The report's original weights were 35 / 25 / 25 / 15 with a
/// fourth, typing area; with that area gone the remaining three keep their relative sizes
/// (35 : 25 : 25) and are rounded to 40 / 30 / 30.
const Map<Domain, double> kDomainWeights = {
  Domain.cognitive: 0.40,
  Domain.speech: 0.30,
  Domain.motor: 0.30,
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
  });

  final String key;
  final Domain domain;
  final Direction direction;
  final String label;
  final String unit;

  /// How much this feature typically varies from one day to the next within a single
  /// healthy person, in the feature's own units. These are the within-person SDs from Table
  /// A.2 of the report.
  ///
  /// Used for one thing only: to stop a baseline's spread being estimated as implausibly
  /// small. With only a few baseline sessions the MAD can come out near zero by luck, and
  /// every ordinary day then looks like a large deviation. A floor tied to typical variation
  /// prevents that without pulling the *centre* of anyone's baseline towards a population
  /// value -- the baseline stays personal.
  final double typicalDaySd;

  /// Flips [z] if needed so that a positive result always means worse.
  ///
  /// The rest of the engine relies on this: once a z-score is oriented,
  /// `max(0, z)` is exactly "the part of the change that is a decline", with no
  /// per-feature knowledge required.
  double orient(double z) => direction == Direction.higherIsWorse ? z : -z;
}

/// The five features, in the order they are measured.
const List<FeatureSpec> kFeatureSpecs = [
  FeatureSpec(
    key: 'delayed_recall',
    typicalDaySd: 0.06,
    domain: Domain.cognitive,
    direction: Direction.lowerIsWorse,
    label: 'Delayed recall',
    unit: 'fraction',
  ),
  FeatureSpec(
    key: 'speaking_rate',
    typicalDaySd: 8.0,
    domain: Domain.speech,
    direction: Direction.lowerIsWorse,
    label: 'Speaking rate',
    unit: 'syllables/min',
  ),
  FeatureSpec(
    key: 'pause_ratio',
    typicalDaySd: 0.025,
    domain: Domain.speech,
    direction: Direction.higherIsWorse,
    label: 'Pause ratio',
  ),
  FeatureSpec(
    key: 'spiral_rmse',
    typicalDaySd: 0.6,
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Spiral tracing error',
    unit: 'dp',
  ),
  FeatureSpec(
    key: 'tremor_index',
    typicalDaySd: 0.012,
    domain: Domain.motor,
    direction: Direction.higherIsWorse,
    label: 'Tremor index',
  ),
];

/// Lookup by feature key.
final Map<String, FeatureSpec> kSpecByKey = {
  for (final spec in kFeatureSpecs) spec.key: spec,
};

/// Feature keys, in measurement order.
final List<String> kFeatureKeys = [for (final spec in kFeatureSpecs) spec.key];

/// The features belonging to [domain], in measurement order.
List<FeatureSpec> specsFor(Domain domain) => kFeatureSpecs
    .where((spec) => spec.domain == domain)
    .toList(growable: false);

/// One test as the engine sees it.
///
/// The engine deals only in extracted features. Raw touch coordinates and audio never reach
/// it -- they are reduced to these five numbers on the device and then discarded, which is
/// what lets the app claim that raw signals never leave the phone.
///
/// An actual test repeats each measurement several times; the features here are the median
/// of those repeats, so a single unusual step cannot define the test.
class EngineSession {
  const EngineSession({
    required this.features,
    this.valid = true,
    this.confounded = false,
    this.sessionId,
  });

  /// Feature key to value. Missing keys make the session unusable.
  final Map<String, double> features;

  /// False when the test could not be scored.
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
