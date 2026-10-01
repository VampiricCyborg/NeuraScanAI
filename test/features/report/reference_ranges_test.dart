/// The population reference ranges.
///
/// What is protected here is honesty: the file ships with no invented numbers, and nothing that
/// is not a complete, published, cited entry is ever treated as a real range.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/features.dart';
import 'package:neurascan_ai/features/report/reference_ranges.dart';

String doc(List<Map<String, Object?>> ranges) =>
    jsonEncode({'version': 1, 'ranges': ranges});

Map<String, Object?> entry({
  String metric = 'delayed_recall',
  String ageBand = 'all',
  Object? low = 0.5,
  Object? high = 0.9,
  String? citation = 'Example et al. 2020',
  String level = 'published',
}) => {
  'metric': metric,
  'age_band': ageBand,
  'low': low,
  'high': high,
  'unit': 'fraction',
  'source_citation': citation,
  'evidence_level': level,
};

void main() {
  group('the file that ships', () {
    final shipped = ReferenceRanges.parse(
      File('assets/reference_ranges.json').readAsStringSync(),
    );

    test('has an entry for every measurement', () {
      for (final key in kFeatureKeys) {
        expect(shipped.forMetric(key), isNotNull, reason: key);
      }
    });

    test('has nothing else', () {
      expect(shipped.entries, hasLength(kFeatureKeys.length));
    });

    test('marks every entry as a placeholder', () {
      for (final range in shipped.entries) {
        expect(
          range.evidenceLevel,
          EvidenceLevel.placeholder,
          reason: range.metric,
        );
      }
    });

    test('contains no invented number', () {
      for (final range in shipped.entries) {
        expect(range.low, isNull, reason: range.metric);
        expect(range.high, isNull, reason: range.metric);
      }
    });

    test('contains no citation', () {
      for (final range in shipped.entries) {
        expect(range.sourceCitation, isNull, reason: range.metric);
      }
    });

    test('has no validated range, so nothing is ever shown as one', () {
      for (final key in kFeatureKeys) {
        expect(shipped.validatedFor(key), isNull, reason: key);
        expect(shipped.forMetric(key)!.isValidated, isFalse, reason: key);
      }
    });

    test('carries the units of the measurements', () {
      for (final spec in kFeatureSpecs) {
        expect(shipped.forMetric(spec.key)!.unit, spec.unit, reason: spec.key);
      }
    });

    test('says in its own note that nothing has been sourced', () {
      final decoded = jsonDecode(
        File('assets/reference_ranges.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final note = decoded['note'] as String;
      expect(note.toLowerCase(), contains('placeholder'));
    });

    test('has every field the brief asks for', () {
      final decoded = jsonDecode(
        File('assets/reference_ranges.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final raw = decoded['ranges'] as List;
      for (final row in raw.cast<Map<String, dynamic>>()) {
        expect(
          row.keys.toSet(),
          containsAll([
            'metric',
            'age_band',
            'low',
            'high',
            'unit',
            'source_citation',
            'evidence_level',
          ]),
        );
      }
    });
  });

  group('what counts as validated', () {
    test('a complete, published, cited entry does', () {
      final ranges = ReferenceRanges.parse(doc([entry()]));
      expect(ranges.forMetric('delayed_recall')!.isValidated, isTrue);
      expect(ranges.validatedFor('delayed_recall'), isNotNull);
    });

    test('a published entry with no citation does not', () {
      final ranges = ReferenceRanges.parse(doc([entry(citation: null)]));
      expect(ranges.forMetric('delayed_recall')!.isValidated, isFalse);
    });

    test('a published entry with a blank citation does not', () {
      final ranges = ReferenceRanges.parse(doc([entry(citation: '   ')]));
      expect(ranges.forMetric('delayed_recall')!.isValidated, isFalse);
    });

    test('a published entry missing a bound does not', () {
      expect(
        ReferenceRanges.parse(doc([entry(low: null)]))
            .validatedFor('delayed_recall'),
        isNull,
      );
      expect(
        ReferenceRanges.parse(doc([entry(high: null)]))
            .validatedFor('delayed_recall'),
        isNull,
      );
    });

    test('a published entry with the bounds the wrong way round does not', () {
      expect(
        ReferenceRanges.parse(doc([entry(low: 0.9, high: 0.5)]))
            .validatedFor('delayed_recall'),
        isNull,
      );
    });

    test('numbers and a citation do not help a placeholder', () {
      // A half-filled row must not pass for a real one.
      final ranges = ReferenceRanges.parse(doc([entry(level: 'placeholder')]));
      expect(ranges.forMetric('delayed_recall')!.isValidated, isFalse);
    });

    test('an evidence level it does not recognise is a placeholder', () {
      final ranges = ReferenceRanges.parse(
        doc([entry(level: 'gold-standard')]),
      );
      expect(
        ranges.forMetric('delayed_recall')!.evidenceLevel,
        EvidenceLevel.placeholder,
      );
      expect(ranges.forMetric('delayed_recall')!.isValidated, isFalse);
    });

    test('a missing evidence level is a placeholder', () {
      final row = entry()..remove('evidence_level');
      expect(
        ReferenceRanges.parse(doc([row]))
            .forMetric('delayed_recall')!
            .evidenceLevel,
        EvidenceLevel.placeholder,
      );
    });
  });

  group('looking one up', () {
    test('finds the band asked for', () {
      final ranges = ReferenceRanges.parse(
        doc([entry(low: 0.4, high: 0.8), entry(ageBand: '60-69')]),
      );
      expect(ranges.forMetric('delayed_recall', ageBand: '60-69')!.low, 0.5);
    });

    test('falls back to the band that covers everyone', () {
      final ranges = ReferenceRanges.parse(doc([entry(low: 0.4, high: 0.8)]));
      expect(ranges.forMetric('delayed_recall', ageBand: '70-79')!.low, 0.4);
    });

    test('is null for a metric with no entry', () {
      final ranges = ReferenceRanges.parse(doc([entry()]));
      expect(ranges.forMetric('tap_rate'), isNull);
    });

    test('a band with no entry and no general one is null', () {
      final ranges = ReferenceRanges.parse(doc([entry(ageBand: '60-69')]));
      expect(ranges.forMetric('delayed_recall', ageBand: '20-29'), isNull);
    });

    test('nothing is null for an empty set', () {
      expect(ReferenceRanges.none.forMetric('delayed_recall'), isNull);
    });
  });

  group('a damaged file', () {
    test('that is not JSON gives no ranges rather than an error', () {
      expect(ReferenceRanges.parse('not json').entries, isEmpty);
    });

    test('that is the wrong shape gives none', () {
      expect(ReferenceRanges.parse('[1, 2]').entries, isEmpty);
      expect(ReferenceRanges.parse('{"ranges": 3}').entries, isEmpty);
    });

    test('with a bad row keeps the good ones', () {
      final ranges = ReferenceRanges.parse(
        jsonEncode({
          'ranges': [
            {'no_metric': true},
            entry(),
          ],
        }),
      );
      expect(ranges.entries, hasLength(1));
    });
  });

  test('a range round-trips through JSON', () {
    final range = ReferenceRanges.parse(doc([entry()]))
        .forMetric('delayed_recall')!;
    final again = ReferenceRange.fromJson(range.toJson());
    expect(again.low, range.low);
    expect(again.high, range.high);
    expect(again.sourceCitation, range.sourceCitation);
    expect(again.evidenceLevel, range.evidenceLevel);
  });
}
