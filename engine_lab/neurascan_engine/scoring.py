"""Turning five features into one deviation index, and explaining the result.

The fusion is deliberately additive: the index is a weighted sum of
worsening-only domain scores.  That choice costs some expressive power against a
learned classifier, but it buys an exact explanation -- each domain's share of
the total *is* its contribution, with no post-hoc attribution method and no
approximation error.
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
    """Mean oriented robust z-score per domain.

    Orientation happens per feature, so a domain score is positive when the
    domain as a whole has moved in the worse direction, whichever way its
    individual features point.  Averaging rather than summing keeps domains
    comparable even though they hold different numbers of features.
    """
    scores: dict[Domain, float] = {}
    for domain in Domain:
        oriented: list[float] = []
        for spec in specs_for(domain):
            if spec.key not in features:
                continue
            raw_z = (features[spec.key] - baseline_median[spec.key]) / baseline_scale[
                spec.key
            ]
            oriented.append(spec.orient(raw_z))
        scores[domain] = sum(oriented) / len(oriented) if oriented else 0.0
    return scores


def domain_scores_from(
    features: dict[str, float], baseline: Baseline
) -> dict[Domain, float]:
    """Convenience wrapper over :func:`domain_scores` taking a Baseline."""
    return domain_scores(features, baseline.median, baseline.scale)


def deviation_index(scores: dict[Domain, float]) -> float:
    """Weighted sum of the worsening part of each domain score.

    Clamping at zero before weighting is what makes the index one-sided: a user
    who traces faster does not earn credit that masks a decline in recall.
    Improvements are still visible in the per-domain trends, they just cannot
    pull the overall index down.
    """
    return sum(
        weight * max(0.0, scores.get(domain, 0.0))
        for domain, weight in DOMAIN_WEIGHTS.items()
    )


def contributions(scores: dict[Domain, float]) -> dict[Domain, float]:
    """Share of the deviation index attributable to each domain.

    Always sums to 1 so the values can be shown directly as percentages.  When
    nothing is deviating there is no signal to apportion, so the fallback is
    the configured domain weights -- which also sum to 1 and keep the report
    screen from having to special-case a perfectly stable session.
    """
    weighted = {
        domain: DOMAIN_WEIGHTS[domain] * max(0.0, scores.get(domain, 0.0))
        for domain in Domain
    }
    total = sum(weighted.values())
    if total <= 0.0:
        return dict(DOMAIN_WEIGHTS)
    return {domain: value / total for domain, value in weighted.items()}


def top_contributor(scores: dict[Domain, float]) -> Domain:
    """Domain with the largest share of the index.

    Used for the one-line summary on the report screen; the full breakdown is
    always shown alongside it, because a cognitive decline routinely shows up
    in speech and typing too.
    """
    shares = contributions(scores)
    return max(shares, key=lambda domain: shares[domain])
