import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/steps.dart';
import 'health_access_cubit.dart';

/// The Connected apps group: the health store and what the app reads from
/// it. On opens the store's settings; Off leads to the Steps page, which
/// explains before asking. Hidden on a device without a health store, and
/// until access is known. Needs [HealthAccessCubit] above it.
class ConnectedAppsGroup extends StatefulWidget {
  const ConnectedAppsGroup({super.key});

  @override
  State<ConnectedAppsGroup> createState() => _ConnectedAppsGroupState();
}

class _ConnectedAppsGroupState extends State<ConnectedAppsGroup> {
  late final HealthAccessCubit _cubit = context.read<HealthAccessCubit>();
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _cubit.load);
    _cubit.load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final access = context.watch<HealthAccessCubit>().state;
    if (access == null || access == StepsAccess.unsupported) {
      return const SizedBox.shrink();
    }
    final on = access.readable;
    return SettingsGroup(
      title: l10n.settingsConnectedApps,
      rows: [
        ListRow(
          title: Theme.of(context).platform == TargetPlatform.iOS
              ? l10n.stepsStoreApple
              : l10n.stepsStoreGoogle,
          detail: l10n.connectedStepsIn,
          value: on ? l10n.connectedOn : l10n.connectedOff,
          end: ListRowEnd.chevron,
          onTap: on ? _cubit.openSettings : () => context.go(Routes.steps),
        ),
      ],
    );
  }
}
