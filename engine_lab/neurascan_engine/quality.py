"""Step-level quality gates.

A step that was not performed properly is worse than no step at all: it enters a
baseline as if it were normal behaviour, or it produces a deviation that has
nothing to do with the user's neurology.  These gates catch the failure modes we
can detect mechanically -- saying almost nothing during the speech step,
abandoning the spiral part-way.

The gates apply to a single step, not to a whole test.  A step that fails is
simply done again, so one quiet room or one slipped finger does not throw away a
test the user has spent minutes on.  (Earlier the gates invalidated the whole
session; with eight steps to a test that would have been far too costly.)

The gates deliberately do not try to detect a user who is simply not trying.
That is what the context check-in is for, and it is handled separately as a
confound rather than as invalidity.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .constants import MIN_SPIRAL_COVERAGE, MIN_VOICED_SECONDS


@dataclass(frozen=True)
class TaskMetrics:
    """The few raw numbers the gates need, per step.

    Everything else about the steps -- the actual trace, the audio -- has
    already been reduced to features by the time the gates run.  The defaults sit
    exactly on each limit, so the default instance is the boundary case.
    """

    #: Seconds of voiced speech detected in the picture description.
    voiced_seconds: float = MIN_VOICED_SECONDS

    #: Share of the guide spiral covered by the trace, in 0..1.
    spiral_coverage: float = MIN_SPIRAL_COVERAGE


@dataclass(frozen=True)
class QualityReport:
    """Outcome of the gates: whether the step counts, and why not."""

    valid: bool
    failures: tuple[str, ...] = field(default=())

    def reason(self) -> str:
        """Human-readable summary, for the retry prompt shown to the user."""
        if self.valid:
            return "The step met the quality checks."
        return "; ".join(self.failures)


def evaluate_quality(metrics: TaskMetrics) -> QualityReport:
    """Apply every gate to *metrics* and report the combined result."""
    failures: list[str] = []

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
