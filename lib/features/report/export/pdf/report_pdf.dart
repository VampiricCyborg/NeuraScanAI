/// The shareable PDF report.
///
/// The one thing that leaves the phone by the user's own hand, and the only one a clinician may
/// ever see. So it has to be readable by someone who has never used the app, and it must never
/// read as a diagnosis: the mandated disclaimer is on the cover, in the summary and on the last
/// page, in the body of the page rather than a footnote, and the wording throughout describes
/// measurements against the person's own usual pattern, not findings.
///
/// Built offline from a [ReportModel], A4 portrait. The text is English whatever the app's
/// language: the built-in PDF fonts have no Tamil glyphs, and shipping a Tamil font is a
/// separate decision (see docs/REPORT_MODULE.md).
library;

import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../app/l10n/generated/app_localizations.dart';
import '../../../../app/widgets.dart'
    show domainLabel, featureLabel, statusHeadline;
import '../../../../data/models.dart';
import '../../../../engine/comparison.dart';
import '../../../../engine/constants.dart';
import '../../../../engine/features.dart';
import '../../../../engine/scoring.dart';
import '../../../../engine/screening_engine.dart';
import '../../../trends/baseline_format.dart';
import '../../calculators/analysis.dart';
import '../../calculators/trend_stats.dart';
import '../../models.dart';
import '../../report_constants.dart';
import '../../widgets/report_text.dart';
import '../report_model.dart';
import 'pdf_charts.dart';

/// The app version stamped on the cover. Kept in step with `pubspec.yaml`.
const String kAppVersion = '1.0.0';

/// The version of the scoring rules, stamped beside the app version so a report can be traced to
/// the rules that produced its status.
const String kEngineVersion = '1.0';

/// The disclaimer, word for word. It is the app's own string, so the screen and the PDF cannot
/// drift apart.
String pdfDisclaimer() => _en.resDisclaimer;

final AppText _en = lookupAppText(const Locale('en'));

const _ink = PdfColor.fromInt(0xFF1A1C1E);
const _muted = PdfColor.fromInt(0xFF5B6770);
const _rule = PdfColor.fromInt(0xFFD5DEE1);
const _brand = PdfColor.fromInt(0xFF146C7A);
const _wash = PdfColor.fromInt(0xFFF1F5F6);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
];

String _date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

/// A finished report.
class BuiltReport {
  const BuiltReport({required this.bytes, required this.pageCount});

  final Uint8List bytes;
  final int pageCount;
}

/// Builds the PDF for [model].
///
/// [compress] is on in the app; the tests turn it off so the page text can be read back.
Future<BuiltReport> buildReportPdf(
  ReportModel model, {
  bool compress = true,
}) async {
  final document = pw.Document(
    compress: compress,
    title: 'NeuraScan AI behavioural report',
    author: 'NeuraScan AI',
    // Named as a summary rather than a result, for the same reason the wording inside is
    // careful: the subject line is what a recipient reads first.
    subject: 'Behavioural measurements against a personal baseline',
  );

  document.addPage(_cover(model));

  final body = <pw.Widget>[
    ..._executiveSummary(model),
    if (model.options.includes(ReportSection.domains) && !model.isEmpty)
      ..._domainSections(model),
    if (model.options.includes(ReportSection.tests) && !model.isEmpty)
      ..._testSections(model),
    if (model.options.includes(ReportSection.log)) ..._logSection(model),
    if (model.options.includes(ReportSection.methods)) ..._methods(model),
    // Always last, so the closing page carries the disclaimer whichever sections were chosen.
    pw.SizedBox(height: 18),
    _disclaimerBox(),
  ];

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 40, 42, 48),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'NeuraScan AI report, ${_date(model.generatedAt)}',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
            pw.Text(
              'Page ${context.pageNumber + 1} of ${context.pagesCount + 1}',
              style: const pw.TextStyle(fontSize: 8, color: _muted),
            ),
          ],
        ),
      ),
      build: (context) => body,
    ),
  );

  final bytes = await document.save();
  return BuiltReport(
    bytes: bytes,
    pageCount: document.document.pdfPageList.pages.length,
  );
}

// -- shared pieces ------------------------------------------------------------------------

