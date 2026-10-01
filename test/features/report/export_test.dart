/// The report's PDF, CSV and JSON, built from a seeded forty-test history.
///
/// These run the real builders end to end: the history comes from a real engine, the model from
/// the same calculators the screens use, and the PDF is built and read back. They check that the
/// report exists, that the disclaimer is where it must be, that nothing but derived data is in
/// the exports, and that the sections the user chooses are the ones that appear.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/features/report/export/pdf/report_pdf.dart';
import 'package:neurascan_ai/features/report/export/report_files.dart';
import 'package:neurascan_ai/features/report/export/report_model.dart';
import 'package:neurascan_ai/features/report/models.dart';
import 'package:neurascan_ai/features/report/reference_ranges.dart';

import 'report_fixtures.dart';

ReportModel modelFor(
  Fixture fixture, {
  ReportOptions options = const ReportOptions(),
  DateTime? now,
}) => buildReportModel(
  sessions: fixture.sessions,
  baseline: fixture.baseline,
  ranges: ReferenceRanges.none,
  options: options,
  now: now ?? fixture.sessions.last.completedAt.add(const Duration(days: 1)),
);

/// The PDF's text, in reading order. Built uncompressed so it can be read back: the document
/// stores each word as its own text run, so the words are joined with spaces.
Future<String> pdfText(ReportModel model) async {
  final built = await buildReportPdf(model, compress: false);
  return pdfWords(built.bytes);
}

String pdfWords(List<int> bytes) {
  final raw = latin1.decode(bytes, allowInvalid: true);
  final runs = RegExp(r'\[\(((?:[^()\\]|\\.)*)\)\]TJ');
  final escape = RegExp(r'\\(.)');
  return runs
      .allMatches(raw)
      .map((m) => m.group(1)!.replaceAllMapped(escape, (e) => e.group(1)!))
      .join(' ');
}

