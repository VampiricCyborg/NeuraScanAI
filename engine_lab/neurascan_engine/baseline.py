"""The personal baseline: what "normal" means for one particular user.

The whole point of NeuraScan is that a score is judged against the user's own
history rather than a population norm, and this module is where that history is
frozen into a comparison point.  Robust statistics are used throughout because
the baseline rests on only a handful of observations, where a single unusual
session would drag a mean and inflate a standard deviation enough to hide a
later decline.
"""

from __future__ import annotations

import statistics
from collections.abc import Iterable, Sequence
from dataclasses import dataclass

from .constants import (
    MAD_TO_SIGMA,
    SCALE_FLOOR_ABSOLUTE,
    SCALE_FLOOR_FRACTION,
)
from .features import FEATURE_KEYS, Session


def median(values: Sequence[float]) -> float:
    """Median of *values*; raises on an empty sequence."""
    if not values:
        raise ValueError("median of an empty sequence")
    return float(statistics.median(values))


def median_absolute_deviation(values: Sequence[float]) -> float:
    """Median of the absolute deviations from the median.

    Preferred over a standard deviation here because it has a breakdown point
    of 50 %: half the baseline sessions would have to be unusual before the
    estimate is affected, whereas one extreme session is enough to inflate an
    SD noticeably at n = 6.
    """
    if not values:
        raise ValueError("MAD of an empty sequence")
    centre = median(values)
    return median([abs(value - centre) for value in values])


def robust_scale(values: Sequence[float]) -> float:
    """Spread of *values* as a floored, sigma-equivalent robust scale.

    The MAD is rescaled by :data:`~neurascan_engine.constants.MAD_TO_SIGMA` so
    that a resulting z-score reads on the familiar standard-deviation scale,
    then floored so that a user whose baseline happens to be perfectly
    consistent does not get infinite z-scores forever after.
    """
    centre = median(values)
    scale = MAD_TO_SIGMA * median_absolute_deviation(values)
    floor = max(SCALE_FLOOR_FRACTION * abs(centre), SCALE_FLOOR_ABSOLUTE)
    return max(scale, floor)


@dataclass(frozen=True)
class Baseline:
    """A frozen per-feature centre and spread for one user on one device.

    Twenty numbers in total -- a median and a scale for each of the nine
    features, plus the session count -- which is what makes the baseline cheap
    enough to hold in memory, store locally and sync as a single document.
    """

    #: Feature key to the median of that feature over the baseline sessions.
    median: dict[str, float]

    #: Feature key to the floored robust scale of that feature.
    scale: dict[str, float]

    #: How many sessions were summarised.  Kept for display and for auditing a
    #: baseline that was frozen under an older rule.
    session_count: int

    @classmethod
    def fit(cls, sessions: Iterable[Session]) -> Baseline:
        """Summarise *sessions* into a baseline.

        Callers are responsible for having already excluded familiarisation,
        invalid and confounded sessions: this method deliberately does not
        re-filter, so that the selection rule lives in exactly one place --
        :class:`~neurascan_engine.engine.ScreeningEngine`.
        """
        pool = list(sessions)
        if not pool:
            raise ValueError("cannot fit a baseline with no sessions")

        medians: dict[str, float] = {}
        scales: dict[str, float] = {}
        for key in FEATURE_KEYS:
            values = [s.features[key] for s in pool if key in s.features]
            if len(values) != len(pool):
                raise ValueError(f"feature {key!r} missing from some sessions")
            medians[key] = median(values)
            scales[key] = robust_scale(values)

        return cls(median=medians, scale=scales, session_count=len(pool))

    def z(self, key: str, value: float) -> float:
        """Raw, unoriented robust z-score of *value* for feature *key*."""
        return (value - self.median[key]) / self.scale[key]

    def to_json(self) -> dict[str, object]:
        """Plain-dict form, as stored locally and synced when sync is on."""
        return {
            "median": dict(self.median),
            "scale": dict(self.scale),
            "sessionCount": self.session_count,
        }

    @classmethod
    def from_json(cls, data: dict[str, object]) -> Baseline:
        """Inverse of :meth:`to_json`."""
        raw_median = data["median"]
        raw_scale = data["scale"]
        assert isinstance(raw_median, dict) and isinstance(raw_scale, dict)
        return cls(
            median={k: float(v) for k, v in raw_median.items()},
            scale={k: float(v) for k, v in raw_scale.items()},
            session_count=int(data["sessionCount"]),  # type: ignore[arg-type]
        )