pw.TextStyle _style({
  double size = 10,
  bool bold = false,
  PdfColor color = _ink,
}) => pw.TextStyle(
  fontSize: size,
  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
  color: color,
  lineSpacing: 2,
);

pw.Widget _h1(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Text(text, style: _style(size: 18, bold: true, color: _brand)),
);

pw.Widget _h2(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 10, bottom: 5),
  child: pw.Text(text, style: _style(size: 12, bold: true)),
);

pw.Widget _p(String text, {PdfColor color = _ink, double size = 10}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Text(
        text,
        style: _style(size: size, color: color),
      ),
    );

pw.Widget _disclaimerBox() => pw.Container(
  width: double.infinity,
  padding: const pw.EdgeInsets.all(10),
  decoration: pw.BoxDecoration(
    color: _wash,
    border: pw.Border.all(color: _brand, width: 0.8),
    borderRadius: pw.BorderRadius.circular(4),
  ),
  child: pw.Text(pdfDisclaimer(), style: _style(bold: true)),
);

pw.Widget _table(
  List<String> headers,
  List<List<String>> rows, {
  Map<int, pw.TableColumnWidth>? widths,
}) {
  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: rows,
    headerStyle: _style(size: 8, bold: true),
    cellStyle: _style(size: 8),
    headerDecoration: const pw.BoxDecoration(color: _wash),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _rule, width: 0.5),
      bottom: pw.BorderSide(color: _rule, width: 0.5),
    ),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    columnWidths: widths,
    cellAlignment: pw.Alignment.centerLeft,
    headerAlignment: pw.Alignment.centerLeft,
  );
}

String _signed(double v, {int digits = 2}) =>
    '${v >= 0 ? '+' : '-'}${v.abs().toStringAsFixed(digits)}';

/// "Not enough data yet (n of 6)", or the trend in words.
String _trendLine(TrendStats stats) => stats.enough
    ? trendWord(_en, stats.direction!)
    : _en.resNotEnoughData(stats.n, kMinSessionsForTrend);

String _statusWord(ScreeningStatus s) => statusHeadline(_en, s);

String _baselineStatusLine(ReportModel m) => switch (m.baselineProgress) {
  BaselineProgress.none => 'Baseline: not set yet',
  BaselineProgress.complete => 'Baseline: complete for all measurements',
  BaselineProgress.partial =>
    'Baseline: set for the core measurements; ${m.pendingMeasurements} '
        'measurements are still calibrating from the first full tests',
};

// -- cover --------------------------------------------------------------------------------

pw.Page _cover(ReportModel m) {
  return pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(54, 60, 54, 54),
    build: (context) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'NeuraScan AI',
          style: _style(size: 30, bold: true, color: _brand),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Behavioural screening report',
          style: _style(size: 16, color: _muted),
        ),
        pw.SizedBox(height: 28),
        pw.Container(height: 2, width: 60, color: _brand),
        pw.SizedBox(height: 28),
        _coverRow('Period', '${_date(m.from)} to ${_date(m.to)}'),
        _coverRow('Created', _date(m.generatedAt)),
        if (m.options.userLabel.trim().isNotEmpty)
          _coverRow('Prepared for', m.options.userLabel.trim()),
        _coverRow(
          'Tests in period',
          '${m.validTests} counted, ${m.setAsideTests} set aside',
        ),
        _coverRow('App version', kAppVersion),
        _coverRow('Scoring version', kEngineVersion),
        _coverRow('Baseline', _baselineStatusLine(m)),
        pw.Spacer(),
        _disclaimerBox(),
      ],
    ),
  );
}

pw.Widget _coverRow(String label, String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.SizedBox(
        width: 110,
        child: pw.Text(label, style: _style(color: _muted)),
      ),
      pw.Expanded(child: pw.Text(value, style: _style(size: 11, bold: true))),
    ],
  ),
);

// -- executive summary --------------------------------------------------------------------

