/// The finger-tapping step.
///
/// Two large buttons, tapped alternately, left and right, as fast as the user can for ten
/// seconds. Only taps that alternate count (see the tapping extractor), so the screen marks
/// which button is next, and a tap on the wrong one is kept but not counted.
///
/// Both buttons react to the press, not the release: a tap that is timed when the finger lifts
/// would be late by however long the finger stayed down, and that varies from tap to tap.
///
/// Every tap is kept with its time until the step ends, then reduced to three numbers; the taps
/// themselves are not stored.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/constants.dart';
import '../../../engine/extractors/tapping_extractor.dart';

/// Runs the tapping step.
class TappingTask extends StatefulWidget {
  const TappingTask({
    required this.onFinished,
    this.seconds = kTappingSeconds,
    super.key,
  });

  /// Receives every tap. The only reference to them.
  final ValueChanged<List<TapEvent>> onFinished;

  final int seconds;

  @override
  State<TappingTask> createState() => _TappingTaskState();
}

enum _Phase { ready, running }

class _TappingTaskState extends State<TappingTask> {
  final _stopwatch = clock.stopwatch();
  final _taps = <TapEvent>[];

  _Phase _phase = _Phase.ready;
  Timer? _ticker;
  int _remainingMs = 0;

  /// The side the user should tap next: the one after the last counted tap.
  int _expectedSide = 0;

  @override
  void initState() {
    super.initState();
    _remainingMs = widget.seconds * 1000;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _start() {
    setState(() => _phase = _Phase.running);
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final remaining = widget.seconds * 1000 - _stopwatch.elapsedMilliseconds;
      if (remaining <= 0) {
        timer.cancel();
        _finish();
      } else {
        setState(() => _remainingMs = remaining);
      }
    });
  }

  void _tap(int side) {
    if (_phase != _Phase.running) return;
    final elapsed = _stopwatch.elapsedMilliseconds;
    if (elapsed > widget.seconds * 1000) return;
    _taps.add(TapEvent(timestampMs: elapsed, side: side));
    if (side == _expectedSide) {
      setState(() => _expectedSide = 1 - _expectedSide);
    }
  }

  void _finish() {
    _stopwatch.stop();
    widget.onFinished(List.unmodifiable(_taps));
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final running = _phase == _Phase.running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.taskTappingTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text.taskTappingBody(widget.seconds),
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: running ? 1 - _remainingMs / (widget.seconds * 1000) : 0,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _TapButton(
                  key: const ValueKey('tap-left'),
                  label: text.taskTappingLeft,
                  next: running && _expectedSide == 0,
                  enabled: running,
                  onTap: () => _tap(0),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _TapButton(
                  key: const ValueKey('tap-right'),
                  label: text.taskTappingRight,
                  next: running && _expectedSide == 1,
                  enabled: running,
                  onTap: () => _tap(1),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),
        if (!running)
          PrimaryButton(
            label: text.start,
            icon: Icons.play_arrow_rounded,
            onPressed: _start,
          )
        else
          // Keeps the layout the same height once the step is running.
          const SizedBox(height: 52),
      ],
    );
  }
}

/// One of the two big buttons.
class _TapButton extends StatelessWidget {
  const _TapButton({
    required this.label,
    required this.next,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final String label;

  /// True for the button the user should tap next.
  final bool next;

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final background = !enabled
        ? colors.surfaceContainerHighest
        : next
        ? colors.primary
        : colors.primaryContainer;
    final foreground = !enabled
        ? colors.onSurfaceVariant
        : next
        ? colors.onPrimary
        : colors.onPrimaryContainer;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => onTap() : null,
        child: Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(kCornerRadius),
            // A shape cue as well as a colour one: the next button has a thick outline.
            border: Border.all(
              color: next ? colors.primary : colors.outlineVariant,
              width: next ? 4 : 1,
            ),
          ),
          alignment: Alignment.center,
          child: ExcludeSemantics(
            child: Text(
              label,
              style: context.texts.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
