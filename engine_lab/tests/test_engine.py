"""UT9 through UT12 -- context gating, persistence and invalid sessions.

Covers Table 9.2 rows UT9 (a confounded session leaves the EWMA unchanged),
UT10-11 (one bad session does not alert but a sustained deviation does) and UT12
(an invalid session is ignored).
"""

from __future__ import annotations

import pytest

from neurascan_engine import (
    DEFAULT_PERSISTENCE,
    EWMA_LAMBDA,
    MILD_FRACTION,
    Domain,
    ScreeningEngine,
    Status,
    contribution_percentages,
    status_of,
)

from .conftest import feed_baseline, make_session

#: A deviation large enough to push the index above the threshold on its own.
SEVERE = {
    "delayed_recall": -9.0,
    "speaking_rate": -9.0,
    "pause_ratio": +9.0,
    "spiral_rmse": +9.0,
    "tremor_index": +9.0,
}


@pytest.fixture
def ready_engine() -> ScreeningEngine:
    """An engine with a frozen baseline, ready to score."""
    engine = ScreeningEngine()
    feed_baseline(engine)
    assert engine.baseline_ready
    return engine


class TestUT9ConfoundedSessionsAreExcluded:
    """UT9 -- a self-reported bad day must not move the smoothed trend."""

    def test_confounded_session_leaves_the_ewma_unchanged(
        self, ready_engine: ScreeningEngine
    ) -> None:
        before = ready_engine.ewma
        result = ready_engine.update(make_session(confounded=True, jitter=SEVERE))
        assert status_of(result) is Status.EXCLUDED_CONTEXT
        assert ready_engine.ewma == before

    def test_confounded_session_leaves_the_run_length_unchanged(
        self, ready_engine: ScreeningEngine
    ) -> None:
        ready_engine.update(make_session(jitter=SEVERE))
        run_before = ready_engine.run
        ready_engine.update(make_session(confounded=True))
        assert ready_engine.run == run_before

    def test_confounded_session_is_not_added_to_history(
        self, ready_engine: ScreeningEngine
    ) -> None:
        length_before = len(ready_engine.history)
        ready_engine.update(make_session(confounded=True, jitter=SEVERE))
        assert len(ready_engine.history) == length_before

    def test_confounded_result_carries_no_index(
        self, ready_engine: ScreeningEngine
    ) -> None:
        result = ready_engine.update(make_session(confounded=True))
        assert "index" not in result

    def test_tired_days_cannot_break_a_run_of_stable_sessions(
        self, ready_engine: ScreeningEngine
    ) -> None:
        """A bad day in the middle of a real decline must not reset the count."""
        ready_engine.update(make_session(jitter=SEVERE))
        ready_engine.update(make_session(jitter=SEVERE))
        ready_engine.update(make_session(confounded=True))
        result = ready_engine.update(make_session(jitter=SEVERE))
        assert status_of(result) is Status.NOTABLE_DEVIATION

    def test_gating_can_be_switched_off_for_ablation(self) -> None:
        """With use_context off, a confounded session is scored like any other."""
        engine = ScreeningEngine(use_context=False)
        feed_baseline(engine)
        before = engine.ewma
        result = engine.update(make_session(confounded=True, jitter=SEVERE))
        assert status_of(result).is_scored
        assert engine.ewma > before


