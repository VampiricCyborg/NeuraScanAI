"""UT3, UT4 and UT5 -- building the personal baseline.

Covers Table 9.2 rows UT3 (familiarisation sessions excluded), UT4 (the median
resists an outlier) and UT5 (the scale floor prevents division by zero).
"""

from __future__ import annotations

import math

import pytest

from neurascan_engine import (
    BASELINE_SESSIONS,
    FAMILIARISATION_SESSIONS,
    Baseline,
    ScreeningEngine,
    Session,
    Status,
    median,
    median_absolute_deviation,
    robust_scale,
    status_of,
)
from neurascan_engine.constants import MAD_TO_SIGMA, SCALE_FLOOR_FRACTION

from .conftest import NOMINAL, make_session, varied_baseline_sessions


def test_the_baseline_is_four_sessions_as_decided() -> None:
    """Pinned so that changing it is deliberate, not a side effect.

    The report's simulation used six.  Four is the team's decision after trying the
    app; see the note on ``BASELINE_SESSIONS`` before changing it.
    """
    assert BASELINE_SESSIONS == 4
    assert FAMILIARISATION_SESSIONS == 2


class TestUT3FamiliarisationExcluded:
    """UT3 -- the first sessions are discarded so practice is not baked in."""

    def test_baseline_is_not_frozen_before_enough_sessions(self) -> None:
        engine = ScreeningEngine()
        for i in range(FAMILIARISATION_SESSIONS + BASELINE_SESSIONS - 1):
            result = engine.update(make_session(session_id=str(i)))
            assert status_of(result) is Status.BUILDING_BASELINE
        assert not engine.baseline_ready

    def test_baseline_freezes_after_familiarisation_plus_the_pool(self) -> None:
        """Test case TC7: two familiarisation plus four pooled sessions."""
        engine = ScreeningEngine()
        for i in range(FAMILIARISATION_SESSIONS + BASELINE_SESSIONS):
            engine.update(make_session(session_id=str(i)))
        assert engine.baseline_ready
        assert engine.baseline is not None
        assert engine.baseline.session_count == BASELINE_SESSIONS

    def test_familiarisation_values_do_not_reach_the_baseline(self) -> None:
        """A wildly different first two sessions must not move the medians."""
        engine = ScreeningEngine()
        engine.update(make_session(delayed_recall=0.10, session_id="practice-1"))
        engine.update(make_session(delayed_recall=0.10, session_id="practice-2"))
        for i in range(BASELINE_SESSIONS):
            engine.update(make_session(delayed_recall=0.80, session_id=f"real-{i}"))

        assert engine.baseline is not None
        assert engine.baseline.median["delayed_recall"] == pytest.approx(0.80)

    def test_progress_climbs_from_zero_to_one(self) -> None:
        engine = ScreeningEngine()
        engine.update(make_session())
        engine.update(make_session())
        assert engine.baseline_progress == 0.0

        seen = []
        for i in range(BASELINE_SESSIONS):
            result = engine.update(make_session(session_id=str(i)))
            seen.append(result["progress"])

        assert seen[0] == pytest.approx(1 / BASELINE_SESSIONS)
        assert seen[-1] == pytest.approx(1.0)
        assert engine.baseline_progress == 1.0

    def test_confounded_sessions_do_not_enter_the_baseline(self) -> None:
        """A tired day must not define what normal looks like."""
        engine = ScreeningEngine()
        engine.update(make_session())
        engine.update(make_session())
        for i in range(BASELINE_SESSIONS):
            engine.update(
                make_session(confounded=True, delayed_recall=0.3, session_id=str(i))
            )
        assert not engine.baseline_ready

        for i in range(BASELINE_SESSIONS):
            engine.update(make_session(delayed_recall=0.8, session_id=f"ok-{i}"))
        assert engine.baseline is not None
        assert engine.baseline.median["delayed_recall"] == pytest.approx(0.8)


