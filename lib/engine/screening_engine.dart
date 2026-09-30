/// The stateful screening engine.
///
/// One instance tracks one user on one device. It accumulates a baseline, then
/// for every later session produces a deviation index, a smoothed index and a
/// status, holding just enough state between sessions -- the baseline, the EWMA
/// level and the current run length -- that the whole thing round-trips through
/// twenty-odd numbers.
///
/// Mirrors `engine_lab/neurascan_engine/engine.py`. The unit tests in
/// `test/engine/` duplicate the Python suite, so a divergence between the two
/// implementations shows up as a test failure rather than as a difference in what
/// two users are told.
library;

import 'baseline.dart';
import 'constants.dart';
import 'features.dart';
import 'scoring.dart';

/// What the engine concluded about a session.
///
/// None of these names mention a disease, which is a hard requirement rather than
/// a stylistic choice: the app is a screening and awareness tool, and the wording
/// it can use is bounded by that.
enum ScreeningStatus {
  /// A quality gate rejected the session; nothing was computed.
  invalidSession('INVALID_SESSION'),

  /// The baseline is not finished yet, so there is nothing to compare against.
  buildingBaseline('BUILDING_BASELINE'),

  /// The check-in reported a confound, so the session is stored but not scored
  /// into the trend.
  excludedContext('EXCLUDED_CONTEXT'),

  /// Smoothed deviation is comfortably below the threshold.
  stable('STABLE'),

  /// Smoothed deviation is elevated but has not met the persistence rule.
  mildDeviation('MILD_DEVIATION'),

  /// Smoothed deviation stayed above the threshold long enough to report.
  notableDeviation('NOTABLE_DEVIATION');

  const ScreeningStatus(this.key);

  /// Stable identifier used in the database and in synced documents.
  final String key;

  static ScreeningStatus fromKey(String key) =>
      ScreeningStatus.values.firstWhere((status) => status.key == key);

  /// True when the status came with an index and domain scores.
  bool get isScored =>
      this == ScreeningStatus.stable ||
      this == ScreeningStatus.mildDeviation ||
      this == ScreeningStatus.notableDeviation;

  /// True when the app should encourage the user to speak to a doctor.
  ///
  /// Only the notable case does. A mild reading is informational, and saying
  /// otherwise would turn ordinary variation into alarm.
  bool get warrantsConsultation => this == ScreeningStatus.notableDeviation;
}

/// Outcome of folding one session into the engine.
///
/// A single type covers every status so that callers do not have to switch on a
/// union; the fields that only apply to a scored session are null otherwise, and
/// [isScored] says which case this is.
class SessionResult {
  const SessionResult({
    required this.status,
    this.index,
    this.ewma,
    this.run,
    this.domains,
    this.contributions,
    this.baselineProgress,
    this.baselineCollected,
    this.sessionId,
  });

  /// A session that failed a quality gate.
  const SessionResult.invalid({String? sessionId})
    : this(status: ScreeningStatus.invalidSession, sessionId: sessionId);

  /// A session pooled towards a baseline that is not yet frozen.
  const SessionResult.building({
    required double progress,
    required int collected,
    String? sessionId,
  }) : this(
         status: ScreeningStatus.buildingBaseline,
         baselineProgress: progress,
         baselineCollected: collected,
         sessionId: sessionId,
       );

  /// A session the context check-in marked as confounded.
  const SessionResult.excluded({String? sessionId})
    : this(status: ScreeningStatus.excludedContext, sessionId: sessionId);

  final ScreeningStatus status;

  /// Raw weighted deviation for this session, before smoothing.
  final double? index;

  /// Smoothed deviation after this session.
  final double? ewma;

  /// Consecutive scored sessions at or above the threshold, including this one.
  final int? run;

  /// Oriented mean z-score per domain. Negative values mean improvement.
  final Map<Domain, double>? domains;

  /// Share of [index] attributable to each domain. Sums to 1.
  final Map<Domain, double>? contributions;

