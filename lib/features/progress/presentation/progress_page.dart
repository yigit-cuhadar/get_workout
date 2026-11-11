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
            leading: const Icon(Icons.directions_run),
            title: Text(l10n.progressCardio),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(Routes.cardio),
          ),
        ],
      ),
    );
  }
}