List<pw.Widget> _executiveSummary(ReportModel m) {
  final widgets = <pw.Widget>[_h1('Summary')];

  if (m.isEmpty) {
    widgets
      ..add(
        _p(
          'There are no full tests in this period, so there is nothing to summarise yet.',
        ),
      )
      ..add(pw.SizedBox(height: 12))
      ..add(_disclaimerBox());
    return widgets;
  }

  final latest = m.latest!;
  final status = latest.status;
  widgets
    ..add(
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _rule),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Latest full test, ${_date(latest.completedAt)}',
              style: _style(size: 9, color: _muted),
            ),
            pw.SizedBox(height: 3),
            pw.Text(_statusWord(status), style: _style(size: 15, bold: true)),
            pw.SizedBox(height: 4),
            pw.Text(_statusBody(latest), style: _style()),
          ],
        ),
      ),
    )
    ..add(pw.SizedBox(height: 10))
    ..add(_disclaimerBox());

  // Where the change came from, summing to 100%.
  if (latest.contributions != null && latest.isCounted) {
    final percent = contributionPercentages(latest.contributions!);
    widgets
      ..add(_h2('Where the change comes from'))
      ..add(
        _table(
          ['Area', 'Share of the change'],
          [
            for (final domain in Domain.values)
              [domainLabel(_en, domain), '${percent[domain] ?? 0}%'],
            ['Total', '${percent.values.fold<int>(0, (a, b) => a + b)}%'],
          ],
        ),
      );
  }

  if (m.topFeatures.isNotEmpty) {
    final total = m.topFeatures.fold<double>(0, (a, b) => a + b.share);
    widgets
      ..add(_h2('What moved the most'))
      ..add(
        _table(
          ['Measurement', 'Share of the change'],
          [
            for (final t in m.topFeatures)
              [featureLabel(_en, t.key), '${(t.share / total * 100).round()}%'],
          ],
        ),
      );
  }

  final notes = contextNotes(latest.checkIn);
  widgets
    ..add(_h2('What may explain this'))
    ..add(
      _p(
        notes.isEmpty
            ? _en.resMayExplainNone
            : _en.resMayExplainBody(
                notes.map((n) => contextNoteLabel(_en, n)).join(', '),
              ),
      ),
    );

  // The overall index over the period.
  widgets
    ..add(_h2('Overall deviation index'))
    ..add(_p(_en.resChartOverallNote, color: _muted, size: 9));
  if (m.indexPoints.isEmpty) {
    widgets.add(_p('No counted tests in this period.'));
  } else {
    widgets
      ..add(
        pdfLineChart(
          points: [
            for (final p in m.indexPoints)
              ChartPoint(value: p.index, counted: true),
          ],
          smoothed: [for (final p in m.indexPoints) p.ewma],
          domain: Domain.cognitive,
          format: (v) => v.toStringAsFixed(1),
          firstDate: _date(m.indexPoints.first.at),
          lastDate: _date(m.indexPoints.last.at),
          guides: const [
            ChartGuide(y: kMildFraction * kDefaultThreshold, label: 'Mild'),
            ChartGuide(y: kDefaultThreshold, label: 'Notable'),
          ],
        ),
      )
      ..add(
        _p(
          'Solid line: each counted test. Dotted line: smoothed. Dashed horizontal lines: the '
          'mild level (${(kMildFraction * kDefaultThreshold).toStringAsFixed(1)}) and the '
          'notable level (${kDefaultThreshold.toStringAsFixed(1)}).',
          color: _muted,
          size: 8,
        ),
      )
      ..add(_trendSummary(m.indexStats));
  }

  return widgets;
}

pw.Widget _trendSummary(TrendStats s) {
  final lines = <String>[
    'Trend: ${_trendLine(s)}',
    if (s.slopeSds != null)
      'Slope: ${_signed(s.slopeSds!)} spreads per test (Theil-Sen)',
    if (s.ewma != null) 'Smoothed level: ${s.ewma!.toStringAsFixed(2)}',
    'In a row at or above the mild level: ${s.runMild}',
    'In a row at or above the notable level: ${s.runNotable}',
    _en.resTrendValidOnly,
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [for (final line in lines) _p(line, size: 9)],
  );
}

String _statusBody(SessionRecord latest) => switch (latest.status) {
  ScreeningStatus.stable => _en.statusStableBody,
  ScreeningStatus.mildDeviation => _en.statusMildBody,
  ScreeningStatus.notableDeviation => _en.statusNotableBody,
  ScreeningStatus.excludedContext => _en.statusExcludedBody(
    confoundingNotes(latest.checkIn)
        .map((n) => contextNoteLabel(_en, n))
        .join(', '),
  ),
  ScreeningStatus.buildingBaseline => _en.dashboardBaselineExplainer,
  ScreeningStatus.invalidSession => _en.statusInvalidBody,
};