  /// How far the baseline is from being frozen, in 0..1.
  final double? baselineProgress;

  /// Sessions accepted into the baseline pool so far.
  final int? baselineCollected;

  final String? sessionId;

  bool get isScored => status.isScored;

  /// Contributions as whole percentages that still total 100.
  Map<Domain, int> contributionPercent() => contributions == null
      ? const {}
      : contributionPercentages(contributions!);

  /// The domain that contributed most, or null when nothing was scored.
  Domain? get leadingDomain =>
      domains == null ? null : topContributor(domains!);

  Map<String, dynamic> toJson() => {
    'status': status.key,
    if (index != null) 'index': index,
    if (ewma != null) 'ewma': ewma,
    if (run != null) 'run': run,
    if (domains != null)
      'domains': {
        for (final entry in domains!.entries) entry.key.key: entry.value,
      },
    if (contributions != null)
      'contributions': {
        for (final entry in contributions!.entries) entry.key.key: entry.value,
      },
    if (baselineProgress != null) 'baselineProgress': baselineProgress,
    if (baselineCollected != null) 'baselineCollected': baselineCollected,
    if (sessionId != null) 'sessionId': sessionId,
  };

  factory SessionResult.fromJson(Map<String, dynamic> json) {
    Map<Domain, double>? domainMap(Object? raw) {
      if (raw == null) return null;
      return {
        for (final entry in (raw as Map).entries)
          Domain.fromKey(entry.key as String): (entry.value as num).toDouble(),
      };
    }

    return SessionResult(
      status: ScreeningStatus.fromKey(json['status'] as String),
      index: (json['index'] as num?)?.toDouble(),
      ewma: (json['ewma'] as num?)?.toDouble(),
      run: (json['run'] as num?)?.toInt(),
      domains: domainMap(json['domains']),
      contributions: domainMap(json['contributions']),
      baselineProgress: (json['baselineProgress'] as num?)?.toDouble(),
      baselineCollected: (json['baselineCollected'] as num?)?.toInt(),
      sessionId: json['sessionId'] as String?,
    );
  }
}

/// Baseline accumulation, deviation fusion, smoothing and persistence.
///
/// The `use*` flags exist so that the engine can be run with parts of its design
/// switched off. That is how the report's method comparison is produced: the same
/// code path evaluates population-norm and single-session variants, which removes
/// the risk of an accidental advantage from comparing two different
/// implementations.
class ScreeningEngine {
  ScreeningEngine({
    this.threshold = kDefaultThreshold,
    this.persistence = kDefaultPersistence,
    this.useContext = true,
    this.useEwma = true,
    Baseline? baseline,
    double ewma = 0.0,
    int run = 0,
    int seen = 0,
  }) : _baseline = baseline,
       _ewma = ewma,
       _run = run,
       _seen = seen;

  /// Smoothed level that counts as notable.
  final double threshold;

  /// Consecutive above-threshold sessions required before reporting.
  final int persistence;

  /// When false, confounded sessions are scored like any other -- the ablation
  /// that isolates the value of the context check-in.
  final bool useContext;

  /// When false, the raw index is used in place of its EWMA.
  final bool useEwma;

  Baseline? _baseline;
  double _ewma;
  int _run;

  /// Sessions seen, including invalid ones. Counting invalid sessions here is
  /// intentional: familiarisation is about how many times the user has met the
  /// tasks, and an attempt that failed a gate still taught them the task.
  int _seen;

  final List<EngineSession> _pool = [];

  /// None until the baseline is frozen.
  Baseline? get baseline => _baseline;

  /// Current smoothed deviation level.
  double get ewma => _ewma;

  /// Consecutive scored sessions at or above the threshold.
  int get run => _run;

  /// Sessions passed to [update], valid or not.
  int get sessionsSeen => _seen;

  /// True once a baseline has been frozen.
  bool get baselineReady => _baseline != null;

