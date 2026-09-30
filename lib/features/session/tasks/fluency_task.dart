/// The verbal-fluency step.
///
/// The user types as many animals as they can in thirty seconds, adding each with the Add button
/// or the keyboard's return key. It is typed, not spoken, because the app has no speech
/// recognition and never sends anything off the phone; the typed words are checked against a
/// built-in animal list by the fluency extractor, and only two numbers are kept.
///
/// Nothing on screen says whether an entry counted. Feedback would change what people do (they
/// would stop trying words that got no tick), and the step is meant to measure retrieval, not
/// to be played. The entries are shown so the user can see what they have entered.
///
/// The field is a [MeasuredTextField], so this step also feeds the passive typing-rhythm
/// measurement.
library;

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/constants.dart';
import '../../../engine/extractors/fluency_extractor.dart';
import '../keystroke_recorder.dart';

/// Runs the fluency step.
class FluencyTask extends StatefulWidget {
  const FluencyTask({
    required this.onFinished,
    this.seconds = kFluencySeconds,
    super.key,
  });

  /// Receives every entry with its time. The only reference to them.
  final ValueChanged<List<FluencyEntry>> onFinished;

  final int seconds;

  @override
  State<FluencyTask> createState() => _FluencyTaskState();
}

enum _Phase { ready, running }

class _FluencyTaskState extends State<FluencyTask> {
  final _controller = TextEditingController();
  final _stopwatch = clock.stopwatch();
  final _entries = <FluencyEntry>[];

  _Phase _phase = _Phase.ready;
  Timer? _ticker;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _remaining = widget.seconds;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    setState(() => _phase = _Phase.running);
    _stopwatch
      ..reset()
      ..start();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        _finish();
      }
    });
  }

  void _add() {
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    setState(() {
      _entries.add(
        FluencyEntry(text: word, timestampMs: _stopwatch.elapsedMilliseconds),
      );
      _controller.clear();
    });
  }

  void _finish() {
    // Whatever was typed but not yet added is added, stamped at the end: the user was in the
    // middle of a word when time ran out, and it should not be lost.
    final pending = _controller.text.trim();
    if (pending.isNotEmpty) {
      _entries.add(
        FluencyEntry(
          text: pending,
          timestampMs: _stopwatch.elapsedMilliseconds.clamp(
            0,
            widget.seconds * 1000,
          ),
        ),
      );
    }
    _stopwatch.stop();
    widget.onFinished(List.unmodifiable(_entries));
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final running = _phase == _Phase.running;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          text.taskFluencyTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text.taskFluencyBody(widget.seconds),
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),

        if (running) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  text.taskFluencyCount(_entries.length),
                  style: context.texts.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: context.colors.primary,
                  ),
                ),
              ),
              Text(
                text.taskFluencyTimeLeft(_remaining),
                style: context.texts.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: 1 - _remaining / widget.seconds,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MeasuredTextField(
                  controller: _controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  // Adding keeps the keyboard up, so a run of animals is a run of returns.
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    hintText: text.taskFluencyHint,
                    prefixIcon: const Icon(Icons.pets_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 56,
                child: FilledButton(
                  // The theme's minimum width is infinite, which throws inside a Row.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 56),
                  ),
                  onPressed: _add,
                  child: Text(text.taskRecallAdd),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],

        Expanded(
          child: running
              ? SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in _entries)
                        Chip(label: Text(entry.text)),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),

        if (!running) ...[
          const SizedBox(height: 16),
          PrimaryButton(
            label: text.start,
            icon: Icons.play_arrow_rounded,
            onPressed: _start,
          ),
        ],
      ],
    );
  }
}
