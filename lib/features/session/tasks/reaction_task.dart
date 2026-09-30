/// The reaction-time step.
///
/// Ten trials. Each waits a random one to four seconds, then turns the target green;
/// the time from that change to the tap is the measurement. The wait is random on
/// purpose -- a fixed interval would let the user learn the rhythm and tap to it, which
/// produces fast, consistent numbers that measure nothing.
///
/// A tap before the change is an anticipation. Up to two are tolerated as impatience and
/// their trials discarded; a third invalidates the session, because a user tapping
/// rhythmically has stopped reacting.
///
/// Timing comes from a [Stopwatch] started in the same frame callback that paints the
/// change, not from the tap handler's own clock. What is being measured is the interval
/// between the user *seeing* green and touching the screen, so the clock has to start
/// when the frame is on the display rather than when the state was set.
library;

import 'dart:async';
import 'dart:math';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../engine/constants.dart';
import '../../../engine/extractors/reaction_extractor.dart';

/// Runs the reaction trials.
class ReactionTask extends StatefulWidget {
  const ReactionTask({
    required this.trialCount,
    required this.onTrial,
    required this.onFinished,
    this.random,
    super.key,
  });

  final int trialCount;

  /// Called once per trial, in order.
  final ValueChanged<ReactionTrial> onTrial;

  final VoidCallback onFinished;

  /// Injected in tests so the foreperiod is deterministic.
  final Random? random;

  @override
  State<ReactionTask> createState() => _ReactionTaskState();
}

enum _TrialPhase { idle, waiting, armed, tooEarly, betweenTrials }

class _ReactionTaskState extends State<ReactionTask> {
  late final Random _random = widget.random ?? Random();
  // From package:clock rather than a bare Stopwatch, so that tests driving fake time see
  // real-looking reaction times. Behaviour in the app is identical.
  final _stopwatch = clock.stopwatch();

  _TrialPhase _phase = _TrialPhase.idle;
  int _completed = 0;
  int _anticipations = 0;
  Timer? _foreperiodTimer;
  Timer? _timeoutTimer;

  @override
  void dispose() {
    _foreperiodTimer?.cancel();
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _beginTrial() {
    if (_completed >= widget.trialCount) {
      widget.onFinished();
      return;
    }

    setState(() => _phase = _TrialPhase.waiting);

    final foreperiod =
        kForeperiodMinMs + _random.nextInt(kForeperiodMaxMs - kForeperiodMinMs);
    _foreperiodTimer = Timer(Duration(milliseconds: foreperiod), _showStimulus);
  }

  void _showStimulus() {
    if (!mounted) return;
    setState(() => _phase = _TrialPhase.armed);

    // Started after the frame showing green has been rasterised, so the interval
    // measured is from the user seeing the change rather than from the state changing.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _phase != _TrialPhase.armed) return;
      _stopwatch
        ..reset()
        ..start();
    });

    // A trial the user never answers has to end by itself, or the session stalls.
    _timeoutTimer = Timer(
      const Duration(milliseconds: kMaxPlausibleReactionMs + 1500),
      () {
        if (!mounted || _phase != _TrialPhase.armed) return;
        _stopwatch.stop();
        widget.onTrial(const ReactionTrial.timedOut());
        _completeTrial();
      },
    );
  }

  void _handleTap() {
    switch (_phase) {
      case _TrialPhase.idle:
      case _TrialPhase.betweenTrials:
        _beginTrial();

      case _TrialPhase.waiting:
        // Tapped before the change.
        _foreperiodTimer?.cancel();
        _anticipations++;
        widget.onTrial(const ReactionTrial.anticipation());
        setState(() => _phase = _TrialPhase.tooEarly);
        // A pause before the next trial, so the warning is read rather than tapped
        // straight through.
        Timer(const Duration(milliseconds: 1400), () {
          if (mounted) _beginTrial();
        });

      case _TrialPhase.armed:
        _timeoutTimer?.cancel();
        _stopwatch.stop();
        widget.onTrial(ReactionTrial.responded(_stopwatch.elapsedMilliseconds));
        _completeTrial();

      case _TrialPhase.tooEarly:
        break;
    }
  }

  void _completeTrial() {
    _completed++;
    if (_completed >= widget.trialCount) {
      widget.onFinished();
      return;
    }
    setState(() => _phase = _TrialPhase.betweenTrials);
    Timer(const Duration(milliseconds: 700), () {
      if (mounted) _beginTrial();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.taskReactionTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text.taskReactionBody(widget.trialCount),
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text.taskReactionTrialProgress(_completed, widget.trialCount),
          style: context.texts.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: context.colors.primary,
          ),
        ),
        const SizedBox(height: 18),

        // The whole remaining area is the target. A small button would add aiming time
        // to every measurement, and aiming is not what the task is for.
        Expanded(
          child: GestureDetector(
            onTapDown: (_) => _handleTap(),
            behavior: HitTestBehavior.opaque,
            child: _Target(phase: _phase),
          ),
        ),

        if (_phase == _TrialPhase.tooEarly) ...[
          const SizedBox(height: 14),
          Text(
            text.taskReactionTooEarly,
            textAlign: TextAlign.center,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_anticipations > kMaxAnticipations) ...[
          const SizedBox(height: 10),
          Text(
            text.statusInvalidBody,
            textAlign: TextAlign.center,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

/// The tap target.
class _Target extends StatelessWidget {
  const _Target({required this.phase});

  final _TrialPhase phase;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;

    final (background, label) = switch (phase) {
      _TrialPhase.idle => (colors.surfaceContainerHighest, text.start),
      _TrialPhase.waiting => (
        colors.surfaceContainerHighest,
        text.taskReactionWait,
      ),
      // A saturated green, not the theme's primary: the change has to be
      // unmistakable at a glance and consistent between light and dark themes, because
      // how quickly it is noticed is part of what is being measured.
      _TrialPhase.armed => (const Color(0xFF17A34A), text.taskReactionTapNow),
      _TrialPhase.tooEarly => (colors.errorContainer, text.taskReactionWait),
      _TrialPhase.betweenTrials => (colors.surfaceContainerHighest, ''),
    };

    final onBackground = phase == _TrialPhase.armed
        ? Colors.white
        : colors.onSurfaceVariant;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(kCornerRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 132,
            height: 132,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onBackground.withValues(alpha: 0.14),
            ),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(height: 22),
            Text(
              label,
              style: context.texts.headlineSmall?.copyWith(
                color: onBackground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
