/// The vocabulary of the results module: the eight tests, the ranges, the trend words.
///
/// Plain values with no behaviour beyond naming, shared by the calculators, the screens and the
/// PDF so that all three mean the same thing by "the spiral test" or "last 30 days".
library;

import '../../engine/features.dart';

/// The eight tests of a full test, in the order they are taken.
enum TestId {
  wordMemory,
  reaction,
  speech,
  spiral,
  typing,
  trail,
  tapping,
  fluency;

  /// The measurements this test yields, in measurement order.
  List<String> get featureKeys => kTestFeatureKeys[this]!;

  /// The domains its measurements belong to, without repeats.
  List<Domain> get domains => [
    for (final domain in Domain.values)
      if (featureKeys.any((key) => kSpecByKey[key]!.domain == domain)) domain,
  ];
}

/// Which measurements each test yields.
///
/// Verbal fluency is listed as cognitive and speech in the project brief; its two measurements
/// are both scored in the cognitive area, because that is what a count of words retrieved under
/// a time limit is. The table is here, and the assignment in `features.dart`, so it is one edit
/// to move them.
const Map<TestId, List<String>> kTestFeatureKeys = {
  TestId.wordMemory: ['immediate_recall', 'delayed_recall'],
  TestId.reaction: ['reaction_median', 'reaction_cv'],
  TestId.speech: ['speaking_rate', 'pause_ratio'],
  TestId.spiral: ['spiral_rmse', 'tremor_index'],
  TestId.typing: ['inter_key_interval', 'inter_key_cv'],
  TestId.trail: ['completion_time', 'error_count', 'switch_cost'],
  TestId.tapping: ['tap_rate', 'tap_interval_cv', 'fatigue_decay'],
  TestId.fluency: ['valid_word_count', 'fluency_half_ratio'],
};

/// The test a measurement belongs to.
TestId testOf(String featureKey) =>
    TestId.values.firstWhere((test) => test.featureKeys.contains(featureKey));

/// Which way a measurement or area has been heading.
enum TrendDirection { improving, stable, declining }

/// How much history a chart or a statistic covers.
enum TrendRange {
  /// The last seven tests.
  last7,

  /// The last thirty days.
  days30,

  /// The last ninety days.
  days90,

  /// Everything since the baseline.
  all,
}
