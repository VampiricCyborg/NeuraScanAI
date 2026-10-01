/// One card per test, and inside it one panel per measurement.
///
/// A measurement is shown against three references, each under its own heading so they cannot
/// be mistaken for one another:
///
/// 1. **Your baseline** -- the most meaningful, and the only one that decides a status.
/// 2. **Your earlier tests** -- the last one, the average of the last four, the best and the
///    worst.
/// 3. **The population range** -- context only, and only ever a range: it is labelled "not yet
///    validated" unless it has a source, and nothing on this screen calls a value normal or
///    abnormal because of it.
///
/// Tests that are not counted, or not measured, are still here, marked as such. Nothing is
/// dropped without saying so.
library;

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../app/theme.dart';
import '../../../app/widgets.dart';
import '../../../engine/comparison.dart';
import '../../trends/baseline_format.dart';
import '../calculators/analysis.dart';
import '../models.dart';
import 'report_text.dart';
import 'verdict.dart';

/// A test and its measurements.
class TestCard extends StatelessWidget {
  const TestCard({
    required this.summary,
    this.onOpenMetric,
    this.initiallyExpanded = false,
    super.key,
  });

  final TestSummary summary;

  /// Called with a measurement's key when the user asks to see its chart.
  final ValueChanged<String>? onOpenMetric;

  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final name = testLabel(text, summary.id);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // The tile draws its own dividers, which sit oddly inside a card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('test-${summary.id.name}'),
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          title: Text(
            name,
            style: context.texts.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [_validityChip(text), ..._domainDots(context, text)],
            ),
          ),
          children: [
            if (summary.validity == TestValidity.notCounted)
              _Notice(
                icon: Icons.nights_stay_outlined,
                text: text.resNotCountedWhy(
                  summary.contextReasons
                      .map((r) => contextNoteLabel(text, r))
                      .join(', '),
                ),
              ),
            if (summary.validity == TestValidity.notMeasured)
              _Notice(
                icon: Icons.do_not_disturb_on_outlined,
                text: summary.id == TestId.typing
                    ? text.resNotMeasuredTyping
                    : text.resNotMeasuredOther,
              ),
            for (final metric in summary.metrics) ...[
              const SizedBox(height: 12),
              MetricCard(
                summary: metric,
                onOpen: onOpenMetric == null
                    ? null
                    : () => onOpenMetric!(metric.spec.key),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _validityChip(AppText text) => switch (summary.validity) {
    TestValidity.valid => StateChip(
      icon: Icons.check_circle_outline,
      label: text.resValid,
    ),
    TestValidity.notCounted => StateChip(
      icon: Icons.block,
      label: text.resNotCounted,
    ),
    TestValidity.notMeasured => StateChip(
      icon: Icons.do_not_disturb_on_outlined,
      label: text.resNotMeasured,
    ),
  };

  /// A dot for each area the test feeds, in the area's colour, with its name beside it.
  Iterable<Widget> _domainDots(BuildContext context, AppText text) => [
    for (final domain in summary.id.domains)
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: context.domainColor(domain.key),
              // A square, not a circle: the chart markers use circles for tests, so the two
              // are not confused.
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            domainLabel(text, domain),
            style: context.texts.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
  ];
}

/// One measurement against the three references.
class MetricCard extends StatelessWidget {
  const MetricCard({required this.summary, this.onOpen, super.key});

  final MetricSummary summary;

  /// Shows the measurement's chart. Null where there is no chart to open.
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final spec = summary.spec;
    final name = featureLabel(text, spec.key);
    final sentence = interpretMetric(text, summary);

    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: context.texts.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                if (summary.value != null)
                  Text(
                    formatFeatureValue(spec.key, summary.value!),
                    style: context.texts.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              sentence,
              style: context.texts.bodyMedium?.copyWith(height: 1.4),
            ),
            if (summary.state == MetricState.measured ||
                summary.state == MetricState.calibrating) ...[
              const SizedBox(height: 14),
              _BaselineBlock(summary: summary),
              const SizedBox(height: 12),
              _EarlierBlock(summary: summary),
            ],
            const SizedBox(height: 12),
            _PopulationBlock(summary: summary),
            if (onOpen != null &&
                (summary.state == MetricState.measured ||
                    summary.state == MetricState.calibrating)) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.show_chart, size: 18),
                  label: Text(text.resChartMetrics),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labelled group of lines inside a measurement panel.
class _Block extends StatelessWidget {
  const _Block({required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: context.texts.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.colors.primary,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(
            note!,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 6),
        ...children,
      ],
    );
  }
}

/// A label, a value and optionally a verdict, allowed to wrap onto a second line.
class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.verdict});

  final String label;
  final String value;
  final Widget? verdict;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '$label: ',
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          ?verdict,
        ],
      ),
    );
  }
}

