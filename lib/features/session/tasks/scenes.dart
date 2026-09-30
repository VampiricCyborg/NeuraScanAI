/// The pictures the user describes in the speech task.
///
/// Ten scenes, drawn in code rather than shipped as images. A drawing can be built from a
/// fixed number of nameable things -- each scene has roughly the same count of people,
/// animals, objects and weather -- so the amount there is to say is comparable from one
/// session to the next. A photograph would vary in how much it invites, and a user's
/// speaking rate would then partly reflect the picture rather than the person, which is the
/// one thing the baseline cannot correct for.
///
/// They are also free of licensing questions and add nothing to the app size.
///
/// Rotation is by session, stepping three at a time through ten scenes. Three and ten share
/// no factor, so every scene comes round once in ten sessions and no scene follows itself.
/// The step is coprime with the word-list rotation's length too, which keeps a given picture
/// from always being paired with the same word list.
library;

import 'package:flutter/material.dart';

/// How many different pictures there are.
const int kSceneCount = 10;

/// The picture to show for the session at [sessionIndex].
///
/// Deterministic, so a replay or a test reproduces the choice.
int sceneIndexFor(int sessionIndex) => (sessionIndex * 3 + 1) % kSceneCount;

/// Short names, used for accessibility and tests.
const List<String> kSceneNames = [
  'market',
  'beach',
  'kitchen',
  'park',
  'station',
  'farm',
  'classroom',
  'party',
  'rain',
  'harbour',
];

/// Paints scene [index] into a canvas.
class ScenePainter extends CustomPainter {
  const ScenePainter(this.index);

  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final s = _Sketch(canvas, size);
    switch (index % kSceneCount) {
      case 0:
        _market(s);
      case 1:
        _beach(s);
      case 2:
        _kitchen(s);
      case 3:
        _park(s);
      case 4:
        _station(s);
      case 5:
        _farm(s);
      case 6:
        _classroom(s);
      case 7:
        _party(s);
      case 8:
        _rain(s);
      case 9:
        _harbour(s);
    }
  }

  @override
  bool shouldRepaint(ScenePainter oldDelegate) => oldDelegate.index != index;
}

