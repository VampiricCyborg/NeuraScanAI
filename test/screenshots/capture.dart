/// Harness for the screenshot and animation captures in `screens_test.dart`.
///
/// The app already runs end to end in a widget test with no emulator (see
/// `test/app/test_harness.dart`), which means the same harness can render the real
/// screens to PNG for the README. Two things have to be added for a picture rather
/// than an assertion: real fonts, because a widget test draws every glyph as a
/// rectangle, and a way to get the rendered layer out as bytes.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/app/l10n/generated/app_localizations.dart';
import 'package:neurascan_ai/app/providers.dart';
import 'package:neurascan_ai/app/router.dart';
import 'package:neurascan_ai/app/theme.dart';
import 'package:neurascan_ai/data/auth_service.dart';
import 'package:neurascan_ai/data/local_db.dart';
import 'package:neurascan_ai/features/session/session_controller.dart';
import 'package:neurascan_ai/services/audio_capture.dart';

import '../app/test_harness.dart';

/// Where the frames are written, relative to the project root.
const String kOutDir = 'docs/images/raw';

/// Logical size of the captured surface: a mid-sized phone.
const Size kPhone = Size(390, 844);

/// Device pixel ratio of the capture, so the PNGs are 780x1688.
const double kScale = 2.0;

/// The Roboto and Material icon fonts that ship with the Flutter SDK.
Directory _materialFonts() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null) {
    final fromEnv = Directory('$root/bin/cache/artifacts/material_fonts');
    if (fromEnv.existsSync()) return fromEnv;
  }
  // <flutter>/bin/cache/dart-sdk/bin/dart -> <flutter>/bin/cache
  final cache = File(Platform.resolvedExecutable).parent.parent.parent;
  return Directory('${cache.path}/artifacts/material_fonts');
}

/// Registers Roboto and the Material icon font with the test engine.
Future<void> loadRealFonts() async {
  final dir = _materialFonts();
  if (!dir.existsSync()) {
    throw StateError(
      'The Flutter SDK material_fonts directory was not found at '
      '${dir.path}. Set FLUTTER_ROOT and run again.',
    );
  }

  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = await File('${dir.path}/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
  ]);
  await family('MaterialIcons', ['materialicons-regular.otf']);
}

/// Pumps the real app with test doubles, at phone size, with real fonts.
Future<TestApp> pumpForCapture(
  WidgetTester tester, {
  AuthAccount? signedIn,
  AudioCaptureService? audio,
}) async {
  tester.view
    ..physicalSize = kPhone * kScale
    ..devicePixelRatio = kScale;
  addTearDown(tester.view.reset);

  final database = LocalDatabase.forTesting();
  final auth = FakeAuthService(signedIn: signedIn);
  final backend = FakeSyncBackend();
  final container = ProviderContainer(
    overrides: [
      localDatabaseProvider.overrideWithValue(database),
      authServiceProvider.overrideWithValue(auth),
      syncBackendProvider.overrideWithValue(backend),
      if (audio != null) audioCaptureProvider.overrideWithValue(audio),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const _CaptureRoot(),
    ),
  );
  await tester.pumpAndSettle();

  final app = TestApp(
    container: container,
    database: database,
    auth: auth,
    backend: backend,
  );
  addTearDown(() async => tester.runAsync(app.dispose));
  return app;
}

/// The app as `main.dart` builds it, minus the debug banner, plus real fonts.
class _CaptureRoot extends ConsumerWidget {
  const _CaptureRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: withRealFonts(buildTheme(Brightness.light)),
      localizationsDelegates: AppText.localizationsDelegates,
      supportedLocales: AppText.supportedLocales,
    );
  }
}

/// Points every text style in [base] at the loaded Roboto.
///
/// Naming the family on the text theme alone is not enough: the button and app bar
/// themes carry their own styles, and a style set there replaces the text theme's
/// outright rather than merging with it, so its null family would fall back to the
/// test engine's rectangle font.
ThemeData withRealFonts(ThemeData base) {
  TextStyle? named(TextStyle? style) => style?.copyWith(fontFamily: 'Roboto');
  ButtonStyle button(ButtonStyle? style) =>
      (style ?? const ButtonStyle()).copyWith(
        textStyle: WidgetStatePropertyAll(
          named(style?.textStyle?.resolve(const {})),
        ),
      );

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Roboto'),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Roboto'),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: named(base.appBarTheme.titleTextStyle),
      toolbarTextStyle: named(base.appBarTheme.toolbarTextStyle),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(base.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(base.outlinedButtonTheme.style),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(base.textButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button(base.elevatedButtonTheme.style),
    ),
  );
}

/// Writes the current frame to `$kOutDir/$name.png`.
Future<void> shoot(WidgetTester tester, String name) async {
  var object = tester.firstElement(find.byType(MaterialApp)).renderObject!;
  while (!object.isRepaintBoundary) {
    object = object.parent!;
  }
  final layer = object.debugLayer! as OffsetLayer;
  await tester.runAsync(() async {
    final image = await layer.toImage(object.paintBounds);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$kOutDir/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

/// How many frames each animation has recorded so far.
final Map<String, int> _frameCounts = {};

/// Writes the current frame as the next frame of the animation called [gif].
Future<void> frame(WidgetTester tester, String gif) async {
  final index = _frameCounts.update(gif, (n) => n + 1, ifAbsent: () => 0);
  await shoot(tester, 'frames/$gif/${index.toString().padLeft(3, '0')}');
}
