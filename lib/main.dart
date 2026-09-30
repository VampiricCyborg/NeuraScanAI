/// Application entry point.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/l10n/generated/app_localizations.dart';
import 'app/providers.dart';
import 'app/router.dart';
import 'app/theme.dart';

void main() {
  runApp(const ProviderScope(child: NeuraScanApp()));
}

/// The root widget.
class NeuraScanApp extends ConsumerWidget {
  const NeuraScanApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'NeuraScan AI',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),

      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),

      // Null follows the device, which is what a user who never opened the
      // settings screen expects.
      locale: ref.watch(localeProvider),
      localizationsDelegates: const [
        AppText.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppText.supportedLocales,

      builder: (context, child) => _AccessibleTextScale(child: child!),
    );
  }
}

/// Keeps the system font scale usable without letting it break the layout.
///
/// The app targets adults over 45 and the non-functional requirements call for text
/// scaling to 200 %, so the scale must be honoured rather than clamped to something
/// small. It is capped at 2.0 because the timed task screens have to fit a stimulus
/// and a countdown on one screen at once; past that point the reaction task stops
/// being a fair measurement, which is worse for the user than a smaller font.
class _AccessibleTextScale extends StatelessWidget {
  const _AccessibleTextScale({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(
          minScaleFactor: 1.0,
          maxScaleFactor: 2.0,
        ),
      ),
      child: child,
    );
  }
}
