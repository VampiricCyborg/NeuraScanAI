/// Widgets shared across screens.
///
/// These exist mostly to make two things impossible to get wrong by accident. The
/// disclaimer is one widget, so it reads identically everywhere and cannot be
/// softened on one screen. Domain labels and colours come from one place, so the
/// colour meaning "speech" on the report is the same colour on the trend chart.
library;

import 'package:flutter/material.dart';

import '../engine/features.dart';
import '../engine/scoring.dart';
import '../engine/screening_engine.dart';
import 'l10n/generated/app_localizations.dart';
import 'theme.dart';

/// The localised name of a domain.
///
/// The engine's own labels are in English and intended for the report and the
/// source; this is what a user sees.
String domainLabel(AppText text, Domain domain) => switch (domain) {
  Domain.cognitive => text.domainCognitive,
  Domain.speech => text.domainSpeech,
  Domain.motor => text.domainMotor,
  Domain.interaction => text.domainInteraction,
};

/// The localised name of a feature.
String featureLabel(AppText text, String featureKey) => switch (featureKey) {
  'delayed_recall' => text.featureDelayedRecall,
  'reaction_median' => text.featureReactionMedian,
  'reaction_cv' => text.featureReactionCv,
  'speaking_rate' => text.featureSpeakingRate,
  'pause_ratio' => text.featurePauseRatio,
  'spiral_rmse' => text.featureSpiralRmse,
  'tremor_index' => text.featureTremorIndex,
  'inter_key_interval' => text.featureInterKeyInterval,
  'inter_key_cv' => text.featureInterKeyCv,
  _ => featureKey,
};

/// The localised heading for a status.
String statusHeadline(AppText text, ScreeningStatus status) => switch (status) {
  ScreeningStatus.stable => text.statusStable,
  ScreeningStatus.mildDeviation => text.statusMild,
  ScreeningStatus.notableDeviation => text.statusNotable,
  ScreeningStatus.buildingBaseline => text.statusBuilding,
  ScreeningStatus.excludedContext => text.statusExcluded,
  ScreeningStatus.invalidSession => text.statusInvalid,
};

/// The standing "not a diagnosis" note.
///
/// One widget rather than a string used in several places, so that the wording
/// cannot drift and cannot quietly be left off a screen that shows a result.
class NotADiagnosisNote extends StatelessWidget {
  const NotADiagnosisNote({this.long = false, super.key});

  /// Whether to show the full explanation rather than the single line.
  final bool long;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              long ? text.notADiagnosisLong : text.notADiagnosis,
              style: context.texts.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A titled card, used for most content blocks.
class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 10)],
                  Expanded(
                    child: Text(
                      title!,
                      style: context.texts.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(
                  subtitle!,
                  style: context.texts.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// The status badge shown on the dashboard and the report.
class StatusBadge extends StatelessWidget {
  const StatusBadge({required this.status, this.compact = false, super.key});

  final ScreeningStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final presentation = context.presentationOf(status);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 14,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        // A tint rather than the full colour: a solid amber block for a notable
        // change reads as an alarm, and the wording is doing enough work already.
        color: presentation.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: presentation.color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            presentation.icon,
            size: compact ? 16 : 20,
            color: presentation.color,
          ),
          const SizedBox(width: 8),
          // Flexible so the headline wraps at large text sizes instead of overflowing.
          Flexible(
            child: Text(
              statusHeadline(text, status),
              style:
                  (compact
                          ? context.texts.labelMedium
                          : context.texts.titleSmall)
                      ?.copyWith(
                        color: presentation.color,
                        fontWeight: FontWeight.w600,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A horizontal bar showing how much each domain contributed.
///
/// Always shows all four, including the ones at zero. A breakdown that hid the
/// domains that did not contribute would make a single-domain change look like the
/// only thing the app measured.
class ContributionBreakdown extends StatelessWidget {
  const ContributionBreakdown({required this.contributions, super.key});

  final Map<Domain, double> contributions;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final percentages = contributionPercentages(contributions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A single stacked bar first, so the relative sizes are visible at a glance
        // before any numbers are read.
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 12,
            child: Row(
              children: [
                for (final domain in Domain.values)
                  if ((contributions[domain] ?? 0) > 0)
                    Expanded(
                      flex: ((contributions[domain] ?? 0) * 1000).round(),
                      child: ColoredBox(color: context.domainColor(domain.key)),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final domain in Domain.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: context.domainColor(domain.key),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(domainLabel(text, domain))),
                Text(
                  '${percentages[domain] ?? 0}%',
                  style: context.texts.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Progress towards a frozen baseline.
class BaselineProgress extends StatelessWidget {
  const BaselineProgress({
    required this.collected,
    required this.required_,
    super.key,
  });

  final int collected;
  final int required_;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final remaining = (required_ - collected).clamp(0, required_);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.dashboardBaselineProgress(collected, required_),
          style: context.texts.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: required_ == 0 ? 1 : collected / required_,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          remaining == 0
              ? text.statusBaselineSetBody
              : text.dashboardBaselineRemaining(remaining),
          style: context.texts.bodyMedium,
        ),
        const SizedBox(height: 10),
        Text(
          text.dashboardBaselineExplainer,
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// A full-width primary action.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Shows a spinner and blocks further taps.
  ///
  /// Taken as a flag rather than left to the caller to disable the button, because
  /// a double tap on "start session" is easy to do and would begin two sessions.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 20),
                  const SizedBox(width: 10),
                ],
                // Flexible so a long label wraps instead of overflowing. The non-functional
                // requirements call for text scaling to 200 %, at which several labels
                // ("That is all I remember") no longer fit on one line.
                Flexible(child: Text(label, textAlign: TextAlign.center)),
              ],
            ),
    );
  }
}

/// A short message with an icon, for empty states.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: context.colors.outline),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.texts.bodyLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 24), action!],
          ],
        ),
      ),
    );
  }
}

/// A question with mutually exclusive answers, used by the check-in.
///
/// Segmented rather than a dropdown so that every option is visible without a tap:
/// the check-in is answered before every session, and hiding the options behind a
/// menu would make it slower each time.
class ChoiceQuestion<T> extends StatelessWidget {
  const ChoiceQuestion({
    required this.question,
    required this.options,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String question;
  final List<({T value, String label})> options;
  final T? selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: context.texts.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final option in options)
              ChoiceChip(
                label: Text(option.label),
                selected: selected == option.value,
                onSelected: (_) => onSelected(option.value),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
