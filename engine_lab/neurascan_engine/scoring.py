"""Turning the features into one deviation index, and explaining the result.

The fusion is deliberately additive: the index is a weighted sum of
worsening-only domain scores.  That choice costs some expressive power against a
learned classifier, but it buys an exact explanation -- each domain's share of
the total *is* its contribution, with no post-hoc attribution method and no
approximation error.

Not every feature has a baseline or a value in every test.  An extended feature
is still calibrating, or a test could not measure it (typing, when the user typed
almost nothing).  Such a feature is left out of its domain's mean, a domain with
nothing left is left out of the index, and the domain weights are re-normalised
over the domains that remain, so a test is never pulled towards zero by something
it could not measure.
"""

from __future__ import annotations

from .baseline import Baseline
from .features import (
    DOMAIN_WEIGHTS,
    Domain,
    specs_for,
)


def domain_scores(
    features: dict[str, float],
    baseline_median: dict[str, float],
    baseline_scale: dict[str, float],
) -> dict[Domain, float]:
    """Mean oriented robust z-score per domain that has data.

    Orientation happens per feature, so a domain score is positive when the
    domain as a whole has moved in the worse direction, whichever way its
    individual features point.  Averaging rather than summing keeps domains
    comparable even though they hold different numbers of features.

    A feature counts only if the test supplied it *and* it has a baseline.  A
    domain with no such feature is absent from the result, which is how callers
    tell "no data" from "no change".
    """
    scores: dict[Domain, float] = {}
    for domain in Domain:
        oriented: list[float] = []
        for spec in specs_for(domain):
            if spec.key not in features or spec.key not in baseline_median:
                continue
            raw_z = (features[spec.key] - baseline_median[spec.key]) / baseline_scale[
                spec.key
            ]
            oriented.append(spec.orient(raw_z))
        if oriented:
            scores[domain] = sum(oriented) / len(oriented)
    return scores


def domain_scores_from(
    features: dict[str, float], baseline: Baseline
) -> dict[Domain, float]:
    """Convenience wrapper over :func:`domain_scores` taking a Baseline."""
    return domain_scores(features, baseline.median, baseline.scale)


def normalised_weights(domains: set[Domain] | frozenset[Domain]) -> dict[Domain, float]:
    """The configured domain weights, re-normalised to sum to one over *domains*.

    With every domain present these are just the configured weights.  With some
    missing the rest are scaled up in proportion, keeping their relative sizes.
    An empty set gives an empty result.
    """
    total = sum(DOMAIN_WEIGHTS[domain] for domain in domains)
    if total <= 0.0:
        return {}
    return {domain: DOMAIN_WEIGHTS[domain] / total for domain in domains}


def deviation_index(scores: dict[Domain, float]) -> float:
    """Weighted sum of the worsening part of each domain score.

    Clamping at zero before weighting is what makes the index one-sided: a user
    who traces faster does not earn credit that masks a decline in recall.
    Improvements are still visible in the per-domain trends, they just cannot
    pull the overall index down.

    The weights are re-normalised over the domains in *scores*.
    """
    weights = normalised_weights(frozenset(scores))
    return sum(weights[domain] * max(0.0, score) for domain, score in scores.items())


def contributions(scores: dict[Domain, float]) -> dict[Domain, float]:
    """Share of the deviation index attributable to each domain.

    Always sums to 1 so the values can be shown directly as percentages, and
    always has an entry for every domain (zero for one with no data).  When
    nothing is deviating there is no signal to apportion, so the fallback is the
    normalised domain weights -- which also sum to 1 and keep the report screen
    from having to special-case a perfectly stable session.
    """
    weights = normalised_weights(frozenset(scores))
    weighted = {domain: weights[domain] * max(0.0, scores[domain]) for domain in scores}
    total = sum(weighted.values())
    if total <= 0.0:
        shares = dict(weights)
    else:
        shares = {domain: value / total for domain, value in weighted.items()}
    return {domain: shares.get(domain, 0.0) for domain in Domain}


def top_contributor(scores: dict[Domain, float]) -> Domain:
    """Domain with the largest share of the index.

    Used for the one-line summary on the report screen; the full breakdown is
    always shown alongside it, because a cognitive decline routinely shows up
    in speech and typing too.
    """
    shares = contributions(scores)
    return max(shares, key=lambda domain: shares[domain])


def feature_contributions(
    features: dict[str, float],
    baseline_median: dict[str, float],
    baseline_scale: dict[str, float],
) -> dict[str, float]:
    """Each feature's exact share of the deviation index, in index units.

    The index is ``sum(w_d * max(0, s_d))`` with ``s_d`` the mean of the oriented
    z-scores in domain ``d``, so inside a domain that is worsening each feature
    contributes ``w_d * z / n_d``, and those numbers add up to the index exactly.
    A feature that moved the good way contributes a negative amount inside a
    domain that is net worse, which is what makes it visible that it was
    offsetting part of the change.  A domain that is not worsening contributes
    nothing, because the index ignores it.

    Only features with a value and a baseline appear.
    """
    scores = domain_scores(features, baseline_median, baseline_scale)
    weights = normalised_weights(frozenset(scores))
    result: dict[str, float] = {}
    for domain, score in scores.items():
        if score <= 0.0:
            continue
        counted = [
            spec
            for spec in specs_for(domain)
            if spec.key in features and spec.key in baseline_median
        ]
        for spec in counted:
            raw_z = (features[spec.key] - baseline_median[spec.key]) / baseline_scale[
                spec.key
            ]
            result[spec.key] = weights[domain] * spec.orient(raw_z) / len(counted)
    return result
