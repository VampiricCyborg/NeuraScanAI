/// Delayed-recall scoring for the memory task.
///
/// The user is shown eight words, does three other tasks for about three
/// minutes, and then types back as many of the words as they remember. The
/// feature is simply the fraction recalled, but "recalled" needs defining: this
/// is typed on a phone keyboard by someone who may be in their seventies, so a
/// transposition or a dropped letter is a typing slip, not a memory failure.
///
/// Scoring therefore accepts a word within an edit distance of one. That is
/// generous enough to forgive "elehpant" but tight enough that it will not
/// silently match two different words from the same list -- which is why the
/// word lists are chosen so that no two entries are within two edits of each
/// other.
library;

import 'dart:math' as math;

/// Maximum edit distance at which a typed word still counts as recalled.
const int kRecallEditTolerance = 1;

/// Levenshtein distance between [a] and [b].
///
/// Uses two rolling rows rather than a full matrix. The words are short enough
/// that it hardly matters for speed, but it keeps the allocation per comparison
/// to two small lists, and this runs once per typed word per session.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);

  for (var i = 0; i < a.length; i++) {
    current[0] = i + 1;
    for (var j = 0; j < b.length; j++) {
      final substitutionCost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
      current[j + 1] = math.min(
        math.min(current[j] + 1, previous[j + 1] + 1),
        previous[j] + substitutionCost,
      );
    }
    final swap = previous;
    previous = current;
    current = swap;
  }

  return previous[b.length];
}

/// Normalises a word for comparison.
///
/// Case and surrounding whitespace carry no information here, and neither does
/// any punctuation the keyboard may have auto-inserted.
String normaliseWord(String word) =>
    word.trim().toLowerCase().replaceAll(RegExp(r'[^a-z஀-௿]'), '');

/// The outcome of scoring one delayed-recall attempt.
class RecallResult {
  const RecallResult({
    required this.fraction,
    required this.matched,
    required this.missed,
    required this.extras,
  });

  /// Words recalled divided by words presented, in 0..1. This is the
  /// `delayed_recall` feature.
  final double fraction;

  /// Presented words the user recalled, in presentation order.
  final List<String> matched;

  /// Presented words the user did not recall.
  final List<String> missed;

  /// Words the user typed that matched nothing on the list.
  ///
  /// Not scored -- intrusions are interesting clinically but we have no baseline
  /// for them -- but shown on the summary screen so the user can see what
  /// happened rather than just a number.
  final List<String> extras;

  int get recalledCount => matched.length;
}

/// Scores [typed] against the [presented] word list.
///
/// Each presented word can be claimed only once, and each typed word can claim
/// only one presented word, so typing the same word three times does not score
/// three times. Ties are resolved by the smaller edit distance, then by
/// presentation order, which keeps the result deterministic.
RecallResult scoreRecall({
  required List<String> presented,
  required List<String> typed,
}) {
  if (presented.isEmpty) {
    return const RecallResult(
      fraction: 0.0,
      matched: [],
      missed: [],
      extras: [],
    );
  }

  final normalisedPresented = presented.map(normaliseWord).toList();
  final claimed = List<bool>.filled(presented.length, false);
  final extras = <String>[];

  for (final raw in typed) {
    final candidate = normaliseWord(raw);
    if (candidate.isEmpty) continue;

    var bestIndex = -1;
    var bestDistance = kRecallEditTolerance + 1;
    for (var i = 0; i < normalisedPresented.length; i++) {
      if (claimed[i]) continue;
      final distance = editDistance(candidate, normalisedPresented[i]);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    if (bestIndex >= 0 && bestDistance <= kRecallEditTolerance) {
      claimed[bestIndex] = true;
    } else {
      extras.add(raw.trim());
    }
  }

  final matched = <String>[];
  final missed = <String>[];
  for (var i = 0; i < presented.length; i++) {
    (claimed[i] ? matched : missed).add(presented[i]);
  }

  return RecallResult(
    fraction: matched.length / presented.length,
    matched: matched,
    missed: missed,
    extras: extras,
  );
}