class _BaselineBlock extends StatelessWidget {
  const _BaselineBlock({required this.summary});

  final MetricSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final key = summary.spec.key;

    if (summary.state == MetricState.calibrating) {
      return _Block(
        title: text.resVsBaselineTitle,
        children: [
          StateChip(icon: Icons.hourglass_top, label: text.resCalibrating),
        ],
      );
    }

    final z = summary.zOriented!;
    return _Block(
      title: text.resVsBaselineTitle,
      note: text.resVsBaselineNote,
      children: [
        Text(
          text.resBaselineLine(
            formatFeatureValue(key, summary.baselineMedian!),
            formatFeatureSpread(
              key,
              summary.baselineScale!,
            ).replaceFirst('±', ''),
          ),
          style: context.texts.bodyMedium,
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            VerdictChip(
              change: summary.vsBaseline!,
              label: changeWord(text, summary.vsBaseline!),
            ),
            Text(
              text.resZScore(_signed(z)),
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EarlierBlock extends StatelessWidget {
  const _EarlierBlock({required this.summary});

  final MetricSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final key = summary.spec.key;

    Widget? chip(Change? change) => change == null
        ? null
        : VerdictChip(change: change, label: directionWord(text, change));

    final hasEarlier = summary.previous != null;
    return _Block(
      title: text.resVsEarlierTitle,
      children: [
        if (!hasEarlier)
          Text(
            text.resNoEarlier,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          )
        else ...[
          _Line(
            label: text.resLast,
            value: formatFeatureValue(key, summary.previous!),
            verdict: chip(summary.vsPrevious),
          ),
          if (summary.rollingMean != null)
            _Line(
              label: text.resAvg4,
              value: formatFeatureValue(key, summary.rollingMean!),
              verdict: chip(summary.vsRolling),
            ),
        ],
        if (summary.best != null)
          _Line(
            label: text.resBest,
            value: formatFeatureValue(key, summary.best!),
          ),
        if (summary.worst != null)
          _Line(
            label: text.resWorst,
            value: formatFeatureValue(key, summary.worst!),
          ),
      ],
    );
  }
}

class _PopulationBlock extends StatelessWidget {
  const _PopulationBlock({required this.summary});

  final MetricSummary summary;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final key = summary.spec.key;
    final range = summary.reference;

    return _Block(
      title: text.resPopulationTitle,
      children: [
        if (range != null && range.isValidated) ...[
          Text(
            text.resPopulationRange(
              formatFeatureValue(key, range.low!),
              formatFeatureValue(key, range.high!),
            ),
            style: context.texts.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (range.sourceCitation != null)
            Text(
              text.resPopulationSource(range.sourceCitation!),
              style: context.texts.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          Text(
            text.resPopulationNote,
            style: context.texts.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ] else
          // The placeholder case, and the only one that ships. No number, no verdict.
          Text(
            text.resPopulationNotValidated,
            style: context.texts.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: context.colors.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: context.texts.bodyMedium)),
        ],
      ),
    );
  }
}

/// A number with its sign always shown, to one place: "+2.0", "-0.4".
String _signed(double value) =>
    '${value >= 0 ? '+' : '−'}${value.abs().toStringAsFixed(1)}';

/// Exposed for tests: how a z-score is written.
String formatZ(double value) => _signed(value);