// -- areas --------------------------------------------------------------------------------

List<pw.Widget> _domainSections(ReportModel m) {
  final out = <pw.Widget>[];
  for (final domain in Domain.values) {
    final points = m.areaPoints[domain] ?? const [];
    final stats = m.areaStats[domain]!;
    out
      ..add(pw.NewPage())
      ..add(_h1(domainLabel(_en, domain)))
      ..add(
        _p(
          'The area score is the combined deviation of this area\'s measurements from the '
          'person\'s own baseline. Higher is worse; zero is exactly as usual.',
          color: _muted,
          size: 9,
        ),
      );
    if (points.isEmpty) {
      out.add(_p('No counted tests in this period.'));
    } else {
      out
        ..add(
          pdfLineChart(
            points: [
              for (final p in points) ChartPoint(value: p.score, counted: true),
            ],
            domain: domain,
            format: (v) => v.toStringAsFixed(1),
            firstDate: _date(points.first.at),
            lastDate: _date(points.last.at),
            median: 0,
          ),
        )
        ..add(_p('Dashed line: your baseline (zero).', color: _muted, size: 8))
        ..add(_trendSummary(stats));
    }

    final keys = [
      for (final spec in kFeatureSpecs)
        if (spec.domain == domain) spec.key,
    ];
    out
      ..add(_h2('Measurements in this area'))
      ..add(
        _table(
          ['Measurement', 'Test', 'Latest', 'Baseline', 'Trend'],
          [for (final key in keys) _domainRow(m, key)],
        ),
      );
  }
  return out;
}

List<String> _domainRow(ReportModel m, String key) {
  final series = m.series[key]!;
  final latestPoint = series.counted.isEmpty ? null : series.counted.last;
  return [
    featureLabel(_en, key),
    testLabel(_en, testOf(key)),
    latestPoint == null ? '-' : formatFeatureValue(key, latestPoint.value),
    series.hasBaseline
        ? formatFeatureValue(key, series.baselineMedian!)
        : 'Calibrating',
    _trendLine(m.metricStats[key]!),
  ];
}

// -- the eight tests ----------------------------------------------------------------------

List<pw.Widget> _testSections(ReportModel m) {
  final out = <pw.Widget>[];
  for (final summary in m.summaries) {
    out
      ..add(pw.NewPage())
      ..add(_h1(testLabel(_en, summary.id)))
      ..add(
        _p(
          'Part of: ${summary.id.domains.map((d) => domainLabel(_en, d)).join(', ')}. '
          'Test of ${_date(m.latest!.completedAt)}.',
          color: _muted,
          size: 9,
        ),
      )
      ..add(_validityLine(summary))
      ..add(pw.SizedBox(height: 4))
      ..add(
        _table(
          [
            'Measurement', 'Value', 'Baseline', 'z', 'vs baseline', 'vs last',
            'vs avg of 4', 'Best', 'Worst', //
          ],
          [for (final metric in summary.metrics) _metricRow(metric)],
          widths: {
            0: const pw.FlexColumnWidth(2.4),
            1: const pw.FlexColumnWidth(1.3),
            2: const pw.FlexColumnWidth(1.5),
            3: const pw.FlexColumnWidth(0.8),
            4: const pw.FlexColumnWidth(1.2),
            5: const pw.FlexColumnWidth(1.1),
            6: const pw.FlexColumnWidth(1.2),
            7: const pw.FlexColumnWidth(1.1),
            8: const pw.FlexColumnWidth(1.1),
          },
        ),
      );

    for (final metric in summary.metrics) {
      out.addAll(_metricBlock(m, metric));
    }
  }
  return out;
}

pw.Widget _validityLine(TestSummary summary) {
  final String text;
  switch (summary.validity) {
    case TestValidity.valid:
      text = 'Status: counted.';
    case TestValidity.notMeasured:
      text = 'Status: not measured in this test.';
    case TestValidity.notCounted:
      text =
          'Status: not counted. ${_en.resNotCountedWhy(summary.contextReasons.map((r) => contextNoteLabel(_en, r)).join(', '))}';
  }
  return _p(text, size: 9);
}

