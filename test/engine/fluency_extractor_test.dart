/// Scoring the verbal-fluency step.
///
/// What is being protected: the count must be of real, different animals only, so that naming
/// one animal five times, or typing nonsense, cannot look like fluency; and a typing slip must
/// not cost a correct answer.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/extractors/animal_lexicon.dart';
import 'package:neurascan_ai/engine/extractors/fluency_extractor.dart';

FluencyEntry at(int seconds, String text) =>
    FluencyEntry(text: text, timestampMs: seconds * 1000);

void main() {
  group('what counts as an animal', () {
    test('a word on the list counts', () {
      final result = extractFluencyFeatures([at(3, 'elephant')]);
      expect(result.validWordCount, 1);
      expect(result.validWords, ['elephant']);
    });

    test('case and surrounding space do not matter', () {
      final result = extractFluencyFeatures([at(2, '  TiGeR  ')]);
      expect(result.validWords, ['tiger']);
    });

    test('punctuation is ignored', () {
      final result = extractFluencyFeatures([at(2, 'lion,'), at(4, 'zebra!')]);
      expect(result.validWordCount, 2);
    });

    test('a plural is credited to the animal', () {
      final result = extractFluencyFeatures([at(2, 'dogs'), at(5, 'foxes')]);
      expect(result.validWords, ['dog', 'fox']);
    });

    test('a plural in -ies is credited', () {
      // "pony" is on the list; "ponies" is its plural.
      final result = extractFluencyFeatures([at(2, 'ponies')]);
      expect(result.validWords, ['pony']);
    });

    test('a word that is not an animal is an intrusion and does not count', () {
      final result = extractFluencyFeatures([at(1, 'table'), at(2, 'cat')]);
      expect(result.validWordCount, 1);
      expect(result.intrusions, 1);
    });

    test('an empty entry is neither counted nor an intrusion', () {
      final result = extractFluencyFeatures([at(1, '   '), at(2, '!!')]);
      expect(result.validWordCount, 0);
      expect(result.intrusions, 0);
    });

    test('naming the same animal twice counts once', () {
      final result = extractFluencyFeatures([
        at(1, 'cat'),
        at(2, 'cat'),
        at(3, 'Cats'),
      ]);
      expect(result.validWordCount, 1);
      expect(result.repeats, 2);
    });

    test('a single typing slip on a longer word is forgiven', () {
      final result = extractFluencyFeatures([at(2, 'elephent')]);
      expect(result.validWords, ['elephant']);
    });

    test('a slip on a short word is not, because short words are too alike', () {
      // "bet" is one edit from "bat" and from "bee": not safe to credit either.
      final result = extractFluencyFeatures([at(2, 'bet')]);
      expect(result.validWordCount, 0);
    });

    test(
      'an entry one slip from two different animals is credited to neither',
      () {
        // Both "tiger" and "tigar"-like ambiguity: a word between two list entries.
        final ambiguous = matchAnimal('goate', {'goats', 'goatt'});
        expect(ambiguous, isNull);
      },
    );

    test('a word two edits away is not credited', () {
      final result = extractFluencyFeatures([at(2, 'elefunt')]);
      expect(result.validWordCount, 0);
    });
  });

  group('timing', () {
    test('an entry exactly at the halfway mark is in the second half', () {
      final result = extractFluencyFeatures([at(15, 'cat')]);
      expect(result.lateCount, 1);
      expect(result.earlyCount, 0);
    });

    test('entries are split between the two halves', () {
      final result = extractFluencyFeatures([
        at(2, 'cat'),
        at(6, 'dog'),
        at(10, 'cow'),
        at(20, 'hen'),
        at(28, 'pig'),
      ]);
      expect(result.earlyCount, 3);
      expect(result.lateCount, 2);
    });

    test('entries after the step ended are ignored', () {
      final result = extractFluencyFeatures([at(5, 'cat'), at(31, 'dog')]);
      expect(result.validWordCount, 1);
    });

    test('entries are scored in time order, whatever order they arrive in', () {
      final result = extractFluencyFeatures([at(20, 'dog'), at(2, 'cat')]);
      expect(result.validWords, ['cat', 'dog']);
    });

    test('a repeat is judged by its first appearance', () {
      // Named early, repeated late: counted once, in the first half.
      final result = extractFluencyFeatures([at(3, 'cat'), at(25, 'cat')]);
      expect(result.earlyCount, 1);
      expect(result.lateCount, 0);
    });
  });

  group('the half ratio', () {
    test('a steady namer has a ratio near one', () {
      final result = extractFluencyFeatures([
        at(3, 'cat'),
        at(8, 'dog'),
        at(12, 'cow'),
        at(18, 'hen'),
        at(22, 'pig'),
        at(27, 'fox'),
      ]);
      expect(result.halfRatio, 1.0);
    });

    test('someone whose output dries up has a ratio below one', () {
      final result = extractFluencyFeatures([
        at(1, 'cat'),
        at(3, 'dog'),
        at(5, 'cow'),
        at(8, 'hen'),
        at(12, 'pig'),
        at(28, 'fox'),
      ]);
      expect(result.earlyCount, 5);
      expect(result.lateCount, 1);
      expect(result.halfRatio, closeTo(2 / 6, 1e-12));
    });

    test('naming nothing in the first half does not divide by zero', () {
      final result = extractFluencyFeatures([at(20, 'cat'), at(25, 'dog')]);
      expect(result.halfRatio, closeTo(3.0, 1e-12));
    });

    test('naming nothing at all gives exactly one', () {
      final result = extractFluencyFeatures(const []);
      expect(result.validWordCount, 0);
      expect(result.halfRatio, 1.0);
    });
  });

  group('languages', () {
    test('Tamil animals are read from the Tamil list', () {
      final result = extractFluencyFeatures([
        at(2, 'யானை'),
        at(5, 'புலி'),
      ], languageCode: 'ta');
      expect(result.validWordCount, 2);
    });

    test('an English animal is not credited in a Tamil test', () {
      final result = extractFluencyFeatures([
        at(2, 'elephant'),
      ], languageCode: 'ta');
      expect(result.validWordCount, 0);
    });

    test('an unknown language is treated as English', () {
      expect(animalsFor('fr'), kEnglishAnimals);
    });
  });

  group('the lists', () {
    test('are large enough to cover the obvious answers', () {
      expect(kEnglishAnimals.length, greaterThan(100));
      expect(kTamilAnimals.length, greaterThan(60));
    });

    test('are lower case and trimmed', () {
      for (final word in kEnglishAnimals) {
        expect(word, normaliseAnimal(word), reason: word);
      }
      for (final word in kTamilAnimals) {
        expect(word, normaliseAnimal(word), reason: word);
      }
    });

    test('every English animal matches itself', () {
      for (final word in kEnglishAnimals) {
        expect(matchAnimal(word, kEnglishAnimals), word);
      }
    });

    test('every Tamil animal matches itself', () {
      for (final word in kTamilAnimals) {
        expect(matchAnimal(word, kTamilAnimals), word);
      }
    });
  });
}
