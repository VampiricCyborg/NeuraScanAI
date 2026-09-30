"""Task-level quality gates.

A session that was not performed properly is worse than no session at all: it
enters the baseline as if it were normal behaviour, or it produces a deviation
that has nothing to do with the user's neurology.  These gates catch the failure
modes we can detect mechanically -- tapping ahead of the stimulus, saying almost
nothing during the speech task, abandoning the spiral part-way -- and mark the
session invalid so the engine ignores it entirely.

The gates deliberately do not try to detect a user who is simply not trying.
That is what the context check-in is for, and it is handled separately as a
confound rather than as invalidity.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .constants import (
    MAX_ANTICIPATIONS,
    MIN_SPIRAL_COVERAGE,
    MIN_VALID_REACTION_TRIALS,
    MIN_VOICED_SECONDS,
)


@dataclass(frozen=True)
class TaskMetrics:
    """The few raw numbers the gates need, per session.

    Everything else about the tasks -- the actual trace, the audio, the trial
    times -- has already been reduced to features by the time the gates run.
    """

    #: Taps that landed before the reaction stimulus appeared.
    anticipations: int = 0

    #: Reaction trials that produced a usable time.
    valid_reaction_trials: int = MIN_VALID_REACTION_TRIALS

    #: Seconds of voiced speech detected in the picture description.
    voiced_seconds: float = MIN_VOICED_SECONDS

    #: Share of the guide spiral covered by the trace, in 0..1.
    spiral_coverage: float = MIN_SPIRAL_COVERAGE


@dataclass(frozen=True)
class QualityReport:
    """Outcome of the gates: whether the session counts, and why not."""

    valid: bool
    failures: tuple[str, ...] = field(default=())

    def reason(self) -> str:
        """Human-readable summary, for the retry prompt shown to the user."""
        if self.valid:
            return "All tasks met the quality checks."
        return "; ".join(self.failures)


def evaluate_quality(metrics: TaskMetrics) -> QualityReport:
    """Apply every gate to *metrics* and report the combined result."""
    failures: list[str] = []

    if metrics.anticipations > MAX_ANTICIPATIONS:
        failures.append(
            f"{metrics.anticipations} taps came before the stimulus "
            f"(at most {MAX_ANTICIPATIONS} allowed)"
        )

    if metrics.valid_reaction_trials < MIN_VALID_REACTION_TRIALS:
        failures.append(
            f"only {metrics.valid_reaction_trials} usable reaction trials "
            f"(at least {MIN_VALID_REACTION_TRIALS} needed)"
        )

    if metrics.voiced_seconds < MIN_VOICED_SECONDS:
        failures.append(
            f"only {metrics.voiced_seconds:.1f} s of speech detected "
            f"(at least {MIN_VOICED_SECONDS:.0f} s needed)"
        )

    if metrics.spiral_coverage < MIN_SPIRAL_COVERAGE:
        failures.append(
            f"spiral only {metrics.spiral_coverage * 100:.0f} % traced "
            f"(at least {MIN_SPIRAL_COVERAGE * 100:.0f} % needed)"
        )

    return QualityReport(valid=not failures, failures=tuple(failures))
