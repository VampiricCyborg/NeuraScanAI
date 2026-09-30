/// The ten pictures for the speech task, and the rotation that chooses between them.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurascan_ai/features/session/tasks/scenes.dart';

void main() {
  group('rotation', () {
    test('there are at least ten pictures', () {
      expect(kSceneCount, greaterThanOrEqualTo(10));
      expect(kSceneNames, hasLength(kSceneCount));
    });

    test('every index is a valid picture', () {
      for (var session = 0; session < 500; session++) {
        expect(sceneIndexFor(session), inInclusiveRange(0, kSceneCount - 1));
      }
    });

    test('ten consecutive sessions show ten different pictures', () {
      // The request was to cycle through the pictures, so none should be skipped.
      for (var start = 0; start < 30; start++) {
        final seen = {
          for (var i = 0; i < kSceneCount; i++) sceneIndexFor(start + i),
        };
        expect(seen, hasLength(kSceneCount), reason: 'from session $start');
      }
    });

    test('no picture follows itself', () {
      for (var session = 0; session < 500; session++) {
        expect(sceneIndexFor(session + 1), isNot(sceneIndexFor(session)));
      }
    });

    test('the same session always gets the same picture', () {
      for (var session = 0; session < 50; session++) {
        expect(sceneIndexFor(session), sceneIndexFor(session));
      }
    });

    test('a picture is not always paired with the same word list', () {
      // Word lists rotate with period six and pictures with period ten. If they moved in
      // step, one picture would always come with one list, and a session's difficulty
      // would depend on that pairing.
      final pairs = {
        for (var session = 0; session < 60; session++)
          '${sceneIndexFor(session)}:${session % 6}',
      };
      expect(pairs.length, greaterThan(kSceneCount));
    });
  });

  group('drawing', () {
    /// Renders scene [index] at [size] and returns a hash of the pixels.
    Future<String> render(WidgetTester tester, int index, Size size) async {
      late Uint8List bytes;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        ScenePainter(index).paint(canvas, size);
        final image = await recorder.endRecording().toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final data = await image.toByteData();
        bytes = data!.buffer.asUint8List();
        image.dispose();
      });
      return '${bytes.length}:${Object.hashAll(bytes)}';
    }

    testWidgets('every picture paints without error', (tester) async {
      for (var i = 0; i < kSceneCount; i++) {
        await render(tester, i, const Size(360, 420));
      }
    });

    testWidgets('every picture is different from every other', (tester) async {
      // Ten copies of one drawing would defeat the purpose of rotating them.
      final hashes = <String>{};
      for (var i = 0; i < kSceneCount; i++) {
        hashes.add(await render(tester, i, const Size(360, 420)));
      }
      expect(hashes, hasLength(kSceneCount));
    });

    testWidgets('every picture actually draws something', (tester) async {
      // An untouched canvas, to compare each scene against. (The painter wraps its index,
      // so an out-of-range scene index would just repaint scene zero.)
      late String blank;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder);
        final image = await recorder.endRecording().toImage(120, 120);
        final data = await image.toByteData();
        blank =
            '${data!.lengthInBytes}:'
            '${Object.hashAll(data.buffer.asUint8List())}';
        image.dispose();
      });
      for (var i = 0; i < kSceneCount; i++) {
        expect(await render(tester, i, const Size(120, 120)), isNot(blank));
      }
    });

    testWidgets('pictures scale to very different panel sizes', (tester) async {
      for (var i = 0; i < kSceneCount; i++) {
        for (final size in const [
          Size(80, 80),
          Size(360, 200),
          Size(400, 900),
        ]) {
          await render(tester, i, size);
        }
      }
    });

    testWidgets('the picture view fills the space it is given', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          // Align loosens the constraints. A SizedBox placed straight under the app is
          // forced to the full screen size, whatever it asks for.
          home: Align(
            child: SizedBox(
              width: 300,
              height: 260,
              child: SceneView(index: 3),
            ),
          ),
        ),
      );
      final box = tester.getSize(find.byType(SceneView));
      expect(box, const Size(300, 260));
    });

    testWidgets('the picture is labelled without describing it', (
      tester,
    ) async {
      // Describing the contents to a screen reader would do the task for the user.
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(const MaterialApp(home: SceneView(index: 4)));
      expect(
        find.bySemanticsLabel('Picture 5 of $kSceneCount'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
