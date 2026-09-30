/// Turning five features into one deviation index, and explaining the result.
///
/// The fusion is deliberately additive: the index is a weighted sum of
/// worsening-only domain scores. That choice costs some expressive power against
/// a learned classifier, but it buys an exact explanation -- each domain's share
/// of the total *is* its contribution, with no post-hoc attribution method and no
/// approximation error.
///
/// Mirrors `engine_lab/neurascan_engine/scoring.py`.
library;

import 'dart:math' as math;

import 'baseline.dart';
import 'features.dart';

/// Mean oriented robust z-score per domain.
///
/// Orientation happens per feature, so a domain score is positive when the
/// domain as a whole has moved in the worse direction, whichever way its
/// individual features point. Averaging rather than summing keeps domains
/// comparable even though they hold different numbers of features.
Map<Domain, double> domainScores(
  Map<String, double> features,
  Map<String, double> baselineMedian,
  Map<String, double> baselineScale,
) {
  final scores = <Domain, double>{};
  for (final domain in Domain.values) {
    final oriented = <double>[];
    for (final spec in specsFor(domain)) {
      final value = features[spec.key];
      final centre = baselineMedian[spec.key];
      final scale = baselineScale[spec.key];
      if (value == null || centre == null || scale == null) {
        continue;
      }
      oriented.add(spec.orient((value - centre) / scale));
    }
    scores[domain] = oriented.isEmpty
        ? 0.0
        : oriented.reduce((a, b) => a + b) / oriented.length;
  }
  return scores;
}

/// Convenience wrapper over [domainScores] taking a [Baseline].
Map<Domain, double> domainScoresFrom(
  Map<String, double> features,
  Baseline baseline,
) => domainScores(features, baseline.median, baseline.scale);

/// Weighted sum of the worsening part of each domain score.
///
/// Clamping at zero before weighting is what makes the index one-sided: a user
/// who traces faster does not earn credit that masks a decline in recall. Improvements are still visible in the per-domain trends, they just
/// cannot pull the overall index down.
double deviationIndex(Map<Domain, double> scores) {
  var total = 0.0;
  kDomainWeights.forEach((domain, weight) {
    total += weight * math.max(0.0, scores[domain] ?? 0.0);
  });
  return total;
}

/// Share of the deviation index attributable to each domain.
///
/// Always sums to 1 so the values can be shown directly as percentages. When
/// nothing is deviating there is no signal to apportion, so the fallback is the
/// configured domain weights -- which also sum to 1 and keep the report screen
/// from having to special-case a perfectly stable session.
Map<Domain, double> contributions(Map<Domain, double> scores) {
  final weighted = <Domain, double>{
    for (final domain in Domain.values)
      domain: kDomainWeights[domain]! * math.max(0.0, scores[domain] ?? 0.0),
  };
  final total = weighted.values.fold<double>(0.0, (a, b) => a + b);
  if (total <= 0.0) {
    return Map<Domain, double>.of(kDomainWeights);
  }
  return {for (final entry in weighted.entries) entry.key: entry.value / total};
}

/// Domain with the largest share of the index.
///
/// Used for the one-line summary on the report screen; the full breakdown is
/// always shown alongside it, because a cognitive decline can show up in speech too.
Domain topContributor(Map<Domain, double> scores) {
  final shares = contributions(scores);
  var best = Domain.values.first;
  for (final domain in Domain.values) {
    if (shares[domain]! > shares[best]!) {
      best = domain;
    }
  }
  return best;
}

/// Contributions as whole percentages that still total 100.
///
/// Rounding each share independently can total 99 or 101, which looks like a bug
/// on the report screen. The largest remainders absorb the leftover points.
Map<Domain, int> contributionPercentages(Map<Domain, double> shares) {
  if (shares.isEmpty) {
    return const {};
  }
  final floored = <Domain, int>{
    for (final entry in shares.entries) entry.key: (entry.value * 100).floor(),
  };
  var leftover = 100 - floored.values.fold<int>(0, (a, b) => a + b);
  if (leftover > 0) {
    final byRemainder = shares.keys.toList()
      ..sort((a, b) {
        final remainderA = shares[a]! * 100 - floored[a]!;
        final remainderB = shares[b]! * 100 - floored[b]!;
        return remainderB.compareTo(remainderA);
      });
    for (final domain in byRemainder) {
      if (leftover == 0) break;
      floored[domain] = floored[domain]! + 1;
      leftover--;
    }
  }
  return floored;
}
