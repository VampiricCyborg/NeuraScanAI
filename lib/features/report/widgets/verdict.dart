/// The small marker that says better, about the same or worse.
///
/// Colour is never the only cue. Each verdict has its own icon shape and a word, and the colours
/// are the blue-green and vermilion of the Okabe-Ito palette, which stay distinguishable to
/// people with the common kinds of colour-blindness. Worse is amber-to-vermilion rather than red:
/// one worse reading is information, not an alarm.
library;

import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../engine/comparison.dart';

/// Colour for a verdict that is a change for the better.
const Color kBetterColor = Color(0xFF009E73);

/// Colour for a verdict that is a change for the worse.
const Color kWorseColor = Color(0xFFD55E00);

/// The colour of [change] on the current theme.
Color verdictColor(BuildContext context, Change change) => switch (change) {
  Change.better => kBetterColor,
  Change.worse => kWorseColor,
  Change.similar => context.colors.onSurfaceVariant,
};

/// The icon of [change]: three different shapes, so the verdict reads without colour.
IconData verdictIcon(Change change) => switch (change) {
  Change.better => Icons.trending_up,
  Change.similar => Icons.trending_flat,
  Change.worse => Icons.trending_down,
};

/// An icon and a word, in the colour of [change].
class VerdictChip extends StatelessWidget {
  const VerdictChip({required this.change, required this.label, super.key});

  final Change change;

  /// The word: "Better", "Improved" or whatever the caller is comparing in.
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = verdictColor(context, change);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(verdictIcon(change), size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: context.texts.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A neutral marker for something that is not a verdict: not counted, not measured,
/// calibrating.
class StateChip extends StatelessWidget {
  const StateChip({required this.icon, required this.label, super.key});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = context.colors.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colors.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: context.texts.labelMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
