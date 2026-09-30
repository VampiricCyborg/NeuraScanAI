/// The rotating word lists.
///
/// The properties asserted here are the ones that would silently corrupt the cognitive
/// measurement if they broke: a repeated list would be learned rather than recalled, and two
/// words close enough to confuse would credit a typing slip as a remembered word.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/engine/constants.dart';
import 'package:neurascan_ai/engine/extractors/memory_extractor.dart';
import 'package:neurascan_ai/features/session/word_lists.dart';

void main() {
  group('list contents', () {
    test('every list has the expected number of words', () {
      for (final list in [...kEnglishWordLists, ...kTamilWordLists]) {
        expect(list.length, kMemoryWordCount, reason: 'list ${list.id}');
      }
    });

    test('there is more than one list to rotate between', () {
      expect(kEnglishWordLists.length, greaterThan(1));
      expect(kTamilWordLists.length, greaterThan(1));
    });

    test('list ids are unique across languages', () {
      final ids = [
        for (final list in [...kEnglishWordLists, ...kTamilWordLists]) list.id,
      ];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('no two words within a list are close enough to confuse', () {
      // The scorer accepts a word one edit away to forgive a typing slip. If two words on
      // the same list were within two edits of each other, a slip on one would silently be
      // credited as the other.
      for (final list in kEnglishWordLists) {
        for (var i = 0; i < list.words.length; i++) {
          for (var j = i + 1; j < list.words.length; j++) {
            expect(
              editDistance(list.words[i], list.words[j]),
              greaterThan(2 * kRecallEditTolerance),
              reason:
                  'list ${list.id}: "${list.words[i]}" and "${list.words[j]}"',
            );
          }
        }
      }
    });

    test('no word appears on two different lists of the same language', () {
      // A word shared between lists would be seen more often than the rotation intends.
      final seen = <String, int>{};
      for (final list in kEnglishWordLists) {
        for (final word in list.words) {
          expect(
            seen.containsKey(word),
            isFalse,
            reason: '"$word" is on lists ${seen[word]} and ${list.id}',
          );
          seen[word] = list.id;
        }
      }
    });

    test('no word is duplicated within a list', () {
      for (final list in [...kEnglishWordLists, ...kTamilWordLists]) {
        expect(list.words.toSet(), hasLength(list.words.length));
      }
    });

    test('Tamil lists are not transliterations of the English ones', () {
      // A translated list would inherit English word lengths and syllable counts, and the
      // point of a list is that its words are equally easy to hold in mind for the person
      // hearing them in their own language.
      final english = {for (final l in kEnglishWordLists) ...l.words};
      for (final list in kTamilWordLists) {
        for (final word in list.words) {
          expect(english.contains(word), isFalse);
        }
      }
    });
  });

  group('language selection', () {
    test('Tamil returns the Tamil lists', () {
      expect(wordListsFor('ta'), kTamilWordLists);
    });

    test('English returns the English lists', () {
      expect(wordListsFor('en'), kEnglishWordLists);
    });

    test('an unknown language falls back to English rather than failing', () {
      expect(wordListsFor('fr'), kEnglishWordLists);
    });
  });

  group('rotation', () {
    test('consecutive sessions never repeat a list', () {
      // The property that matters: repeating a list measures how well it was learned.
      var previous = pickWordList(sessionIndex: 0);
      for (var session = 1; session < 200; session++) {
        final next = pickWordList(sessionIndex: session);
        expect(next.id, isNot(previous.id), reason: 'at session $session');
        previous = next;
      }
    });

    test('every list is used once in every pass before any is reused', () {
      const lists = kEnglishWordLists;
      for (var cycle = 0; cycle < 10; cycle++) {
        final pass = {
          for (var i = 0; i < lists.length; i++)
            pickWordList(sessionIndex: cycle * lists.length + i).id,
        };
        expect(pass, hasLength(lists.length), reason: 'cycle $cycle');
      }
    });

    test('a later cycle is not identical to the first', () {
      // Without this, a user doing hundreds of sessions would see a perfectly predictable
      // order and could anticipate the list.
      final first = [
        for (var i = 0; i < kEnglishWordLists.length; i++)
          pickWordList(sessionIndex: i).id,
      ];
      final later = [
        for (var i = 0; i < kEnglishWordLists.length; i++)
          pickWordList(sessionIndex: kEnglishWordLists.length + i).id,
      ];
      expect(later, isNot(first));
    });

    test('the same session index always gives the same list', () {
      // Needed so a test or a replay can reproduce which list a session used.
      for (var i = 0; i < 20; i++) {
        expect(
          pickWordList(sessionIndex: i).id,
          pickWordList(sessionIndex: i).id,
        );
      }
    });

    test('Tamil rotates too', () {
      var previous = pickWordList(sessionIndex: 0, languageCode: 'ta');
      for (var session = 1; session < 20; session++) {
        final next = pickWordList(sessionIndex: session, languageCode: 'ta');
        expect(next.id, isNot(previous.id));
        previous = next;
      }
    });

    test('always returns a list, however large the session index', () {
      expect(
        pickWordList(sessionIndex: 99999).words,
        hasLength(kMemoryWordCount),
      );
    });
  });
}
