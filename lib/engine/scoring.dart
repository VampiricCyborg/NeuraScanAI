/// Turning the features into one deviation index, and explaining the result.
///
/// The fusion is deliberately additive: the index is a weighted sum of
/// worsening-only domain scores. That choice costs some expressive power against
/// a learned classifier, but it buys an exact explanation -- each domain's share
/// of the total *is* its contribution, with no post-hoc attribution method and no
/// approximation error.
///
/// Not every feature has a baseline or a value in every test. An extended feature is still
/// calibrating, or a test could not measure it (typing, when the user typed almost nothing).
/// Such a feature is left out of its domain's mean, a domain with nothing left is left out of
/// the index, and the domain weights are re-normalised over the domains that remain, so a
/// test is never pulled towards zero by something it could not measure.
///
/// Mirrors `engine_lab/neurascan_engine/scoring.py`.
library;

import 'dart:math' as math;

import 'baseline.dart';
import 'features.dart';

/// Mean oriented robust z-score per domain that has data.
///
/// Orientation happens per feature, so a domain score is positive when the domain as a
/// whole has moved in the worse direction, whichever way its individual features point.
/// Averaging rather than summing keeps domains comparable even though they hold different
/// numbers of features.
///
/// A feature counts only if the test supplied it *and* it has a baseline. A domain with no
/// such feature is absent from the result, which is how callers tell "no data" from "no
/// change".
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
    if (oriented.isNotEmpty) {
      scores[domain] = oriented.reduce((a, b) => a + b) / oriented.length;
    }
  }
  return scores;
}

/// Convenience wrapper over [domainScores] taking a [Baseline].
Map<Domain, double> domainScoresFrom(
  Map<String, double> features,
  Baseline baseline,
) => domainScores(features, baseline.median, baseline.scale);

/// The configured domain weights, re-normalised to sum to one over [domains].
///
/// With every domain present these are just the configured weights. With some missing the
/// rest are scaled up in proportion, keeping their relative sizes. An empty set gives an
/// empty result.
Map<Domain, double> normalisedWeights(Iterable<Domain> domains) {
  final present = domains.toSet();
  final total = present.fold<double>(0.0, (sum, d) => sum + kDomainWeights[d]!);
  if (total <= 0.0) return const {};
  return {
    for (final domain in present) domain: kDomainWeights[domain]! / total,
  };
}

/// Weighted sum of the worsening part of each domain score.
///
/// Clamping at zero before weighting is what makes the index one-sided: a user who traces
/// faster does not earn credit that masks a decline in recall. Improvements are still
/// visible in the per-domain trends, they just cannot pull the overall index down.
///
/// The weights are re-normalised over the domains in [scores].
double deviationIndex(Map<Domain, double> scores) {
  final weights = normalisedWeights(scores.keys);
  var total = 0.0;
  scores.forEach((domain, score) {
    total += weights[domain]! * math.max(0.0, score);
  });
  return total;
}

/// Share of the deviation index attributable to each domain.
///
/// Always sums to 1 so the values can be shown directly as percentages, and always has an
/// entry for every domain (zero for one with no data). When nothing is deviating there is no
/// signal to apportion, so the fallback is the normalised domain weights -- which also sum to
/// 1 and keep the report screen from having to special-case a perfectly stable session.
Map<Domain, double> contributions(Map<Domain, double> scores) {
  final weights = normalisedWeights(scores.keys);
  final weighted = <Domain, double>{
    for (final entry in scores.entries)
      entry.key: weights[entry.key]! * math.max(0.0, entry.value),
  };
  final total = weighted.values.fold<double>(0.0, (a, b) => a + b);
  final shares = total <= 0.0
      ? weights
      : {for (final entry in weighted.entries) entry.key: entry.value / total};
  return {for (final domain in Domain.values) domain: shares[domain] ?? 0.0};
}

/// Each feature's exact share of the deviation index, in index units.
///
/// The index is `sum(w_d * max(0, s_d))` with `s_d` the mean of the oriented z-scores in
/// domain `d`, so inside a domain that is worsening each feature contributes `w_d * z / n_d`,
/// and those numbers add up to the index exactly. A feature that moved the good way
/// contributes a negative amount inside a domain that is net worse, which is what makes it
/// visible that it was offsetting part of the change. A domain that is not worsening
/// contributes nothing, because the index ignores it.
///
/// Only features with a value and a baseline appear.
Map<String, double> featureContributions(
  Map<String, double> features,
  Map<String, double> baselineMedian,
  Map<String, double> baselineScale,
) {
  final scores = domainScores(features, baselineMedian, baselineScale);
  final weights = normalisedWeights(scores.keys);
  final result = <String, double>{};
  scores.forEach((domain, score) {
    if (score <= 0.0) return;
    final counted = [
      for (final spec in specsFor(domain))
        if (features.containsKey(spec.key) &&
            baselineMedian.containsKey(spec.key))
          spec,
    ];
    for (final spec in counted) {
      final z =
          (features[spec.key]! - baselineMedian[spec.key]!) /
          baselineScale[spec.key]!;
      result[spec.key] = weights[domain]! * spec.orient(z) / counted.length;
    }
  });
  return result;
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
