/// Turning a feature's raw number into something a person can read.
///
/// The engine works in raw units -- milliseconds, fractions, dp. On a screen that means
/// "0.75" for recall, which is meaningless, so each feature gets the form a person would
/// expect: 75 %, 312 ms, 140 a minute.
library;

/// A feature's value, formatted for display.
String formatFeatureValue(String key, double value) => switch (key) {
  // Shares are shown as percentages.
  'immediate_recall' ||
  'delayed_recall' ||
  'pause_ratio' ||
  'fatigue_decay' => '${(value * 100).round()}%',
  'reaction_median' || 'inter_key_interval' => '${value.round()} ms',
  'speaking_rate' => '${value.round()}/min',
  'spiral_rmse' => '${value.toStringAsFixed(1)} dp',
  'completion_time' => '${value.toStringAsFixed(1)} s',
  'switch_cost' => '${value.toStringAsFixed(2)} s',
  'tap_rate' => '${value.toStringAsFixed(1)}/s',
  // Counts are whole numbers.
  'error_count' || 'valid_word_count' => '${value.round()}',
  // Dimensionless indices have no natural unit.
  _ => value.toStringAsFixed(2),
};

/// How much a feature usually varies, formatted like [formatFeatureValue] but as a spread.
String formatFeatureSpread(String key, double spread) =>
    '±${formatFeatureValue(key, spread)}';
