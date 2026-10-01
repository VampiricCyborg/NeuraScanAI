/// Providers for the results module.
///
/// Everything is derived from the stored tests, the engine's baseline and the reference ranges,
/// by the pure functions in `calculators/analysis.dart`. Nothing here holds state of its own, so
/// a new test, a baseline being redone or a range being filled in flows through by itself.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models.dart';
import '../../engine/features.dart';
import 'calculators/analysis.dart';
import 'reference_ranges.dart';

/// The population reference ranges, loaded once from the bundled asset.
///
/// Falls back to no ranges if the asset cannot be read, which reads as "not yet validated".
final referenceRangesProvider = FutureProvider<ReferenceRanges>(
  (ref) => ReferenceRanges.load(rootBundle),
);

/// Every measurement's series over the current baseline's tests.
final allSeriesProvider = Provider<Map<String, MetricSeries>>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  final baseline = ref.watch(engineProvider).value?.baseline;
  final ranges =
      ref.watch(referenceRangesProvider).value ?? ReferenceRanges.none;
  return buildAllSeries(sessions: sessions, baseline: baseline, ranges: ranges);
});

/// The most recent full test, counted or set aside.
final latestFullTestProvider = Provider<SessionRecord?>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  for (final session in sessions.reversed) {
    if (session.isFullTest) return session;
  }
  return null;
});

/// The eight test summaries for the full test [sessionId].
final testSummariesProvider = Provider.family<List<TestSummary>, String>((
  ref,
  sessionId,
) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  final session = sessions.where((s) => s.id == sessionId).firstOrNull;
  if (session == null || !session.isFullTest) return const [];
  return summariseTests(series: ref.watch(allSeriesProvider), session: session);
});

/// The measurements that moved the index most in the full test [sessionId].
final topContributorsProvider = Provider.family<List<TopContributor>, String>((
  ref,
  sessionId,
) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  final baseline = ref.watch(engineProvider).value?.baseline;
  final session = sessions.where((s) => s.id == sessionId).firstOrNull;
  if (session == null || baseline == null) return const [];
  return topContributors(session: session, baseline: baseline);
});

/// Every test of the current baseline, counted or not, for the log.
final sessionLogProvider = Provider<List<SessionLogRow>>(
  (ref) => buildSessionLog(ref.watch(sessionsProvider).value ?? const []),
);

/// The overall index and its smoothed value over the counted tests.
final indexSeriesProvider = Provider<List<IndexPoint>>(
  (ref) => buildIndexSeries(ref.watch(sessionsProvider).value ?? const []),
);

/// Each area's score over the counted tests.
final areaSeriesProvider = Provider<Map<Domain, List<DomainPoint>>>((ref) {
  final sessions = ref.watch(sessionsProvider).value ?? const [];
  return {
    for (final domain in Domain.values)
      domain: buildDomainSeries(domain, sessions),
  };
});

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
