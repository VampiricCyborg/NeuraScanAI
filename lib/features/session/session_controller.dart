/// The state machine that runs one screening session.
///
/// A session is a fixed sequence -- check-in, word encoding, reaction, speech, spiral,
/// then delayed recall -- and the order is not cosmetic. The words are shown first and
/// asked for last so that roughly three minutes of other work sits between encoding and
/// recall; that delay is what makes it a *delayed* recall measurement rather than a test
/// of working memory. Moving the recall step earlier would change what the cognitive
/// domain measures.
///
/// The controller holds the raw task output for the length of one session and nothing
/// longer. When the session ends it extracts the nine features, hands them to the
/// engine, saves the derived result, and drops the raw data.
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models.dart';
import '../../engine/constants.dart';
import '../../engine/extractors/memory_extractor.dart';
import '../../engine/extractors/reaction_extractor.dart';
import '../../engine/extractors/speech_extractor.dart';
import '../../engine/extractors/spiral_extractor.dart';
import '../../engine/features.dart';
import '../../engine/quality.dart';
import '../../engine/screening_engine.dart';
import '../../services/audio_capture.dart';
import '../../services/record_audio_capture.dart';
import 'keystroke_recorder.dart';
import 'tasks/scenes.dart';
import 'word_lists.dart';

/// Where the user is in the session.
enum SessionStep {
  checkIn,
  memoryEncoding,
  reaction,
  speech,
  spiral,
  delayedRecall,
  computing,
  finished;

  /// Steps the user actually performs, for the progress indicator.
  static List<SessionStep> get userFacing => const [
    SessionStep.checkIn,
    SessionStep.memoryEncoding,
    SessionStep.reaction,
    SessionStep.speech,
    SessionStep.spiral,
    SessionStep.delayedRecall,
  ];

  /// One-based position among the steps the user performs.
  int get displayNumber => userFacing.indexOf(this) + 1;
}

/// The session's state, as the screens see it.
class SessionState {
  const SessionState({
    required this.step,
    required this.startedAt,
    required this.wordList,
    this.sceneIndex = 0,
    this.checkIn,
    this.result,
    this.savedSessionId,
    this.quality,
    this.recallDetail,
    this.error,
    this.saving = false,
  });

  final SessionStep step;
  final DateTime startedAt;

  /// The words shown this session.
  final WordList wordList;

  /// Which picture the speech task shows this session.
  final int sceneIndex;

  /// Null until the check-in is answered.
  final CheckIn? checkIn;

  /// Null until the engine has run.
  final SessionResult? result;

  /// Null until the session has been stored.
  final String? savedSessionId;

  /// Which gates passed, once the tasks are done.
  final QualityReport? quality;

  /// Which words were recalled, for the summary.
  final RecallDetail? recallDetail;

  /// Set when something went wrong that the user has to be told about.
  final String? error;

  final bool saving;

  bool get isFinished => step == SessionStep.finished;

  SessionState copyWith({
    SessionStep? step,
    CheckIn? checkIn,
    SessionResult? result,
    String? savedSessionId,
    QualityReport? quality,
    RecallDetail? recallDetail,
    String? error,
    bool? saving,
    bool clearError = false,
  }) => SessionState(
    step: step ?? this.step,
    startedAt: startedAt,
    wordList: wordList,
    sceneIndex: sceneIndex,
    checkIn: checkIn ?? this.checkIn,
    result: result ?? this.result,
    savedSessionId: savedSessionId ?? this.savedSessionId,
    quality: quality ?? this.quality,
    recallDetail: recallDetail ?? this.recallDetail,
    error: clearError ? null : (error ?? this.error),
    saving: saving ?? this.saving,
  );
}

/// Runs a session and stores its result.
class SessionController extends Notifier<SessionState> {
  /// Raw task output, held only for the length of this session.
  final _reactionTrials = <ReactionTrial>[];
  List<TracePoint> _spiralTrace = const [];
  GuideSpiral? _spiralGuide;
  SpeechResult? _speechResult;
  RecallResult? _recallResult;

  /// Typing timings, collected by the fields inside the session.
  final keystrokes = KeystrokeLog();

  @override
  SessionState build() {
    final sessionIndex = ref.read(sessionsProvider).value?.length ?? 0;
    return SessionState(
      step: SessionStep.checkIn,
      startedAt: DateTime.now(),
      // The same list twice in a row would be learned rather than recalled, so the
      // choice follows the session count and rotates.
      wordList: pickWordList(
        sessionIndex: sessionIndex,
        languageCode: ref.read(profileProvider).value?.languageCode ?? 'en',
      ),
      // Ten pictures, rotated by session so the user is not describing the same one twice
      // running.
      sceneIndex: sceneIndexFor(sessionIndex),
    );
  }

  // -- step transitions -----------------------------------------------------

  /// Records the check-in and moves to the first task.
  void submitCheckIn(CheckIn checkIn) {
    state = state.copyWith(
      checkIn: checkIn,
      step: SessionStep.memoryEncoding,
      clearError: true,
    );
  }

