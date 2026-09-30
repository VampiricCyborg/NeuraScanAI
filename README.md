# NeuraScan AI

Intelligent behavioural screening for neurological risk analysis. A Flutter app that turns a
four-minute smartphone session into nine behavioural features, compares them with the user's
**own** baseline rather than a population norm, and reports a sustained change only after it
persists.

> **NeuraScan AI does not diagnose any condition.** It is a screening and awareness tool, has
> not been clinically validated, and is not a medical device. All quantitative results in the
> project report come from a simulated cohort.

Submitted for Mobile Application Development (CS4504), Chennai Institute of Technology.
The full report and poster are in [`documentation/`](documentation/).

## How it works

A session is a check-in followed by five tasks:

| Step | Measures | Features |
| --- | --- | --- |
| Check-in | Sleep, tiredness, illness | Marks confounded days |
| Word recall | Encoding, then recall about three minutes later | Delayed recall |
| Reaction | Ten trials, random 1-4 s wait | Reaction median, reaction CV |
| Speech | Twenty seconds describing a picture | Speaking rate, pause ratio |
| Spiral | Tracing a three-turn guide | Spiral RMSE, tremor index (4-12 Hz) |
| Typing | Timing inside the app's own fields | Inter-key interval, inter-key CV |

The engine then:

1. discards the first two sessions (practice effect);
2. freezes a per-feature median and MAD from the next four valid sessions (the report's
   simulation used six; see the note in `lib/engine/constants.dart`);
3. converts later sessions to robust z-scores, averaged into four domains and combined with
   weights 35 / 25 / 25 / 15 %, counting only changes in the worse direction;
4. smooths the index with an EWMA (lambda 0.3);
5. reports a notable change only after three consecutive sessions above threshold.

Because the fusion is additive, each domain's share of the total is its exact contribution.

## Privacy

- Audio is analysed on the device and dropped; it is never written to disk.
- Touch traces and typed text are never stored. Only per-keystroke timestamps are kept during a
  session, and they are discarded when it ends.
- The local database is SQLite encrypted with SQLCipher; the key lives in the Android Keystore /
  iOS Keychain.
- Cloud backup is **off by default**. When on, only derived features and scores are uploaded.

## Repository layout

```
lib/
  engine/     screening engine, feature extractors (pure Dart, no Flutter dependency)
  data/       encrypted Drift database, repository, auth and sync interfaces
  features/   screens: onboarding, auth, dashboard, session and tasks, trends, report, profile
  services/   PDF report, notifications, audio capture
  app/        theme, router, providers, localisation (English and Tamil)
engine_lab/   Python reference implementation of the engine and its tests
test/         Dart tests: engine, data layer, widgets and a full session flow
```

The engine was written and tested in Python first (`engine_lab/`); the Dart engine mirrors it
module for module, and the tests mirror the Python suite case for case.

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

- **Speech input is simulated in this build.** The feature extraction is the real signal
  processing, but the microphone is replaced by `SimulatedAudioCapture`, so nothing here shows
  the speech features track real speech. Swap in a real recorder by implementing
  `AudioCaptureService` and changing one provider.
- **Cloud sync and Firebase are not wired to a project.** Authentication is local and sync is a
  disabled backend by default. Both sit behind interfaces, so a Firebase implementation replaces
  them without touching the screens.
- No clinical validation. Thresholds were calibrated on synthetic data.
