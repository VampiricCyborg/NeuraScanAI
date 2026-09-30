"""The stateful screening engine.

One instance tracks one user on one device. It accumulates a baseline, then for
every later session produces a deviation index, a smoothed index and a status,
holding just enough state between sessions -- the baseline, the EWMA level and
the current run length -- that the whole thing round-trips through twenty-odd
numbers.

The Dart implementation in ``lib/engine/screening_engine.dart`` mirrors this
module, and the unit tests in ``engine_lab/tests/`` are duplicated as Dart tests
so that a divergence between the two shows up as a test failure rather than as a
difference in what two users are told.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum

from .baseline import Baseline
from .constants import (
    BASELINE_SESSIONS,
    DEFAULT_PERSISTENCE,
    DEFAULT_THRESHOLD,
    EWMA_LAMBDA,
    FAMILIARISATION_SESSIONS,
    MILD_FRACTION,
)
from .features import Domain, Session
from .scoring import contributions, deviation_index, domain_scores


class Status(Enum):
    """What the engine concluded about a session.

    None of these names mention a disease, which is a hard requirement rather
    than a stylistic choice: the app is a screening and awareness tool, and the
    wording it can use is bounded by that.
    """

    #: A quality gate rejected the session; nothing was computed.
    INVALID_SESSION = "INVALID_SESSION"

    #: The baseline is not finished yet, so there is nothing to compare against.
    BUILDING_BASELINE = "BUILDING_BASELINE"

    #: The check-in reported a confound, so the session is stored but not scored
    #: into the trend.
    EXCLUDED_CONTEXT = "EXCLUDED_CONTEXT"

    #: Smoothed deviation is comfortably below the threshold.
    STABLE = "STABLE"

    #: Smoothed deviation is elevated but has not met the persistence rule.
    MILD_DEVIATION = "MILD_DEVIATION"

    #: Smoothed deviation stayed above the threshold long enough to report.
    NOTABLE_DEVIATION = "NOTABLE_DEVIATION"

    @property
    def is_scored(self) -> bool:
        """True when the status came with an index and domain scores."""
        return self in (
            Status.STABLE,
            Status.MILD_DEVIATION,
            Status.NOTABLE_DEVIATION,
        )


@dataclass
class ScreeningEngine:
    """Baseline accumulation, deviation fusion, smoothing and persistence.

    The ``use_*`` flags exist so that the engine can be run with parts of its
    design switched off. That is how the report's method comparison is
    produced: the same code path evaluates population-norm and single-session
    variants, which removes the risk of an accidental advantage from comparing
    two different implementations.
    """

    #: Smoothed level that counts as notable.
    threshold: float = DEFAULT_THRESHOLD

    #: Consecutive above-threshold sessions required before reporting.
    persistence: int = DEFAULT_PERSISTENCE

    #: When False, confounded sessions are scored like any other -- the
    #: ablation that isolates the value of the context check-in.
    use_context: bool = True

    #: When False, the raw index is used in place of its EWMA.
    use_ewma: bool = True

    #: Every scored result, oldest first, for the trend charts.
    history: list[dict] = field(default_factory=list)

    #: None until the baseline is frozen.
    baseline: Baseline | None = None

    #: Current smoothed deviation level.
    ewma: float = 0.0

    #: Consecutive scored sessions at or above the threshold.
    run: int = 0

    #: Sessions seen, including invalid ones. Counting invalid sessions here is
    #: intentional: familiarisation is about how many times the user has met the
    #: tasks, and an attempt that failed a gate still taught them the task.
    _seen: int = 0

    #: Sessions accepted into the baseline so far.
    _pool: list[Session] = field(default_factory=list)

    # -- properties ---------------------------------------------------------

    @property
    def baseline_ready(self) -> bool:
        """True once a baseline has been frozen."""
        return self.baseline is not None

    @property
    def baseline_progress(self) -> float:
        """How far the baseline is from being frozen, in 0..1."""
        if self.baseline is not None:
            return 1.0
        return min(1.0, len(self._pool) / BASELINE_SESSIONS)

    @property
    def sessions_seen(self) -> int:
        """Sessions passed to :meth:`update`, valid or not."""
        return self._seen

    # -- main entry point ---------------------------------------------------

    def update(self, session: Session) -> dict:
        """Fold *session* into the engine state and report the outcome.

        The order of the checks matters and is the heart of the design:
        invalidity beats everything, baseline building comes before scoring, and
        a confound is checked before the EWMA is touched so that a bad day
        cannot move the smoothed trend even slightly.
        """
        self._seen += 1

        if not session.valid:
            return {"status": Status.INVALID_SESSION}

        if self.baseline is None:
            return self._accumulate_baseline(session)

        if self.use_context and session.confounded:
            return {"status": Status.EXCLUDED_CONTEXT}

        return self._score(session)

    # -- internals ----------------------------------------------------------

    def _accumulate_baseline(self, session: Session) -> dict:
        """Pool *session* if it qualifies, and freeze the baseline when full."""
        usable = self._seen > FAMILIARISATION_SESSIONS and not (
            self.use_context and session.confounded
        )
        if usable:
            self._pool.append(session)

        if len(self._pool) >= BASELINE_SESSIONS:
            self.baseline = Baseline.fit(self._pool)

        return {
            "status": Status.BUILDING_BASELINE,
            "progress": len(self._pool) / BASELINE_SESSIONS,
            "collected": len(self._pool),
            "required": BASELINE_SESSIONS,
            "frozen": self.baseline is not None,
        }

    def _score(self, session: Session) -> dict:
        """Score a valid, unconfounded session against the frozen baseline."""
        assert self.baseline is not None

        scores = domain_scores(
            session.features, self.baseline.median, self.baseline.scale
        )
        index = deviation_index(scores)

        self.ewma = (
            EWMA_LAMBDA * index + (1 - EWMA_LAMBDA) * self.ewma
            if self.use_ewma
            else index
        )
        self.run = self.run + 1 if self.ewma >= self.threshold else 0

        if self.run >= self.persistence:
            status = Status.NOTABLE_DEVIATION
        elif self.ewma >= MILD_FRACTION * self.threshold:
            status = Status.MILD_DEVIATION
        else:
            status = Status.STABLE

        result = {
            "status": status,
            "index": index,
            "ewma": self.ewma,
            "run": self.run,
            "domains": scores,
            "contributions": contributions(scores),
            "sessionId": session.session_id,
        }
        self.history.append(result)
        return result

    # -- state serialisation ------------------------------------------------

    def to_json(self) -> dict[str, object]:
        """The state that must survive an app restart.

        Deliberately excludes ``history``, which lives in the local database and
        would be duplicated here, and excludes the baseline pool once the
        baseline is frozen, since the raw sessions are no longer needed.
        """
        return {
            "threshold": self.threshold,
            "persistence": self.persistence,
            "useContext": self.use_context,
            "useEwma": self.use_ewma,
            "baseline": self.baseline.to_json() if self.baseline else None,
            "ewma": self.ewma,
            "run": self.run,
            "seen": self._seen,
            "poolSize": len(self._pool),
        }


def status_of(result: dict) -> Status:
    """Read the status out of an :meth:`ScreeningEngine.update` result."""
    status = result["status"]
    assert isinstance(status, Status)
    return status


def contribution_percentages(result: dict) -> dict[Domain, int]:
    """Contributions as whole percentages that still total 100.

    Rounding each share independently can total 99 or 101, which looks like a
    bug on the report screen. The largest remainders absorb the leftover points.
    """
    shares = result.get("contributions")
    if not shares:
        return {}

    floored = {domain: int(share * 100) for domain, share in shares.items()}
    leftover = 100 - sum(floored.values())
    if leftover > 0:
        by_remainder = sorted(
            shares,
            key=lambda d: shares[d] * 100 - floored[d],
            reverse=True,
        )
        for domain in by_remainder[:leftover]:
            floored[domain] += 1
    return floored