class TestUT10OneBadSessionDoesNotAlert:
    """UT10 -- a single spike is not a trend."""

    def test_one_severe_session_does_not_raise_a_notable_deviation(
        self, ready_engine: ScreeningEngine
    ) -> None:
        """Test case TC8: one very poor session must not alert."""
        result = ready_engine.update(make_session(jitter=SEVERE))
        assert status_of(result) is not Status.NOTABLE_DEVIATION

    def test_two_severe_sessions_still_do_not_alert(
        self, ready_engine: ScreeningEngine
    ) -> None:
        ready_engine.update(make_session(jitter=SEVERE))
        result = ready_engine.update(make_session(jitter=SEVERE))
        assert status_of(result) is not Status.NOTABLE_DEVIATION
        assert ready_engine.run < DEFAULT_PERSISTENCE

    def test_ewma_damps_a_single_spike(self, ready_engine: ScreeningEngine) -> None:
        """One session can move the smoothed value by at most lambda of the gap."""
        result = ready_engine.update(make_session(jitter=SEVERE))
        assert result["ewma"] == pytest.approx(EWMA_LAMBDA * result["index"])
        assert result["ewma"] < result["index"]

    def test_a_spike_followed_by_recovery_returns_to_stable(
        self, ready_engine: ScreeningEngine
    ) -> None:
        ready_engine.update(make_session(jitter=SEVERE))
        for _ in range(12):
            result = ready_engine.update(make_session())
        assert status_of(result) is Status.STABLE
        assert ready_engine.run == 0

    def test_run_resets_when_the_index_falls_back(
        self, ready_engine: ScreeningEngine
    ) -> None:
        ready_engine.update(make_session(jitter=SEVERE))
        ready_engine.update(make_session(jitter=SEVERE))
        assert ready_engine.run > 0
        for _ in range(10):
            ready_engine.update(make_session())
        assert ready_engine.run == 0


class TestUT11SustainedDeviationAlerts:
    """UT11 -- a deviation that persists is reported."""

    def test_repeated_severe_sessions_eventually_alert(
        self, ready_engine: ScreeningEngine
    ) -> None:
        statuses = [
            status_of(ready_engine.update(make_session(jitter=SEVERE)))
            for _ in range(10)
        ]
        assert Status.NOTABLE_DEVIATION in statuses

    def test_alert_needs_the_full_persistence_window(
        self, ready_engine: ScreeningEngine
    ) -> None:
        """The run counter must reach the configured length, not merely rise."""
        first_alert_at = None
        for i in range(1, 15):
            result = ready_engine.update(make_session(jitter=SEVERE))
            if status_of(result) is Status.NOTABLE_DEVIATION:
                first_alert_at = i
                break
        assert first_alert_at is not None
        assert ready_engine.run >= DEFAULT_PERSISTENCE

    def test_a_shorter_persistence_window_alerts_sooner(self) -> None:
        def sessions_until_alert(persistence: int) -> int:
            engine = ScreeningEngine(persistence=persistence)
            feed_baseline(engine)
            for i in range(1, 30):
                if status_of(engine.update(make_session(jitter=SEVERE))) is (
                    Status.NOTABLE_DEVIATION
                ):
                    return i
            raise AssertionError("no alert raised")

        assert sessions_until_alert(1) < sessions_until_alert(3)
        assert sessions_until_alert(3) < sessions_until_alert(5)

    def test_a_mild_band_sits_between_stable_and_notable(
        self, ready_engine: ScreeningEngine
    ) -> None:
        seen = {
            status_of(ready_engine.update(make_session(jitter=SEVERE)))
            for _ in range(6)
        }
        assert Status.MILD_DEVIATION in seen
        assert Status.NOTABLE_DEVIATION in seen

    def test_mild_means_elevated_but_not_yet_persistent(
        self, ready_engine: ScreeningEngine
    ) -> None:
        """Mild is the band above the mild fraction with the run still short.

        It covers two situations rather than one: a smoothed value between the
        mild fraction and the threshold, and a value already over the threshold
        whose run has not yet reached the persistence length. Both are reported
        the same way to the user, because in both cases the app is saying "this
        is worth watching" rather than "this has persisted".
        """
        seen_mild = 0
        for _ in range(6):
            result = ready_engine.update(make_session(jitter=SEVERE))
            if status_of(result) is Status.MILD_DEVIATION:
                seen_mild += 1
                assert result["ewma"] >= MILD_FRACTION * ready_engine.threshold
                assert result["run"] < ready_engine.persistence
        assert seen_mild > 0, "never passed through the mild band"

    def test_a_value_below_the_mild_fraction_reads_as_stable(
        self, ready_engine: ScreeningEngine
    ) -> None:
        result = ready_engine.update(make_session())
        assert result["ewma"] < MILD_FRACTION * ready_engine.threshold
        assert status_of(result) is Status.STABLE

    def test_an_alert_explains_which_domains_contributed(
        self, ready_engine: ScreeningEngine
    ) -> None:
        cognitive_decline = {"delayed_recall": -9.0}
        for _ in range(8):
            result = ready_engine.update(make_session(jitter=cognitive_decline))
            if status_of(result) is Status.NOTABLE_DEVIATION:
                shares = result["contributions"]
                assert shares[Domain.COGNITIVE] == pytest.approx(1.0)
                assert contribution_percentages(result)[Domain.COGNITIVE] == 100
                return
        raise AssertionError("no alert raised")

    def test_percentages_always_total_one_hundred(
        self, ready_engine: ScreeningEngine
    ) -> None:
        result = ready_engine.update(
            make_session(
                jitter={
                    "delayed_recall": -5.0,
                    "pause_ratio": +3.0,
                    "tremor_index": +2.0,
                }
            )
        )
        assert sum(contribution_percentages(result).values()) == 100


