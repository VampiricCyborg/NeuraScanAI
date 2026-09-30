/// The state machine that runs one test.
///
/// A test is a plan of screens (see session_plan.dart). This walks through it, scores each
/// step the moment it finishes, and at the end combines the repeats into one value per
/// measurement, hands that to the engine, and stores the result.
///
/// Raw data is held for as short a time as it can be. Audio goes to the feature extractor as
/// soon as the speech step ends and the touch trace as soon as the spiral does; only the
/// resulting numbers are kept for the rest of the test. Nothing raw is ever stored.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models.dart';
import '../../engine/constants.dart';
import '../../engine/extractors/memory_extractor.dart';
import '../../engine/extractors/speech_extractor.dart';
import '../../engine/extractors/spiral_extractor.dart';
import '../../engine/features.dart';
import '../../engine/quality.dart';
import '../../engine/robust_stats.dart';
import '../../engine/screening_engine.dart';
import '../../services/audio_capture.dart';
import '../../services/record_audio_capture.dart';
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
enum StepRetry { speechTooQuiet, spiralIncomplete }

/// The test's state, as the screens see it.
class SessionState {
  const SessionState({
    required this.plan,
    required this.startedAt,
    required this.wordLists,
    required this.sceneIndexes,
    required this.testNumber,
    required this.baselineTotal,
    required this.isPractice,
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

  /// The word lists for this test: one for a baseline test, three for an actual one.
  final List<WordList> wordLists;

  /// The picture for each speech step.
  final List<int> sceneIndexes;

  /// Which test this is, counting from one, among those taken so far.
  final int testNumber;

  /// How many tests set the baseline: four with a practice run, three without.
  final int baselineTotal;

  /// True for the first baseline test, which is a practice run and does not count.
  final bool isPractice;

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
    wordLists: wordLists,
    sceneIndexes: sceneIndexes,
    testNumber: testNumber,
    baselineTotal: baselineTotal,
    isPractice: isPractice,
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
  // What each step produced. Only numbers are kept, never the audio or the trace.
  final _recalls = <RecallResult>[];
  final _speech = <SpeechResult>[];
  final _spirals = <SpiralResult>[];

  @override
  SessionState build() {
    // Tests of the current baseline only: the list is already limited to it.
    final testsTaken = ref.read(sessionsProvider).value?.length ?? 0;
    final baselineReady =
        ref.read(engineProvider).value?.baselineReady ?? false;
    final kind = baselineReady ? TestKind.actual : TestKind.baseline;
    final plan = TestPlan.of(kind);
    final profile = ref.read(profileProvider).value;
    final language = profile?.languageCode ?? 'en';
    // Only the first baseline opens with a practice test.
    final hasPractice = (profile?.baselineEpoch ?? 0) == 0;

    return SessionState(
      plan: plan,
      startedAt: DateTime.now(),
      testNumber: testsTaken + 1,
      baselineTotal: hasPractice ? kBaselineTests : kBaselineSessions,
      isPractice:
          kind == TestKind.baseline &&
          hasPractice &&
          testsTaken < kFamiliarisationSessions,
      // The same list twice in a row would be learned rather than recalled, so the choices
      // follow the count of tests and rotate. Each test uses its own run of consecutive
      // lists and pictures, so an actual test does not reuse what the last one showed.
      wordLists: pickWordListsForTest(
        testIndex: testsTaken,
        count: plan.wordLists,
        languageCode: language,
      ),
      sceneIndexes: [
        for (var i = 0; i < plan.speechSteps; i++)
          sceneIndexFor(testsTaken * kActualSpeechSteps + i),
      ],
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
    _speech.add(result);
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
    _spirals.add(result);
    _advance();
  }

  /// Scores the recall of the current screen's word list.
  ///
  /// The closing recall also ends the test: it is the last screen of every plan.
  Future<void> finishRecall(List<String> typedWords) async {
    final screen = state.screen;
    if (screen == null) return;

    _recalls.add(
      scoreRecall(
        presented: state.wordLists[screen.index].words,
        typed: typedWords,
      ),
    );

    if (screen.isFinalPart || state.screenIndex + 1 >= state.plan.length) {
      state = state.copyWith(phase: SessionPhase.computing);
      await _computeAndSave();
    } else {
      _advance();
    }
  }

  /// Abandons the test without storing anything.
  void abandon() {
    _recalls.clear();
    _speech.clear();
    _spirals.clear();
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

  /// The test's value for each measurement: the median of its repeats.
  ///
  /// The median rather than the mean, for the same reason the baseline uses one: a single
  /// unusual step -- a distracted word list, a slipped finger -- should not define the test.
  Map<String, double> _aggregate() => {
    'delayed_recall': median([for (final r in _recalls) r.fraction]),
    'speaking_rate': median([for (final r in _speech) r.speakingRate]),
    'pause_ratio': median([for (final r in _speech) r.pauseRatio]),
    'spiral_rmse': median([for (final r in _spirals) r.rmse]),
    'tremor_index': median([for (final r in _spirals) r.tremorIndex]),
  };

  /// Combines the steps, runs the engine and stores the result.
  Future<void> _computeAndSave() async {
    final userId = ref.read(currentUserIdProvider);
    final checkIn = state.checkIn;
    if (userId == null ||
        checkIn == null ||
        _spirals.isEmpty ||
        _speech.isEmpty) {
      state = state.copyWith(
        phase: SessionPhase.finished,
        error: 'The test could not be saved.',
      );
      return;
    }

    final features = _aggregate();
    final repository = ref.read(repositoryProvider);
    final engine = await repository.loadEngine(userId);

    final result = engine.update(
      EngineSession(features: features, confounded: checkIn.isConfounded),
    );

    // Every list's words together, so the summary can say "19 of 24".
    final recalled = [for (final r in _recalls) ...r.matched];
    final missed = [for (final r in _recalls) ...r.missed];

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
        listId: state.wordLists.first.id,
        recalled: recalled,
        missed: missed,
      ),
    );

    await repository.saveSession(session: record, engine: engine);

    // From here the test exists only as five numbers and the scores derived from them.
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
