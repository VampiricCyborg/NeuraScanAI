# NeuraScan AI

Intelligent behavioural screening for neurological risk analysis. A Flutter app that turns short
smartphone tests into five behavioural measurements, compares them with the user's **own**
baseline rather than a population norm, and reports a sustained change only after it persists.

> **NeuraScan AI does not diagnose any condition.** It is a screening and awareness tool, has
> not been clinically validated, and is not a medical device. All quantitative results in the
> project report come from a simulated cohort.

Submitted for Mobile Application Development (CS4504), Chennai Institute of Technology.
The full report and poster are in [`documentation/`](documentation/).

## How it works

There are two kinds of test, built from the same three kinds of step, so a step in a full test is
always something the baseline also measured.

| Step | What the user does | Measurements |
| --- | --- | --- |
| Words | Learn a list of eight words; type them back later, after other steps | Delayed recall |
| Speech | Describe a picture aloud for twenty seconds (ten pictures rotate) | Speaking rate, pause ratio |
| Precision | Trace a three-turn guide spiral with one finger | Tracing error (RMSE), tremor index (4-12 Hz) |

A short check-in (sleep, tiredness, illness) comes first and marks confounded days.

**The baseline** is four short tests of three steps each: words, speech, precision. The first is a
practice run and is discarded (everyone improves just by getting used to the tasks); the next
three set the baseline. After that, a **full test** can be taken at any time. It has **eight
steps**: three word lists, three picture descriptions and two spiral tracings. Each measurement is
taken several times and the test's value is the median of its repeats, so one unusual step cannot
define the result. A step that does not pass its quality check (too little speech, a half-traced
spiral) is simply asked for again, not thrown away with the whole test.

The engine then:

1. freezes a per-measurement median and MAD from the three counted baseline tests. The report's
   simulation used six, and three is a much noisier estimate, so the spread is never allowed
   below half of a measurement's typical day-to-day variation (see the note in
   `lib/engine/constants.dart` and `engine_lab/baseline_sensitivity.py`);
2. converts each full test to robust z-scores, averaged into three areas (thinking, speech,
   movement) and combined with weights 40 / 30 / 30 %, counting only changes in the worse
   direction;
3. smooths the index with an EWMA (lambda 0.3);
4. reports a notable change only after three consecutive tests above threshold.

**Results come straight after each full test**: a status, and a comparison of that test with the
baseline and with the previous full test, for every measurement and every area, in the words
"better", "about the same" and "worse" (a change smaller than the user's own usual spread counts
as the same). The Trends tab charts them. Until the first full test, it shows the user's own
baseline and clearly labelled *simulated* example trends so the measurements make sense.

The user can **change their baseline** in settings. Earlier tests are kept (and exported) but no
longer count towards the trends or the new baseline; a later baseline is three tests, with no
practice run.

Because the fusion is additive, each area's share of the total is its exact contribution.

## Privacy

- Audio is captured from the microphone into memory, analysed on the device and dropped; it is
  never written to disk.
- Touch traces are reduced to two numbers and dropped. Typed words are scored on the device;
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
  services/   PDF report, notifications, audio capture
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
- No clinical validation. Thresholds were calibrated on synthetic data, and the report's figures
  describe an earlier design (nine measurements, four areas, a six-test baseline); they have not
  been re-run for the five-measurement engine, beyond the quick sensitivity check in
  `engine_lab/baseline_sensitivity.py`.
