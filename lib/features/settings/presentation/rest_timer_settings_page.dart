import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/choice_sheet.dart';
import '../../../l10n/app_localizations.dart';
import '../../notifications/presentation/notification_permission.dart';
import '../../programs/presentation/program_text.dart';
import '../../workout/presentation/rest_timer_cubit.dart';
import '../domain/user_settings.dart';
import 'settings_cubit.dart';
import 'settings_section.dart';

/// The rest timer's settings, from Profile's Workout group: the switch,
/// then, while it is on, the default rest, the notification and the
/// sound. Needs [SettingsCubit], [RestTimerCubit] and `NotificationsCubit`
/// above it.
class RestTimerSettingsPage extends StatelessWidget {
  const RestTimerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final cubit = context.read<SettingsCubit>();
    final rest = settings.restTimer;
    void updateRest(RestTimerSettings rest) =>
        cubit.update(settings.copyWith(restTimer: rest));
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.settingsRestTimer),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
        children: [
          ListRowCard(
            children: [
              ListRow(
                title: l10n.settingsRestTimer,
                detail: l10n.settingsRestTimerOn,
                trailing: ForgeSwitch(
                  value: rest.enabled,
                  onChanged: (on) => updateRest(rest.copyWith(enabled: on)),
                ),
              ),
              // A rest timer that is off has nothing to set.
              if (rest.enabled) ...[
                ChoiceSettingRow(
                  title: l10n.settingsRestDefault,
                  values: ({
                    ...RestTimerSettings.choicesS,
                    rest.defaultS,
                  }.toList()..sort()),
                  selected: rest.defaultS,
                  labelOf: l10n.restClock,
                  onChanged: (seconds) =>
                      updateRest(rest.copyWith(defaultS: seconds)),
                ),
                ListRow(
                  title: l10n.settingsRestNotify,
                  trailing: ForgeSwitch(
                    value: rest.notify ?? false,
                    onChanged: (on) => _setNotify(context, on),
                  ),
                ),
                ChoiceSettingRow(
                  title: l10n.settingsRestAlert,
                  values: RestAlert.values,
                  selected: rest.alert,
                  labelOf: (alert) => alert == const RestTimerSettings().alert
                      ? l10n.settingDefault(l10n.restAlertLabel(alert))
                      : l10n.restAlertLabel(alert),
                  onChanged: (alert) => updateRest(rest.copyWith(alert: alert)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Turns the rest notification on, asking for the device's permission as
/// the reminders do, or off.
Future<void> _setNotify(BuildContext context, bool on) {
  final rest = context.read<RestTimerCubit>();
  if (!on) return rest.setNotify(false);
  return turnOnNotifying(
    context,
    reason: AppLocalizations.of(context).restNotifyPermissionReason,
    store: () => rest.setNotify(true),
  );
}
