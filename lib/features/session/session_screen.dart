/// The session host.
///
/// Shows one step at a time and nothing else: no bottom navigation, no back arrow that
/// silently discards four minutes of work. The only way out is an explicit confirmation,
/// because a session abandoned by accident costs the user the whole four minutes and costs
/// the trend a data point.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../checkin/checkin_step.dart';
import 'keystroke_recorder.dart';
import 'session_controller.dart';
import 'tasks/memory_task.dart';
import 'tasks/reaction_task.dart';
import 'tasks/recall_task.dart';
import 'tasks/speech_task.dart';
import 'tasks/spiral_task.dart';

/// Runs one session from the check-in to the stored result.
class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  /// Asks before discarding the session.
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

  /// Confirms, then discards the session and returns home.
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

    // Navigate once the session has been stored. Done in a listener rather than in build
    // so that a rebuild cannot push the summary twice.
    ref.listen(sessionControllerProvider, (previous, next) {
      if (next.isFinished && next.savedSessionId != null && mounted) {
        context.go('${Routes.summary}?sessionId=${next.savedSessionId}');
      }
    });

    final showProgress = SessionStep.userFacing.contains(state.step);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _leaveIfConfirmed(controller);
      },
      child: Scaffold(
        appBar: AppBar(
          title: showProgress
              ? Text(
                  text.sessionProgress(
                    state.step.displayNumber,
                    SessionStep.userFacing.length,
                  ),
                )
              : Text(text.appName),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: text.cancel,
            onPressed: () => _leaveIfConfirmed(controller),
          ),
          bottom: showProgress
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(
                    value:
                        state.step.displayNumber /
                        SessionStep.userFacing.length,
                    minHeight: 4,
                  ),
                )
              : null,
        ),
        // Every field inside a session records its typing rhythm into this session's log.
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
}

/// Picks the widget for the current step.
class _StepView extends ConsumerWidget {
  const _StepView({required this.state, required this.controller});

  final SessionState state;
  final SessionController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (state.step) {
      case SessionStep.checkIn:
        return CheckInStep(onSubmitted: controller.submitCheckIn);

      case SessionStep.memoryEncoding:
        return MemoryTask(
          wordList: state.wordList,
          onReady: controller.finishMemoryEncoding,
        );

      case SessionStep.reaction:
        return ReactionTask(
          trialCount: sessionReactionTrials,
          onTrial: controller.recordReactionTrial,
          onFinished: controller.finishReaction,
        );

      case SessionStep.speech:
        return SpeechTask(
          capture: ref.watch(audioCaptureProvider),
          onFinished: controller.finishSpeech,
        );

      case SessionStep.spiral:
        return SpiralTask(onFinished: controller.finishSpiral);

      case SessionStep.delayedRecall:
        return RecallTask(onFinished: controller.finishRecall);

      case SessionStep.computing:
      case SessionStep.finished:
        return const Center(child: CircularProgressIndicator());
    }
  }
}
