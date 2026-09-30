/// The test host.
///
/// Shows one screen at a time and nothing else: no bottom navigation, no back arrow that
/// silently discards several minutes of work. The only way out is an explicit confirmation,
/// because a test abandoned by accident costs the user the whole test and costs the trend a
/// data point.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../engine/constants.dart';
import '../checkin/checkin_step.dart';
import 'keystroke_recorder.dart';
import 'session_controller.dart';
import 'session_plan.dart';
import 'tasks/fluency_task.dart';
import 'tasks/memory_task.dart';
import 'tasks/reaction_task.dart';
import 'tasks/recall_task.dart';
import 'tasks/speech_task.dart';
import 'tasks/spiral_task.dart';
import 'tasks/tapping_task.dart';
import 'tasks/trail_task.dart';
import 'tasks/typing_note.dart';

/// Runs one test from the check-in to the stored result.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  /// Asks before discarding the test.
  Future<bool> _confirmLeave() async {
    final text = AppText.of(context);
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.sessionQuitTitle),
        content: Text(text.sessionQuitBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(text.sessionQuitStay),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(text.sessionQuitConfirm),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  /// Confirms, then discards the test and returns home.
  ///
  /// Both exits share this so that the dialog, the discard and the navigation cannot
  /// drift apart, and so the context guard after the await is written once.
  Future<void> _leaveIfConfirmed(SessionController controller) async {
    if (!await _confirmLeave()) return;
    controller.abandon();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final state = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);

    // Navigate once the test has been stored. Done in a listener rather than in build
    // so that a rebuild cannot push the summary twice.
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next.isFinished && next.savedSessionId != null && mounted) {
        context.go('${Routes.summary}?sessionId=${next.savedSessionId}');
      }
    });

    final screen = state.screen;
    final progress = screen == null
        ? 0.0
        : screen.isFinalPart
        ? 1.0
        : screen.stepNumber! / state.plan.totalSteps;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveIfConfirmed(controller);
      },
      child: Scaffold(
        appBar: AppBar(
          title: screen != null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      screen.isFinalPart
                          ? text.sessionFinalPart
                          : text.sessionProgress(
                              screen.stepNumber!,
                              state.plan.totalSteps,
                            ),
                    ),
                    Text(
                      '${_kindLabel(text, state)} · ${_stepName(text, screen)}',
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                )
              : Text(text.appName),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: text.cancel,
            onPressed: () => _leaveIfConfirmed(controller),
          ),
          bottom: screen != null
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(value: progress, minHeight: 4),
                )
              : null,
        ),
        // Every text box inside a test records its typing rhythm into this test's log.
        body: KeystrokeScope(
          log: controller.keystrokes,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(kPagePadding),
              child: _StepView(state: state, controller: controller),
            ),
          ),
        ),
      ),
    );
  }

  /// "Practice test", "Baseline test 3 of 4" or "Full test".
  static String _kindLabel(AppText text, SessionState state) {
    if (state.isPractice) return text.sessionKindPractice;
    return switch (state.kind) {
      TestKind.baseline => text.sessionKindBaseline(
        state.testNumber,
        state.baselineTotal,
      ),
      TestKind.actual => text.sessionKindActual,
    };
  }

  static String _stepName(AppText text, PlannedScreen screen) =>
      switch (screen.step) {
        StepKind.words => text.sessionStepWords,
        StepKind.reaction => text.sessionStepReaction,
        StepKind.speech => text.sessionStepSpeech,
        StepKind.precision => text.sessionStepPrecision,
        StepKind.typing => text.sessionStepTyping,
        StepKind.trail => text.sessionStepTrail,
        StepKind.tapping => text.sessionStepTapping,
        StepKind.fluency => text.sessionStepFluency,
      };
}

/// Picks the widget for the current screen.
class _StepView extends ConsumerWidget {
  const _StepView({required this.state, required this.controller});

  final SessionState state;
  final SessionController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = AppText.of(context);

    switch (state.phase) {
      case SessionPhase.checkIn:
        return CheckInStep(onSubmitted: controller.submitCheckIn);

      case SessionPhase.computing:
        return const Center(child: CircularProgressIndicator());

      case SessionPhase.finished:
        // Finished with nothing saved means something went wrong; a saved test navigates
        // away from here, so this is only ever seen on failure.
        if (state.savedSessionId == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  text.sessionInvalidBody,
                  textAlign: TextAlign.center,
                  style: context.texts.bodyMedium,
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: text.cancel,
                  onPressed: () => context.go(Routes.home),
                ),
              ],
            ),
          );
        }
        return const Center(child: CircularProgressIndicator());

      case SessionPhase.running:
        final screen = state.screen;
        if (screen == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state.retry != null) _RetryBanner(reason: state.retry!),
            Expanded(child: _screenFor(context, ref, screen)),
          ],
        );
    }
  }

  /// The widget for one screen. Keyed by position and attempt so that a step asked for
  /// again starts clean instead of inheriting the state of the attempt that failed.
  Widget _screenFor(BuildContext context, WidgetRef ref, PlannedScreen screen) {
    final key = ValueKey(
      '${screen.kind.name}-${state.screenIndex}-${state.attempt}',
    );

    return switch (screen.kind) {
      ScreenKind.learnWords => MemoryTask(
        key: key,
        wordList: state.wordList,
        onReady: controller.finishLearn,
      ),
      ScreenKind.immediateRecall => RecallTask(
        key: key,
        kind: RecallKind.immediate,
        onFinished: controller.finishImmediateRecall,
      ),
      ScreenKind.reaction => ReactionTask(
        key: key,
        trialCount: kReactionTrials,
        onTrial: controller.recordReactionTrial,
        onFinished: controller.finishReaction,
      ),
      ScreenKind.speech => SpeechTask(
        key: key,
        capture: ref.watch(audioCaptureProvider),
        sceneIndex: state.sceneIndex,
        onFinished: controller.finishSpeech,
      ),
      ScreenKind.precision => SpiralTask(
        key: key,
        onFinished: controller.finishPrecision,
      ),
      ScreenKind.typingNote => TypingNote(
        key: key,
        onContinue: controller.finishTypingNote,
      ),
      ScreenKind.trail => TrailTask(
        key: key,
        onFinished: controller.finishTrail,
      ),
      ScreenKind.tapping => TappingTask(
        key: key,
        onFinished: controller.finishTapping,
      ),
      ScreenKind.fluency => FluencyTask(
        key: key,
        onFinished: controller.finishFluency,
      ),
      ScreenKind.recallWords => RecallTask(
        key: key,
        onFinished: controller.finishRecall,
      ),
    };
  }
}

/// Explains why a step is being done again.
class _RetryBanner extends StatelessWidget {
  const _RetryBanner({required this.reason});

  final StepRetry reason;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final message = switch (reason) {
      StepRetry.speechTooQuiet => text.taskSpeechTooQuiet,
      StepRetry.spiralIncomplete => text.taskSpiralTryAgain,
      StepRetry.reactionUnusable => text.taskReactionRetry,
      StepRetry.tappingTooFew => text.taskTappingRetry,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.errorContainer,
        borderRadius: BorderRadius.circular(kCornerRadius),
      ),
      child: Text(
        message,
        style: context.texts.bodyMedium?.copyWith(
          color: context.colors.onErrorContainer,
        ),
      ),
    );
  }
}
