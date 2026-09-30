/// The state machine that runs one test.
///
/// A test is a plan of screens (see session_plan.dart). This walks through it, scores each
/// step the moment it finishes, and at the end gathers the steps' measurements, hands them to
/// the engine, and stores the result.
///
/// Raw data is held for as short a time as it can be. Audio goes to the feature extractor as
/// soon as the speech step ends, the touch trace as soon as the spiral does, the taps as soon
/// as the tapping step does; only the resulting numbers are kept for the rest of the test.
/// Keystroke timings are kept until the test ends, because the typing measurement needs the
/// typing from several steps, and they hold no letters. Nothing raw is ever stored.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models.dart';
import '../../engine/constants.dart';
import '../../engine/extractors/fluency_extractor.dart';
import '../../engine/extractors/memory_extractor.dart';
import '../../engine/extractors/reaction_extractor.dart';
import '../../engine/extractors/speech_extractor.dart';
import '../../engine/extractors/spiral_extractor.dart';
import '../../engine/extractors/tapping_extractor.dart';
import '../../engine/extractors/trail_extractor.dart';
import '../../engine/features.dart';
import '../../engine/quality.dart';
import '../../engine/screening_engine.dart';
import '../../services/audio_capture.dart';
import '../../services/record_audio_capture.dart';
import 'keystroke_recorder.dart';
import 'session_plan.dart';
import 'tasks/scenes.dart';
import 'word_lists.dart';

/// Where the user is in the test.
enum SessionPhase {
  /// The three-question check-in, before any step.
  checkIn,

  /// Working through the plan's screens.
  running,

  /// Scoring and storing.
  computing,

  finished,
}

/// Why a step is being asked for again.
///
/// A closed set rather than a message so the screen decides the wording and can translate it.
enum StepRetry {
  speechTooQuiet,
  spiralIncomplete,
  reactionUnusable,
  tappingTooFew,
}

/// The test's state, as the screens see it.
class SessionState {
  const SessionState({
    required this.plan,
    required this.startedAt,
    required this.wordList,
    required this.sceneIndex,
    required this.testNumber,
    required this.baselineTotal,
    required this.isPractice,
    required this.languageCode,
    this.phase = SessionPhase.checkIn,
    this.screenIndex = 0,
    this.checkIn,
    this.result,
    this.savedSessionId,
    this.recallDetail,
    this.retry,
    this.attempt = 0,
    this.error,
  });

  final TestPlan plan;
  final DateTime startedAt;

  /// The word list for this test. One word-memory step, recalled twice in a full test.
  final WordList wordList;

  /// The picture for the speech step.
  final int sceneIndex;

  /// Which test this is, counting from one, among those taken so far.
  final int testNumber;

  /// How many tests set the baseline: four with a practice run, three without.
  final int baselineTotal;

  /// True for the first baseline test, which is a practice run and does not count.
  final bool isPractice;

  /// 'en' or 'ta': the language the fluency step is scored in.
  final String languageCode;

  final SessionPhase phase;
  final int screenIndex;

  /// Null until the check-in is answered.
  final CheckIn? checkIn;

  /// Null until the engine has run.
  final SessionResult? result;

  /// Null until the test has been stored.
  final String? savedSessionId;

  /// Which words were recalled, for the summary.
  final RecallDetail? recallDetail;

  /// Set when the current step has to be done again.
  final StepRetry? retry;

  /// How many times the current screen has been reset. Used as part of the screen's key, so
  /// that a retried step starts fresh instead of keeping the state of the failed attempt.
  final int attempt;

  /// Set when something went wrong that the user has to be told about.
  final String? error;

  bool get isFinished => phase == SessionPhase.finished;
  bool get isRunning => phase == SessionPhase.running;
  bool get saving => phase == SessionPhase.computing;

  TestKind get kind => plan.kind;

  /// The screen being shown, or null outside the running phase.
  PlannedScreen? get screen =>
      isRunning && screenIndex < plan.length ? plan.screens[screenIndex] : null;