/// The picture panel, sized to fill whatever it is given.
class SceneView extends StatelessWidget {
  const SceneView({required this.index, super.key});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // Read out as a name only. Describing the contents would do the task for the user.
      label: 'Picture ${(index % kSceneCount) + 1} of $kSceneCount',
      image: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: CustomPaint(
          painter: ScenePainter(index),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

// -- palette --------------------------------------------------------------------------
//
// Fixed rather than taken from the theme. The scenes sit on their own panel, and a picture
// that changed colour with light and dark mode would be a different picture.

const _sky = Color(0xFFBFE3F2);
const _skyDusk = Color(0xFFF6C89F);
const _skyRain = Color(0xFF9DB2BF);
const _grass = Color(0xFF8CC084);
const _sand = Color(0xFFF0D9A3);
const _sea = Color(0xFF5DA9CC);
const _wood = Color(0xFF9C6B3F);
const _ink = Color(0xFF3A3F47);
const _red = Color(0xFFD9534F);
const _yellow = Color(0xFFF2C14E);
const _blue = Color(0xFF3F7CAC);
const _green = Color(0xFF4F9D69);
const _white = Color(0xFFFFFFFF);
const _cream = Color(0xFFFFF4DC);
const _grey = Color(0xFFB8C0C8);
const _pink = Color(0xFFE88AA8);
const _brick = Color(0xFFB5654A);

/// A tiny drawing helper working in fractions of the canvas, so every scene is written once
/// and scales to any panel size.
class _Sketch {
  _Sketch(this.canvas, this.size);

  final Canvas canvas;
  final Size size;

  double _x(double f) => f * size.width;
  double _y(double f) => f * size.height;
  double _u(double f) => f * size.shortestSide;

  void fill(Color color, double x, double y, double w, double h) {
    canvas.drawRect(
      Rect.fromLTWH(_x(x), _y(y), _x(w), _y(h)),
      Paint()..color = color,
    );
  }

  void round(
    Color color,
    double x,
    double y,
    double w,
    double h, [
    double r = 0.02,
  ]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_x(x), _y(y), _x(w), _y(h)),
        Radius.circular(_u(r)),
      ),
      Paint()..color = color,
    );
  }

  void circle(Color color, double x, double y, double r) {
    canvas.drawCircle(Offset(_x(x), _y(y)), _u(r), Paint()..color = color);
  }

  void oval(Color color, double x, double y, double w, double h) {
    canvas.drawOval(
      Rect.fromLTWH(_x(x), _y(y), _x(w), _y(h)),
      Paint()..color = color,
    );
  }

  void line(
    Color color,
    double x1,
    double y1,
    double x2,
    double y2, [
    double w = 0.006,
  ]) {
    canvas.drawLine(
      Offset(_x(x1), _y(y1)),
      Offset(_x(x2), _y(y2)),
      Paint()
        ..color = color
        ..strokeWidth = _u(w)
        ..strokeCap = StrokeCap.round,
    );
  }

  void tri(
    Color color,
    double x1,
    double y1,
    double x2,
    double y2,
    double x3,
    double y3,
  ) {
    canvas.drawPath(
      Path()
        ..moveTo(_x(x1), _y(y1))
        ..lineTo(_x(x2), _y(y2))
        ..lineTo(_x(x3), _y(y3))
        ..close(),
      Paint()..color = color,
    );
  }

  /// A simple standing person: head, body, arms and legs.
  void person(double x, double y, Color shirt, {double scale = 1.0}) {
    final h = 0.05 * scale;
    circle(_ink.withValues(alpha: 0.85), x, y, h * 0.6);
    line(shirt, x, y + h * 0.7, x, y + h * 2.6, 0.02 * scale);
    line(_ink, x, y + h * 1.0, x - h * 0.9, y + h * 1.9, 0.008 * scale);
    line(_ink, x, y + h * 1.0, x + h * 0.9, y + h * 1.9, 0.008 * scale);
    line(_ink, x, y + h * 2.6, x - h * 0.6, y + h * 4.0, 0.008 * scale);
    line(_ink, x, y + h * 2.6, x + h * 0.6, y + h * 4.0, 0.008 * scale);
  }

  /// A tree: trunk and round crown.
  void tree(double x, double y, {double scale = 1.0, Color crown = _green}) {
    fill(_wood, x - 0.01 * scale, y, 0.02 * scale, 0.14 * scale);
    circle(crown, x, y - 0.02 * scale, 0.09 * scale);
  }

  /// A small four-legged animal.
  void animal(double x, double y, Color body, {double scale = 1.0}) {
    oval(body, x, y, 0.11 * scale, 0.06 * scale);
    circle(body, x + 0.115 * scale, y + 0.005 * scale, 0.026 * scale);
    line(
      _ink,
      x + 0.02 * scale,
      y + 0.05 * scale,
      x + 0.02 * scale,
      y + 0.09 * scale,
    );
    line(
      _ink,
      x + 0.09 * scale,
      y + 0.05 * scale,
      x + 0.09 * scale,
      y + 0.09 * scale,
    );
  }

  /// A bird as a small "v".
  void bird(double x, double y) {
    final p = Path()
      ..moveTo(_x(x - 0.02), _y(y))
      ..quadraticBezierTo(_x(x - 0.01), _y(y - 0.02), _x(x), _y(y))
      ..quadraticBezierTo(_x(x + 0.01), _y(y - 0.02), _x(x + 0.02), _y(y));
    canvas.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _u(0.006)
        ..strokeCap = StrokeCap.round
        ..color = _ink,
    );
  }

  /// A rounded cloud.
  void cloud(double x, double y, {Color color = _white, double scale = 1.0}) {
    circle(color, x, y, 0.04 * scale);
    circle(color, x + 0.04 * scale, y - 0.015 * scale, 0.05 * scale);
    circle(color, x + 0.09 * scale, y, 0.04 * scale);
    fill(color, x, y, 0.09 * scale, 0.04 * scale);
  }

  /// A house-like block with a window.
  void building(Color wall, double x, double y, double w, double h) {
    fill(wall, x, y, w, h);
    fill(_cream, x + w * 0.2, y + h * 0.2, w * 0.2, h * 0.16);
    fill(_cream, x + w * 0.6, y + h * 0.2, w * 0.2, h * 0.16);
    fill(_wood, x + w * 0.4, y + h * 0.62, w * 0.2, h * 0.38);
  }

  /// A round-faced clock.
  void clock(double x, double y, double r) {
    circle(_white, x, y, r);
    circle(_ink, x, y, r * 0.06);
    line(_ink, x, y, x, y - r * 0.6, 0.004);
    line(_ink, x, y, x + r * 0.45, y, 0.004);
  }

  /// A window with a cross frame.
  void window(double x, double y, double w, double h, {Color glass = _sky}) {
    fill(glass, x, y, w, h);
    line(_white, x + w / 2, y, x + w / 2, y + h);
    line(_white, x, y + h / 2, x + w, y + h / 2);
  }

  /// A balloon on a string.
  void balloon(Color color, double x, double y) {
    oval(color, x - 0.025, y - 0.04, 0.05, 0.07);
    line(_ink, x, y + 0.03, x, y + 0.13, 0.003);
  }
}

