import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../l10n/app_localizations.dart';
import 'notifications_cubit.dart';

/// Turns on something that notifies, after making sure the device lets the
/// app notify: asked in the app first with one line, the [reason], and
/// pointed to the system settings when the device refuses. [store] keeps
/// the wish either way, so it works once notifications are allowed; "Not
/// now" leaves everything as it was. Needs [NotificationsCubit] above.
Future<void> turnOnNotifying(
  BuildContext context, {
  required String reason,
  required Future<void> Function() store,
}) async {
  final notifications = context.read<NotificationsCubit>();
  if (notifications.state.allowed != true && !await _explain(context, reason)) {
    return;
  }
  final allowed = await notifications.allow();
  await store();
  if (!allowed && context.mounted) {
    await _showNotificationsOff(context, notifications);
  }
}

Future<bool> _explain(BuildContext context, String reason) async {
  final l10n = AppLocalizations.of(context);
  final allow = await showForgeDialog<bool>(
    context: context,
    builder: (context) => ForgeDialog(
      title: l10n.remindersPermissionTitle,
      message: reason,
      action: ForgeButton(
        label: l10n.remindersAllow,
        onPressed: () => Navigator.pop(context, true),
      ),
      cancel: ForgeButton(
        label: l10n.remindersLater,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context, false),
      ),
    ),
  );
  return allow ?? false;
}

/// Says that the device does not let the app notify, with the way to its
/// settings.
Future<void> _showNotificationsOff(
  BuildContext context,
  NotificationsCubit notifications,
) async {
  final l10n = AppLocalizations.of(context);
  final open = await showForgeDialog<bool>(
    context: context,
    builder: (context) => ForgeDialog(
      title: l10n.notificationsOffTitle,
      message: l10n.remindersBlocked,
      action: ForgeButton(
        label: l10n.remindersOpenSettings,
        onPressed: () => Navigator.pop(context, true),
      ),
      cancel: ForgeButton(
        label: l10n.close,
        variant: ForgeButtonVariant.secondary,
        onPressed: () => Navigator.pop(context, false),
      ),
    ),
  );
  if (open ?? false) await notifications.openSettings();
}
