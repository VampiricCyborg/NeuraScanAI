"""Shared fixtures and helpers for the screening-engine tests.

The helpers here build sessions from the same nominal feature values used as the
population means in the report's simulation parameters, so a "typical" session in
these tests looks like a typical session in the evaluation.
"""

from __future__ import annotations

import pytest

from neurascan_engine import BASELINE_SESSIONS, Domain, Session

#: Nominal feature values for an average user having an average day. Tests
#: perturb individual features away from these to create a targeted deviation.
NOMINAL: dict[str, float] = {
    "delayed_recall": 0.75,
    "reaction_median": 320.0,
    "reaction_cv": 0.15,
    "speaking_rate": 140.0,
    "pause_ratio": 0.22,
    "spiral_rmse": 6.0,
    "tremor_index": 0.10,
    "inter_key_interval": 260.0,
    "inter_key_cv": 0.35,
}

#: Within-person day-to-day spread of each feature, from Table A.2 of the
#: report. Used to express a perturbation in units the engine will recognise.
WITHIN_SD: dict[str, float] = {
    "delayed_recall": 0.06,
    "reaction_median": 18.0,
    "reaction_cv": 0.02,
    "speaking_rate": 8.0,
    "pause_ratio": 0.025,
    "spiral_rmse": 0.6,
    "tremor_index": 0.012,
    "inter_key_interval": 15.0,
    "inter_key_cv": 0.035,
}


def make_session(
    *,
    valid: bool = True,
    confounded: bool = False,
    session_id: str | None = None,
    jitter: dict[str, float] | None = None,
    **overrides: float,
) -> Session:
    """Build a session from the nominal values.

    ``overrides`` sets a feature to an absolute value; ``jitter`` nudges a
    feature by a number of within-person SDs, which is usually the more
    readable way to say "this user is a bit slower today".
    """
    features = dict(NOMINAL)
    if jitter:
        for key, sds in jitter.items():
            features[key] = features[key] + sds * WITHIN_SD[key]
    features.update(overrides)
    return Session(
        features=features,
        valid=valid,
        confounded=confounded,
        session_id=session_id,
    )


def varied_baseline_sessions(count: int = BASELINE_SESSIONS) -> list[Session]:
    """Sessions that differ slightly, so every feature has a non-zero spread.

    A baseline fitted from identical sessions would have a MAD of zero on every
    feature and rely entirely on the scale floor, which is not what most tests
    want to exercise.

    The default is exactly the number the engine pools.  A larger default would
    leave the extra sessions to be *scored* after the baseline froze, quietly
    giving every test an engine with history and a non-zero EWMA.

    The first four offsets are symmetric about zero, so the baseline centre is
    the nominal value whatever the pool size -- a typical session then reads as
    typical rather than as slightly off.
    """
    offsets = [-1.0, 0.5, -0.5, 1.0, -0.25, 0.25, -0.75, 0.75, 0.0, 1.25]
    sessions: list[Session] = []
    for i in range(count):
        offset = offsets[i % len(offsets)]
        sessions.append(
            make_session(
                session_id=f"baseline-{i + 1}",
                jitter={key: offset for key in WITHIN_SD},
            )
        )
    return sessions


def feed_baseline(engine, sessions: list[Session] | None = None) -> None:
    """Drive *engine* through familiarisation and baseline building.

    Sends two familiarisation sessions first, because the engine discards that
    many before it starts pooling, then the baseline sessions themselves.
    """
    engine.update(make_session(session_id="familiarisation-1"))
    engine.update(make_session(session_id="familiarisation-2"))
    for session in sessions if sessions is not None else varied_baseline_sessions():
        engine.update(session)


@pytest.fixture
def nominal() -> dict[str, float]:
    """The nominal feature values, as a fresh copy."""
    return dict(NOMINAL)


@pytest.fixture
def within_sd() -> dict[str, float]:
    """The within-person SDs, as a fresh copy."""
    return dict(WITHIN_SD)


@pytest.fixture
def all_domains() -> tuple[Domain, ...]:
    """Every domain, in declaration order."""
    return tuple(Domain)