// -- the ten scenes -----------------------------------------------------------------------

void _market(_Sketch s) {
  s.fill(_sky, 0, 0, 1, 0.62);
  s.fill(_grass, 0, 0.62, 1, 0.38);
  s.circle(_yellow, 0.82, 0.14, 0.06);
  s.tree(0.12, 0.42);
  s.fill(_wood, 0.40, 0.46, 0.34, 0.20);
  for (var i = 0; i < 5; i++) {
    s.fill(i.isEven ? _red : _white, 0.40 + i * 0.068, 0.39, 0.068, 0.07);
  }
  for (var i = 0; i < 6; i++) {
    s.circle(i.isEven ? _red : _yellow, 0.44 + i * 0.05, 0.51, 0.022);
  }
  s.person(0.26, 0.50, _blue);
  s.person(0.84, 0.54, _pink, scale: 0.9);
  s.animal(0.58, 0.78, _wood);
  s.bird(0.34, 0.14);
  s.bird(0.48, 0.09);
  s.bird(0.6, 0.16);
}

void _beach(_Sketch s) {
  s.fill(_sky, 0, 0, 1, 0.42);
  s.fill(_sea, 0, 0.42, 1, 0.22);
  s.fill(_sand, 0, 0.64, 1, 0.36);
  s.circle(_yellow, 0.16, 0.14, 0.07);
  s.cloud(0.5, 0.16);
  s.cloud(0.78, 0.26, scale: 0.8);
  // Sailing boat.
  s.tri(_white, 0.6, 0.30, 0.6, 0.44, 0.72, 0.44);
  s.fill(_red, 0.57, 0.44, 0.18, 0.03);
  // Umbrella.
  s.line(_ink, 0.30, 0.62, 0.30, 0.86, 0.008);
  s.tri(_red, 0.18, 0.62, 0.42, 0.62, 0.30, 0.52);
  s.person(0.52, 0.66, _blue, scale: 0.9);
  // Child with a bucket.
  s.person(0.74, 0.72, _yellow, scale: 0.7);
  s.fill(_green, 0.79, 0.84, 0.035, 0.04);
  s.bird(0.28, 0.32);
  s.bird(0.4, 0.26);
}

void _kitchen(_Sketch s) {
  s.fill(_cream, 0, 0, 1, 0.68);
  s.fill(_wood, 0, 0.68, 1, 0.32);
  s.window(0.62, 0.10, 0.22, 0.26);
  s.clock(0.34, 0.16, 0.06);
  // Counter and stove.
  s.fill(_grey, 0.06, 0.50, 0.46, 0.22);
  s.fill(_ink, 0.12, 0.44, 0.16, 0.06);
  s.fill(_red, 0.13, 0.36, 0.14, 0.08);
  // Steam.
  s.line(_grey, 0.16, 0.32, 0.18, 0.24);
  s.line(_grey, 0.21, 0.32, 0.19, 0.22);
  s.line(_grey, 0.25, 0.32, 0.27, 0.24);
  // Table with a fruit bowl.
  s.fill(_wood, 0.58, 0.60, 0.34, 0.03);
  s.line(_wood, 0.62, 0.63, 0.62, 0.86, 0.012);
  s.line(_wood, 0.88, 0.63, 0.88, 0.86, 0.012);
  s.oval(_blue, 0.68, 0.55, 0.14, 0.05);
  s.circle(_red, 0.72, 0.55, 0.02);
  s.circle(_yellow, 0.77, 0.55, 0.02);
  s.person(0.42, 0.56, _pink);
  s.animal(0.12, 0.86, _ink, scale: 0.8);
}

void _park(_Sketch s) {
  s.fill(_sky, 0, 0, 1, 0.55);
  s.fill(_grass, 0, 0.55, 1, 0.45);
  s.cloud(0.10, 0.14, scale: 0.9);
  s.tree(0.82, 0.36, scale: 1.2);
  s.tree(0.68, 0.44, scale: 0.8, crown: const Color(0xFF6DB273));
  // Pond with ducks.
  s.oval(_sea, 0.10, 0.70, 0.36, 0.16);
  s.oval(_yellow, 0.20, 0.74, 0.06, 0.04);
  s.oval(_yellow, 0.32, 0.77, 0.06, 0.04);
  // Bench and a person sitting.
  s.fill(_wood, 0.52, 0.66, 0.20, 0.03);
  s.fill(_wood, 0.52, 0.60, 0.20, 0.02);
  s.person(0.62, 0.55, _green, scale: 0.8);
  // Kite.
  s.tri(_red, 0.30, 0.10, 0.36, 0.20, 0.24, 0.20);
  s.line(_ink, 0.30, 0.20, 0.22, 0.56, 0.003);
  s.person(0.22, 0.58, _blue, scale: 0.8);
  s.animal(0.44, 0.88, _wood, scale: 0.8);
}