void main() {
  // Forty full tests, a few of them set aside, with a steady slow decline.
  final fixture = buildFixture(
    fullTests: 40,
    setAside: {5, 17, 30},
    declineSds: 0.04,
  );

  group('the file name', () {
    test('is NeuraScan_Report_<yyyy-mm-dd>.pdf', () {
      expect(
        reportFileName(DateTime(2026, 3, 7, 18, 30)),
        'NeuraScan_Report_2026-03-07.pdf',
      );
    });

    test('keeps the date for the data files too', () {
      expect(
        reportFileName(DateTime(2026, 12, 2), extension: 'csv'),
        'NeuraScan_Report_2026-12-02.csv',
      );
    });
  });

  group('the report model', () {
    test('counts the valid tests and the ones set aside', () {
      final model = modelFor(fixture);
      expect(model.setAsideTests, 3);
      expect(model.validTests, 37);
    });

    test('lists every test, counted or not, in the log', () {
      final model = modelFor(fixture);
      // The practice and baseline tests are listed too: nothing is silently dropped.
      expect(model.log.length, fixture.sessions.length);
      expect(model.log.where((r) => !r.counted), isNotEmpty);
    });

    test('covers a period of the last seven tests', () {
      final model = modelFor(
        fixture,
        options: const ReportOptions(period: TrendRange.last7),
      );
      expect(
        model.sessions.where((s) => s.completedAt.isAfter(model.from)),
        isNotEmpty,
      );
      expect(model.indexPoints.length, lessThanOrEqualTo(7));
    });

    test('a period with no full tests is empty', () {
      final model = modelFor(
        fixture,
        now: DateTime(2020),
        options: const ReportOptions(period: TrendRange.days30),
      );
      expect(model.isEmpty, isTrue);
    });

    test('trend statistics are only given with enough valid tests', () {
      final short = buildFixture(fullTests: 4);
      final model = modelFor(short);
      expect(model.indexStats.enough, isFalse);
      expect(modelFor(fixture).indexStats.enough, isTrue);
    });
  });

  group('the PDF', () {
    test('is built, and has pages', () async {
      final built = await buildReportPdf(modelFor(fixture));
      expect(built.pageCount, greaterThan(0));
      expect(built.bytes.length, greaterThan(1000));
      // A PDF starts with its signature.
      expect(latin1.decode(built.bytes.sublist(0, 5)), '%PDF-');
    });

    test('a full report runs to many pages: cover, summary, areas, eight tests, log, methods', () async {
      final built = await buildReportPdf(modelFor(fixture));
      // Cover, summary, four areas, eight tests, the log and the methods, at the least.
      expect(built.pageCount, greaterThanOrEqualTo(16));
    });

    test('carries the mandated disclaimer on the cover, the summary and the last page', () async {
      final model = modelFor(fixture);
      final text = await pdfText(model);
      final count = 'This is a screening and awareness tool'
          .allMatches(text)
          .length;
      // Cover, summary, and the closing page, at least.
      expect(count, greaterThanOrEqualTo(3));
    });

    test('the disclaimer is word for word what was asked for', () {
      expect(
        pdfDisclaimer(),
        'This is a screening and awareness tool, not a diagnosis. Many things such as stress, '
        'poor sleep or illness can change results. If you are concerned, please discuss this '
        'report with a doctor.',
      );
    });

    test(
      'has the disclaimer on the last page whichever sections are chosen',
      () async {
        final model = modelFor(
          fixture,
          options: const ReportOptions(sections: {}),
        );
        final text = await pdfText(model);
        expect(
          'This is a screening and awareness tool'.allMatches(text).length,
          greaterThanOrEqualTo(3),
        );
      },
    );

    test('leaves out the sections the user did not choose', () async {
      final everything = await buildReportPdf(modelFor(fixture));
      final minimal = await buildReportPdf(
        modelFor(fixture, options: const ReportOptions(sections: {})),
      );
      expect(minimal.pageCount, lessThan(everything.pageCount));

      final text = await pdfText(
        modelFor(fixture, options: const ReportOptions(sections: {})),
      );
      expect(text.contains('Methods and limitations'), isFalse);
      expect(text.contains('Every test in the period'), isFalse);
    });

    test('puts the user\'s label on the cover', () async {
      final text = await pdfText(
        modelFor(
          fixture,
          options: const ReportOptions(userLabel: 'Test Person'),
        ),
      );
      expect(text.contains('Test Person'), isTrue);
    });

    test('states the versions and the baseline status on the cover', () async {
      final text = await pdfText(modelFor(fixture));
      expect(text.contains(kAppVersion), isTrue);
      expect(text.contains('Scoring version'), isTrue);
      expect(text.contains('Baseline'), isTrue);
    });

    test(
      'shows the population range as not yet validated, with no number',
      () async {
        final text = await pdfText(modelFor(fixture));
        expect(text.contains('Reference range not yet validated'), isTrue);
      },
    );

    test(
      'never says diagnosis outside the disclaimer, or "you have"',
      () async {
        final text = await pdfText(modelFor(fixture));
        final outside = text.replaceAll(pdfDisclaimer(), '').toLowerCase();
        for (final w in ['diagnos', 'disease', 'you have']) {
          final i = outside.indexOf(w);
          expect(
            i,
            -1,
            reason: i < 0
                ? ''
                : '$w: ...${outside.substring(i < 40 ? 0 : i - 40, i + 40)}...',
          );
        }
      },
    );

    test(
      'an empty period still produces a short report with the disclaimer',
      () async {
        final model = modelFor(
          fixture,
          now: DateTime(2020),
          options: const ReportOptions(period: TrendRange.days30),
        );
        final built = await buildReportPdf(model, compress: false);
        expect(built.pageCount, greaterThan(0));
        expect(
          pdfWords(built.bytes)
              .contains('This is a screening and awareness tool'),
          isTrue,
        );
      },
    );

    test('holds no raw audio or touch trace data', () async {
      final text = (await pdfText(modelFor(fixture))).toLowerCase();
      for (final word in [
        'waveform',
        'pcm',
        'touch trace',
        'raw audio',
        'samples',
      ]) {
        expect(text.contains(word), isFalse, reason: word);
      }
    });
  });

  group('the CSV', () {
    test('has a header and one row for every test', () {
      final model = modelFor(fixture);
      final lines = const LineSplitter().convert(buildCsv(model));
      expect(lines.length, 1 + model.log.length);
    });

    test('has only the allowed columns', () {
      final header = const LineSplitter()
          .convert(buildCsv(modelFor(fixture)))
          .first
          .split(',');
      expect(header, [...kExportedSessionFields, ...kExportedFeatureKeys]);
    });

    test('every row has as many cells as the header', () {
      final lines = const LineSplitter().convert(buildCsv(modelFor(fixture)));
      final width = lines.first.split(',').length;
      for (final line in lines) {
        expect(line.split(',').length, width);
      }
    });

    test('marks a test that was not counted', () {
      final csv = buildCsv(modelFor(fixture));
      expect(csv.contains(',false,'), isTrue);
      expect(csv.contains(',true,'), isTrue);
    });
  });

  group('the JSON', () {
    final model = modelFor(fixture);
    final data = jsonDecode(buildJson(model)) as Map<String, dynamic>;

    test('holds the allowed top-level fields and no others', () {
      expect(data.keys.toSet(), {
        'app',
        'app_version',
        'scoring_version',
        'generated_at',
        'period',
        'note',
        'baseline',
        'sessions',
        'trends',
        'metric_trends',
      });
    });

    test('each test has only the allowed fields', () {
      final allowed = {...kExportedSessionFields, ...kExportedFeatureKeys};
      for (final session in data['sessions'] as List) {
        expect((session as Map).keys.toSet(), allowed);
      }
    });

    test('lists every test', () {
      expect((data['sessions'] as List).length, model.log.length);
    });

    test('says what it is not', () {
      expect(data['note'] as String, contains('No audio, no touch traces'));
    });

    test('has the baseline of each measurement that has one', () {
      final baseline = data['baseline'] as Map<String, dynamic>;
      expect(baseline.keys, everyElement(isIn(kFeatureKeys)));
      expect(baseline, isNotEmpty);
    });
  });
}
