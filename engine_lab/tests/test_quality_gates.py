"""UT1 and UT2 -- the task-level quality gates.

These two tests cover the report's Table 9.2 rows UT1-2: the gates must reject
more than two anticipations, fewer than eight voiced seconds, and a spiral traced
below 70 %.
"""

from __future__ import annotations

from neurascan_engine import TaskMetrics, evaluate_quality
from neurascan_engine.constants import (
    MAX_ANTICIPATIONS,
    MIN_SPIRAL_COVERAGE,
    MIN_VALID_REACTION_TRIALS,
    MIN_VOICED_SECONDS,
)


class TestUT1AcceptableSessions:
    """UT1 -- a session that met every task requirement passes the gates."""

    def test_nominal_metrics_are_valid(self) -> None:
        report = evaluate_quality(TaskMetrics())
        assert report.valid
        assert report.failures == ()

    def test_two_anticipations_are_tolerated(self) -> None:
        """Two early taps are impatience, not a broken task."""
        report = evaluate_quality(TaskMetrics(anticipations=MAX_ANTICIPATIONS))
        assert report.valid

    def test_metrics_exactly_at_the_limits_pass(self) -> None:
        """The gates are inclusive at their boundaries."""
        report = evaluate_quality(
            TaskMetrics(
                anticipations=MAX_ANTICIPATIONS,
                valid_reaction_trials=MIN_VALID_REACTION_TRIALS,
                voiced_seconds=MIN_VOICED_SECONDS,
                spiral_coverage=MIN_SPIRAL_COVERAGE,
            )
        )
        assert report.valid


class TestUT2RejectedSessions:
    """UT2 -- each gate rejects its own failure mode."""

    def test_three_anticipations_invalidate_the_session(self) -> None:
        """Test case TC4: tapping ahead three times means the user is not reacting."""
        report = evaluate_quality(TaskMetrics(anticipations=3))
        assert not report.valid
        assert any("before the stimulus" in f for f in report.failures)

    def test_short_speech_invalidates_the_session(self) -> None:
        """Test case TC5: near-silence for twenty seconds cannot be scored."""
        report = evaluate_quality(TaskMetrics(voiced_seconds=3.0))
        assert not report.valid
        assert any("speech" in f for f in report.failures)

    def test_speech_just_below_the_floor_is_rejected(self) -> None:
        report = evaluate_quality(TaskMetrics(voiced_seconds=MIN_VOICED_SECONDS - 0.1))
        assert not report.valid

    def test_partial_spiral_invalidates_the_session(self) -> None:
        """Test case TC6: half a spiral biases the radial-error statistics."""
        report = evaluate_quality(TaskMetrics(spiral_coverage=0.50))
        assert not report.valid
        assert any("spiral" in f for f in report.failures)

    def test_too_few_reaction_trials_invalidate_the_session(self) -> None:
        report = evaluate_quality(TaskMetrics(valid_reaction_trials=4))
        assert not report.valid
        assert any("reaction trials" in f for f in report.failures)

    def test_every_failure_is_reported_not_just_the_first(self) -> None:
        """The retry prompt should tell the user everything that went wrong."""
        report = evaluate_quality(
            TaskMetrics(anticipations=5, voiced_seconds=1.0, spiral_coverage=0.1)
        )
        assert not report.valid
        assert len(report.failures) == 3

    def test_reason_summarises_the_failures(self) -> None:
        report = evaluate_quality(TaskMetrics(voiced_seconds=0.0, spiral_coverage=0.2))
        assert "speech" in report.reason()
        assert "spiral" in report.reason()

    def test_reason_is_reassuring_when_valid(self) -> None:
        assert "met the quality checks" in evaluate_quality(TaskMetrics()).reason()
