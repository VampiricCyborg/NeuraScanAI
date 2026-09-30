/// The personal baseline: what "normal" means for one particular user.
///
/// The whole point of NeuraScan is that a score is judged against the user's own
/// history rather than a population norm, and this file is where that history is
/// frozen into a comparison point. The statistics themselves live in
/// `robust_stats.dart`; this file is about when they are taken and what is kept.
///
/// Mirrors `engine_lab/neurascan_engine/baseline.py`.
library;

import 'features.dart';
// Prefixed because this class has a `median` field, which would otherwise shadow
// the top-level function of the same name throughout the class body.
import 'robust_stats.dart' as stats;

export 'robust_stats.dart' show median, medianAbsoluteDeviation, robustScale;

/// A frozen per-feature centre and spread for one user on one device.
///
/// Eleven numbers in total -- a median and a scale for each of the five
/// features, plus the session count -- which is what makes the baseline cheap
/// enough to hold in memory, store locally and sync as a single document.
class Baseline {
  const Baseline({
    required this.median,
    required this.scale,
    required this.sessionCount,
  });

  /// Feature key to the median of that feature over the baseline sessions.
  final Map<String, double> median;

  /// Feature key to the floored robust scale of that feature.
  final Map<String, double> scale;

  /// How many sessions were summarised. Kept for display and for auditing a
  /// baseline that was frozen under an older rule.
  final int sessionCount;

  /// Summarises [sessions] into a baseline.
  ///
  /// Only the core features are fitted, and every session must supply all of them: they are
  /// what the baseline tests measure. Any extended feature the sessions happen to carry is
  /// ignored here; it calibrates separately (see [extended]).
  ///
  /// Callers are responsible for having already excluded familiarisation,
  /// invalid and confounded sessions: this constructor deliberately does not
  /// re-filter, so that the selection rule lives in exactly one place --
  /// `ScreeningEngine`.
  factory Baseline.fit(List<EngineSession> sessions) {
    if (sessions.isEmpty) {
      throw ArgumentError('cannot fit a baseline with no sessions');
    }

    final medians = <String, double>{};
    final scales = <String, double>{};
    for (final key in kCoreFeatureKeys) {
      final values = <double>[];
      for (final session in sessions) {
        final value = session.features[key];
        if (value == null) {
          throw ArgumentError('feature "$key" missing from some sessions');
        }
        values.add(value);
      }
      medians[key] = stats.median(values);
      scales[key] = stats.robustScale(
        values,
        typicalSd: kSpecByKey[key]!.typicalDaySd,
      );
    }

    return Baseline(
      median: medians,
      scale: scales,
      sessionCount: sessions.length,
    );
  }

  /// True once every feature, core and extended, has a baseline.
  bool get isComplete => kFeatureKeys.every(median.containsKey);

  /// Features that do not have a baseline yet, in measurement order.
  List<String> get pendingKeys => [
    for (final key in kFeatureKeys)
      if (!median.containsKey(key)) key,
  ];

  /// A copy with a baseline added for each pending feature that has enough data.
  ///
  /// A pending feature is fixed from the first [required] values it has across [sessions],
  /// oldest first. Fixing it from those and no more means later tests cannot move it, which
  /// is what makes it a baseline rather than a running average. A feature with fewer values
  /// is left pending; one that a test could not measure simply does not contribute that
  /// test.
  ///
  /// The existing entries are never touched.
  Baseline extended(List<EngineSession> sessions, {required int required}) {
    final medians = Map<String, double>.of(median);
    final scales = Map<String, double>.of(scale);
    for (final key in pendingKeys) {
      final values = <double>[
        for (final session in sessions)
          if (session.features[key] != null) session.features[key]!,
      ];
      if (values.length < required) continue;
      final used = values.sublist(0, required);
      medians[key] = stats.median(used);
      scales[key] = stats.robustScale(
        used,
        typicalSd: kSpecByKey[key]!.typicalDaySd,
      );
    }
    return Baseline(median: medians, scale: scales, sessionCount: sessionCount);
  }

  /// Raw, unoriented robust z-score of [value] for feature [key].
  double z(String key, double value) => (value - median[key]!) / scale[key]!;

  /// Plain-map form, as stored locally and synced when sync is on.
  Map<String, dynamic> toJson() => {
    'median': Map<String, double>.of(median),
    'scale': Map<String, double>.of(scale),
    'sessionCount': sessionCount,
  };

  /// Inverse of [toJson].
  factory Baseline.fromJson(Map<String, dynamic> json) {
    Map<String, double> numbers(Object? raw) => {
      for (final entry in (raw as Map).entries)
        entry.key as String: (entry.value as num).toDouble(),
    };
    return Baseline(
      median: numbers(json['median']),
      scale: numbers(json['scale']),
      sessionCount: (json['sessionCount'] as num).toInt(),
    );
  }
}