class TestUT4MedianResistsOutliers:
    """UT4 -- one unusual session cannot drag the centre of the baseline."""

    def test_median_ignores_a_single_extreme_value(self) -> None:
        clean = [300.0, 310.0, 320.0, 330.0, 340.0, 350.0]
        polluted = [300.0, 310.0, 320.0, 330.0, 340.0, 5000.0]
        assert median(clean) == median(polluted) == 325.0

    def test_mean_would_have_moved_a_long_way(self) -> None:
        """Stated explicitly, because this is the reason for the design choice."""
        polluted = [300.0, 310.0, 320.0, 330.0, 340.0, 5000.0]
        mean = sum(polluted) / len(polluted)
        assert mean > 1000.0
        assert median(polluted) == 325.0

    def test_baseline_median_survives_one_bad_session(self) -> None:
        sessions = [
            make_session(reaction_median=v, session_id=str(i))
            for i, v in enumerate([300.0, 310.0, 320.0, 330.0, 340.0, 5000.0])
        ]
        baseline = Baseline.fit(sessions)
        assert baseline.median["reaction_median"] == pytest.approx(325.0)

    def test_mad_is_the_median_of_absolute_deviations(self) -> None:
        values = [1.0, 2.0, 3.0, 4.0, 100.0]
        assert median(values) == 3.0
        assert median_absolute_deviation(values) == 1.0


class TestUT5ScaleFloor:
    """UT5 -- a perfectly consistent baseline must not produce infinite z."""

    def test_identical_values_give_a_positive_scale(self) -> None:
        values = [0.75] * BASELINE_SESSIONS
        assert median_absolute_deviation(values) == 0.0
        scale = robust_scale(values)
        assert scale > 0.0
        assert scale == pytest.approx(SCALE_FLOOR_FRACTION * 0.75)

    def test_z_score_stays_finite_on_a_flat_baseline(self) -> None:
        sessions = [make_session(session_id=str(i)) for i in range(BASELINE_SESSIONS)]
        baseline = Baseline.fit(sessions)
        z = baseline.z("delayed_recall", 0.50)
        assert math.isfinite(z)
        assert z < 0.0

    def test_all_zero_feature_still_yields_a_usable_scale(self) -> None:
        """A median of zero cannot use the proportional floor."""
        scale = robust_scale([0.0] * BASELINE_SESSIONS)
        assert scale > 0.0
        assert math.isfinite(1.0 / scale)

    def test_real_spread_is_preferred_over_the_floor(self) -> None:
        """The floor must not quietly widen a baseline that has real variation."""
        values = [300.0, 310.0, 320.0, 330.0, 340.0, 350.0]
        mad = median_absolute_deviation(values)
        assert robust_scale(values) == pytest.approx(MAD_TO_SIGMA * mad)

    def test_engine_never_divides_by_zero_with_a_flat_baseline(self) -> None:
        engine = ScreeningEngine()
        engine.update(make_session())
        engine.update(make_session())
        for i in range(BASELINE_SESSIONS):
            engine.update(make_session(session_id=str(i)))

        result = engine.update(make_session(delayed_recall=0.70))
        assert math.isfinite(result["index"])
        assert math.isfinite(result["ewma"])


class TestBaselineFitting:
    """Contract checks around Baseline.fit itself."""

    def test_fit_rejects_an_empty_pool(self) -> None:
        with pytest.raises(ValueError, match="no sessions"):
            Baseline.fit([])

    def test_fit_rejects_a_session_missing_a_feature(self) -> None:
        incomplete = dict(NOMINAL)
        del incomplete["tremor_index"]
        with pytest.raises(ValueError, match="tremor_index"):
            Baseline.fit([Session(features=incomplete)] * BASELINE_SESSIONS)

    def test_baseline_round_trips_through_json(self) -> None:
        baseline = Baseline.fit(varied_baseline_sessions())
        restored = Baseline.from_json(baseline.to_json())
        assert restored.median == pytest.approx(baseline.median)
        assert restored.scale == pytest.approx(baseline.scale)
        assert restored.session_count == baseline.session_count

    def test_baseline_holds_twenty_odd_numbers(self) -> None:
        """The state is small enough to sync as one document."""
        baseline = Baseline.fit(varied_baseline_sessions())
        assert len(baseline.median) == 9
        assert len(baseline.scale) == 9
