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

  group('the lists for one test', () {
    // Each test now has one word-memory step, but the picker still supports a test with
    // several lists, and the rule that none repeats within a test or straight after the last
    // test's final one is worth keeping for any count.
    const kListsPerTest = 3;

    // A full test learns and recalls three lists. Two of them being the same would make the
    // second a repeat of what was just learned, and a list returning too soon would be
    // recalled from practice rather than from memory.
    for (final language in ['en', 'ta']) {
      test('a full test never has the same list twice ($language)', () {
        for (var test = 0; test < 60; test++) {
          final lists = pickWordListsForTest(
            testIndex: test,
            count: kListsPerTest,
            languageCode: language,
          );
          expect(lists, hasLength(kListsPerTest));
          expect(
            {for (final list in lists) list.id},
            hasLength(kListsPerTest),
            reason: 'test $test',
          );
        }
      });

      test(
        'the next test does not open with the list the last one closed on ($language)',
        () {
          var previous = pickWordListsForTest(
            testIndex: 0,
            count: kListsPerTest,
            languageCode: language,
          );
          for (var test = 1; test < 60; test++) {
            final next = pickWordListsForTest(
              testIndex: test,
              count: kListsPerTest,
              languageCode: language,
            );
            expect(
              next.first.id,
              isNot(previous.last.id),
              reason: 'test $test',
            );
            previous = next;
          }
        },
      );

      test('a baseline test never repeats the list before it ($language)', () {
        var previous = pickWordListsForTest(
          testIndex: 0,
          count: 1,
          languageCode: language,
        ).single;
        for (var test = 1; test < 60; test++) {
          final next = pickWordListsForTest(
            testIndex: test,
            count: 1,
            languageCode: language,
          ).single;
          expect(next.id, isNot(previous.id), reason: 'test $test');
          previous = next;
        }
      });

      test('the same test always gets the same lists ($language)', () {
        List<int> ids(int test) => [
          for (final list in pickWordListsForTest(
            testIndex: test,
            count: kListsPerTest,
            languageCode: language,
          ))
            list.id,
        ];
        for (var test = 0; test < 20; test++) {
          expect(ids(test), ids(test));
        }
      });
    }

    test('there are enough lists that a full test does not use most of them', () {
      // Three lists a test out of a small pool would bring each one back within a couple of
      // tests. Twice the number a test needs is the least that spaces them out.
      expect(kEnglishWordLists.length, greaterThanOrEqualTo(kListsPerTest * 3));
      expect(kTamilWordLists.length, greaterThanOrEqualTo(kListsPerTest * 2));
    });
  });
}
