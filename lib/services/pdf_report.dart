/// The shareable PDF report.
///
/// This is the one artefact that leaves the phone by the user's own hand, and the only one
/// a clinician will ever see. Two things follow from that.
///
/// It has to be readable by someone who has never used the app. A doctor given a sheet of
/// z-scores will discard it, so the report leads with what changed and how confident the
/// measurement is, and explains the method in a paragraph rather than assuming it.
///
/// It must not read as a diagnosis. A document with a letterhead and a percentage carries
/// more authority than the app intends, so the disclaimer is on the first page, in the body
/// rather than a footnote, and the language throughout describes measurements rather than
/// findings.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/models.dart';
import '../engine/comparison.dart';
import '../engine/constants.dart';
import '../engine/features.dart';
import '../engine/scoring.dart';
import '../engine/screening_engine.dart';
import '../features/trends/baseline_format.dart';

/// Everything the report needs.
class ReportData {
  const ReportData({
    required this.generatedAt,
    required this.sessions,
    required this.status,
    required this.contributions,
    this.displayName,
    this.deviationSeries = const [],
    this.comparison,
  });

  final DateTime generatedAt;

  /// Scored sessions in the reporting period, oldest first.
  final List<SessionRecord> sessions;

  final ScreeningStatus status;
  final Map<Domain, double> contributions;
  final String? displayName;

  /// The smoothed index over the period, for the sparkline.
  final List<({DateTime at, double ewma})> deviationSeries;

  /// The latest full test against the baseline and the test before it, when there is one.
  final TestComparison? comparison;

  DateTime get periodStart =>
      sessions.isEmpty ? generatedAt : sessions.first.completedAt;

  DateTime get periodEnd =>
      sessions.isEmpty ? generatedAt : sessions.last.completedAt;

  int get sessionCount => sessions.length;
}

/// Brand colour, matching the app.
const _brand = PdfColor.fromInt(0xFF146C7A);
const _ink = PdfColor.fromInt(0xFF1A1C1E);
const _muted = PdfColor.fromInt(0xFF5B6770);
const _rule = PdfColor.fromInt(0xFFD5DEE1);

/// Per-domain colours, matching the app so a report and a screen agree.
const _domainColors = <String, PdfColor>{
  'cognitive': PdfColor.fromInt(0xFF146C7A),
  'speech': PdfColor.fromInt(0xFF7A5BA6),
  'motor': PdfColor.fromInt(0xFFB4530A),
};

/// Builds the PDF.
Future<Uint8List> buildReportPdf(ReportData data) async {
  final document = pw.Document(
    title: 'NeuraScan AI behavioural screening report',
    author: 'NeuraScan AI',
    // Named as a summary rather than a result, for the same reason the wording inside is
    // careful: the subject line is what a recipient reads first.
    subject: 'Behavioural measurement summary. Not a diagnosis.',
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 40, 42, 48),
      footer: (context) => _footer(context, data),
      build: (context) => [
        _header(data),
        pw.SizedBox(height: 18),
        _disclaimerBox(),
        pw.SizedBox(height: 18),
        _statusBlock(data),
        pw.SizedBox(height: 18),
        if (data.comparison != null) ...[
          _comparisonBlock(data.comparison!),
          pw.SizedBox(height: 18),
        ],
        if (data.deviationSeries.length >= 2) ...[
          _trendBlock(data),
          pw.SizedBox(height: 18),
        ],
        _contributionBlock(data),
        pw.SizedBox(height: 18),
        _methodBlock(),
        pw.SizedBox(height: 18),
        _sessionTable(data),
      ],
    ),
  );

  return document.save();
}

pw.Widget _header(ReportData data) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'NeuraScan AI',
                style: const pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                  color: _brand,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                'Behavioural measurement summary',
                style: const pw.TextStyle(fontSize: 11, color: _muted),
              ),
            ],
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              if (data.displayName != null)
                pw.Text(
                  data.displayName!,
                  style: const pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              pw.Text(
                'Prepared ${_formatDate(data.generatedAt)}',
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
              pw.Text(
                '${_formatDate(data.periodStart)} to ${_formatDate(data.periodEnd)}',
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
              pw.Text(
                '${data.sessionCount} full test${data.sessionCount == 1 ? '' : 's'}',
                style: const pw.TextStyle(fontSize: 9, color: _muted),
              ),
            ],
          ),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Divider(color: _rule, thickness: 1),
    ],
  );
}

