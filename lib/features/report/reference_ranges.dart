/// Population reference ranges, shown for context and never used to decide anything.
///
/// The app's whole approach is to judge a person against their own baseline, because a range
/// for "people in general" says little about one individual. A reference range is still useful
/// context -- it lets a reader see how a personal baseline sits against a population -- so it can
/// be shown, with two hard rules:
///
/// * **It is never a verdict.** Nothing here, and nothing that reads it, calls a value normal or
///   abnormal. The range is drawn as a shaded band and quoted as a range, nothing more.
/// * **It is only shown when it has a source.** The numbers live in `assets/reference_ranges.json`
///   and every entry that ships is a placeholder: no value has been sourced. An entry counts as
///   validated only if it is marked `published`, has both bounds and has a citation. Anything
///   else is shown as "Reference range not yet validated", whatever numbers it carries, so a
///   half-filled row cannot pass for a real one.
///
/// To add a range, see `docs/REPORT_MODULE.md`.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// How well supported a range is.
enum EvidenceLevel {
  /// Taken from a cited source.
  published,

  /// A slot waiting for a source. Carries no claim.
  placeholder;

  /// The level named [key], or [placeholder] for anything unrecognised: an entry that cannot
  /// say what it is must not be treated as evidence.
  static EvidenceLevel parse(Object? key) =>
      key == 'published' ? published : placeholder;
}

/// One range: a metric, an age band and the values with their source.
class ReferenceRange {
  const ReferenceRange({
    required this.metric,
    required this.ageBand,
    required this.unit,
    required this.evidenceLevel,
    this.low,
    this.high,
    this.sourceCitation,
  });

  factory ReferenceRange.fromJson(Map<String, dynamic> json) => ReferenceRange(
    metric: json['metric'] as String,
    ageBand: json['age_band'] as String? ?? 'all',
    low: (json['low'] as num?)?.toDouble(),
    high: (json['high'] as num?)?.toDouble(),
    unit: json['unit'] as String? ?? '',
    sourceCitation: json['source_citation'] as String?,
    evidenceLevel: EvidenceLevel.parse(json['evidence_level']),
  );

  final String metric;

  /// 'all' when the range is not split by age.
  final String ageBand;

  final double? low;
  final double? high;
  final String unit;
  final String? sourceCitation;
  final EvidenceLevel evidenceLevel;

  /// True only for a complete, published, cited entry.
  ///
  /// Everything the screens and the report do with a range is gated on this.
  bool get isValidated =>
      evidenceLevel == EvidenceLevel.published &&
      low != null &&
      high != null &&
      low! <= high! &&
      (sourceCitation?.trim().isNotEmpty ?? false);

  Map<String, dynamic> toJson() => {
    'metric': metric,
    'age_band': ageBand,
    'low': low,
    'high': high,
    'unit': unit,
    'source_citation': sourceCitation,
    'evidence_level': evidenceLevel.name,
  };
}

/// All the ranges, looked up by metric and age band.
class ReferenceRanges {
  const ReferenceRanges(this.entries);

  /// No ranges at all: every lookup is null and everything reads as not yet validated.
  static const ReferenceRanges none = ReferenceRanges([]);

  /// Reads the asset's JSON text.
  ///
  /// A malformed file gives [none] rather than an error: the reference is context, and the
  /// results must not fail to open because of it.
  factory ReferenceRanges.parse(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return none;
      final list = decoded['ranges'];
      if (list is! List) return none;
      return ReferenceRanges([
        for (final item in list)
          if (item is Map<String, dynamic> && item['metric'] is String)
            ReferenceRange.fromJson(item),
      ]);
    } on FormatException {
      return none;
    }
  }

  /// Loads `assets/reference_ranges.json` from [bundle].
  static Future<ReferenceRanges> load(AssetBundle bundle) async {
    try {
      return ReferenceRanges.parse(
        await bundle.loadString('assets/reference_ranges.json'),
      );
    } on Object {
      return none;
    }
  }

  final List<ReferenceRange> entries;

  /// The range for [metric] in [ageBand], falling back to the band that covers everyone, or
  /// null if there is none.
  ReferenceRange? forMetric(String metric, {String ageBand = 'all'}) {
    ReferenceRange? everyone;
    for (final entry in entries) {
      if (entry.metric != metric) continue;
      if (entry.ageBand == ageBand) return entry;
      if (entry.ageBand == 'all') everyone = entry;
    }
    return everyone;
  }

  /// The range for [metric] if, and only if, it is validated.
  ReferenceRange? validatedFor(String metric, {String ageBand = 'all'}) {
    final range = forMetric(metric, ageBand: ageBand);
    return range != null && range.isValidated ? range : null;
  }
}
