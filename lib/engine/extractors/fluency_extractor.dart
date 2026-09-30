/// Scoring the verbal-fluency step.
///
/// The user types as many animals as they can in thirty seconds. Two features come out:
///
/// * `valid_word_count` -- how many different, real animals they named. Word retrieval under a
///   time limit is the classic fluency measure, and the count drops early in some cognitive
///   conditions.
/// * `fluency_half_ratio` -- how the second half compares with the first. A person whose
///   output collapses after the first fifteen seconds has a different pattern from one who
///   simply names fewer, steadily. It is `(late + 1) / (early + 1)`, where early and late are
///   the valid animals named in the first and last fifteen seconds; lower is worse. The plus
///   one keeps it defined for someone who named nothing in the first half, at the cost of
///   pulling every ratio a little towards one.
///
/// What counts as an animal is decided by a built-in list (see `animal_lexicon.dart`),
/// because the check must run on the device and offline. An entry is accepted when, after
/// trimming and lower-casing, it is on the list; or is the plural of a word on it; or is one
/// typing slip away from exactly one word on it (for words of five letters or more, the same
/// tolerance the word-recall step allows). Naming the same animal twice counts once. Anything
/// else is an intrusion and is not counted, but is not penalised beyond that.
///
/// Mirrors nothing in `engine_lab`: extraction is on-device only, and the engine never sees
/// the words, only the two numbers.
library;

import '../constants.dart';
import 'animal_lexicon.dart';
import 'memory_extractor.dart' show editDistance;

/// Shortest word a typing slip is forgiven in. Shorter words are too close to one another
/// (ant, ape, asp; bat, bar) for one edit to be safe.
const int kFluencyFuzzyMinLength = 5;

/// One entry the user added, with when they added it.
class FluencyEntry {
  const FluencyEntry({required this.text, required this.timestampMs});

  /// What the user typed, before any normalisation.
  final String text;

  /// Milliseconds after the step started.
  final int timestampMs;
}

/// What the fluency step produced.
class FluencyResult {
  const FluencyResult({
    required this.validWordCount,
    required this.earlyCount,
    required this.lateCount,
    required this.halfRatio,
    required this.validWords,
    required this.repeats,
    required this.intrusions,
  });

  /// Different, real animals named. The `valid_word_count` feature.
  final int validWordCount;

  /// Valid animals named in the first half of the time.
  final int earlyCount;

  /// Valid animals named in the second half.
  final int lateCount;

  /// `(late + 1) / (early + 1)`. The `fluency_half_ratio` feature.
  final double halfRatio;

  /// The animals that counted, as they appear in the list, in the order named.
  final List<String> validWords;

  /// Entries that repeated an animal already named.
  final int repeats;

  /// Entries that were not animals.
  final int intrusions;
}

/// Lower-cases [text], drops anything that is not a letter, mark or space, and collapses runs
/// of spaces.
String normaliseAnimal(String text) {
  final cleaned = text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\s]', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return cleaned;
}

/// The list entry that [text] names, or null if it is not an animal on [lexicon].
///
/// Exact match first, then a plural, then a single typing slip to one unique word.
String? matchAnimal(String text, Set<String> lexicon) {
  final word = normaliseAnimal(text);
  if (word.isEmpty) return null;
  if (lexicon.contains(word)) return word;

  // Plurals. Only ever tried on a word that is not itself on the list, so "bus"-like words
  // are not stripped, and only for scripts that have this kind of plural.
  if (word.endsWith('ies') &&
      lexicon.contains('${word.substring(0, word.length - 3)}y')) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.endsWith('es') &&
      lexicon.contains(word.substring(0, word.length - 2))) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s') &&
      lexicon.contains(word.substring(0, word.length - 1))) {
    return word.substring(0, word.length - 1);
  }

  if (word.length < kFluencyFuzzyMinLength) return null;
  String? found;
  for (final candidate in lexicon) {
    if (candidate.length < kFluencyFuzzyMinLength) continue;
    if (editDistance(word, candidate) <= 1) {
      // Two different animals both one slip away: the entry is ambiguous, so it is not
      // credited to either.
      if (found != null && found != candidate) return null;
      found = candidate;
    }
  }
  return found;
}

/// Scores [entries], typed in [languageCode], over [durationMs].
///
/// Entries stamped after [durationMs] are ignored: the step has ended.
FluencyResult extractFluencyFeatures(
  List<FluencyEntry> entries, {
  String languageCode = 'en',
  int durationMs = kFluencySeconds * 1000,
}) {
  final lexicon = animalsFor(languageCode);
  final ordered = [...entries]
    ..sort((a, b) => a.timestampMs.compareTo(b.timestampMs));

  final seen = <String>{};
  final valid = <String>[];
  var early = 0;
  var late = 0;
  var repeats = 0;
  var intrusions = 0;

  for (final entry in ordered) {
    if (entry.timestampMs > durationMs) continue;
    final animal = matchAnimal(entry.text, lexicon);
    if (animal == null) {
      if (normaliseAnimal(entry.text).isNotEmpty) intrusions++;
      continue;
    }
    if (!seen.add(animal)) {
      repeats++;
      continue;
    }
    valid.add(animal);
    if (entry.timestampMs < durationMs / 2) {
      early++;
    } else {
      late++;
    }
  }

  return FluencyResult(
    validWordCount: valid.length,
    earlyCount: early,
    lateCount: late,
    halfRatio: (late + 1) / (early + 1),
    validWords: valid,
    repeats: repeats,
    intrusions: intrusions,
  );
}