class TestUT12InvalidSessionsAreIgnored:
    """UT12 -- a session that failed a gate changes nothing."""

    def test_invalid_session_returns_invalid_status(
        self, ready_engine: ScreeningEngine
    ) -> None:
        result = ready_engine.update(make_session(valid=False, jitter=SEVERE))
        assert status_of(result) is Status.INVALID_SESSION

    def test_invalid_session_leaves_the_ewma_unchanged(
        self, ready_engine: ScreeningEngine
    ) -> None:
        before = ready_engine.ewma
        ready_engine.update(make_session(valid=False, jitter=SEVERE))
        assert ready_engine.ewma == before

    def test_invalid_session_leaves_the_run_unchanged(
        self, ready_engine: ScreeningEngine
    ) -> None:
        ready_engine.update(make_session(jitter=SEVERE))
        run_before = ready_engine.run
        ready_engine.update(make_session(valid=False))
        assert ready_engine.run == run_before

    def test_invalid_session_is_not_pooled_into_the_baseline(self) -> None:
        engine = ScreeningEngine()
        engine.update(make_session())
        engine.update(make_session())
        for _ in range(6):
            engine.update(make_session(valid=False))
        assert not engine.baseline_ready

    def test_invalid_session_adds_nothing_to_history(
        self, ready_engine: ScreeningEngine
    ) -> None:
        length_before = len(ready_engine.history)
        ready_engine.update(make_session(valid=False))
        assert len(ready_engine.history) == length_before

    def test_invalid_sessions_still_count_as_familiarisation(self) -> None:
        """A failed attempt still taught the user what the task looks like."""
        engine = ScreeningEngine()
        engine.update(make_session(valid=False))
        engine.update(make_session(valid=False))
        assert engine.sessions_seen == 2
        for i in range(6):
            engine.update(make_session(session_id=str(i)))
        assert engine.baseline_ready


class TestEngineStatePersistence:
    """The engine must survive an app restart without losing its place."""

    def test_state_json_holds_the_baseline_and_smoothing_state(
        self, ready_engine: ScreeningEngine
    ) -> None:
        ready_engine.update(make_session(jitter=SEVERE))
        state = ready_engine.to_json()
        assert state["baseline"] is not None
        assert state["ewma"] == ready_engine.ewma
        assert state["run"] == ready_engine.run

    def test_state_json_excludes_history(self, ready_engine: ScreeningEngine) -> None:
        """History lives in the local database; duplicating it would drift."""
        ready_engine.update(make_session())
        assert "history" not in ready_engine.to_json()

    def test_state_before_baseline_reports_no_baseline(self) -> None:
        engine = ScreeningEngine()
        engine.update(make_session())
        assert engine.to_json()["baseline"] is None
