/// The word-encoding step.
///
/// Shows eight words and lets the user say when they have them. There is no timer: a
/// forced encoding window would measure reading speed as much as memory, and a user who
/// needs longer to read the list is not the same as a user who cannot remember it.
///
/// What is timed is the gap before recall, which the session's task order guarantees.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../word_lists.dart';

/// Presents the words to remember.
class MemoryTask extends StatelessWidget {
  const MemoryTask({required this.wordList, required this.onReady, super.key});

  final WordList wordList;
  final VoidCallback onReady;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.taskMemoryTitle,
                  style: context.texts.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  text.taskMemoryBody,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                // A grid rather than a list: a vertical list invites the user to learn
                // the words as an ordered sequence, and recall is scored without regard
                // to order.
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 2.4,
                  children: [
                    for (final word in wordList.words)
                      Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: context.colors.primaryContainer,
                          borderRadius: BorderRadius.circular(kCornerRadius),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          word,
                          textAlign: TextAlign.center,
                          style: context.texts.titleMedium?.copyWith(
                            color: context.colors.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        PrimaryButton(
          label: text.taskMemoryReady,
          icon: Icons.check,
          onPressed: onReady,
        ),
      ],
    );
  }
}
