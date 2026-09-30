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
    MIN_MONITORING_SESSIONS,
    PRIOR_SCALE_FLOOR_FRACTION,
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
from neurascan_engine.features import SPEC_BY_KEY

from .conftest import NOMINAL, make_session, varied_baseline_sessions


def test_the_session_counts_are_as_decided() -> None:
    """Pinned so that changing them is deliberate, not a side effect.

    Three baseline sessions, and eight tests after it before the app gives a
    verdict.  The report's simulation used six for the baseline; see the notes on
    ``BASELINE_SESSIONS`` and ``PRIOR_SCALE_FLOOR_FRACTION`` before changing either.
    """
    assert BASELINE_SESSIONS == 3
    assert FAMILIARISATION_SESSIONS == 2
    assert MIN_MONITORING_SESSIONS == 8


def test_the_verdict_needs_more_evidence_than_the_baseline() -> None:
    """The point of separating them: the reference can be quick, the trend cannot."""
    assert MIN_MONITORING_SESSIONS > BASELINE_SESSIONS


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


class TestSmallBaselineDoesNotUnderstateVariability:
    """The safeguard that makes a three-session baseline usable.

    The MAD of three values is the smaller of two gaps, which can be tiny by luck.
    Left alone, an ordinary day then scores as a large deviation; measured on
    healthy simulated users that gave about half of them a false alert.
    """

    def test_a_lucky_tight_pair_no_longer_gives_a_tiny_scale(self) -> None:
        # Two of the three values almost coincide, so the MAD is 0.1 -- but the
        # feature's ordinary day-to-day spread is 18 ms.
        values = [320.0, 320.1, 335.0]
        typical = SPEC_BY_KEY["reaction_median"].typical_day_to_day_sd
        floor = PRIOR_SCALE_FLOOR_FRACTION * typical
        # Without the safeguard only the small proportional floor (2 % of the
        # median, 6.4 ms) stands between this baseline and a tiny scale.
        assert robust_scale(values) < floor
        assert robust_scale(values, typical) >= floor

    def test_the_floor_is_a_fraction_of_typical_variation(self) -> None:
        typical = 18.0
        assert robust_scale([300.0, 300.0, 300.0], typical) == pytest.approx(
            PRIOR_SCALE_FLOOR_FRACTION * typical
        )

    def test_a_genuinely_wide_spread_is_left_alone(self) -> None:
        # A user who really is variable keeps their own, larger scale.
        values = [200.0, 320.0, 480.0]
        typical = SPEC_BY_KEY["reaction_median"].typical_day_to_day_sd
        assert robust_scale(values, typical) == pytest.approx(robust_scale(values))

    def test_it_never_moves_the_centre(self) -> None:
        # Personal baselines stay personal: only the spread is regularised.
        sessions = [
            make_session(reaction_median=v, session_id=str(i))
            for i, v in enumerate([300.0, 300.1, 340.0])
        ]
        baseline = Baseline.fit(sessions)
        assert baseline.median["reaction_median"] == pytest.approx(300.1)

    def test_every_feature_has_a_typical_spread(self) -> None:
        for spec in SPEC_BY_KEY.values():
            assert spec.typical_day_to_day_sd > 0.0, spec.key

    def test_fit_applies_it_to_every_feature(self) -> None:
        baseline = Baseline.fit(
            [make_session(session_id=str(i)) for i in range(BASELINE_SESSIONS)]
        )
        for key, spec in SPEC_BY_KEY.items():
            assert (
                baseline.scale[key]
                >= (PRIOR_SCALE_FLOOR_FRACTION * spec.typical_day_to_day_sd) - 1e-12
            ), key

    def test_identical_sessions_no_longer_make_every_deviation_huge(self) -> None:
        # Three identical baseline sessions have a MAD of zero.  Previously the tiny
        # proportional floor then made a perfectly ordinary day look enormous.
        baseline = Baseline.fit(
            [make_session(session_id=str(i)) for i in range(BASELINE_SESSIONS)]
        )
        ordinary_day = baseline.z("reaction_median", 320.0 + 18.0)
        assert abs(ordinary_day) < 3.0
