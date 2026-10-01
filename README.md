# NeuraScan AI

Intelligent behavioural screening for neurological risk analysis. A Flutter app that turns short
smartphone tests into eighteen behavioural measurements in four areas, compares them with the user's **own**
baseline rather than a population norm, and reports a sustained change only after it persists.

> **NeuraScan AI does not diagnose any condition.** It is a screening and awareness tool, has
> not been clinically validated, and is not a medical device. All quantitative results in the
> project report come from a simulated cohort.

Submitted for Mobile Application Development (CS4504), Chennai Institute of Technology.
The full report and poster are in [`documentation/`](documentation/).

## How it works

There are two kinds of test.

**The baseline** is four short tests of three steps each: words, speech and a spiral tracing. The
first is a practice run and is discarded (everyone improves just by getting used to the tasks); the
next three set the baseline for the five measurements those steps give.

**A full test** can be taken at any time afterwards. It has **eight different steps**:

| # | Step | What the user does | Measurements | Area |
| --- | --- | --- | --- | --- |
| 1 | Word memory | Learn eight words; type them back straight away and again about three minutes later | Immediate recall, delayed recall | Cognitive |
| 2 | Reaction time | Tap as soon as the circle changes, ten times after a random 1-4 s wait | Median reaction time, variability (CV) | Cognitive |
| 3 | Speech | Describe a picture aloud for 20 s | Speaking rate, pause ratio | Speech |
| 4 | Spiral tracing | Trace a guide spiral with one finger | Tracing error (RMSE), tremor index (4-12 Hz) | Motor |
| 5 | Typing rhythm | Passive: timed while the user types the recall and fluency answers | Inter-key interval, its variability | Interaction |
| 6 | Trail-making | Tap 1, A, 2, B, 3, C ... in order | Completion time, errors, switch cost | Cognitive |
| 7 | Finger tapping | Alternate two buttons for 10 s | Tap rate, interval variability, fatigue decay | Motor |
| 8 | Verbal fluency | Type as many animals as possible in 30 s | Valid word count, late/early ratio | Cognitive |

A short check-in (sleep, tiredness, illness) comes first and marks confounded days: such a test is
saved and shown, marked "not counted", and left out of every average and trend.

The thirteen measurements the baseline tests never take (steps 2, 5, 6, 7, 8 and immediate recall)
get their baseline from the user's **first three counted full tests**, and are shown as raw
values, marked "calibrating", until then. The first of them includes a practice effect; that is
a known limitation (see `kExtensionFamiliarisation` in `lib/engine/constants.dart`).

The engine then:

1. freezes a per-measurement median and MAD, never letting the spread fall below half of a
   measurement's typical day-to-day variation (see the note in `lib/engine/constants.dart`);
2. converts each full test to robust z-scores, averaged into four areas and combined with weights
   35 / 25 / 25 / 15 % (re-normalised over the areas that have data), counting only changes in the
   worse direction;
3. smooths the index with an EWMA (lambda 0.3);
4. reports a notable change only after three consecutive tests above threshold.

Because the fusion is additive, each area's share of the total, and each measurement's, is its
exact contribution.

### Results, trends and the report

**Results come straight after each full test**: the status, a card for each of the eight steps,
and a comparison of every measurement three ways, kept apart:

1. **against the user's own baseline** (the only one that drives any status),
2. **against their earlier tests** (last, average of the last four, best, worst),
3. **against a population range**, for context only and never a verdict. The ranges live in
   `assets/reference_ranges.json`; every entry that ships is a placeholder, so the app says
   "Reference range not yet validated".

The Trends tab charts each measurement and area (baseline line, usual-spread band, smoothed line,
hollow markers for tests that were set aside) and gives a Theil-Sen slope and direction, but only
from six valid tests; before that it says "Not enough data yet (n of 6)".

The **report** is a paged A4 PDF built offline (cover, summary, a page per area, a section per
test, the log of every test, methods and limitations, with the disclaimer on the cover, the
summary and the last page), plus CSV and JSON of the derived data. The user chooses the period and
the sections, previews it, and confirms before every export. See
[`docs/REPORT_MODULE.md`](docs/REPORT_MODULE.md).

The user can **change their baseline** in settings. Earlier tests are kept (and exported) but no
longer count towards the trends or the new baseline; a later baseline is three tests, with no
practice run.

## Privacy

- Audio is captured from the microphone into memory, analysed on the device and dropped; it is
  never written to disk.
- Touch traces are reduced to a few numbers and dropped. Typed words are scored on the device;
  which words were recalled stays local and is never synced.
- The local database is SQLite encrypted with SQLCipher; the key lives in the Android Keystore /
  iOS Keychain.
- Cloud backup is **off by default**. When on, only the derived measurements and scores are
  uploaded.

## Repository layout

```
lib/
  engine/     screening engine, feature extractors, comparison (pure Dart, no Flutter dependency)
  data/       encrypted Drift database, repository, auth and sync interfaces
  features/   screens: onboarding, auth, dashboard, session and steps, trends, report, profile
  services/   notifications, audio capture
  features/report/   results, trend and report module: calculators, charts, PDF, CSV/JSON export
  app/        theme, router, providers, localisation (English and Tamil)
engine_lab/   Python reference implementation of the engine and its tests
test/         Dart tests: engine, data layer, widgets and full test flows
```

The engine was written and tested in Python first (`engine_lab/`); the Dart engine mirrors it
module for module, and the tests mirror the Python suite case for case. The better/worse
comparison is display logic on top of the engine and exists only in Dart.

## Running

Requires Flutter 3.47+ (Dart 3.13+), JDK 17 and the Android SDK.

```bash
flutter pub get
flutter gen-l10n
dart run build_runner build      # generates the Drift database code
flutter run
```

```bash
flutter analyze
flutter test
cd engine_lab && python -m pytest
```

## Known limitations

- **Cloud sync and Firebase are not wired to a project.** Authentication is local and sync is a
  disabled backend by default. Both sit behind interfaces, so a Firebase implementation replaces
  them without touching the screens.
- **The Android build is the one that has been run on a device.** The iOS project is generated but
  has not been built.
- No clinical validation. Thresholds were calibrated on synthetic data, and the project report's
  figures describe an earlier design; they have not been re-run for the eighteen-measurement
  engine.
- **Nine of the new measurements use provisional typical-day variations** (`provisional: true` in
  `lib/engine/features.dart`), and the minimum change for a trend to be called a direction
  (`kTrendMinChangeSds`) is untuned. Both want replacing with pilot data.
- **The population reference ranges are all placeholders.** No range, source or age band has been
  invented; see `docs/REPORT_MODULE.md` for how to add a real one.
- **The PDF is in English** whatever the app's language: its built-in fonts have no Tamil glyphs.
- Verbal fluency is listed as cognitive and speech in the brief; both of its measurements are
  scored as cognitive.
