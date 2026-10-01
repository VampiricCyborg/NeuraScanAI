# Results, trends and report module

Everything the user sees after a full test, in the Trends tab, and in the exported report. It lives
in `lib/features/report/` and **reads** the screening engine; it never changes a status. The status
is still the engine's rule: the smoothed deviation index, the persistence count and the check-in.

## What a user can do

| Where | What |
| --- | --- |
| Summary (straight after a full test) | Status, exact contribution by area, the (up to) three measurements that moved the index most, what the user logged ("what may explain this"), and a card for each of the eight tests |
| Trends tab, *Latest test* | The same, for the latest full test |
| Trends tab, *Trends* | Charts per area and per measurement, range selector (7 tests / 30 days / 90 days / all), Theil-Sen slope, direction, smoothed value, runs above the mild and notable levels |
| Trends tab, *Every test* | The log of every test: counted, set aside, practice or baseline, with the reason |
| Report screen | Choose the period and sections, label the report, preview it, then share, save, print, or save CSV / JSON. A consent dialog is shown **before every export** |

## Data flow

```
stored tests (SessionRecord)  +  engine baseline (frozen median / spread)  +  reference_ranges.json
                       \                      |                                  /
                        v                     v                                 v
                  calculators/analysis.dart  (pure functions, no Flutter, no state)
                  calculators/trend_stats.dart, theil_sen.dart
                                      |
          +---------------------------+--------------------------+
          v                           v                          v
   providers.dart              export/report_model.dart    (unit tests)
   (screens, cards, charts)    (one model for the whole report)
                                      |
                  +-------------------+--------------------+
                  v                                        v
        export/pdf/report_pdf.dart              export/report_files.dart
        (A4 PDF, vector charts)                 (CSV, JSON, file name)
                  \                                        /
                   v                                      v
                 export/report_delivery.dart  (share, save, print)
```

The screens, the PDF, the CSV and the JSON all read the same calculators, so they cannot disagree
about a number.

### The three comparisons, kept apart

For every measurement of a test (`MetricSummary` in `analysis.dart`):

1. **Personal baseline**, the primary reference and the only one that drives any status: the frozen
   median and spread, the z-score (oriented so positive is always worse), and a better / about the
   same / worse word. "About the same" means within `kSimilarBandSds` of the user's own spread.
2. **Earlier tests**: last valid test, the average of the last four valid tests before this one
   (`kRollingWindow`), best and worst so far, and improved / stable / worse against each.
3. **Population range**, context only. Drawn as a shaded band on charts and quoted as a range,
   **never read as normal or abnormal**. It is shown only if the entry is validated (below).

Only **valid** tests count in anything: full tests that were scored. A test the check-in set aside
is listed and marked "not counted", drawn as a hollow marker, and left out of every average, best,
worst, slope and run. It is never dropped silently.

### Trend rules

* `kMinSessionsForTrend` = 6 valid tests. Below that every screen and the PDF say
  "Not enough data yet (n of 6)" and give no direction.
* The slope is the Theil-Sen estimate over test order. The direction is *improving* or *declining*
  only if the total change across the period is at least `kTrendMinChangeSds` (0.5) of the user's
  own spread, otherwise *stable*. **This threshold is provisional and untuned.**
* The smoothed value is the engine's own EWMA (`kEwmaLambda`). "Runs" count consecutive latest tests
  at or above the mild (0.6 x threshold) and notable (threshold) levels.

All of these are in `report_constants.dart` and `engine/constants.dart`.

## Reference ranges: how to add a real one

`assets/reference_ranges.json` is versioned and editable. **Every entry that ships is a
placeholder**: `low` and `high` are `null`, there is no citation, and the app shows
"Reference range not yet validated". No range, source or age band has been invented.

Each entry has:

| Field | Meaning |
| --- | --- |
| `metric` | The measurement key, e.g. `reaction_median` (see `lib/engine/features.dart`) |
| `age_band` | `all`, or a band such as `60-69`. A specific band is preferred over `all` |
| `low`, `high` | The range, in the measurement's own unit as the app stores it (fractions, not percent, for recall; milliseconds for reaction time) |
| `unit` | The unit, for the reader |
| `source_citation` | A real, checkable citation. **Required** |
| `evidence_level` | `published` or `placeholder` |

An entry is shown as a range **only** if it is `published`, has both bounds with `low <= high`, and
has a non-blank `source_citation`. Anything else, however many numbers it carries, is shown as
"Reference range not yet validated". (`ReferenceRange.isValidated`, tested in
`test/features/report/reference_ranges_test.dart`.)

To add one:

1. Find the published source and read off the range for the same measurement and unit. Do not
   convert a population figure for a different task (a different reaction-time task, a different
   word list) and call it the same measurement.
2. Fill `low`, `high`, `unit`, `source_citation`, and set `evidence_level` to `published`.
3. Run `flutter test test/features/report`.

