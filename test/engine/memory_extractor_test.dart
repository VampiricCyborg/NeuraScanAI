/// Delayed-recall scoring.
///
/// The interesting cases are all about the edit-distance tolerance: it has to
/// forgive a typing slip without quietly awarding a word the user did not
/// remember.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/memory_extractor.dart';

void main() {
  const presented = [
    'elephant',
    'harbour',
    'ribbon',
    'copper',
    'violin',
    'tunnel',
    'blanket',
    'meadow',
  ];

  group('edit distance', () {
    test('identical words are zero apart', () {
      expect(editDistance('violin', 'violin'), 0);
    });

    test('one substitution is one apart', () {
      expect(editDistance('violin', 'violon'), 1);
    });

    test('one deletion is one apart', () {
      expect(editDistance('violin', 'viotin'), 1);
      expect(editDistance('violin', 'iolin'), 1);
    });

    test('one insertion is one apart', () {
      expect(editDistance('violin', 'violins'), 1);
    });

    test('a transposition costs two, being a delete plus an insert', () {
      // Levenshtein has no transposition operation, which is why the tolerance is
      // one: admitting two edits to catch swaps would also start matching
      // genuinely different words.
      expect(editDistance('violin', 'voilin'), 2);
    });

    test('an empty word costs the length of the other', () {
      expect(editDistance('', 'ribbon'), 6);
      expect(editDistance('ribbon', ''), 6);
      expect(editDistance('', ''), 0);
    });

    test('distance is symmetric', () {
      expect(editDistance('harbour', 'harbor'), editDistance('harbor', 'harbour'));
    });
  });

  group('word normalisation', () {
    test('case and surrounding whitespace are ignored', () {
      expect(normaliseWord('  Elephant '), 'elephant');
    });

    test('punctuation the keyboard added is stripped', () {
      expect(normaliseWord('ribbon,'), 'ribbon');
      expect(normaliseWord("copper's"), 'coppers');
    });

    test('Tamil script survives normalisation', () {
      // The recall task runs in Tamil too, so the filter must not strip the
      // script it is meant to accept.
      expect(normaliseWord(' யானை '), 'யானை');
    });
  });

  group('recall scoring', () {
    test('a perfect recall scores one', () {
      final result = scoreRecall(presented: presented, typed: presented);
      expect(result.fraction, 1.0);
      expect(result.recalledCount, 8);
      expect(result.missed, isEmpty);
      expect(result.extras, isEmpty);
    });

    test('recalling nothing scores zero', () {
      final result = scoreRecall(presented: presented, typed: const []);
      expect(result.fraction, 0.0);
      expect(result.missed, hasLength(8));
    });

    test('half the words scores one half', () {
      final result = scoreRecall(
        presented: presented,
        typed: const ['elephant', 'harbour', 'ribbon', 'copper'],
      );
      expect(result.fraction, 0.5);
    });

    test('a dropped letter still counts as recalled', () {
      final result = scoreRecall(
        presented: presented,
        typed: const ['elephnt'],
      );
      expect(result.recalledCount, 1);
      expect(result.matched, ['elephant']);
    });

    test('a transposition does not count, being two edits away', () {
      // The cost of a tolerance of one: a swapped pair of letters reads as a
      // delete plus an insert, so 'elehpant' is rejected even though a human
      // would call it a slip. Widening the tolerance to two would fix that and
      // start matching genuinely different words instead, which is the worse
      // failure -- it would credit the user with a word they did not recall.
      final result = scoreRecall(presented: presented, typed: const ['elehpant']);
      expect(editDistance('elehpant', 'elephant'), 2);
      expect(result.recalledCount, 0);
      expect(result.extras, ['elehpant']);
    });

    test('punctuation is stripped before matching, not counted as an edit', () {
      // 'elepant2' normalises to 'elepant', which is one edit from 'elephant'.
      final result = scoreRecall(presented: presented, typed: const ['elepant2']);
      expect(result.recalledCount, 1);
      expect(result.matched, ['elephant']);
    });

    test('typing the same word three times scores once', () {
      final result = scoreRecall(
        presented: presented,
        typed: const ['violin', 'violin', 'violin'],
      );
      expect(result.recalledCount, 1);
      expect(result.extras, hasLength(2));
    });

    test('an unrelated word is recorded as an extra, not scored', () {
      final result = scoreRecall(
        presented: presented,
        typed: const ['violin', 'bicycle'],
      );
      expect(result.recalledCount, 1);
      expect(result.extras, ['bicycle']);
    });

    test('blank entries are ignored rather than counted as extras', () {
      final result = scoreRecall(
        presented: presented,
        typed: const ['violin', '', '   ', ','],
      );
      expect(result.recalledCount, 1);
      expect(result.extras, isEmpty);
    });

    test('a nearer word wins when two are within tolerance', () {
      // 'copper' is one edit from 'coppe'; 'copper' itself is exact, so the exact
      // match must take it.
      final result = scoreRecall(
        presented: const ['copper', 'coppe'],
        typed: const ['copper'],
      );
      expect(result.matched, ['copper']);
      expect(result.missed, ['coppe']);
    });

    test('matched and missed together account for every presented word', () {
      final result = scoreRecall(
        presented: presented,
        typed: const ['elephant', 'ribbon', 'meadow'],
      );
      expect(result.matched.length + result.missed.length, presented.length);
    });

    test('matched words keep their presentation order', () {
      final result = scoreRecall(
        presented: presented,
        typed: const ['meadow', 'elephant'],
      );
      expect(result.matched, ['elephant', 'meadow']);
    });

    test('an empty presented list scores zero rather than dividing by zero', () {
      final result = scoreRecall(presented: const [], typed: const ['anything']);
      expect(result.fraction, 0.0);
    });

    test('no two words on a list are within the tolerance of each other', () {
      // The word lists must not contain a pair that the tolerance could confuse,
      // or a slip on one word would silently score the other.
      for (var i = 0; i < presented.length; i++) {
        for (var j = i + 1; j < presented.length; j++) {
          expect(
            editDistance(presented[i], presented[j]),
            greaterThan(2 * kRecallEditTolerance),
            reason: '${presented[i]} and ${presented[j]} are too close',
          );
        }
      }
    });
  });
}