  SessionState copyWith({
    SessionPhase? phase,
    int? screenIndex,
    CheckIn? checkIn,
    SessionResult? result,
    String? savedSessionId,
    RecallDetail? recallDetail,
    StepRetry? retry,
    int? attempt,
    String? error,
    bool clearRetry = false,
    bool clearError = false,
  }) => SessionState(
    plan: plan,
    startedAt: startedAt,
    wordList: wordList,
    sceneIndex: sceneIndex,
    testNumber: testNumber,
    baselineTotal: baselineTotal,
    isPractice: isPractice,
    languageCode: languageCode,
    phase: phase ?? this.phase,
    screenIndex: screenIndex ?? this.screenIndex,
    checkIn: checkIn ?? this.checkIn,
    result: result ?? this.result,
    savedSessionId: savedSessionId ?? this.savedSessionId,
    recallDetail: recallDetail ?? this.recallDetail,
    retry: clearRetry ? null : (retry ?? this.retry),
    attempt: attempt ?? this.attempt,
    error: clearError ? null : (error ?? this.error),
  );
}

/// Runs a test and stores its result.
class SessionController extends Notifier<SessionState> {
  /// Timing of every key press in the app's own text boxes during this test.
  ///
  /// Owned here, so it cannot outlive the test and carry one test's typing into the next.
  final keystrokes = KeystrokeLog();

  // What each step produced. Only numbers, never the audio, the trace or the taps.
  RecallResult? _immediateRecall;
  RecallResult? _delayedRecall;
  ReactionResult? _reaction;
  SpeechResult? _speech;
  SpiralResult? _spiral;
  TrailResult? _trail;
  TappingResult? _tapping;
  FluencyResult? _fluency;

  /// Reaction trials of the attempt in progress. Cleared when the step is asked for again.
  final _reactionTrials = <ReactionTrial>[];

  @override
  SessionState build() {
    // Tests of the current baseline only: the list is already limited to it.
    final testsTaken = ref.read(sessionsProvider).value?.length ?? 0;
    final baselineReady =
        ref.read(engineProvider).value?.baselineReady ?? false;
    final kind = baselineReady ? TestKind.actual : TestKind.baseline;
    final profile = ref.read(profileProvider).value;
    final language = profile?.languageCode ?? 'en';
    // Only the first baseline opens with a practice test.
    final hasPractice = (profile?.baselineEpoch ?? 0) == 0;

    return SessionState(
      plan: TestPlan.of(kind),
      startedAt: DateTime.now(),
      testNumber: testsTaken + 1,
      baselineTotal: hasPractice ? kBaselineTests : kBaselineSessions,
      isPractice:
          kind == TestKind.baseline &&
          hasPractice &&
          testsTaken < kFamiliarisationSessions,
      languageCode: language,
      // The same list or picture twice in a row would be learned rather than recalled or
      // described afresh, so the choices follow the count of tests and rotate.
      wordList: pickWordListsForTest(
        testIndex: testsTaken,
        count: 1,
        languageCode: language,
      ).single,
      sceneIndex: sceneIndexFor(testsTaken),
    );
  }

  // -- step transitions -----------------------------------------------------

  /// Records the check-in and starts the first step.
  void submitCheckIn(CheckIn checkIn) {
    state = state.copyWith(
      checkIn: checkIn,
      phase: SessionPhase.running,
      screenIndex: 0,
      clearError: true,
    );
  }

  /// The user has read the words.
  void finishLearn() => _advance();

  /// Scores the recall straight after the words were shown.
  void finishImmediateRecall(List<String> typedWords) {
    _immediateRecall = scoreRecall(
      presented: state.wordList.words,
      typed: typedWords,
    );
    _advance();
  }

  /// Notes one reaction trial. The step is judged when it finishes.
  void recordReactionTrial(ReactionTrial trial) => _reactionTrials.add(trial);

