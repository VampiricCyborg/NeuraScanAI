"""UT1 and UT2 -- the step-level quality gates.

Covers the report's Table 9.2 rows UT1-2: the gates must reject fewer than eight
voiced seconds, a spiral traced below 70 %, more than two anticipations and too
few taps.  The gates apply to a single step -- a failed step is done again
rather than costing the user a whole test.
"""

from __future__ import annotations

from neurascan_engine import TaskMetrics, evaluate_quality
from neurascan_engine.constants import (
    MAX_ANTICIPATIONS,
    MIN_SPIRAL_COVERAGE,
    MIN_VALID_REACTION_TRIALS,
    MIN_VALID_TAPS,
    MIN_VOICED_SECONDS,
)


class TestUT1AcceptableSteps:
    """UT1 -- a step that met its requirement passes the gates."""

    def test_nominal_metrics_are_valid(self) -> None:
        report = evaluate_quality(TaskMetrics())
        assert report.valid
        assert report.failures == ()

    def test_metrics_exactly_at_the_limits_pass(self) -> None:
        """The gates are inclusive at their boundaries, and the defaults sit on them."""
        boundary = TaskMetrics()
        assert boundary.voiced_seconds == MIN_VOICED_SECONDS
        assert boundary.spiral_coverage == MIN_SPIRAL_COVERAGE
        assert evaluate_quality(boundary).valid

    def test_generous_speech_and_a_full_spiral_pass(self) -> None:
        report = evaluate_quality(TaskMetrics(voiced_seconds=18.0, spiral_coverage=1.0))
        assert report.valid


class TestUT2RejectedSteps:
    """UT2 -- each gate rejects its own failure mode."""

    def test_short_speech_is_rejected(self) -> None:
        """Test case TC5: near-silence for twenty seconds cannot be scored."""
        report = evaluate_quality(TaskMetrics(voiced_seconds=3.0))
        assert not report.valid
        assert any("speech" in f for f in report.failures)

    def test_speech_just_below_the_floor_is_rejected(self) -> None:
        report = evaluate_quality(TaskMetrics(voiced_seconds=MIN_VOICED_SECONDS - 0.1))
        assert not report.valid

    def test_partial_spiral_is_rejected(self) -> None:
        """Test case TC6: half a spiral biases the radial-error statistics."""
        report = evaluate_quality(TaskMetrics(spiral_coverage=0.50))
        assert not report.valid
        assert any("spiral" in f for f in report.failures)

    def test_a_spiral_just_below_the_gate_is_rejected(self) -> None:
        report = evaluate_quality(
            TaskMetrics(spiral_coverage=MIN_SPIRAL_COVERAGE - 0.01)
        )
        assert not report.valid

    def test_every_failure_is_reported_not_just_the_first(self) -> None:
        """The retry prompt should tell the user everything that went wrong."""
        report = evaluate_quality(TaskMetrics(voiced_seconds=1.0, spiral_coverage=0.1))
        assert not report.valid
        assert len(report.failures) == 2

    def test_reason_summarises_the_failures(self) -> None:
        report = evaluate_quality(TaskMetrics(voiced_seconds=0.0, spiral_coverage=0.2))
        assert "speech" in report.reason()
        assert "spiral" in report.reason()

    def test_reason_is_reassuring_when_valid(self) -> None:
        assert "met the quality checks" in evaluate_quality(TaskMetrics()).reason()

    def test_too_many_anticipations_are_rejected(self) -> None:
        """Test case TC4: a user guessing the stimulus is not reacting to it."""
        report = evaluate_quality(TaskMetrics(anticipations=MAX_ANTICIPATIONS + 1))
        assert not report.valid
        assert any("before the stimulus" in f for f in report.failures)

    def test_two_anticipations_are_tolerated_as_ordinary_impatience(self) -> None:
        assert evaluate_quality(TaskMetrics(anticipations=MAX_ANTICIPATIONS)).valid

    def test_too_few_usable_reaction_trials_are_rejected(self) -> None:
        report = evaluate_quality(
            TaskMetrics(valid_reaction_trials=MIN_VALID_REACTION_TRIALS - 1)
        )
        assert not report.valid
        assert any("reaction trials" in f for f in report.failures)

    def test_too_few_taps_are_rejected(self) -> None:
        report = evaluate_quality(TaskMetrics(valid_taps=MIN_VALID_TAPS - 1))
        assert not report.valid
        assert any("taps" in f for f in report.failures)

    def test_the_default_sits_exactly_on_every_limit(self) -> None:
        boundary = TaskMetrics()
        assert boundary.anticipations == MAX_ANTICIPATIONS
        assert boundary.valid_reaction_trials == MIN_VALID_REACTION_TRIALS
        assert boundary.valid_taps == MIN_VALID_TAPS
