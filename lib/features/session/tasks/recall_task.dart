/// The word-recall screens: immediate, straight after the words are shown, and delayed, at the
/// end of the test.
///
/// The user types back a word list. Asked straight away it measures how much was taken in;
/// asked again at the end, after the other steps, it measures how much was kept. That gap is
/// what makes the second a delayed recall measurement rather than a test of how many words can
/// be held in mind for a few seconds.
///
/// Words are added one at a time rather than typed into a single box. A comma-separated
/// list would be split on punctuation the user may not use consistently, and a wrong split
/// would score as a missed word -- turning a formatting difference into an apparent memory
/// failure.
///
/// The field is a [MeasuredTextField], so the typing here also feeds the passive typing-rhythm
/// measurement.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../keystroke_recorder.dart';

/// Which of the two recalls a [RecallTask] is.
enum RecallKind {
  /// Straight after the words were shown.
  immediate,

  /// At the end of the test, after the other steps.
  delayed,
}

/// Collects the words the user remembers.
class RecallTask extends StatefulWidget {
  const RecallTask({
    required this.onFinished,
    this.kind = RecallKind.delayed,
    this.listLabel,
    super.key,
  });

  /// Whether this is the immediate or the delayed recall. Only the wording differs.
  final RecallKind kind;

  /// A line above the title, if the test needs one. Null for none.
  final String? listLabel;

  /// Receives the words in the order they were entered.
  final ValueChanged<List<String>> onFinished;

  @override
  State<RecallTask> createState() => _RecallTaskState();
}

class _RecallTaskState extends State<RecallTask> {
  final _controller = TextEditingController();
  final _words = <String>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add() {
    final word = _controller.text.trim();
    if (word.isEmpty) return;
    setState(() {
      _words.add(word);
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.listLabel != null) ...[
          Text(
            widget.listLabel!,
            style: context.texts.labelLarge?.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
        ],
        Text(
          widget.kind == RecallKind.immediate
              ? text.taskImmediateTitle
              : text.taskRecallTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.kind == RecallKind.immediate
              ? text.taskImmediateBody
              : text.taskRecallBody,
          style: context.texts.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MeasuredTextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                // Submitting adds the word and keeps the keyboard up, so eight words
                // take eight taps of the return key rather than sixteen taps total.
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: text.taskRecallHint,
                  prefixIcon: const Icon(Icons.text_fields),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 56,
              child: FilledButton(
                // That is right for full-width buttons but throws inside a Row, which is
                // what would have shown users a red error screen on this step.
                style: FilledButton.styleFrom(minimumSize: const Size(88, 56)),
                onPressed: _add,
                child: Text(text.taskRecallAdd),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        Expanded(
          child: _words.isEmpty
              ? Center(
                  child: Text(
                    text.taskRecallNoneYet,
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var i = 0; i < _words.length; i++)
                        InputChip(
                          label: Text(_words[i]),
                          // Removable, because a user who mistypes and adds the wrong
                          // word should be able to correct it rather than have it scored
                          // as an intrusion.
                          onDeleted: () => setState(() => _words.removeAt(i)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                        ),
                    ],
                  ),
                ),
        ),

        const SizedBox(height: 12),
        PrimaryButton(
          label: text.taskRecallFinish,
          icon: Icons.check,
          // Enabled even with nothing entered. Remembering none of the words is a
          // legitimate result, and blocking it would quietly exclude the users the app
          // exists to notice.
          onPressed: () => widget.onFinished(List.unmodifiable(_words)),
        ),
      ],
    );
  }
}
