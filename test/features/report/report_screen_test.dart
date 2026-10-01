/// The report screen: choosing what goes in, the consent dialog, and what is handed over.
///
/// Delivery is replaced with a recording fake, since the real one opens system sheets. Everything
/// else is real: the providers, the database, the model and the PDF, CSV and JSON builders.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/l10n/generated/app_localizations.dart';
import 'package:neurascan_ai/app/theme.dart';
import 'package:neurascan_ai/features/report/export/report_delivery.dart';
import 'package:neurascan_ai/features/report/report_screen.dart';

import '../../app/seed_history.dart';
import '../../app/test_harness.dart';

/// A delivery that records what it was asked to do.
class RecordingDelivery extends ReportDelivery {
  final calls = <({String action, String fileName, Uint8List bytes})>[];
  bool saves = true;

  @override
  Future<bool> share({
    required String fileName,
    required Uint8List bytes,
    required ExportFormat format,
    String? subject,
  }) async {
    calls.add((action: 'share', fileName: fileName, bytes: bytes));
    return true;
  }

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required ExportFormat format,
  }) async {
    calls.add((action: 'save', fileName: fileName, bytes: bytes));
    return saves;
  }

  @override
  Future<bool> printPdf({
    required String fileName,
    required Uint8List bytes,
  }) async {
    calls.add((action: 'print', fileName: fileName, bytes: bytes));
    return true;
  }
}

void main() {
  late RecordingDelivery delivery;

  Future<TestApp> screen(WidgetTester tester, {int fullTests = 4}) async {
    final app = await pumpApp(tester, signedIn: consentPendingAccount);
    await completeOnboarding(app);
    await tester.pumpAndSettle();
    if (fullTests > 0) await seed(app, history(actual: fullTests));

    delivery = RecordingDelivery();
    final container = ProviderContainer(
      parent: app.container,
      overrides: [reportDeliveryProvider.overrideWithValue(delivery)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          localizationsDelegates: AppText.localizationsDelegates,
          supportedLocales: AppText.supportedLocales,
          home: const ReportScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return app;
  }

  /// Taps [label], lets real asynchronous work (the PDF build) finish, and settles.
  Future<void> tapAndWait(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 800)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('before any full test the report says to take one', (
    tester,
  ) async {
    await screen(tester, fullTests: 0);

    expect(find.text('Save to device'), findsNothing);
    expect(find.text('Share'), findsNothing);
  });

  testWidgets(
    'offers the period, the sections, a label and the export actions',
    (tester) async {
      await screen(tester);

      for (final label in ['Last 7 tests', '30 days', '90 days', 'All']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      for (final label in [
        'A page for each area',
        'A section for each of the eight tests',
        'Every test in the period',
        'Methods and limitations',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(find.byKey(const ValueKey('report-label')), findsOneWidget);
      expect(find.text('Preview the PDF'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Save to device'), findsOneWidget);
      expect(find.text('Print'), findsOneWidget);
      expect(find.text('Save data as CSV'), findsOneWidget);
      expect(find.text('Save data as JSON'), findsOneWidget);
    },
  );

  testWidgets('says what the report will contain', (tester) async {
    await screen(tester);

    expect(
      find.textContaining('4 counted tests and 0 set aside'),
      findsOneWidget,
    );
    expect(find.text('The PDF is written in English.'), findsOneWidget);
  });

  testWidgets('every export asks first, and cancelling hands over nothing', (
    tester,
  ) async {
    await screen(tester);

    await tapAndWait(tester, 'Share');
    expect(find.text('Before you export'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(delivery.calls, isEmpty);
  });

  testWidgets('sharing, once confirmed, hands over the PDF with its dated name', (
    tester,
  ) async {
    await screen(tester);

    await tapAndWait(tester, 'Share');
    await confirm(tester);

    expect(delivery.calls, hasLength(1));
    final call = delivery.calls.single;
    final now = DateTime.now();
    final date =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(call.action, 'share');
    expect(call.fileName, 'NeuraScan_Report_$date.pdf');
    expect(latin1.decode(call.bytes.sublist(0, 5)), '%PDF-');
  });

  testWidgets('each export asks again, not just the first', (tester) async {
    await screen(tester);

    await tapAndWait(tester, 'Share');
    await confirm(tester);
    await tapAndWait(tester, 'Save to device');
    expect(find.text('Before you export'), findsOneWidget);
    await confirm(tester);

    expect(delivery.calls.map((c) => c.action), ['share', 'save']);
  });

  testWidgets('saving, printing, CSV and JSON each go to the right place', (
    tester,
  ) async {
    await screen(tester);

    await tapAndWait(tester, 'Print');
    await confirm(tester);
    await tapAndWait(tester, 'Save data as CSV');
    await confirm(tester);
    await tapAndWait(tester, 'Save data as JSON');
    await confirm(tester);

    expect(delivery.calls.map((c) => c.action), ['print', 'save', 'save']);
    expect(delivery.calls[1].fileName, endsWith('.csv'));
    expect(delivery.calls[2].fileName, endsWith('.json'));
    expect(utf8.decode(delivery.calls[1].bytes), startsWith('completed_at,'));
    expect(
      jsonDecode(utf8.decode(delivery.calls[2].bytes)),
      containsPair('app', 'NeuraScan AI'),
    );
  });

  testWidgets('a save the user backs out of says nothing was saved', (
    tester,
  ) async {
    await screen(tester);
    delivery.saves = false;

    await tapAndWait(tester, 'Save to device');
    await confirm(tester);

    expect(find.text('Nothing was saved.'), findsOneWidget);
  });

  testWidgets('a save that worked says so', (tester) async {
    await screen(tester);

    await tapAndWait(tester, 'Save to device');
    await confirm(tester);

    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('the data files say they never hold audio or touch recordings', (
    tester,
  ) async {
    await screen(tester);

    await tester.scrollUntilVisible(
      find.textContaining('never include audio'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('never include audio or touch recordings'),
      findsOneWidget,
    );
  });

  testWidgets('the sections can be unticked', (tester) async {
    await screen(tester);

    final tile = find.byKey(const ValueKey('section-log'));
    expect(tester.widget<CheckboxListTile>(tile).value, isTrue);
    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(tile).value, isFalse);
  });

  testWidgets('the label is editable', (tester) async {
    await screen(tester);

    await tester.enterText(
      find.byKey(const ValueKey('report-label')),
      'My report',
    );
    await tester.pump();
    expect(find.text('My report'), findsOneWidget);
  });
}