/// The disclaimer, in the body of the first page.
pw.Widget _disclaimerBox() {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: const PdfColor.fromInt(0xFFF2F6F7),
      border: pw.Border.all(color: _rule),
      borderRadius: pw.BorderRadius.circular(6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'This is not a diagnosis.',
          style: const pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'NeuraScan AI measures how one person\'s performance on a set of short '
          'smartphone tasks changes over time, compared with that same person\'s '
          'earlier measurements. It does not compare against a clinical population, '
          'has not been clinically validated, and cannot indicate the presence or '
          'absence of any condition. A change in these measurements has many ordinary '
          'explanations, including sleep, mood, medication and practice. This document '
          'is intended to support a conversation with a clinician, not to replace one.',
          style: const pw.TextStyle(fontSize: 9, color: _ink, lineSpacing: 1.6),
        ),
      ],
    ),
  );
}

pw.Widget _statusBlock(ReportData data) {
  final (heading, body) = switch (data.status) {
    ScreeningStatus.stable => (
      'Measurements within the usual range',
      'Across this period the smoothed deviation index stayed below the threshold. '
          'Performance on all three measured areas remained consistent with this '
          'person\'s own established baseline.',
    ),
    ScreeningStatus.mildDeviation => (
      'Some movement from the usual range',
      'The smoothed deviation index rose above the informational level but did not '
          'persist for the required number of consecutive tests. This is common '
          'and frequently resolves without further change.',
    ),
    ScreeningStatus.notableDeviation => (
      'A sustained change from the usual range',
      'The smoothed deviation index remained above the threshold for '
          '$kDefaultPersistence consecutive valid tests, which is the condition '
          'the app uses to distinguish a persistent shift from day-to-day variation. '
          'The contributing areas are broken down below.',
    ),
    ScreeningStatus.buildingBaseline => (
      'Baseline not yet established',
      'The baseline tests have not all been completed, so no comparison against a '
          'personal baseline is available yet.',
    ),
    ScreeningStatus.excludedContext => (
      'Most recent test set aside',
      'The most recent test was excluded from the trend because the pre-test '
          'check-in reported poor sleep, heavy fatigue, or illness or a medication '
          'change.',
    ),
    ScreeningStatus.invalidSession => (
      'Most recent test not counted',
      'The most recent test did not meet the task quality checks and was excluded.',
    ),
  };

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Summary'),
      pw.SizedBox(height: 8),
      pw.Text(
        heading,
        style: const pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.Text(body, style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.6)),
    ],
  );
}

/// The latest full test against the baseline and the previous test, measurement by measurement.
pw.Widget _comparisonBlock(TestComparison comparison) {
  String word(Change? change) => switch (change) {
    Change.better => 'Better',
    Change.similar => 'About the same',
    Change.worse => 'Worse',
    null => '--',
  };

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Latest test compared with baseline and previous test'),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: const [
          'Measurement',
          'This test',
          'Usual',
          'Previous',
          'Against usual',
          'Against previous',
        ],
        headerStyle: const pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: 8.5),
        headerDecoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF2F6F7),
        ),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          for (var i = 1; i <= 5; i++) i: pw.Alignment.centerRight,
        },
        border: pw.TableBorder.all(color: _rule, width: 0.5),
        data: [
          for (final m in comparison.measurements)
            [
              m.spec.label,
              formatFeatureValue(m.spec.key, m.value),
              formatFeatureValue(m.spec.key, m.baselineMedian),
              m.previous == null
                  ? '--'
                  : formatFeatureValue(m.spec.key, m.previous!),
              word(m.vsBaseline),
              word(m.vsPrevious),
            ],
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Better and worse are judged against how much each measurement usually varies '
        'for this person: a change of less than one usual spread is reported as about '
        'the same.',
        style: const pw.TextStyle(fontSize: 8, color: _muted, lineSpacing: 1.4),
      ),
    ],
  );
}

