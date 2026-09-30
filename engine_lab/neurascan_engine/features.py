"""The eighteen behavioural features and the four domains that group them.

A feature is described by a handful of things: which domain it belongs to, which
direction counts as worse, what it is called, and whether the baseline tests
measure it.  Keeping that description in one place means the scoring code never
has to special-case a feature, and adding a nineteenth is a one-line change here
plus a weight review.

The app has two kinds of test.  A *baseline* test has three steps -- words,
speech and a precision (spiral) tracing -- so those steps yield the five **core**
features, which get their baseline from the four baseline tests.  A full
(*actual*) test has eight steps, five of which (reaction time, typing rhythm,
trail-making, finger tapping, verbal fluency) the baseline tests never ran.  Those
thirteen **extended** features get their baseline from the user's first few full
tests instead (see :mod:`neurascan_engine.engine`); until then they are reported
as raw values and do not feed the deviation index.
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


#: Weight of each domain in the deviation index.  These are the project
#: report's weights (35 / 25 / 25 / 15).  Cognition carries the most weight
#: because delayed recall is the best-established early signal in the
#: literature; typing is passive and noisier, so it carries the least.  They
#: sum to one, and :func:`~neurascan_engine.scoring.normalised_weights`
#: re-normalises them over whichever domains have data in a given test, so a test
#: in which a domain could not be measured is not dragged towards zero by it.
DOMAIN_WEIGHTS: dict[Domain, float] = {
    Domain.COGNITIVE: 0.35,
    Domain.SPEECH: 0.25,
    Domain.MOTOR: 0.25,
    Domain.INTERACTION: 0.15,
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
    #: single healthy person, in the feature's own units.
    #:
    #: They are used for one thing only: to stop a baseline's spread being
    #: estimated as implausibly small.  With only a few baseline sessions the
    #: MAD can come out near zero by luck, and every ordinary day then looks like
    #: a large deviation.  A floor tied to typical variation prevents that
    #: without pulling the *centre* of anyone's baseline towards a population
    #: value -- the baseline stays personal.
    typical_day_to_day_sd: float = 0.0

    #: True when the baseline tests measure this feature, so its baseline comes
    #: from them.  False for the features only a full test measures.
    core: bool = False

    #: True when :attr:`typical_day_to_day_sd` is a provisional estimate rather
    #: than a figure from the report's Table A.2.  The floor it sets is a
    #: safeguard, not a finding, but it should be replaced with measured values
    #: once pilot data exists.
    provisional: bool = False

    def orient(self, z: float) -> float:
        """Flip *z* if needed so that a positive result always means worse.

        The rest of the engine relies on this: once a z-score is oriented,
        ``max(0, z)`` is exactly "the part of the change that is a decline",
        with no per-feature knowledge required.
        """
        return z if self.direction is Direction.HIGHER_IS_WORSE else -z


_LOW = Direction.LOWER_IS_WORSE
_HIGH = Direction.HIGHER_IS_WORSE

#: The eighteen features, in the order the tests measure them.
FEATURE_SPECS: tuple[FeatureSpec, ...] = (
    # 1. Word memory
    FeatureSpec(
        key="immediate_recall",
        domain=Domain.COGNITIVE,
        direction=_LOW,
        label="Immediate recall",
        unit="fraction",
        typical_day_to_day_sd=0.05,
        provisional=True,
    ),
    FeatureSpec(
        key="delayed_recall",
        domain=Domain.COGNITIVE,
        direction=_LOW,
        label="Delayed recall",
        unit="fraction",
        typical_day_to_day_sd=0.06,
        core=True,
    ),
    # 2. Reaction time
    FeatureSpec(
        key="reaction_median",
        domain=Domain.COGNITIVE,
        direction=_HIGH,
        label="Reaction time (median)",
        unit="ms",
        typical_day_to_day_sd=18.0,
    ),
    FeatureSpec(
        key="reaction_cv",
        domain=Domain.COGNITIVE,
        direction=_HIGH,
        label="Reaction consistency (CV)",
        typical_day_to_day_sd=0.02,
    ),
    # 3. Speech description
    FeatureSpec(
        key="speaking_rate",
        domain=Domain.SPEECH,
        direction=_LOW,
        label="Speaking rate",
        unit="syllables/min",
        typical_day_to_day_sd=8.0,
        core=True,
    ),
    FeatureSpec(
        key="pause_ratio",
        domain=Domain.SPEECH,
        direction=_HIGH,
        label="Pause ratio",
        typical_day_to_day_sd=0.025,
        core=True,
    ),
    # 4. Spiral tracing
    FeatureSpec(
        key="spiral_rmse",
        domain=Domain.MOTOR,
        direction=_HIGH,
        label="Spiral tracing error",
        unit="dp",
        typical_day_to_day_sd=0.6,
        core=True,
    ),
    FeatureSpec(
        key="tremor_index",
        domain=Domain.MOTOR,
        direction=_HIGH,
        label="Tremor index",
        typical_day_to_day_sd=0.012,
        core=True,
    ),
    # 5. Typing rhythm (passive)
    FeatureSpec(
        key="inter_key_interval",
        domain=Domain.INTERACTION,
        direction=_HIGH,
        label="Typing interval",
        unit="ms",
        typical_day_to_day_sd=15.0,
    ),
    FeatureSpec(
        key="inter_key_cv",
        domain=Domain.INTERACTION,
        direction=_HIGH,
        label="Typing rhythm (CV)",
        typical_day_to_day_sd=0.035,
    ),
    # 6. Trail-making lite
    FeatureSpec(
        key="completion_time",
        domain=Domain.COGNITIVE,
        direction=_HIGH,
        label="Trail-making time",
        unit="s",
        typical_day_to_day_sd=1.5,
        provisional=True,
    ),
    FeatureSpec(
        key="error_count",
        domain=Domain.COGNITIVE,
        direction=_HIGH,
        label="Trail-making errors",
        unit="taps",
        typical_day_to_day_sd=0.8,
        provisional=True,
    ),
    FeatureSpec(
        key="switch_cost",
        domain=Domain.COGNITIVE,
        direction=_HIGH,
        label="Attention-switching cost",
        unit="s/tap",
        typical_day_to_day_sd=0.15,
        provisional=True,
    ),
    # 7. Finger tapping
    FeatureSpec(
        key="tap_rate",
        domain=Domain.MOTOR,
        direction=_LOW,
        label="Tapping speed",
        unit="taps/s",
        typical_day_to_day_sd=0.25,
        provisional=True,
    ),
    FeatureSpec(
        key="tap_interval_cv",
        domain=Domain.MOTOR,
        direction=_HIGH,
        label="Tapping regularity (CV)",
        typical_day_to_day_sd=0.04,
        provisional=True,
    ),
    FeatureSpec(
        key="fatigue_decay",
        domain=Domain.MOTOR,
        direction=_HIGH,
        label="Tapping fatigue decay",
        unit="fraction",
        typical_day_to_day_sd=0.05,
        provisional=True,
    ),
    # 8. Verbal fluency
    FeatureSpec(
        key="valid_word_count",
        domain=Domain.COGNITIVE,
        direction=_LOW,
        label="Animals named",
        unit="words",
        typical_day_to_day_sd=2.0,
        provisional=True,
    ),
    FeatureSpec(
        key="fluency_half_ratio",
        domain=Domain.COGNITIVE,
        direction=_LOW,
        label="Fluency, last 15 s vs first 15 s",
        typical_day_to_day_sd=0.15,
        provisional=True,
    ),
)

#: Lookup by feature key.
SPEC_BY_KEY: dict[str, FeatureSpec] = {spec.key: spec for spec in FEATURE_SPECS}

#: Feature keys, in measurement order.
FEATURE_KEYS: tuple[str, ...] = tuple(spec.key for spec in FEATURE_SPECS)

#: The features the baseline tests measure.
CORE_FEATURE_KEYS: tuple[str, ...] = tuple(s.key for s in FEATURE_SPECS if s.core)

#: The features only a full test measures, which calibrate from full tests.
EXTENDED_FEATURE_KEYS: tuple[str, ...] = tuple(
    s.key for s in FEATURE_SPECS if not s.core
)


def specs_for(domain: Domain) -> tuple[FeatureSpec, ...]:
    """Return the features belonging to *domain*, in measurement order."""
    return tuple(spec for spec in FEATURE_SPECS if spec.domain is domain)


@dataclass
class Session:
    """One test as the engine sees it.

    The engine deals only in extracted features.  Raw touch coordinates and
    audio never reach it -- they are reduced to these numbers on the device and
    then discarded, which is what lets the app claim that raw signals never
    leave the phone.

    A baseline test supplies the core features; a full test supplies those and
    the extended ones.  A feature a test could not measure -- typing, when the
    user typed almost nothing -- is simply absent.
    """

    #: Feature key to value.  A baseline test must supply every core feature.
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
        """Core feature keys the session does not supply."""
        return tuple(key for key in CORE_FEATURE_KEYS if key not in self.features)