  /// Judges the reaction trials, asking for the step again if they are not usable.
  ///
  /// More than two taps before the circle changed, or too few trials that gave a plausible time,
  /// mean the user was guessing or not attending, and the median would measure that.
  void finishReaction() {
    final trials = List<ReactionTrial>.of(_reactionTrials);
    _reactionTrials.clear();
    final result = extractReactionFeatures(trials);
    final quality = evaluateQuality(
      TaskMetrics(
        anticipations: result.anticipations,
        validReactionTrials: result.usableTrials,
      ),
    );
    if (!quality.valid) {
      _retry(StepRetry.reactionUnusable);
      return;
    }
    _reaction = result;
    _advance();
  }

  /// Measures the speech step from [samples], which are dropped once measured.
  ///
  /// A step that did not get enough speech is asked for again rather than counted: a quiet
  /// room or a covered microphone should cost the user twenty seconds, not the whole test.
  void finishSpeech(Float64List samples) {
    final result = extractSpeechFeatures(samples);
    final quality = evaluateQuality(
      TaskMetrics(voicedSeconds: result.voicedSeconds),
    );
    if (!quality.valid) {
      _retry(StepRetry.speechTooQuiet);
      return;
    }
    _speech = result;
    _advance();
  }

  /// Measures the precision step from [trace], which is dropped once measured.
  void finishPrecision({
    required List<TracePoint> trace,
    required GuideSpiral guide,
  }) {
    final result = extractSpiralFeatures(trace: trace, guide: guide);
    final quality = evaluateQuality(
      TaskMetrics(spiralCoverage: result.coverage),
    );
    if (!quality.valid) {
      _retry(StepRetry.spiralIncomplete);
      return;
    }
    _spiral = result;
    _advance();
  }

  /// The passive typing step has been read.
  void finishTypingNote() => _advance();

  /// Scores the trail-making step. Every circle was reached by the time this is called.
  void finishTrail({required TrailPartLog partA, required TrailPartLog partB}) {
    _trail = extractTrailFeatures(partA: partA, partB: partB);
    _advance();
  }

  /// Scores the tapping step from [taps], which are dropped once measured.
  ///
  /// Too few taps that alternated means the user hammered one button or barely tapped, and the
  /// rate and its regularity would rest on almost nothing.
  void finishTapping(List<TapEvent> taps) {
    final result = extractTappingFeatures(taps);
    final quality = evaluateQuality(TaskMetrics(validTaps: result.validTaps));
    if (!quality.valid) {
      _retry(StepRetry.tappingTooFew);
      return;
    }
    _tapping = result;
    _advance();
  }

  /// Scores the fluency step from [entries], which are dropped once scored.
  ///
  /// There is no quality gate: naming no animals is a real result, and blocking it would
  /// exclude the people the test exists to notice.
  void finishFluency(List<FluencyEntry> entries) {
    _fluency = extractFluencyFeatures(
      entries,
      languageCode: state.languageCode,
    );
    _advance();
  }

  /// Scores the closing recall, which ends the test.
  Future<void> finishRecall(List<String> typedWords) async {
    _delayedRecall = scoreRecall(
      presented: state.wordList.words,
      typed: typedWords,
    );
    state = state.copyWith(phase: SessionPhase.computing);
    await _computeAndSave();
  }

  /// Abandons the test without storing anything.
  void abandon() {
    _immediateRecall = null;
    _delayedRecall = null;
    _reaction = null;
    _speech = null;
    _spiral = null;
    _trail = null;
    _tapping = null;
    _fluency = null;
    _reactionTrials.clear();
    keystrokes.clear();
  }

  void _advance() {
    state = state.copyWith(
      screenIndex: state.screenIndex + 1,
      clearRetry: true,
      clearError: true,
    );
  }

  void _retry(StepRetry reason) {
    state = state.copyWith(retry: reason, attempt: state.attempt + 1);
  }

  // -- computation ----------------------------------------------------------

