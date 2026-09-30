/// A full test laid out against the baseline and the test before it.
///
/// Shown straight after each full test and at the top of the trends screen. Each area and each
/// measurement gets two verdicts -- against the user's usual value, and against their last
/// test -- in plain words, with the numbers underneath for anyone who wants them.
///
/// The wording is "better", "about the same" and "worse" rather than a colour scale or a
/// percentage, because a change inside a person's ordinary variation is the most common
/// result and has to read as unremarkable rather than as a small failure.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../engine/comparison.dart';
import 'baseline_format.dart';

/// The comparison of one test with the baseline and the previous test.
class ComparisonSection extends StatelessWidget {
  const ComparisonSection({required this.comparison, super.key});

  final TestComparison comparison;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return SectionCard(
      title: text.comparisonTitle,
      subtitle: text.comparisonIntro,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!comparison.hasPrevious) ...[
            _Note(text: text.comparisonFirstTest),
            const SizedBox(height: 16),
          ],
          for (final area in comparison.areas) ...[
            _AreaBlock(area: area, hasPrevious: comparison.hasPrevious),
            const SizedBox(height: 18),
          ],
          Text(
            text.comparisonExplain,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// One area: its own verdicts, then each of its measurements.
class _AreaBlock extends StatelessWidget {
  const _AreaBlock({required this.area, required this.hasPrevious});

  final AreaComparison area;
  final bool hasPrevious;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: context.domainColor(area.domain.key),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              domainLabel(text, area.domain),
              style: context.texts.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _Verdicts(
          vsUsual: area.vsBaseline,
          vsLast: hasPrevious ? area.vsPrevious : null,
        ),
        const SizedBox(height: 8),
        for (final measurement in area.measurements)
          _MeasurementRow(measurement: measurement, hasPrevious: hasPrevious),
      ],
    );
  }
}

String _value(String key, double value) => formatFeatureValue(key, value);

/// One measurement: the value, what is usual, what it was last time, and the verdicts.
class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({required this.measurement, required this.hasPrevious});

  final MeasurementComparison measurement;
  final bool hasPrevious;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final key = measurement.spec.key;

    final usual = _value(key, measurement.baselineMedian);
    final spread = formatFeatureSpread(key, measurement.baselineScale);
    final details = [
      '${text.comparisonUsual}: $usual $spread',
      if (measurement.previous != null)
        '${text.comparisonLastTest}: ${_value(key, measurement.previous!)}',
    ];

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  featureLabel(text, key),
                  style: context.texts.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                formatFeatureValue(key, measurement.value),
                style: context.texts.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            details.join('   '),
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _Verdicts(
            vsUsual: measurement.vsBaseline,
            vsLast: hasPrevious ? measurement.vsPrevious : null,
          ),
        ],
      ),
    );
  }
}

/// The two verdicts, one per line.
class _Verdicts extends StatelessWidget {
  const _Verdicts({required this.vsUsual, required this.vsLast});

  final Change vsUsual;

  /// Null when there is no earlier test.
  final Change? vsLast;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _VerdictLine(label: text.comparisonVsUsual, change: vsUsual),
        if (vsLast != null) ...[
          const SizedBox(height: 4),
          _VerdictLine(label: text.comparisonVsLast, change: vsLast!),
        ],
      ],
    );
  }
}

class _VerdictLine extends StatelessWidget {
  const _VerdictLine({required this.label, required this.change});

  final String label;
  final Change change;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final colors = context.colors;

    final (icon, word, color) = switch (change) {
      Change.better => (
        Icons.trending_up,
        text.comparisonBetter,
        colors.primary,
      ),
      Change.similar => (
        Icons.trending_flat,
        text.comparisonSimilar,
        colors.onSurfaceVariant,
      ),
      // Amber rather than red: a single worse reading is information, not an alarm.
      Change.worse => (
        Icons.trending_down,
        text.comparisonWorse,
        colors.tertiary,
      ),
    };

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.texts.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ),
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          word,
          style: context.texts.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: context.texts.bodySmall?.copyWith(
          color: context.colors.onPrimaryContainer,
          height: 1.4,
        ),
      ),
    );
  }
}
