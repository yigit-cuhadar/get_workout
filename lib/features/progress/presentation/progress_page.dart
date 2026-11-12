import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';

/// The Progress tab: one row per kind of progress.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabProgress)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.calendar_month),
            title: Text(l10n.progressCalendar),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.calendar),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.progressHistory),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.history),
          ),
          ListTile(
            leading: const Icon(Icons.accessibility_new),
            title: Text(l10n.progressVolume),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.volume),
          ),
          ListTile(
            leading: const Icon(Icons.trending_up),
            title: Text(l10n.progressStrength),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.strength),
          ),
          ListTile(
            leading: const Icon(Icons.directions_run),
            title: Text(l10n.progressCardio),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.cardio),
          ),
          ListTile(
            leading: const Icon(Icons.directions_walk),
            title: Text(l10n.progressSteps),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.steps),
          ),
          ListTile(
            leading: const Icon(Icons.monitor_weight_outlined),
            title: Text(l10n.progressBody),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.body),
          ),
        ],
      ),
    );
  }
}
