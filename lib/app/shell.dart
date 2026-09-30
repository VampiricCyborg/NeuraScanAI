/// The navigation shell around the three main tabs.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'l10n/generated/app_localizations.dart';
import 'router.dart';

/// Bottom navigation around the home, trends and profile tabs.
class AppShell extends StatelessWidget {
  const AppShell({required this.child, super.key});

  final Widget child;

  static const _destinations = [Routes.home, Routes.trends, Routes.profile];

  @override
  Widget build(BuildContext context) {
    final text = AppText.of(context);
    final location = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexFor(location),
        onDestinationSelected: (index) => context.go(_destinations[index]),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: text.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.show_chart_outlined),
            selectedIcon: const Icon(Icons.show_chart),
            label: text.navTrends,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: text.navProfile,
          ),
        ],
      ),
    );
  }

  /// Which tab [location] belongs to.
  ///
  /// Uses a prefix match so that a nested route -- the privacy screen under the
  /// profile tab -- keeps its parent tab selected rather than clearing the
  /// selection.
  int _indexFor(String location) {
    for (var i = _destinations.length - 1; i >= 0; i--) {
      if (location.startsWith(_destinations[i])) return i;
    }
    return 0;
  }
}