List<String> _metricRow(MetricSummary s) {
  final key = s.spec.key;
  String v(double? x) => x == null ? '-' : formatFeatureValue(key, x);
  String c(Change? x) => x == null ? '-' : directionWord(_en, x);
  switch (s.state) {
    case MetricState.notMeasured:
      return [
        featureLabel(_en, key),
        'Not measured',
        '-',
        '-',
        '-',
        '-',
        '-',
        '-',
        '-',
      ];
    case MetricState.notCounted:
      return [
        featureLabel(_en, key),
        v(s.value),
        '-',
        '-',
        'Not counted',
        '-',
        '-',
        '-',
        '-',
      ];
    case MetricState.calibrating:
      return [
        featureLabel(_en, key),
        v(s.value),
        'Calibrating',
        '-',
        '-',
        '-',
        '-',
        v(s.best),
        v(s.worst),
      ];
    case MetricState.measured:
      return [
        featureLabel(_en, key),
        v(s.value),
        v(s.baselineMedian),
        _signed(s.zOriented!),
        changeWord(_en, s.vsBaseline!),
        c(s.vsPrevious),
        c(s.vsRolling),
        v(s.best),
        v(s.worst),
      ];
  }
}

/// One measurement: the sentence, the three-way comparison and the chart.
List<pw.Widget> _metricBlock(ReportModel m, MetricSummary s) {
  final key = s.spec.key;
  final series = m.series[key]!;
  final stats = m.metricStats[key]!;
  String v(double? x) => x == null ? '-' : formatFeatureValue(key, x);

  final range = s.reference;
  final population = range != null && range.isValidated
      ? 'Population range (context only): ${v(range.low)} to ${v(range.high)}. '
            'Source: ${range.sourceCitation}.'
      : _en.resPopulationNotValidated;

  final spread = s.baselineScale == null
      ? ''
      : formatFeatureSpread(key, s.baselineScale!).replaceFirst('±', '');
  final baselineLine =
      '1. Your baseline: ${v(s.baselineMedian)}, usually within $spread '
      '(the only comparison that sets your status).';
  final earlierLine =
      '2. Your earlier tests: last ${v(s.previous)}, average of the last four '
      '${v(s.rollingMean)}, best ${v(s.best)}, worst ${v(s.worst)}.';

  final lines = <String>[
    interpretMetric(_en, s),
    if (s.state == MetricState.measured) baselineLine,
    if (s.state == MetricState.measured || s.state == MetricState.calibrating)
      earlierLine,
    '3. $population',
    'Trend over the period: ${_trendLine(stats)}.',
  ];

  final points = series.points;
  final counted = series.counted;
  return [
    pw.SizedBox(height: 4),
    pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.5)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(featureLabel(_en, key), style: _style(size: 11, bold: true)),
          pw.SizedBox(height: 3),
          for (final line in lines) _p(line, size: 9),
          if (points.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pdfLineChart(
              points: [
                for (final p in points)
                  ChartPoint(value: p.value, counted: p.counted),
              ],
              smoothed: [for (final p in series.smoothed) p.value],
              domain: s.spec.domain,
              format: (x) => formatFeatureValue(key, x),
              firstDate: _date(points.first.at),
              lastDate: _date(points.last.at),
              median: series.baselineMedian,
              spread: series.baselineScale,
              population: range != null && range.isValidated
                  ? (low: range.low!, high: range.high!)
                  : null,
              height: 100,
            ),
            pw.SizedBox(height: 2),
            _p(
              'Filled marker: counted test. Hollow marker: set aside, not counted. Dashed line: '
              'your baseline. Shaded band: your usual spread. Dotted line: smoothed. '
              '${counted.length} counted of ${points.length} tests.',
              color: _muted,
              size: 7.5,
            ),
          ],
        ],
      ),
    ),
  ];
}

// -- log ----------------------------------------------------------------------------------

