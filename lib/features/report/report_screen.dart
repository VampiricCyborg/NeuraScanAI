/// The explainable report, and the way to share it.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../engine/features.dart';
import '../../services/pdf_report.dart';
import '../trends/comparison_section.dart';

/// Status, breakdown, and a PDF export.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key});

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  bool _exporting = false;

  Future<void> _export(ReportData data) async {
    final text = AppText.of(context);
    setState(() => _exporting = true);
    try {
      final bytes = await buildReportPdf(data);
      final directory = await getTemporaryDirectory();
      final file = File(
        '${directory.path}/neurascan-report-'
        '${data.generatedAt.toIso8601String().split('T').first}.pdf',
      );
      await file.writeAsBytes(bytes);

      // Recorded before sharing, so that a report the user did produce is logged even if
      // they dismiss the share sheet.
      final userId = ref.read(currentUserIdProvider);
      if (userId != null) {
        await ref
            .read(repositoryProvider)
            .recordReport(
              userId: userId,
              periodStart: data.periodStart,
              periodEnd: data.periodEnd,
              status: data.status,
              contributions: data.contributions,
              sessionCount: data.sessionCount,
            );
      }

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: text.reportTitle),
      );
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text.reportExportFailed)));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final profile = ref.watch(profileProvider).value;
    final sessions = ref.watch(sessionsProvider).value ?? const [];
    final scored = sessions.where((s) => s.countsTowardsTrend).toList();
    final latest = ref.watch(latestScoredSessionProvider);
    final status = ref.watch(currentStatusProvider);

    final verdictReady = ref.watch(verdictReadyProvider);
    final baselineReady =
        ref.watch(engineProvider).value?.baselineReady ?? false;

    // A report needs at least one full test to compare with the baseline.
    if (!verdictReady || scored.isEmpty || latest == null) {
      return Scaffold(
        appBar: AppBar(title: Text(text.reportTitle)),
        body: baselineReady
            ? ListView(
                padding: const EdgeInsets.all(kPagePadding),
                children: [
                  SectionCard(
                    title: text.trendsFirstTestTitle,
                    leading: Icon(
                      Icons.play_circle_outline,
                      color: context.colors.primary,
                    ),
                    child: Text(
                      text.reportNeedFirstTest,
                      style: context.texts.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              )
            : EmptyState(
                icon: Icons.description_outlined,
                message: text.reportNoData,
              ),
      );
    }

    final contributions =
        latest.contributions ??
        {for (final domain in Domain.values) domain: 0.0};

    final data = ReportData(
      generatedAt: DateTime.now(),
      sessions: scored,
      status: status,
      contributions: contributions,
      displayName: profile?.displayName,
      deviationSeries: ref.watch(deviationSeriesProvider),
      comparison: ref.watch(comparisonProvider(null)),
    );

    return Scaffold(
      appBar: AppBar(title: Text(text.reportTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(kPagePadding),
          children: [
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StatusBadge(status: status),
                  const SizedBox(height: 14),
                  Text(
                    text.reportPeriod(
                      _formatDate(data.periodStart),
                      _formatDate(data.periodEnd),
                    ),
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text.reportSessionCount(data.sessionCount),
                    style: context.texts.bodyMedium?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (data.comparison != null) ...[
              ComparisonSection(comparison: data.comparison!),
              const SizedBox(height: 14),
            ],

            SectionCard(
              title: text.reportContributions,
              subtitle: text.reportContributionsBody,
              child: ContributionBreakdown(contributions: contributions),
            ),
            const SizedBox(height: 14),

            SectionCard(
              title: text.reportTalkToDoctor,
              leading: Icon(
                Icons.medical_services_outlined,
                color: context.colors.primary,
              ),
              child: Text(
                text.reportTalkToDoctorBody,
                style: context.texts.bodyMedium?.copyWith(height: 1.5),
              ),
            ),
            const SizedBox(height: 14),

            const NotADiagnosisNote(long: true),
            const SizedBox(height: 20),

            PrimaryButton(
              label: text.reportExport,
              icon: Icons.ios_share,
              busy: _exporting,
              onPressed: () => _export(data),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime when) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${when.day} ${months[when.month - 1]} ${when.year}';
  }
}