  /// How far the baseline is from being frozen, in 0..1.
  double get baselineProgress {
    if (_baseline != null) return 1.0;
    final progress = _pool.length / kBaselineSessions;
    return progress > 1.0 ? 1.0 : progress;
  }

  /// Sessions still needed before the baseline freezes.
  int get baselineRemaining {
    if (_baseline != null) return 0;
    return kBaselineSessions - _pool.length;
  }

  /// Folds [session] into the engine state and reports the outcome.
  ///
  /// The order of the checks matters and is the heart of the design: invalidity
  /// beats everything, baseline building comes before scoring, and a confound is
  /// checked before the EWMA is touched so that a bad day cannot move the
  /// smoothed trend even slightly.
  SessionResult update(EngineSession session) {
    _seen += 1;

    if (!session.valid) {
      return SessionResult.invalid(sessionId: session.sessionId);
    }

    if (_baseline == null) {
      return _accumulateBaseline(session);
    }

    if (useContext && session.confounded) {
      return SessionResult.excluded(sessionId: session.sessionId);
    }

    return _score(session);
  }

  SessionResult _accumulateBaseline(EngineSession session) {
    final usable =
        _seen > kFamiliarisationSessions && !(useContext && session.confounded);
    if (usable) {
      _pool.add(session);
    }

    if (_pool.length >= kBaselineSessions) {
      _baseline = Baseline.fit(_pool);
    }

    return SessionResult.building(
      progress: _pool.length / kBaselineSessions,
      collected: _pool.length,
      sessionId: session.sessionId,
    );
  }

  SessionResult _score(EngineSession session) {
    final baseline = _baseline!;
    final scores = domainScores(
      session.features,
      baseline.median,
      baseline.scale,
    );
    final index = deviationIndex(scores);

    _ewma = useEwma ? kEwmaLambda * index + (1 - kEwmaLambda) * _ewma : index;
    _run = _ewma >= threshold ? _run + 1 : 0;

    final ScreeningStatus status;
    if (_run >= persistence) {
      status = ScreeningStatus.notableDeviation;
    } else if (_ewma >= kMildFraction * threshold) {
      status = ScreeningStatus.mildDeviation;
    } else {
      status = ScreeningStatus.stable;
    }

    return SessionResult(
      status: status,
      index: index,
      ewma: _ewma,
      run: _run,
      domains: scores,
      contributions: contributions(scores),
      sessionId: session.sessionId,
    );
  }

  /// The state that must survive an app restart.
  ///
  /// Deliberately excludes the session history, which lives in the local
  /// database and would drift if duplicated here, and excludes the baseline pool
  /// once the baseline is frozen, since the raw sessions are no longer needed.
  Map<String, dynamic> toJson() => {
    'threshold': threshold,
    'persistence': persistence,
    'useContext': useContext,
    'useEwma': useEwma,
    'baseline': _baseline?.toJson(),
    'ewma': _ewma,
    'run': _run,
    'seen': _seen,
  };

  /// Restores an engine from [toJson].
  ///
  /// A baseline that has not been frozen yet cannot be restored, because the pool
  /// holds whole sessions rather than a summary. Those live in the local database
  /// and are replayed through [update] on startup instead.
  factory ScreeningEngine.fromJson(
    Map<String, dynamic> json,
  ) => ScreeningEngine(
    threshold: (json['threshold'] as num?)?.toDouble() ?? kDefaultThreshold,
    persistence: (json['persistence'] as num?)?.toInt() ?? kDefaultPersistence,
    useContext: json['useContext'] as bool? ?? true,
    useEwma: json['useEwma'] as bool? ?? true,
    baseline: json['baseline'] == null
        ? null
        : Baseline.fromJson((json['baseline'] as Map).cast<String, dynamic>()),
    ewma: (json['ewma'] as num?)?.toDouble() ?? 0.0,
    run: (json['run'] as num?)?.toInt() ?? 0,
    seen: (json['seen'] as num?)?.toInt() ?? 0,
  );
}
