/// The files a report can be saved as: the PDF's name, and the CSV and JSON of the data.
///
/// The CSV and JSON hold *derived* data only -- the measurements each test produced, the scores
/// built from them and the context the user logged. Raw audio and raw touch traces are never
/// stored by the app, so they cannot be here; [kExportedSessionFields] and [kExportedFeatureKeys]
/// are the allow-list a test checks the files against, so a field cannot be added by accident.
library;

import 'dart:convert';

import '../../../engine/features.dart';
import '../calculators/analysis.dart';
import '../calculators/trend_stats.dart';
import 'pdf/report_pdf.dart' show kAppVersion, kEngineVersion, pdfDisclaimer;
import 'report_model.dart';

/// The PDF's file name: `NeuraScan_Report_<yyyy-mm-dd>.pdf`.
String reportFileName(DateTime when, {String extension = 'pdf'}) =>
    'NeuraScan_Report_${_isoDate(when)}.$extension';

String _isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// The per-test fields in the CSV and JSON, besides one value for each measurement.
const List<String> kExportedSessionFields = [
  'completed_at',
  'kind',
  'counted',
  'status',
  'index',
  'smoothed_index',
  'sleep',
  'fatigue',
  'illness_or_medication_change',
  'score_cognitive',
  'score_speech',
  'score_motor',
  'score_interaction',
  'share_cognitive',
  'share_speech',
  'share_motor',
  'share_interaction',
];

/// The measurements exported, in their measurement order.
final List<String> kExportedFeatureKeys = [
  for (final spec in kFeatureSpecs) spec.key,
];

String _kind(LogKind kind) => switch (kind) {
  LogKind.practice => 'practice',
  LogKind.baseline => 'baseline',
  LogKind.full => 'full',
};

/// One test as an ordered map of the allowed fields.
Map<String, Object?> _sessionFields(SessionLogRow row) {
  final s = row.session;
  return {
    'completed_at': s.completedAt.toUtc().toIso8601String(),
    'kind': _kind(row.kind),
    'counted': row.counted,
    'status': s.status.key,
    'index': s.index,
    'smoothed_index': s.ewma,
    'sleep': s.checkIn.sleep.key,
    'fatigue': s.checkIn.fatigue.key,
    'illness_or_medication_change': s.checkIn.illnessOrMedicationChange,
    for (final domain in Domain.values)
      'score_${domain.key}': s.domainScores?[domain],
    for (final domain in Domain.values)
      'share_${domain.key}': s.contributions?[domain],
    for (final key in kExportedFeatureKeys) key: s.features[key],
  };
}

String _csvCell(Object? value) {
  if (value == null) return '';
  final text = value is double ? value.toStringAsFixed(6) : '$value';
  return text.contains(RegExp('[",\n]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

/// The tests of the report as CSV: one row per test, counted or not, one column per field.
String buildCsv(ReportModel model) {
  final header = [...kExportedSessionFields, ...kExportedFeatureKeys];
  final lines = <String>[header.join(',')];
  for (final row in model.log) {
    final fields = _sessionFields(row);
    lines.add(
      [for (final column in header) _csvCell(fields[column])].join(','),
    );
  }
  return '${lines.join('\n')}\n';
}

/// The report's data as JSON: the baseline, each test, and the trend statistics.
String buildJson(ReportModel model) {
  final series = model.series;
  final data = <String, Object?>{
    'app': 'NeuraScan AI',
    'app_version': kAppVersion,
    'scoring_version': kEngineVersion,
    'generated_at': model.generatedAt.toUtc().toIso8601String(),
    'period': {
      'from': model.from.toUtc().toIso8601String(),
      'to': model.to.toUtc().toIso8601String(),
    },
    'note':
        'Derived measurements only. No audio, no touch traces. ${pdfDisclaimer()}',
    'baseline': {
      for (final key in kExportedFeatureKeys)
        if (series[key]!.hasBaseline)
          key: {
            'median': series[key]!.baselineMedian,
            'spread': series[key]!.baselineScale,
          },
    },
    'sessions': [for (final row in model.log) _sessionFields(row)],
    'trends': {
      'overall': _statsJson(model.indexStats),
      for (final entry in model.areaStats.entries)
        entry.key.key: _statsJson(entry.value),
    },
    'metric_trends': {
      for (final entry in model.metricStats.entries)
        entry.key: _statsJson(entry.value),
    },
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}

Map<String, Object?> _statsJson(TrendStats stats) => {
  'valid_tests': stats.n,
  'enough_for_trend': stats.enough,
  'direction': stats.direction?.name,
  'slope_spreads_per_test': stats.slopeSds,
  'smoothed_deviation': stats.ewma,
  'tests_in_a_row_mild': stats.runMild,
  'tests_in_a_row_notable': stats.runNotable,
};