  /// The user has finished reading the words.
  void finishMemoryEncoding() {
    state = state.copyWith(step: SessionStep.reaction, clearError: true);
  }

  /// Records one reaction trial.
  void recordReactionTrial(ReactionTrial trial) => _reactionTrials.add(trial);

  /// Moves on from the reaction task.
  void finishReaction() {
    state = state.copyWith(step: SessionStep.speech, clearError: true);
  }

  /// Extracts the speech features from [samples] and drops the audio.
  ///
  /// Takes the buffer rather than reading it from the service, so that the only
  /// reference to the recording is a parameter that goes out of scope here.
  void finishSpeech(Float64List samples) {
    _speechResult = extractSpeechFeatures(samples);
    state = state.copyWith(step: SessionStep.spiral, clearError: true);
  }

  /// Records the spiral trace and moves to the recall step.
  void finishSpiral({
    required List<TracePoint> trace,
    required GuideSpiral guide,
  }) {
    _spiralTrace = trace;
    _spiralGuide = guide;
    state = state.copyWith(step: SessionStep.delayedRecall, clearError: true);
  }

  /// Scores the recall, then computes and stores the session.
  Future<void> finishRecall(List<String> typedWords) async {
    _recallResult = scoreRecall(
      presented: state.wordList.words,
      typed: typedWords,
    );
    state = state.copyWith(step: SessionStep.computing, saving: true);
    await _computeAndSave();
  }

  /// Abandons the session without storing anything.
  void abandon() {
    _reactionTrials.clear();
    _spiralTrace = const [];
    _speechResult = null;
    _recallResult = null;
    keystrokes.clear();
  }

  // -- computation ----------------------------------------------------------

  /// Extracts features, runs the engine and stores the result.
  Future<void> _computeAndSave() async {
    final userId = ref.read(currentUserIdProvider);
    final checkIn = state.checkIn;
    if (userId == null || checkIn == null) {
      state = state.copyWith(
        step: SessionStep.finished,
        saving: false,
        error: 'The session could not be saved.',
      );
      return;
    }

    final reaction = extractReactionFeatures(_reactionTrials);
    final speech = _speechResult;
    final spiral = _spiralGuide == null
        ? null
        : extractSpiralFeatures(trace: _spiralTrace, guide: _spiralGuide!);
    final typing = keystrokes.extractFeatures();
    final recall = _recallResult;

    final quality = evaluateQuality(
      TaskMetrics(
        anticipations: reaction.anticipations,
        validReactionTrials: reaction.usableTrials,
        voicedSeconds: speech?.voicedSeconds ?? 0,
        spiralCoverage: spiral?.coverage ?? 0,
      ),
    );

    // An invalid session is stored with no features rather than with the unusable
    // ones. Keeping partial features would invite a later change to start scoring
    // them.
    final features = quality.valid
        ? <String, double>{
            'delayed_recall': recall?.fraction ?? 0,
            'reaction_median': reaction.medianMs,
            'reaction_cv': reaction.coefficientOfVariation,
            'speaking_rate': speech?.speakingRate ?? 0,
            'pause_ratio': speech?.pauseRatio ?? 0,
            'spiral_rmse': spiral?.rmse ?? 0,
            'tremor_index': spiral?.tremorIndex ?? 0,
            'inter_key_interval': typing.medianIntervalMs,
            'inter_key_cv': typing.coefficientOfVariation,
          }
        : const <String, double>{};

    final repository = ref.read(repositoryProvider);
    final engine = await repository.loadEngine(userId);

    final result = engine.update(
      EngineSession(
        features: features,
        valid: quality.valid,
        confounded: checkIn.isConfounded,
      ),
    );

    final sessionId = _generateId();
    final record = SessionRecord(
      id: sessionId,
      userId: userId,
      startedAt: state.startedAt,
      completedAt: DateTime.now(),
      checkIn: checkIn,
      features: features,
      valid: quality.valid,
      status: result.status,
      invalidReasons: quality.failures,
      index: result.index,
      ewma: result.ewma,
      run: result.run,
      domainScores: result.domains,
      contributions: result.contributions,
      recallDetail: recall == null
          ? null
          : RecallDetail(
              listId: state.wordList.id,
              recalled: recall.matched,
              missed: recall.missed,
            ),
    );

    await repository.saveSession(session: record, engine: engine);

    // The raw task data is dropped here. From this point the session exists only as
    // nine numbers and the scores derived from them.
    _reactionTrials.clear();
    _spiralTrace = const [];
    _speechResult = null;
    keystrokes.clear();

    state = state.copyWith(
      step: SessionStep.finished,
      result: result,
      savedSessionId: sessionId,
      quality: quality,
      recallDetail: record.recallDetail,
      saving: false,
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

/// The session in progress.
///
/// Auto-disposed, which is what guarantees that leaving a session discards its raw
/// data: the notifier goes with the route, and the raw buffers go with it.
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

/// How many reaction trials a session runs.
const int sessionReactionTrials = kReactionTrials;
