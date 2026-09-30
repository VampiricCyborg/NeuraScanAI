"""The five behavioural features and the three domains that group them.

A feature is described by three things: which domain it belongs to, which
direction counts as worse, and what it is called.  Keeping that description in
one place means the scoring code never has to special-case a feature, and
adding a sixth feature is a one-line change here plus a weight review.

The app measures three things -- words, speech and a precision (spiral)
tracing -- and each yields one or two features.  An earlier design also had a
reaction-time task and a typing-rhythm measurement (nine features, four
domains).  Both were dropped when the tests were restructured around the three
steps, because a step in an actual test has to be something the baseline also
measured, or there is nothing to compare it with.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Domain(Enum):
    """The three behavioural domains fused into a single deviation index."""

    COGNITIVE = "cognitive"
    SPEECH = "speech"
    MOTOR = "motor"


#: Weight of each domain in the deviation index.  Cognition carries the most
#: weight because delayed recall is the best-established early signal in the
#: literature.  The report's original weights were 35 / 25 / 25 / 15 with a
#: fourth, typing domain; with that domain gone the remaining three keep their
#: relative sizes (35 : 25 : 25) and are rounded to 40 / 30 / 30.
DOMAIN_WEIGHTS: dict[Domain, float] = {
    Domain.COGNITIVE: 0.40,
    Domain.SPEECH: 0.30,
    Domain.MOTOR: 0.30,
}


class Direction(Enum):
    """Which way a feature moves when the user is doing worse."""

    #: Worse when the value rises, e.g. tracing error.
    HIGHER_IS_WORSE = "higher"
    #: Worse when the value falls, e.g. words recalled.
    LOWER_IS_WORSE = "lower"


@dataclass(frozen=True)
class FeatureSpec:
    """Static description of one behavioural feature."""

    key: str
    domain: Domain
    direction: Direction
    label: str
    unit: str = ""

    #: How much this feature typically varies from one day to the next within a
    #: single healthy person, in the feature's own units.  These are the
    #: within-person SDs from Table A.2 of the report.
    #:
    #: They are used for one thing only: to stop a baseline's spread being
    #: estimated as implausibly small.  With only a few baseline sessions the
    #: MAD can come out near zero by luck, and every ordinary day then looks like
    #: a large deviation.  A floor tied to typical variation prevents that
    #: without pulling the *centre* of anyone's baseline towards a population
    #: value -- the baseline stays personal.
    typical_day_to_day_sd: float = 0.0

    def orient(self, z: float) -> float:
        """Flip *z* if needed so that a positive result always means worse.

        The rest of the engine relies on this: once a z-score is oriented,
        ``max(0, z)`` is exactly "the part of the change that is a decline",
        with no per-feature knowledge required.
        """
        return z if self.direction is Direction.HIGHER_IS_WORSE else -z


#: The five features, in the order they are measured.
FEATURE_SPECS: tuple[FeatureSpec, ...] = (
    FeatureSpec(
        key="delayed_recall",
        typical_day_to_day_sd=0.06,
        domain=Domain.COGNITIVE,
        direction=Direction.LOWER_IS_WORSE,
        label="Delayed recall",
        unit="fraction",
    ),
    FeatureSpec(
        key="speaking_rate",
        typical_day_to_day_sd=8.0,
        domain=Domain.SPEECH,
        direction=Direction.LOWER_IS_WORSE,
        label="Speaking rate",
        unit="syllables/min",
    ),
    FeatureSpec(
        key="pause_ratio",
        typical_day_to_day_sd=0.025,
        domain=Domain.SPEECH,
        direction=Direction.HIGHER_IS_WORSE,
        label="Pause ratio",
    ),
    FeatureSpec(
        key="spiral_rmse",
        typical_day_to_day_sd=0.6,
        domain=Domain.MOTOR,
        direction=Direction.HIGHER_IS_WORSE,
        label="Spiral tracing error",
        unit="dp",
    ),
    FeatureSpec(
        key="tremor_index",
        typical_day_to_day_sd=0.012,
        domain=Domain.MOTOR,
        direction=Direction.HIGHER_IS_WORSE,
        label="Tremor index",
    ),
)

#: Lookup by feature key.
SPEC_BY_KEY: dict[str, FeatureSpec] = {spec.key: spec for spec in FEATURE_SPECS}

#: Feature keys, in measurement order.
FEATURE_KEYS: tuple[str, ...] = tuple(spec.key for spec in FEATURE_SPECS)


def specs_for(domain: Domain) -> tuple[FeatureSpec, ...]:
    """Return the features belonging to *domain*, in measurement order."""
    return tuple(spec for spec in FEATURE_SPECS if spec.domain is domain)


@dataclass
class Session:
    """One test as the engine sees it.

    The engine deals only in extracted features.  Raw touch coordinates and
    audio never reach it -- they are reduced to these five numbers on the device
    and then discarded, which is what lets the app claim that raw signals never
    leave the phone.

    An actual test repeats each measurement several times; the features here
    are the median of those repeats, so a single unusual step cannot define the
    test.
    """

    #: Feature key to value.  Missing keys make the session unusable.
    features: dict[str, float] = field(default_factory=dict)

    #: False when the test could not be scored.
    valid: bool = True

    #: True when the context check-in reported poor sleep, heavy fatigue, or
    #: illness or a medication change.  Confounded sessions are stored and
    #: shown to the user but kept out of the baseline and the trend.
    confounded: bool = False

    #: Optional identifier, carried through for storage and display.
    session_id: str | None = None

    def missing_features(self) -> tuple[str, ...]:
        """Feature keys the session does not supply."""
        return tuple(key for key in FEATURE_KEYS if key not in self.features)