void _station(_Sketch s) {
  s.fill(_sky, 0, 0, 1, 0.5);
  s.fill(_grey, 0, 0.72, 1, 0.28);
  s.fill(_ink, 0, 0.68, 1, 0.04);
  // Train.
  s.round(_blue, 0.05, 0.38, 0.62, 0.28);
  for (var i = 0; i < 4; i++) {
    s.fill(_cream, 0.10 + i * 0.14, 0.44, 0.09, 0.10);
  }
  s.round(_red, 0.62, 0.42, 0.14, 0.24);
  s.circle(_ink, 0.16, 0.68, 0.03);
  s.circle(_ink, 0.50, 0.68, 0.03);
  // Platform clock on a pole.
  s.line(_ink, 0.86, 0.30, 0.86, 0.74, 0.012);
  s.clock(0.86, 0.24, 0.07);
  s.person(0.20, 0.76, _red, scale: 0.8);
  s.person(0.34, 0.76, _green, scale: 0.8);
  s.person(0.46, 0.78, _yellow, scale: 0.7);
  s.fill(_wood, 0.60, 0.84, 0.18, 0.03);
  s.bird(0.5, 0.16);
}

void _farm(_Sketch s) {
  s.fill(_sky, 0, 0, 1, 0.5);
  s.fill(_grass, 0, 0.5, 1, 0.5);
  s.circle(_yellow, 0.14, 0.14, 0.06);
  // Barn.
  s.fill(_red, 0.58, 0.36, 0.30, 0.26);
  s.tri(_brick, 0.55, 0.36, 0.91, 0.36, 0.73, 0.20);
  s.fill(_white, 0.68, 0.46, 0.10, 0.16);
  // Fence.
  for (var i = 0; i < 8; i++) {
    s.fill(_wood, 0.04 + i * 0.05, 0.60, 0.012, 0.10);
  }
  s.line(_wood, 0.04, 0.63, 0.42, 0.63, 0.008);
  // Cows and chickens.
  s.animal(0.14, 0.74, _white, scale: 1.2);
  s.animal(0.40, 0.80, _ink, scale: 1.1);
  s.circle(_yellow, 0.66, 0.86, 0.02);
  s.circle(_yellow, 0.72, 0.88, 0.02);
  // Haystack.
  s.tri(_yellow, 0.78, 0.86, 0.94, 0.86, 0.86, 0.74);
  s.person(0.52, 0.66, _blue, scale: 0.8);
  s.cloud(0.38, 0.18, scale: 0.8);
}

void _classroom(_Sketch s) {
  s.fill(_cream, 0, 0, 1, 0.7);
  s.fill(_wood, 0, 0.7, 1, 0.3);
  // Blackboard with writing.
  s.round(_green, 0.10, 0.10, 0.50, 0.28, 0.01);
  s.line(_white, 0.16, 0.20, 0.40, 0.20);
  s.line(_white, 0.16, 0.28, 0.50, 0.28);
  s.window(0.70, 0.10, 0.20, 0.26);
  s.clock(0.66, 0.06, 0.04);
  s.person(0.66, 0.42, _red, scale: 0.9);
  // Desks with pupils.
  for (var i = 0; i < 3; i++) {
    final x = 0.14 + i * 0.26;
    s.fill(_wood, x, 0.66, 0.16, 0.03);
    s.person(x + 0.08, 0.54, i.isEven ? _blue : _pink, scale: 0.7);
  }
  // Globe.
  s.circle(_sea, 0.88, 0.62, 0.05);
  s.line(_ink, 0.88, 0.67, 0.88, 0.74, 0.008);
  s.animal(0.10, 0.86, _yellow, scale: 0.6);
}