/// A sparkline of the smoothed index with the threshold marked.
pw.Widget _trendBlock(ReportData data) {
  final values = data.deviationSeries.map((point) => point.ewma).toList();
  final highest = values.reduce((a, b) => a > b ? a : b);
  final ceiling =
      (highest > kDefaultThreshold ? highest : kDefaultThreshold) * 1.15;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Smoothed deviation over the period'),
      pw.SizedBox(height: 8),
      pw.Container(
        height: 110,
        width: double.infinity,
        decoration: pw.BoxDecoration(border: pw.Border.all(color: _rule)),
        child: pw.CustomPaint(
          size: const PdfPoint(500, 110),
          painter: (canvas, size) {
            const left = 4.0;
            final right = size.x - 4;
            const bottom = 6.0;
            final top = size.y - 6;

            double xFor(int index) =>
                left + (right - left) * index / (values.length - 1);
            double yFor(double value) =>
                bottom + (top - bottom) * (value / ceiling).clamp(0.0, 1.0);

            // Threshold line.
            canvas
              ..setStrokeColor(const PdfColor.fromInt(0xFFB4530A))
              ..setLineWidth(0.8)
              ..setLineDashPattern([3, 3])
              ..moveTo(left, yFor(kDefaultThreshold))
              ..lineTo(right, yFor(kDefaultThreshold))
              ..strokePath()
              ..setLineDashPattern();

            // The series.
            canvas
              ..setStrokeColor(_brand)
              ..setLineWidth(1.4)
              ..moveTo(xFor(0), yFor(values.first));
            for (var i = 1; i < values.length; i++) {
              canvas.lineTo(xFor(i), yFor(values[i]));
            }
            canvas.strokePath();
          },
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Solid line: smoothed deviation index. Dashed line: the level treated as '
        'notable. Horizontal axis is test number, not calendar time, because '
        'tests are not evenly spaced.',
        style: const pw.TextStyle(fontSize: 8, color: _muted, lineSpacing: 1.4),
      ),
    ],
  );
}

