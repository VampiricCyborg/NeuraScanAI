/// The delayed-recall step.
///
/// The user types back the words shown at the start of the session, with about three
/// minutes of other tasks in between. That gap is what makes this a delayed recall
/// measurement, and it is why this step is last rather than second.
///
/// Words are added one at a time rather than typed into a single box. A comma-separated
/// list would be split on punctuation the user may not use consistently, and a wrong split
/// would score as a missed word -- turning a formatting difference into an apparent memory
/// failure.
///
/// This is also the screen where the typing-rhythm features get their data, which is why
/// the field is a [MeasuredTextField].
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../keystroke_recorder.dart';

/// Collects the words the user remembers.
class RecallTask extends StatefulWidget {
  const RecallTask({required this.onFinished, super.key});

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
        Text(
          text.taskRecallTitle,
          style: context.texts.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          text.taskRecallBody,
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
