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
import '../checkin/checkin_step.dart';
import 'session_controller.dart';
import 'session_plan.dart';
import 'tasks/memory_task.dart';
import 'tasks/recall_task.dart';
import 'tasks/speech_task.dart';
import 'tasks/spiral_task.dart';

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
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(kPagePadding),
            child: _StepView(state: state, controller: controller),
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
        StepKind.speech => text.sessionStepSpeech,
        StepKind.precision => text.sessionStepPrecision,
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
    final text = AppText.of(context);
    final key = ValueKey(
      '${screen.kind.name}-${state.screenIndex}-${state.attempt}',
    );

    return switch (screen.kind) {
      ScreenKind.learnWords => MemoryTask(
        key: key,
        wordList: state.wordLists[screen.index],
        onReady: controller.finishLearn,
      ),
      ScreenKind.speech => SpeechTask(
        key: key,
        capture: ref.watch(audioCaptureProvider),
        sceneIndex: state.sceneIndexes[screen.index],
        onFinished: controller.finishSpeech,
      ),
      ScreenKind.precision => SpiralTask(
        key: key,
        onFinished: controller.finishPrecision,
      ),
      ScreenKind.recallWords => RecallTask(
        key: key,
        listLabel: state.plan.wordLists > 1
            ? text.taskRecallListLabel(screen.index + 1, state.plan.wordLists)
            : null,
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
