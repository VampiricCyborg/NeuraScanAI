"""Shared fixtures and helpers for the screening-engine tests.

The helpers here build sessions from the same nominal feature values used as the
population means in the report's simulation parameters, so a "typical" session in
these tests looks like a typical session in the evaluation.

There are two kinds of session.  :func:`make_session` builds what a baseline test
produces -- the five core features.  :func:`make_full_session` builds what a full
test produces: those and the thirteen extended ones.
"""

from __future__ import annotations

import pytest

from neurascan_engine import (
    BASELINE_SESSIONS,
    CORE_FEATURE_KEYS,
    FAMILIARISATION_SESSIONS,
    Domain,
    Session,
)

#: Nominal core feature values for an average user having an average day.  Tests
#: perturb individual features away from these to create a targeted deviation.
NOMINAL_CORE: dict[str, float] = {
    "delayed_recall": 0.75,
    "speaking_rate": 140.0,
    "pause_ratio": 0.22,
    "spiral_rmse": 6.0,
    "tremor_index": 0.10,
}

#: Nominal values for the features only a full test measures.  Illustrative
#: figures for an unimpaired adult, used to exercise the engine; they are not
#: population norms and are not used by the app.
NOMINAL_EXTENDED: dict[str, float] = {
    "immediate_recall": 0.85,
    "reaction_median": 320.0,
    "reaction_cv": 0.15,
    "inter_key_interval": 260.0,
    "inter_key_cv": 0.35,
    "completion_time": 11.0,
    "error_count": 1.0,
    "switch_cost": 0.35,
    "tap_rate": 4.5,
    "tap_interval_cv": 0.10,
    "fatigue_decay": 0.08,
    "valid_word_count": 16.0,
    "fluency_half_ratio": 0.8,
}

#: Every feature's nominal value.
NOMINAL: dict[str, float] = {**NOMINAL_CORE, **NOMINAL_EXTENDED}

#: Within-person day-to-day spread of each feature.  The core and the first
#: typing and reaction figures are from Table A.2 of the report; the rest are the
#: provisional estimates in ``features.py``.  Used to express a perturbation in
#: units the engine will recognise.
WITHIN_SD: dict[str, float] = {
    "delayed_recall": 0.06,
    "speaking_rate": 8.0,
    "pause_ratio": 0.025,
    "spiral_rmse": 0.6,
    "tremor_index": 0.012,
    "immediate_recall": 0.05,
    "reaction_median": 18.0,
    "reaction_cv": 0.02,
    "inter_key_interval": 15.0,
    "inter_key_cv": 0.035,
    "completion_time": 1.5,
    "error_count": 0.8,
    "switch_cost": 0.15,
    "tap_rate": 0.25,
    "tap_interval_cv": 0.04,
    "fatigue_decay": 0.05,
    "valid_word_count": 2.0,
    "fluency_half_ratio": 0.15,
}


def make_session(
    *,
    valid: bool = True,
    confounded: bool = False,
    session_id: str | None = None,
    jitter: dict[str, float] | None = None,
    full: bool = False,
    **overrides: float,
) -> Session:
    """Build a session from the nominal values.

    By default this is a *baseline-style* session with the five core features;
    pass ``full=True`` for a full test with all eighteen.

    ``overrides`` sets a feature to an absolute value; ``jitter`` nudges a
    feature by a number of within-person SDs, which is usually the more
    readable way to say "this user is a bit slower today".
    """
    features = dict(NOMINAL if full else NOMINAL_CORE)
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


def make_full_session(**kwargs) -> Session:
    """A full test: every feature, at its nominal value unless changed."""
    return make_session(full=True, **kwargs)


def varied_baseline_sessions(count: int = BASELINE_SESSIONS) -> list[Session]:
    """Baseline-style sessions that differ slightly, so every feature has spread.

    A baseline fitted from identical sessions would have a MAD of zero on every
    feature and rely entirely on the scale floor, which is not what most tests
    want to exercise.

    The default is exactly the number the engine pools.  A larger default would
    leave the extra sessions to be *scored* after the baseline froze, quietly
    giving every test an engine with history and a non-zero EWMA.

    The first three offsets are symmetric about zero, so the baseline centre is
    the nominal value whatever the pool size -- a typical session then reads as
    typical rather than as slightly off.
    """
    offsets = [-1.0, 1.0, 0.0, 0.5, -0.5, 0.25, -0.25, 0.75, -0.75, 1.25]
    sessions: list[Session] = []
    for i in range(count):
        offset = offsets[i % len(offsets)]
        sessions.append(
            make_session(
                session_id=f"baseline-{i + 1}",
                jitter={key: offset for key in CORE_FEATURE_KEYS},
            )
        )
    return sessions


def varied_full_sessions(count: int) -> list[Session]:
    """Full tests that differ slightly, for calibrating the extended features.

    Offsets follow :func:`varied_baseline_sessions`, so the first three are
    symmetric about zero and the calibrated centre is the nominal value.
    """
    offsets = [-1.0, 1.0, 0.0, 0.5, -0.5, 0.25, -0.25, 0.75, -0.75, 1.25]
    return [
        make_full_session(
            session_id=f"full-{i + 1}",
            jitter={key: offsets[i % len(offsets)] for key in WITHIN_SD},
        )
        for i in range(count)
    ]


def feed_baseline(engine, sessions: list[Session] | None = None) -> None:
    """Drive *engine* through familiarisation and baseline building.

    Sends the practice run first, because the engine discards that many tests
    before it starts pooling, then the baseline tests themselves.
    """
    for i in range(FAMILIARISATION_SESSIONS):
        engine.update(make_session(session_id=f"familiarisation-{i + 1}"))
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