Even a validated range is context: it is a shaded band and a quoted range, with the note "Shown for
context. It never decides your status."

## The PDF

`export/pdf/report_pdf.dart`, built offline with the `pdf` package, A4 portrait, paged:

1. Cover: app name, period, date created, the user's label (editable), app version, scoring
   version, baseline status, and the disclaimer.
2. Summary: status, exact contributions by area (summing to 100%), what moved most, what may
   explain this, the overall index chart with the mild and notable levels, and the disclaimer.
3. A page for each of the four areas (optional).
4. A section for each of the eight tests: a metric table, the three-way comparison in words, and a
   vector chart per measurement (optional).
5. The log of every test in the period (optional).
6. Methods and limitations (optional).
7. The disclaimer again, always last.

The disclaimer is the app's own string (`resDisclaimer`), word for word:

> This is a screening and awareness tool, not a diagnosis. Many things such as stress, poor sleep
> or illness can change results. If you are concerned, please discuss this report with a doctor.

No other text in the PDF uses the words "diagnosis", "disease" or "you have" (tested).

The file is named `NeuraScan_Report_<yyyy-mm-dd>.pdf`.

Charts are drawn as vector graphics straight into the PDF (`pdf_charts.dart`), so they are sharp at
any zoom. Each area has its own marker shape (circle, diamond, triangle, square) as well as its
colour, set-aside tests are hollow, and every chart carries a legend line in words.

## CSV and JSON

`export/report_files.dart`. **Derived data only**: for each test the date, kind, whether it counted,
status, index, smoothed index, check-in answers, area scores and shares, and the eighteen
measurements. The app never stores raw audio or raw touch traces, so there are none to leave out;
the field lists `kExportedSessionFields` and `kExportedFeatureKeys` are an allow-list that the tests
check the files against, so a new field cannot be added by accident.

## Privacy and consent

Before **each** export the user is told the file holds their measurements and what they logged, and
that once shared, saved or printed it leaves the app's privacy settings. Nothing is exported without
confirming. The export is recorded locally (`recordReport`) as before; the file itself stays on the
phone unless the user sends it.

## Accessibility

* Text scales to 200% (widget tests pump every card and chart at 2.0x in English and Tamil, light
  and dark, with no overflow).
* Colour-blind-safe palette (Okabe-Ito); verdicts are an icon **and** a word, never colour alone;
  set-aside tests are hollow markers; areas have marker shapes in the PDF.
* Charts carry a spoken description, e.g. "Reaction time, trend stable over 9 tests", or "not
  enough data for a trend yet, 3 of 6 tests".

## Tests

```
flutter test test/features/report
```

| File | Covers |
| --- | --- |
| `trend_calculators_test.dart` | Theil-Sen, EWMA, rolling average, runs, min-data rule, range filtering |
| `analysis_test.dart` | Series, the three-way values, exclusion handling, calibrating and not-measured states, contributions summing to 100% |
| `reference_ranges_test.dart` | The validated-only rule, the shipped asset is all placeholder |
| `results_widgets_test.dart` | A card for each state, the charts, hollow markers, "n of 6", 200% text, Tamil, the three views |
| `report_screen_test.dart` | Options, the consent dialog before each export, what is handed over |
| `export_test.dart` | PDF from a seeded 40-test history: pages, the disclaimer on cover, summary and last page, forbidden words, no raw data; CSV and JSON allow-lists |

## Known limitations and placeholders

* **Reference ranges: all placeholders.** Nothing has been sourced.
* **Provisional numbers.** Nine measurements' typical-day variations (`provisional: true` in
  `lib/engine/features.dart`) and `kTrendMinChangeSds` are estimates, not measured values.
* **The first three full tests set the baseline of the thirteen extended measurements**, and the
  first includes a practice effect (`kExtensionFamiliarisation` = 0 is the knob).
* **Delayed recall** is one of nine equally weighted measurements in the cognitive area, so a
  change in it alone is muted in the area score.
* **Verbal fluency** is assigned entirely to the cognitive area, although the brief lists it as
  cognitive and speech. The assignment is in `features.dart`, one edit to move it.
* **The PDF is English only.** Its built-in fonts have no Tamil glyphs; embedding a Tamil font is a
  separate step. The on-screen results are in English and Tamil, and the Tamil text was written
  by the developer, not a translator.
* **The preview screen** uses the `printing` package's PDF viewer, which needs a platform to render
  pages, so it is not covered by an automated test. The PDF it shows is the one the tests cover.
* **Save to device** uses the system file dialog (Storage Access Framework on Android, Files on
  iOS) through `file_picker`; the native dialog itself is not covered by an automated test, and the
  iOS path has never been built.
* An invalid session (one that failed a quality gate) is listed in the log as a baseline-kind
  row; it is marked not counted but not labelled as invalid.
