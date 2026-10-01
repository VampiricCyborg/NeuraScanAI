/// Choosing what goes in a report, and exporting it.
///
/// The user picks the period and the sections, can label the report, sees what it will contain,
/// and then shares, saves or prints the PDF, or saves the data as CSV or JSON. Every export asks
/// first: the file holds the person's measurements, and once it leaves the app the app's own
/// privacy settings no longer apply to it, so the user is told that and confirms each time.
library;

import 'dart:convert';

// Flutter has its own Baseline widget, which would clash with the engine's.
import 'package:flutter/material.dart' hide Baseline;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/providers.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../engine/features.dart';
import 'export/pdf/report_pdf.dart';
import 'export/report_delivery.dart';
import 'export/report_files.dart';
import 'export/report_model.dart';
import 'models.dart';
import 'providers.dart';
import 'reference_ranges.dart';
import 'widgets/charts.dart';

/// The report: options, preview and export.
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({this.now, super.key});

  /// Overridable so tests can pin the period.
  final DateTime? now;

  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  TrendRange _period = TrendRange.all;
  Set<ReportSection> _sections = {...ReportSection.values};
  TextEditingController? _label;
  bool _busy = false;

  @override
  void dispose() {
    _label?.dispose();
    super.dispose();
  }

  ReportModel _model() {
    final sessions = ref.read(sessionsProvider).value ?? const [];
    return buildReportModel(
      sessions: sessions,
      baseline: ref.read(engineProvider).value?.baseline,
      ranges: ref.read(referenceRangesProvider).value ?? ReferenceRanges.none,
      options: ReportOptions(
        period: _period,
        sections: _sections,
        userLabel: _label?.text ?? '',
      ),
      now: widget.now ?? DateTime.now(),
    );
  }

  Future<bool> _confirm() async {
    final text = AppText.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.repConsentTitle),
        content: Text(text.repConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.repConsentCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(text.repConsentContinue),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _export(ExportFormat format, _Action action) async {
    final text = AppText.of(context);
    if (!await _confirm() || !mounted) return;

    setState(() => _busy = true);
    try {
      final model = _model();
      final fileName = reportFileName(
        model.generatedAt,
        extension: format.extension,
      );
      final bytes = switch (format) {
        ExportFormat.pdf => (await buildReportPdf(model)).bytes,
        ExportFormat.csv => utf8.encode(buildCsv(model)),
        ExportFormat.json => utf8.encode(buildJson(model)),
      };

      // Recorded before the file leaves, so that a report the user did produce is logged even
      // if they dismiss the share sheet.
      final userId = ref.read(currentUserIdProvider);
      final latest = model.latest;
      if (userId != null && latest != null) {
        await ref
            .read(repositoryProvider)
            .recordReport(
              userId: userId,
              periodStart: model.from,
              periodEnd: model.to,
              status: latest.status,
              contributions:
                  latest.contributions ??
                  {for (final d in Domain.values) d: 0.0},
              sessionCount: model.validTests,
            );
      }

      final delivery = ref.read(reportDeliveryProvider);
      String? message;
      switch (action) {
        case _Action.share:
          await delivery.share(
            fileName: fileName,
            bytes: bytes,
            format: format,
            subject: text.reportTitle,
          );
        case _Action.save:
          final saved = await delivery.save(
            fileName: fileName,
            bytes: bytes,
            format: format,
          );
          message = saved ? text.repSaved : text.repNotSaved;
        case _Action.print:
          await delivery.printPdf(fileName: fileName, bytes: bytes);
      }
      if (message != null && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text.reportExportFailed)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final profile = ref.watch(profileProvider).value;
    final baselineReady =
        ref.watch(engineProvider).value?.baselineReady ?? false;
    ref.watch(referenceRangesProvider);

    final hasFullTest = ref.watch(latestFullTestProvider) != null;
    if (!hasFullTest) {
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

    _label ??= TextEditingController(text: profile?.displayName?.trim() ?? '');
    // The model is rebuilt on every change of option; it is cheap -- plain maths over the
    // stored tests -- and keeps the preview line honest.
    final preview = _model();
    final empty = preview.isEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(text.reportTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(kPagePadding),
          children: [
            SectionCard(
              title: text.repPeriodTitle,
              subtitle: text.repPeriodNote,
              child: RangeSelector(
                value: _period,
                onChanged: (range) => setState(() => _period = range),
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: text.repSectionsTitle,
              subtitle: text.repSectionsNote,
              padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
              child: Column(
                children: [
                  for (final (section, label) in [
                    (ReportSection.domains, text.repSecDomains),
                    (ReportSection.tests, text.repSecTests),
                    (ReportSection.log, text.repSecLog),
                    (ReportSection.methods, text.repSecMethods),
                  ])
                    CheckboxListTile(
                      key: ValueKey('section-${section.name}'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _sections.contains(section),
                      title: Text(label),
                      onChanged: (on) => setState(() {
                        _sections = {
                          ..._sections.where((s) => s != section),
                          if (on ?? false) section,
                        };
                      }),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: text.repLabelTitle,
              child: TextField(
                key: const ValueKey('report-label'),
                controller: _label,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(hintText: text.repLabelHint),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: text.repPreviewTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (empty)
                    Text(
                      text.repNothingInPeriod,
                      style: context.texts.bodyMedium?.copyWith(height: 1.5),
                    )
                  else ...[
                    Text(
                      text.repPreviewBody(
                        preview.validTests,
                        preview.setAsideTests,
                        _date(preview.from),
                        _date(preview.to),
                      ),
                      style: context.texts.bodyMedium?.copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      text.repPdfEnglish,
                      style: context.texts.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          context.push(Routes.reportPreview, extra: _model()),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(text.repPreviewOpen),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            SectionCard(
              title: text.repExportTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PrimaryButton(
                    label: text.repShare,
                    icon: Icons.ios_share,
                    busy: _busy,
                    onPressed: empty
                        ? null
                        : () => _export(ExportFormat.pdf, _Action.share),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: empty || _busy
                        ? null
                        : () => _export(ExportFormat.pdf, _Action.save),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(text.repSave),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: empty || _busy
                        ? null
                        : () => _export(ExportFormat.pdf, _Action.print),
                    icon: const Icon(Icons.print_outlined),
                    label: Text(text.repPrint),
                  ),
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: empty || _busy
                        ? null
                        : () => _export(ExportFormat.csv, _Action.save),
                    icon: const Icon(Icons.table_chart_outlined),
                    label: Text(text.repCsv),
                  ),
                  TextButton.icon(
                    onPressed: empty || _busy
                        ? null
                        : () => _export(ExportFormat.json, _Action.save),
                    icon: const Icon(Icons.data_object),
                    label: Text(text.repJson),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    text.repDataNote,
                    style: context.texts.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const NotADiagnosisNote(long: true),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  String _date(DateTime d) => '${d.day}/${d.month}/${d.year}';
}

enum _Action { share, save, print }

/// The PDF as it will be, page by page.
class ReportPreviewScreen extends StatelessWidget {
  const ReportPreviewScreen({required this.model, super.key});

  final ReportModel model;

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(text.repPreviewScreenTitle)),
      body: PdfPreview(
        build: (_) async => (await buildReportPdf(model)).bytes,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: false,
        allowSharing: false,
        useActions: false,
        loadingWidget: Center(child: Text(text.repBuilding)),
        pdfFileName: reportFileName(model.generatedAt),
      ),
    );
  }
}
