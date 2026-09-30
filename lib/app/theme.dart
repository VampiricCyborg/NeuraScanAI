/// The app's Material 3 theme.
///
/// Two constraints shaped this beyond ordinary taste. The first is the audience:
/// the app targets adults over 45, so nothing depends on a small tap target or a
/// fine colour distinction, and every text style survives the system font scale
/// being turned up to 200 %. The second is tone: a screening result is something
/// people will read while worried, so the palette stays calm and the status
/// colours avoid the red-alert register that would turn ordinary variation into
/// alarm.
library;

import 'package:flutter/material.dart';

import '../engine/screening_engine.dart';

/// The brand colour, a desaturated teal.
///
/// Chosen for a clinical rather than a consumer-wellness feel, and dark enough
/// that white text on it clears WCAG AA at body sizes.
const Color kBrandSeed = Color(0xFF146C7A);

/// Minimum tap target, from the non-functional requirements.
///
/// Material's default is 48 dp already, but several controls in the task screens
/// are built by hand and would otherwise end up smaller.
const double kMinTapTarget = 48.0;

/// Standard page padding. Generous, because the task screens are read at arm's
/// length by someone who may be holding the phone loosely.
const double kPagePadding = 20.0;

/// Corner radius used across cards and buttons.
const double kCornerRadius = 16.0;

/// Colour and iconography for one screening status.
///
/// Grouped into a single type so that a status can never pick up a colour
/// without also picking up the matching icon and label, which is how a
/// colour-only distinction slips into a UI.
class StatusPresentation {
  const StatusPresentation({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;
}

/// How each status is presented.
///
/// The notable case is amber rather than red. It means "this has persisted, and
/// is worth discussing with a doctor", not "something is wrong with you", and
/// red would say the second thing.
const Map<ScreeningStatus, StatusPresentation> kStatusPresentation = {
  ScreeningStatus.stable: StatusPresentation(
    color: Color(0xFF2E7D57),
    icon: Icons.check_circle_outline,
    label: 'Stable',
  ),
  ScreeningStatus.mildDeviation: StatusPresentation(
    color: Color(0xFF9A6A00),
    icon: Icons.trending_up,
    label: 'Worth watching',
  ),
  ScreeningStatus.notableDeviation: StatusPresentation(
    color: Color(0xFFB4530A),
    icon: Icons.info_outline,
    label: 'Notable change',
  ),
  ScreeningStatus.buildingBaseline: StatusPresentation(
    color: Color(0xFF146C7A),
    icon: Icons.donut_large,
    label: 'Building your baseline',
  ),
  ScreeningStatus.excludedContext: StatusPresentation(
    color: Color(0xFF5B6770),
    icon: Icons.nights_stay_outlined,
    label: 'Set aside',
  ),
  ScreeningStatus.invalidSession: StatusPresentation(
    color: Color(0xFF5B6770),
    icon: Icons.replay,
    label: 'Not counted',
  ),
};

/// Colour for each behavioural domain, used consistently across the report
/// breakdown and the trend charts.
///
/// Distinguishable in the common forms of colour blindness, and always paired
/// with a text label rather than standing alone as the only cue.
const Map<String, Color> kDomainColors = {
  'cognitive': Color(0xFF146C7A),
  'speech': Color(0xFF7A5BA6),
  'motor': Color(0xFFB4530A),
  'interaction': Color(0xFF5B8C3A),
};

/// Builds the app theme for [brightness].
ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kBrandSeed,
    brightness: brightness,
  );
  final isLight = brightness == Brightness.light;

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: isLight ? const Color(0xFFF4F9FB) : scheme.surface,
    visualDensity: VisualDensity.standard,

    appBarTheme: AppBarTheme(
      backgroundColor: isLight ? const Color(0xFFF4F9FB) : scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
    ),

    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kCornerRadius),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),

    // Buttons are deliberately taller than Material's default: they are pressed
    // under time pressure during the reaction task, and by users who may not
    // have a steady aim.
    //
    // The minimum width is finite on purpose. This was Size.fromHeight(52), whose
    // minimum width is infinite: fine in a stretched column, but it throws inside a
    // Row (which crashed the recall step) and stretches buttons across dialogs.
    // Full-width buttons get their width from the parent's stretch or tight
    // constraints, not from the theme.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(kMinTapTarget, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCornerRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(kMinTapTarget, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kCornerRadius),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isLight ? Colors.white : scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.secondaryContainer,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),

    listTileTheme: const ListTileThemeData(
      minVerticalPadding: 12,
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),

    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      space: 1,
      thickness: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      linearMinHeight: 10,
      linearTrackColor: scheme.surfaceContainerHighest,
    ),
  );
}

/// Convenience accessors for the theme extensions used across screens.
extension ThemeShortcuts on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;

  /// Presentation for [status], falling back to the neutral treatment.
  StatusPresentation presentationOf(ScreeningStatus status) =>
      kStatusPresentation[status] ??
      kStatusPresentation[ScreeningStatus.invalidSession]!;

  /// Colour for a domain key, falling back to the brand colour.
  Color domainColor(String domainKey) => kDomainColors[domainKey] ?? kBrandSeed;
}
