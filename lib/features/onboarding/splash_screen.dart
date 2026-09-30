/// The launch screen.
///
/// Shown while the stored sign-in and profile are read. It does no navigating of
/// its own -- the router's redirect decides where to go once those have loaded --
/// which keeps the decision about who may see what in one place.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../app/theme.dart';

/// Brand and a progress indicator, shown while auth state loads.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _BrandMark(size: 88),
              const SizedBox(height: 28),
              Text(
                text.appName,
                style: context.texts.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                text.appTagline,
                textAlign: TextAlign.center,
                style: context.texts.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 44),
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    backgroundColor: context.colors.surfaceContainerHighest,
                    semanticsLabel: text.loading,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The app mark: concentric rings around a dot.
///
/// Drawn rather than shipped as an image so it takes the theme's colours and stays
/// crisp at any size. The shape is meant to read as a measurement narrowing on a
/// centre, which is what the personal baseline does.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _BrandMarkPainter(
          color: context.colors.primary,
          faded: context.colors.primary.withValues(alpha: 0.28),
        ),
      ),
    );
  }
}

class _BrandMarkPainter extends CustomPainter {
  const _BrandMarkPainter({required this.color, required this.faded});

  final Color color;
  final Color faded;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..color = faded;

    canvas.drawCircle(centre, radius * 0.92, ring);
    canvas.drawCircle(centre, radius * 0.62, ring);

    canvas.drawCircle(centre, radius * 0.26, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BrandMarkPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.faded != faded;
}
