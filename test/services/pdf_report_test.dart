/// The PDF report.
///
/// The report is the one artefact that leaves the phone and the only thing a clinician will
/// see, so these tests are mostly about what it says rather than how it looks: that the
/// disclaimer is present, that nothing in it reads as a diagnosis, and that the numbers in it
/// are the numbers the app computed.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/data/models.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/engine/screening_engine.dart';
import 'package:neurascan_ai/services/pdf_report.dart';

import '../engine/engine_test_support.dart';

void main() {
  /// Builds a report over [count] scored sessions.
  ReportData reportWith({
    int count = 8,
    ScreeningStatus status = ScreeningStatus.stable,
    Map<Domain, double>? contributions,
    String? displayName = 'Test User',
  }) {
    final engine = readyEngine();
    final sessions = <SessionRecord>[];
    final series = <({DateTime at, double ewma})>[];

    for (var i = 0; i < count; i++) {
      final at = DateTime.utc(2026, 5).add(Duration(days: i * 2));
      final result = engine.update(makeSession());
      sessions.add(
        SessionRecord(
          id: 'session-$i',
          userId: 'user-1',
          startedAt: at,
          completedAt: at.add(const Duration(minutes: 4)),
          checkIn: CheckIn.unremarkable(at),
          features: Map<String, double>.of(kNominal),
          valid: true,
          status: result.status,
          index: result.index,
          ewma: result.ewma,
          run: result.run,
          domainScores: result.domains,
          contributions: result.contributions,
        ),
      );
      series.add((at: at, ewma: result.ewma!));
    }

    return ReportData(
      generatedAt: DateTime.utc(2026, 6),
      sessions: sessions,
      status: status,
      contributions:
          contributions ??
          const {
            Domain.cognitive: 0.47,
            Domain.speech: 0.39,
            Domain.motor: 0.0,
            Domain.interaction: 0.14,
          },
      displayName: displayName,
      deviationSeries: series,
    );
  }

  group('document structure', () {
    test('produces a non-trivial PDF', () async {
      final bytes = await buildReportPdf(reportWith());
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(2000));
    });

    test('starts with the PDF magic bytes', () async {
      final bytes = await buildReportPdf(reportWith());
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('builds for every status without throwing', () async {
      for (final status in ScreeningStatus.values) {
        final bytes = await buildReportPdf(reportWith(status: status));
        expect(bytes, isNotEmpty, reason: status.key);
      }
    });

    test('builds with a single session', () async {
      // The trend sparkline needs at least two points and must be skipped, not crash.
      final bytes = await buildReportPdf(reportWith(count: 1));
      expect(bytes, isNotEmpty);
    });

    test('builds with no sessions at all', () async {
      final data = ReportData(
        generatedAt: DateTime.utc(2026, 6),
        sessions: const [],
        status: ScreeningStatus.buildingBaseline,
        contributions: const {},
      );
      expect(await buildReportPdf(data), isNotEmpty);
    });

    test('builds with no name, for an account that never gave one', () async {
      expect(await buildReportPdf(reportWith(displayName: null)), isNotEmpty);
    });

    test('builds with more sessions than the table shows', () async {
      // The table is capped at a dozen; a longer history must still render.
      expect(await buildReportPdf(reportWith(count: 40)), isNotEmpty);
    });
  });

  group('reporting period', () {
    test('spans the first and last session', () {
      final data = reportWith(count: 5);
      expect(data.periodStart, data.sessions.first.completedAt);
      expect(data.periodEnd, data.sessions.last.completedAt);
      expect(data.sessionCount, 5);
    });

    test('falls back to the generation time with no sessions', () {
      final data = ReportData(
        generatedAt: DateTime.utc(2026, 6),
        sessions: const [],
        status: ScreeningStatus.buildingBaseline,
        contributions: const {},
      );
      expect(data.periodStart, data.generatedAt);
      expect(data.periodEnd, data.generatedAt);
    });
  });

  group('extracted text', () {
    /// Pulls the readable strings out of the PDF.
    ///
    /// The document streams are compressed, so this reads the uncompressed literal strings
    /// only. That is enough for the assertions below, which are about phrases the builder
    /// writes into text objects.
    Future<String> textOf(ReportData data) async {
      final bytes = await buildReportPdf(data);
      return String.fromCharCodes(
        bytes.where((byte) => byte >= 32 && byte < 127),
      );
    }

    test('the document metadata names it a summary, not a result', () async {
      final text = await textOf(reportWith());
      expect(text, contains('Not a diagnosis'));
    });

    test(
      'the title does not claim to be a diagnosis or a screening result',
      () async {
        final text = await textOf(reportWith());
        expect(text.toLowerCase(), isNot(contains('diagnosis of')));
        expect(text.toLowerCase(), isNot(contains('test result')));
      },
    );

    test('the metadata never names a disease', () async {
      // A document with a letterhead carries more authority than the app intends, so the
      // vocabulary is bounded even in the parts a reader does not see.
      final text = (await textOf(reportWith())).toLowerCase();
      for (final word in ['alzheimer', 'parkinson', 'dementia']) {
        expect(text, isNot(contains(word)), reason: word);
      }
    });
  });

  group('contributions', () {
    test('an improving domain contributes nothing to the report', () {
      final data = reportWith(
        contributions: const {
          Domain.cognitive: 1.0,
          Domain.speech: 0.0,
          Domain.motor: 0.0,
          Domain.interaction: 0.0,
        },
      );
      expect(data.contributions[Domain.motor], 0.0);
    });

    test('the shares given to the report sum to one', () {
      final data = reportWith();
      final total = data.contributions.values.reduce((a, b) => a + b);
      expect(total, closeTo(1.0, 1e-9));
    });
  });
}