List<pw.Widget> _logSection(ReportModel m) {
  String kind(SessionLogRow row) => switch (row.kind) {
    LogKind.practice => 'Practice',
    LogKind.baseline => 'Baseline',
    LogKind.full => 'Full test',
  };
  String why(SessionLogRow row) {
    if (row.counted) return '';
    return switch (row.kind) {
      LogKind.practice => 'Practice only',
      LogKind.baseline when row.reasons.isEmpty => 'Builds the baseline',
      _ when row.reasons.isNotEmpty =>
        row.reasons.map((r) => contextNoteLabel(_en, r)).join(', '),
      _ => '',
    };
  }

  return [
    pw.NewPage(),
    _h1('Every test in the period'),
    _p(
      'Tests that were not counted are listed too, with the reason. They are left out of every '
      'average, best, worst and trend.',
      color: _muted,
      size: 9,
    ),
    if (m.log.isEmpty)
      _p('No tests in this period.')
    else
      _table(
        ['Date', 'Kind', 'Counted', 'Status', 'Index', 'Reason'],
        [
          for (final row in m.log)
            [
              _date(row.session.completedAt),
              kind(row),
              row.counted ? 'Yes' : 'Not counted',
              _statusWord(row.session.status),
              row.session.index == null
                  ? '-'
                  : row.session.index!.toStringAsFixed(2),
              why(row),
            ],
        ],
        widths: {
          0: const pw.FlexColumnWidth(1.4),
          1: const pw.FlexColumnWidth(1.1),
          2: const pw.FlexColumnWidth(1.1),
          3: const pw.FlexColumnWidth(2.2),
          4: const pw.FlexColumnWidth(0.8),
          5: const pw.FlexColumnWidth(2.4),
        },
      ),
  ];
}

// -- methods and limitations --------------------------------------------------------------

List<pw.Widget> _methods(ReportModel m) {
  final weights = kDomainWeights.entries
      .map((e) => '${domainLabel(_en, e.key)} ${(e.value * 100).round()}%')
      .join(', ');
  return [
    pw.NewPage(),
    _h1('Methods and limitations'),
    _h2('How the numbers are made'),
    _p(
      'Each test yields a few measurements, for example the time to react or the number of '
      'words remembered. Every measurement is compared with the same person\'s own usual '
      'value, not with other people. The usual value (the baseline) is the median of the '
      'person\'s first tests, and the usual spread is a robust estimate of how much it varies '
      'from day to day.',
    ),
    _p(
      'A measurement\'s z-score is how many usual spreads today\'s value is from the baseline, '
      'turned so that a positive number always means worse. Only worse-than-usual movement '
      'counts towards the overall index; improvement is shown but does not offset it.',
    ),
    _p(
      'The index combines the four areas ($weights). The weights are the project\'s own; if '
      'an area could not be measured in a test the others are re-weighted to total 100%. The '
      'index is smoothed with an exponentially weighted average (weight '
      '${kEwmaLambda.toStringAsFixed(1)} on the newest test). A change is called mild at '
      '${(kMildFraction * kDefaultThreshold).toStringAsFixed(1)} and notable at '
      '${kDefaultThreshold.toStringAsFixed(1)} only if it persists for $kDefaultPersistence '
      'tests in a row.',
    ),
    _p(
      'The trend lines use the Theil-Sen slope across counted tests, and are only stated from '
      '$kMinSessionsForTrend counted tests. A trend is called improving or declining only if '
      'the total change over the period is at least '
      '${kTrendMinChangeSds.toStringAsFixed(1)} usual spread; this threshold is provisional.',
    ),
    _p(
      'The five measurements of the three-step baseline test have a baseline from the baseline '
      'tests. The other thirteen have theirs set from the first $kExtensionTests counted full '
      'tests, and are shown as raw values until then.',
    ),
    _h2('What this report cannot tell you'),
    _p(
      'The measurements are affected by many things unrelated to health: sleep, tiredness, '
      'stress, illness, a noisy room, a different phone or how the test was held. Tests taken '
      'when the person reported poor sleep, heavy tiredness or illness are set aside and not '
      'counted.',
    ),
    _p(
      'The population ranges, where shown, are context only and are never used to decide '
      'anything. No range has been validated in this version of the app, so none is shown as '
      'a number. Some of the values the baseline uses to avoid an implausibly small spread '
      'are provisional estimates, not measured figures.',
    ),
    _p(
      'The app has not been clinically validated. Its results are not a medical finding of any '
      'kind, and should not be used to make decisions about health or treatment.',
    ),
    _p(
      'Baseline at the time of this report: ${_baselineStatusLine(m)}.',
      color: _muted,
      size: 9,
    ),
  ];
}
