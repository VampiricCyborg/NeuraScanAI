"""The nine behavioural features and the four domains that group them.

A feature is described by three things: which domain it belongs to, which
direction counts as worse, and what it is called.  Keeping that description in
one place means the scoring code never has to special-case a feature, and
adding a tenth feature is a one-line change here plus a weight review.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum


class Domain(Enum):
    """The four behavioural domains fused into a single deviation index."""

    COGNITIVE = "cognitive"
    SPEECH = "speech"
    MOTOR = "motor"
    INTERACTION = "interaction"


#: Weight of each domain in the deviation index.  Cognition carries the most
#: weight because delayed recall is the best-established early signal in the
#: literature; interaction carries the least because passive typing is the
#: noisiest and the most confounded by what the user happens to be typing.
DOMAIN_WEIGHTS: dict[Domain, float] = {
    Domain.COGNITIVE: 0.35,
    Domain.SPEECH: 0.25,
    Domain.MOTOR: 0.25,
    Domain.INTERACTION: 0.15,
}


class Direction(Enum):
    """Which way a feature moves when the user is doing worse."""

    #: Worse when the value rises, e.g. reaction time.
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

    def orient(self, z: float) -> float:
        """Flip *z* if needed so that a positive result always means worse.

        The rest of the engine relies on this: once a z-score is oriented,
        ``max(0, z)`` is exactly "the part of the change that is a decline",
        with no per-feature knowledge required.
        """
        return z if self.direction is Direction.HIGHER_IS_WORSE else -z


#: The nine features, in the order they appear in the report.
FEATURE_SPECS: tuple[FeatureSpec, ...] = (
    FeatureSpec(
        key="delayed_recall",
        domain=Domain.COGNITIVE,
        direction=Direction.LOWER_IS_WORSE,
        label="Delayed recall",
        unit="fraction",
    ),
    FeatureSpec(
        key="reaction_median",
        domain=Domain.COGNITIVE,
        direction=Direction.HIGHER_IS_WORSE,
        label="Reaction median",
        unit="ms",
    ),
    FeatureSpec(
        key="reaction_cv",
        domain=Domain.COGNITIVE,
        direction=Direction.HIGHER_IS_WORSE,
        label="Reaction variability",
    ),
    FeatureSpec(
        key="speaking_rate",
        domain=Domain.SPEECH,
        direction=Direction.LOWER_IS_WORSE,
        label="Speaking rate",
        unit="syllables/min",
    ),
    FeatureSpec(
        key="pause_ratio",
        domain=Domain.SPEECH,
        direction=Direction.HIGHER_IS_WORSE,
        label="Pause ratio",
    ),
    FeatureSpec(
        key="spiral_rmse",
        domain=Domain.MOTOR,
        direction=Direction.HIGHER_IS_WORSE,
        label="Spiral tracing error",
        unit="dp",
    ),
    FeatureSpec(
        key="tremor_index",
        domain=Domain.MOTOR,
        direction=Direction.HIGHER_IS_WORSE,
        label="Tremor index",
    ),
    FeatureSpec(
        key="inter_key_interval",
        domain=Domain.INTERACTION,
        direction=Direction.HIGHER_IS_WORSE,
        label="Inter-key interval",
        unit="ms",
    ),
    FeatureSpec(
        key="inter_key_cv",
        domain=Domain.INTERACTION,
        direction=Direction.HIGHER_IS_WORSE,
        label="Inter-key variability",
    ),
)

#: Lookup by feature key.
SPEC_BY_KEY: dict[str, FeatureSpec] = {spec.key: spec for spec in FEATURE_SPECS}

#: Feature keys, in report order.
FEATURE_KEYS: tuple[str, ...] = tuple(spec.key for spec in FEATURE_SPECS)


def specs_for(domain: Domain) -> tuple[FeatureSpec, ...]:
    """Return the features belonging to *domain*, in report order."""
    return tuple(spec for spec in FEATURE_SPECS if spec.domain is domain)


@dataclass
class Session:
    """One screening session as the engine sees it.

    The engine deals only in extracted features.  Raw touch coordinates, audio
    and keystroke timings never reach it -- they are reduced to these nine
    numbers on the device and then discarded, which is what lets the app claim
    that raw signals never leave the phone.
    """

    #: Feature key to value.  Missing keys make the session unusable.
    features: dict[str, float] = field(default_factory=dict)

    #: False when a quality gate rejected one of the tasks.
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