pw.Widget _contributionBlock(ReportData data) {
  final percentages = contributionPercentages(data.contributions);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Where the change is coming from'),
      pw.SizedBox(height: 8),
      pw.Text(
        'These shares are exact rather than estimated: the deviation index is a '
        'weighted sum, so each area\'s share of the total is its contribution. They '
        'sum to 100%. A change in one area often shows up in others, which is why all '
        'three are reported.',
        style: const pw.TextStyle(fontSize: 9, color: _muted, lineSpacing: 1.5),
      ),
      pw.SizedBox(height: 12),
      for (final domain in Domain.values)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 7),
          child: pw.Row(
            children: [
              pw.Container(
                width: 88,
                child: pw.Text(
                  domain.label,
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ),
              // Two flexed boxes rather than a fraction of a stack: package:pdf has
              // no FractionallySizedBox, and flex weights lay out identically.
              pw.Expanded(
                child: pw.Container(
                  height: 12,
                  decoration: pw.BoxDecoration(
                    color: const PdfColor.fromInt(0xFFEDF1F2),
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Expanded(
                        flex: (percentages[domain] ?? 0).clamp(0, 100),
                        child: pw.Container(
                          decoration: pw.BoxDecoration(
                            color: _domainColors[domain.key] ?? _brand,
                            borderRadius: pw.BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      pw.Expanded(
                        flex: (100 - (percentages[domain] ?? 0)).clamp(0, 100),
                        child: pw.SizedBox(),
                      ),
                    ],
                  ),
                ),
              ),
              pw.Container(
                width: 38,
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '${percentages[domain] ?? 0}%',
                  style: const pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

/// How the numbers were produced.
///
/// Included because a clinician cannot judge a measurement without knowing how it was
/// taken, and because the method is the honest answer to "how much should I trust this".
pw.Widget _methodBlock() {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('How these measurements were taken'),
      pw.SizedBox(height: 8),
      pw.Text(
        'Every test is made of three kinds of step on the person\'s own smartphone: '
        'recall of an eight-word list after other steps, twenty seconds of spoken '
        'picture description, and tracing a three-turn guide spiral. Five features '
        'are extracted on the device: the share of words recalled, speaking rate, '
        'the share of time spent pausing, tracing error and a tremor index.\n\n'
        'The baseline is set by four short tests of three steps each. The first is a '
        'practice run and is discarded to reduce the practice effect; the next '
        '$kBaselineSessions fix a median and a median absolute deviation for each '
        'feature, which are then frozen as that person\'s baseline. Because a spread '
        'estimated from so few tests is unreliable, it is never allowed to fall below '
        'half of the feature\'s typical day-to-day variation. The baseline can be set '
        'again by the user; earlier tests are kept but no longer counted.\n\n'
        'A full test has eight steps: three word lists, three picture descriptions and '
        'two spiral tracings. Each feature is measured several times in a test and the '
        'test\'s value is the median of those repeats, so one unusual step cannot define '
        'the result. Each full test is expressed as robust z-scores against the '
        'baseline, averaged within three areas, weighted (cognitive 40%, speech 30%, '
        'motor 30%) and summed, counting only changes in the worse direction. It is '
        'also compared with the previous full test.\n\n'
        'The result is smoothed with an exponentially weighted moving average and a '
        'sustained change is reported only after $kDefaultPersistence consecutive '
        'valid tests above threshold, so a single test does not raise it. Tests where '
        'a pre-test check-in reported poor sleep, heavy fatigue, or illness or a '
        'medication change are recorded but excluded from both the baseline and the '
        'trend.\n\n'
        'Audio is analysed on the device and deleted immediately afterwards; no '
        'recording, touch trace or typed text is stored or transmitted.',
        style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.6),
      ),
    ],
  );
}

pw.Widget _sessionTable(ReportData data) {
  // The most recent dozen. A full history would run to pages and a clinician reading this
  // wants the recent trend, not an archive.
  final recent = data.sessions.length <= 12
      ? data.sessions
      : data.sessions.sublist(data.sessions.length - 12);

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _sectionTitle('Recent full tests'),
      pw.SizedBox(height: 8),
      pw.TableHelper.fromTextArray(
        headers: const ['Date', 'Cognitive', 'Speech', 'Motor', 'Smoothed'],
        headerStyle: const pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
        ),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF2F6F7),
        ),
        cellAlignments: {
          0: pw.Alignment.centerLeft,
          for (var i = 1; i <= 4; i++) i: pw.Alignment.centerRight,
        },
        border: pw.TableBorder.all(color: _rule, width: 0.5),
        data: [
          for (final session in recent)
            [
              _formatDate(session.completedAt),
              _formatScore(session.domainScores?[Domain.cognitive]),
              _formatScore(session.domainScores?[Domain.speech]),
              _formatScore(session.domainScores?[Domain.motor]),
              session.ewma?.toStringAsFixed(2) ?? '--',
            ],
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        'Area figures are robust z-scores against this person\'s own baseline: 0 is '
        'their usual level, positive is worse, negative is better. Only tests '
        'included in the trend are listed.',
        style: const pw.TextStyle(fontSize: 8, color: _muted, lineSpacing: 1.4),
      ),
    ],
  );
}

pw.Widget _footer(pw.Context context, ReportData data) {
  return pw.Column(
    children: [
      pw.Divider(color: _rule, thickness: 0.5),
      pw.SizedBox(height: 4),
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'NeuraScan AI 1.0.0 -- screening and awareness only, not a diagnosis',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
          pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _sectionTitle(String title) => pw.Text(
  title.toUpperCase(),
  style: const pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: _brand,
    letterSpacing: 0.8,
  ),
);

String _formatScore(double? score) =>
    score == null ? '--' : score.toStringAsFixed(2);

/// A date a reader in any locale can parse unambiguously.
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
