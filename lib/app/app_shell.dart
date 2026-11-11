import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';

/// The five tabs. Each branch keeps its own stack; tapping the open tab
/// returns it to its first page.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.today_outlined),
            label: l10n.tabToday,
          ),
          NavigationDestination(
            icon: const Icon(Icons.event_note_outlined),
            label: l10n.tabPrograms,
          ),
          NavigationDestination(
            icon: const Icon(Icons.accessibility_new),
            label: l10n.tabExercises,
          ),
          NavigationDestination(
            icon: const Icon(Icons.insights_outlined),
            label: l10n.tabProgress,
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: l10n.tabProfile,
          ),
        ],
      ),
    );
  }
}
