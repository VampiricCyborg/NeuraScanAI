/// Turning a feature's raw number into something a person can read.
///
/// The engine works in raw units -- milliseconds, fractions, dp. On a screen that means
/// "0.75" for recall, which is meaningless, so each feature gets the form a person would
/// expect: 75 %, 312 ms, 140 a minute.
library;

/// A feature's value, formatted for display.
String formatFeatureValue(String key, double value) => switch (key) {
  // Shares are shown as percentages.
  'delayed_recall' || 'pause_ratio' => '${(value * 100).round()}%',
  'speaking_rate' => '${value.round()}/min',
  'spiral_rmse' => '${value.toStringAsFixed(1)} dp',
  // Dimensionless indices have no natural unit.
  _ => value.toStringAsFixed(2),
};

/// How much a feature usually varies, formatted like [formatFeatureValue] but as a spread.
String formatFeatureSpread(String key, double spread) =>
    '±${formatFeatureValue(key, spread)}';
