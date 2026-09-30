/// The rotating word lists for the memory task.
///
/// Rotation matters more than it looks. Asking for the same eight words every session
/// would measure how well the user had learned that list, and their recall would climb
/// for weeks -- which is exactly the drift the app is built to detect, pointing the
/// wrong way. So there are several lists and a session does not reuse the one before it.
///
/// Within a list, no two words are within two edits of each other. The recall scorer
/// accepts a word one edit away to forgive a typing slip, and if two words on the same
/// list were that close, a slip on one would silently be credited as the other.
///
/// The lists are matched for the properties that make a word easy to remember: all are
/// concrete, familiar nouns of two or three syllables, with no semantic category shared
/// by more than two words in a list -- because a list that happens to contain four
/// animals is easier than one that does not, and the baseline cannot tell the difference
/// between an easier list and a better day.
library;

import 'dart:math';

/// One set of words presented together.
class WordList {
  const WordList({required this.id, required this.words});

  /// Stable identifier, stored with the session so rotation is reproducible.
  final int id;

  final List<String> words;

  int get length => words.length;
}

/// The English lists.
const List<WordList> kEnglishWordLists = [
  WordList(
    id: 1,
    words: [
      'elephant',
      'harbour',
      'ribbon',
      'copper',
      'violin',
      'tunnel',
      'blanket',
      'meadow',
    ],
  ),
  WordList(
    id: 2,
    words: [
      'lantern',
      'cabbage',
      'marble',
      'sparrow',
      'kettle',
      'anchor',
      'pumpkin',
      'thistle',
    ],
  ),
  WordList(
    id: 3,
    words: [
      'jasmine',
      'bucket',
      'whistle',
      'camel',
      'pillow',
      'granite',
      'trumpet',
      'orchard',
    ],
  ),
  WordList(
    id: 4,
    words: [
      'mango',
      'saddle',
      'lizard',
      'curtain',
      'pepper',
      'compass',
      'walnut',
      'stadium',
    ],
  ),
  WordList(
    id: 5,
    words: [
      'candle',
      'dolphin',
      'bracelet',
      'turnip',
      'mirror',
      'falcon',
      'cushion',
      'quarry',
    ],
  ),
  WordList(
    id: 6,
    words: [
      'basket',
      'peacock',
      'hammer',
      'coconut',
      'window',
      'beetle',
      'napkin',
      'valley',
    ],
  ),
];

/// The Tamil lists.
///
/// Not translations of the English ones. A translated list would inherit English word
/// lengths and syllable counts, and the point of a list is that its words are equally
/// easy to hold in mind for the person hearing them in their own language.
const List<WordList> kTamilWordLists = [
  WordList(
    id: 101,
    words: [
      'யானை',
      'துறைமுகம்',
      'ரிப்பன்',
      'செம்பு',
      'வயலின்',
      'சுரங்கம்',
      'கம்பளி',
      'புல்வெளி',
    ],
  ),
  WordList(
    id: 102,
    words: [
      'விளக்கு',
      'முட்டைகோஸ்',
      'பலகை',
      'சிட்டுக்குருவி',
      'கெட்டில்',
      'நங்கூரம்',
      'பூசணி',
      'முள்செடி',
    ],
  ),
  WordList(
    id: 103,
    words: [
      'மல்லிகை',
      'வாளி',
      'விசில்',
      'ஒட்டகம்',
      'தலையணை',
      'கருங்கல்',
      'எக்காளம்',
      'தோட்டம்',
    ],
  ),
  WordList(
    id: 104,
    words: [
      'மாம்பழம்',
      'சேணம்',
      'பல்லி',
      'திரைச்சீலை',
      'மிளகு',
      'திசைகாட்டி',
      'அக்ரூட்',
      'மைதானம்',
    ],
  ),
];

/// The lists available for [languageCode].
List<WordList> wordListsFor(String languageCode) =>
    languageCode == 'ta' ? kTamilWordLists : kEnglishWordLists;

/// Picks the list for a session.
///
/// Cycles by session index so that consecutive sessions never repeat a list, and a
/// given list does not come round again until every other one has been used.
///
/// The order is a shuffle that is fixed per cycle, so a user does not see the same
/// sequence on every pass, but the same session index always gives the same list. That
/// determinism is deliberate: the list a session used is stored with it, and a replay or a
/// test has to be able to reproduce the choice. An earlier version drew a fresh random
/// offset on every call, which let two consecutive sessions land on the same list.
WordList pickWordList({required int sessionIndex, String languageCode = 'en'}) {
  final lists = wordListsFor(languageCode);
  if (lists.length == 1) return lists.first;

  final cycle = sessionIndex ~/ lists.length;
  final order = _cycleOrder(cycle, lists.length);
  return lists[order[sessionIndex % lists.length]];
}

/// The order lists are used in during [cycle], as indices into the language's lists.
List<int> _cycleOrder(int cycle, int length) {
  List<int> shuffled(int forCycle) {
    // Cycle zero keeps the natural order, so a new user's first pass is predictable.
    final order = List<int>.generate(length, (i) => i);
    if (forCycle > 0) order.shuffle(Random(forCycle * 7919 + 13));
    return order;
  }

  final order = shuffled(cycle);
  if (cycle == 0) return order;

  // The last list of one pass must not be the first of the next, or two consecutive
  // sessions would share a list across the boundary.
  final previousLast = shuffled(cycle - 1).last;
  if (order.first == previousLast) {
    final swap = order[0];
    order[0] = order[1];
    order[1] = swap;
  }
  return order;
}