  /// The test's measurements, by feature key.
  ///
  /// A baseline test supplies the five core features. A full test supplies those and the
  /// thirteen more its extra steps produce. Typing is included only if enough key presses were
  /// timed for the rhythm to mean anything; otherwise it is left out, and the engine scores the
  /// test on the rest.
  Map<String, double> _features() {
    final recall = _delayedRecall!;
    final speech = _speech!;
    final spiral = _spiral!;

    final features = <String, double>{
      'delayed_recall': recall.fraction,
      'speaking_rate': speech.speakingRate,
      'pause_ratio': speech.pauseRatio,
      'spiral_rmse': spiral.rmse,
      'tremor_index': spiral.tremorIndex,
    };
    if (state.kind == TestKind.baseline) return features;

    final reaction = _reaction!;
    final trail = _trail!;
    final tapping = _tapping!;
    final fluency = _fluency!;
    final typing = keystrokes.extractFeatures();

    return {
      'immediate_recall': _immediateRecall!.fraction,
      'delayed_recall': features['delayed_recall']!,
      'reaction_median': reaction.medianMs,
      'reaction_cv': reaction.coefficientOfVariation,
      'speaking_rate': features['speaking_rate']!,
      'pause_ratio': features['pause_ratio']!,
      'spiral_rmse': features['spiral_rmse']!,
      'tremor_index': features['tremor_index']!,
      if (typing.hasEnoughData) ...{
        'inter_key_interval': typing.medianIntervalMs,
        'inter_key_cv': typing.coefficientOfVariation,
      },
      'completion_time': trail.completionTimeS,
      'error_count': trail.errorCount.toDouble(),
      'switch_cost': trail.switchCostS,
      'tap_rate': tapping.tapRate,
      'tap_interval_cv': tapping.intervalCv,
      'fatigue_decay': tapping.fatigueDecay,
      'valid_word_count': fluency.validWordCount.toDouble(),
      'fluency_half_ratio': fluency.halfRatio,
    };
  }

  /// Combines the steps, runs the engine and stores the result.
  Future<void> _computeAndSave() async {
    final userId = ref.read(currentUserIdProvider);
    final checkIn = state.checkIn;
    if (userId == null ||
        checkIn == null ||
        _delayedRecall == null ||
        _speech == null ||
        _spiral == null) {
      state = state.copyWith(
        phase: SessionPhase.finished,
        error: 'The test could not be saved.',
      );
      return;
    }

    final features = _features();
    final repository = ref.read(repositoryProvider);
    final engine = await repository.loadEngine(userId);

    final result = engine.update(
      EngineSession(features: features, confounded: checkIn.isConfounded),
    );

    final recall = _delayedRecall!;
    final sessionId = _generateId();
    final record = SessionRecord(
      id: sessionId,
      userId: userId,
      startedAt: state.startedAt,
      completedAt: DateTime.now(),
      checkIn: checkIn,
      features: features,
      valid: true,
      status: result.status,
      index: result.index,
      ewma: result.ewma,
      run: result.run,
      domainScores: result.domains,
      contributions: result.contributions,
      recallDetail: RecallDetail(
        listId: state.wordList.id,
        recalled: recall.matched,
        missed: recall.missed,
      ),
    );

    await repository.saveSession(session: record, engine: engine);

    // From here the test exists only as its measurements and the scores derived from them.
    abandon();

    state = state.copyWith(
      phase: SessionPhase.finished,
      result: result,
      savedSessionId: sessionId,
      recallDetail: record.recallDetail,
    );
  }

  static String _generateId() {
    final random = Random.secure();
    return List<int>.generate(
      12,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// The test in progress.
///
/// Auto-disposed, which is what guarantees that leaving a test discards its data: the
/// notifier goes with the route, and what it held goes with it.
final sessionControllerProvider =
    NotifierProvider.autoDispose<SessionController, SessionState>(
      SessionController.new,
    );

/// The real microphone. Tests override this with the simulator or a silent source.
final audioCaptureProvider = Provider<AudioCaptureService>((ref) {
  final capture = RecordAudioCapture();
  ref.onDispose(capture.dispose);
  return capture;
});
