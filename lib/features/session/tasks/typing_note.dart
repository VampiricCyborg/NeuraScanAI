/// The typing-rhythm step.
///
/// This is the one step with nothing to do. Typing rhythm is timed while the user types in the
/// app's own text boxes -- the word recalls and the fluency step -- and only the gap between
/// key presses is kept, never which keys. So that it still has its place in the eight steps, and
/// so that the user knows it is being measured, this screen says so and shows how many key
/// presses have been timed so far.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../keystroke_recorder.dart';

/// Explains the passive step and moves on when the user is ready.
class TypingNote extends StatelessWidget {
  const TypingNote({required this.onContinue, super.key});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final timed = KeystrokeScope.maybeOf(context)?.length ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text.taskTypingTitle,
                  style: context.texts.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  text.taskTypingBody,
                  style: context.texts.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Icon(
                      Icons.keyboard_outlined,
                      color: context.colors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text.taskTypingCount(timed),
                        style: context.texts.titleMedium?.copyWith(
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
          label: text.taskTypingContinue,
          icon: Icons.arrow_forward,
          onPressed: onContinue,
        ),
      ],
    );
  }
}