void _party(_Sketch s) {
  s.fill(_skyDusk.withValues(alpha: 0.5), 0, 0, 1, 0.7);
  s.fill(_wood, 0, 0.7, 1, 0.3);
  // Banner.
  s.line(_ink, 0.06, 0.10, 0.94, 0.10, 0.004);
  for (var i = 0; i < 8; i++) {
    s.tri(
      [_red, _yellow, _blue, _green][i % 4],
      0.10 + i * 0.10,
      0.10,
      0.16 + i * 0.10,
      0.10,
      0.13 + i * 0.10,
      0.17,
    );
  }
  s.balloon(_red, 0.12, 0.30);
  s.balloon(_blue, 0.20, 0.26);
  s.balloon(_yellow, 0.86, 0.28);
  // Table with a cake and candles.
  s.fill(_white, 0.32, 0.60, 0.36, 0.04);
  s.line(_wood, 0.36, 0.64, 0.36, 0.86, 0.012);
  s.line(_wood, 0.64, 0.64, 0.64, 0.86, 0.012);
  s.round(_pink, 0.42, 0.50, 0.16, 0.10, 0.01);
  for (var i = 0; i < 3; i++) {
    s.fill(_yellow, 0.45 + i * 0.04, 0.44, 0.008, 0.06);
  }
  // Presents.
  s.fill(_blue, 0.74, 0.78, 0.08, 0.08);
  s.fill(_green, 0.84, 0.80, 0.07, 0.06);
  s.person(0.22, 0.52, _green, scale: 0.9);
  s.person(0.78, 0.50, _red, scale: 0.9);
  s.animal(0.08, 0.88, _white, scale: 0.7);
}

void _rain(_Sketch s) {
  s.fill(_skyRain, 0, 0, 1, 0.66);
  s.fill(_grey, 0, 0.66, 1, 0.34);
  s.cloud(0.08, 0.10, color: _grey, scale: 1.2);
  s.cloud(0.55, 0.14, color: _grey);
  // Rain streaks.
  for (var i = 0; i < 22; i++) {
    final x = 0.04 + (i * 0.045) % 0.94;
    final y = 0.20 + ((i * 7) % 9) * 0.05;
    s.line(_blue.withValues(alpha: 0.6), x, y, x - 0.012, y + 0.04, 0.003);
  }
  s.building(_brick, 0.04, 0.34, 0.24, 0.36);
  s.building(_yellow, 0.72, 0.30, 0.24, 0.40);
  // Lamp post.
  s.line(_ink, 0.50, 0.40, 0.50, 0.72, 0.010);
  s.circle(_yellow, 0.50, 0.38, 0.03);
  // Two people under umbrellas.
  s.person(0.34, 0.62, _blue, scale: 0.8);
  s.tri(_red, 0.26, 0.58, 0.42, 0.58, 0.34, 0.50);
  s.person(0.62, 0.64, _green, scale: 0.8);
  s.tri(_yellow, 0.54, 0.60, 0.70, 0.60, 0.62, 0.52);
  // Car and puddle.
  s.round(_red, 0.20, 0.84, 0.22, 0.07);
  s.circle(_ink, 0.25, 0.92, 0.02);
  s.circle(_ink, 0.37, 0.92, 0.02);
  s.oval(_sea, 0.62, 0.86, 0.20, 0.05);
}

void _harbour(_Sketch s) {
  s.fill(_skyDusk, 0, 0, 1, 0.46);
  s.fill(_sea, 0, 0.46, 1, 0.30);
  s.fill(_wood, 0, 0.74, 1, 0.26);
  s.circle(_yellow, 0.70, 0.30, 0.09);
  // Lighthouse.
  s.tri(_white, 0.08, 0.72, 0.22, 0.72, 0.15, 0.22);
  s.fill(_red, 0.11, 0.42, 0.08, 0.06);
  s.fill(_red, 0.125, 0.56, 0.05, 0.05);
  s.circle(_yellow, 0.15, 0.20, 0.025);
  // Boats.
  s.round(_blue, 0.40, 0.54, 0.24, 0.07);
  s.line(_ink, 0.52, 0.54, 0.52, 0.32, 0.008);
  s.tri(_white, 0.52, 0.32, 0.52, 0.52, 0.62, 0.52);
  s.round(_red, 0.72, 0.60, 0.20, 0.06);
  // Crates and a fisherman.
  s.fill(_brick, 0.30, 0.78, 0.09, 0.09);
  s.fill(_brick, 0.39, 0.78, 0.09, 0.09);
  s.fill(_brick, 0.345, 0.69, 0.09, 0.09);
  s.person(0.62, 0.74, _green, scale: 0.9);
  s.line(_ink, 0.66, 0.78, 0.78, 0.66, 0.004);
  s.bird(0.30, 0.16);
  s.bird(0.42, 0.10);
  s.bird(0.52, 0.18);
  s.animal(0.84, 0.88, _yellow, scale: 0.6);
}
