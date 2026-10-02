# Screenshots

Every picture in the root `README.md` is the real app. Nothing is a mock-up, and
nothing was taken by hand on a device, so the whole set can be regenerated after a
UI change in about a minute.

## How it works

`test/app/test_harness.dart` already runs the entire app in a widget test with an
in-memory database, a fake auth service and a recording sync backend — no
emulator, no platform channels, no cloud project. `test/screenshots` adds the two
things a picture needs that an assertion does not:

- **Real fonts.** A widget test draws every glyph as a rectangle. `capture.dart`
  loads Roboto and the Material icon font out of the Flutter SDK's own cache and
  points the theme at them.
- **A way out.** `shoot()` walks up to the nearest repaint boundary and writes the
  rendered layer to a PNG.

`drive.dart` then plays the eight steps the same way `session_flow_test.dart`
does, with a hook after each move so a frame can be recorded mid-trace or
mid-trial. `story.dart` seeds a history with the day-to-day variation a real
person has, because seeding identical sessions — which is what the assertions
want — produces flat lines and empty charts.

## Running it

From the project root:

```bash
flutter test test/screenshots --dart-define=capture=true
python tool/screenshots/compose.py
```

The first writes full-resolution frames and a generated PDF to `docs/images/raw`,
which is not committed. The second produces everything the README links to:
rounded phone shots, the labelled grid of the eight steps, the GIFs, and a strip
of real pages rasterised from that PDF. About 2.5 MB in all.

Without `--dart-define=capture=true` every case skips itself, so an ordinary
`flutter test` run and CI never spend time on it.

`compose.py` needs Pillow, and PyMuPDF for the report pages:

```bash
python -m pip install pillow pymupdf
```

## Adding a shot

Add a `shoot(tester, 'name')` where you want it in `screens_test.dart`, then name
it in `compose.py` — in `singles()` for a plain screenshot, in `STEPS` for the
grid, or in `animations()` if you recorded a sequence with `frame()`.

The diagrams in `docs/images/*.svg` are hand-written rather than generated. They
use presentation attributes only, with no stylesheet and no media query, so they
render the same way everywhere; the pale background is the app's own, which is
what keeps them legible on a dark page as well as a light one.
