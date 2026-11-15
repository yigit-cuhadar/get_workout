import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/widgets/choice_sheet.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../../notifications/presentation/notification_permission.dart';
import '../../programs/presentation/program_text.dart';
import '../../workout/presentation/rest_timer_cubit.dart';
import '../domain/user_settings.dart';
import 'first_weekday.dart';
import 'settings_cubit.dart';
import 'warmup_settings_page.dart';

/// The Units and Workout groups of the settings. Needs [SettingsCubit],
/// [RestTimerCubit] and `NotificationsCubit` above it.
class WorkoutSettingsGroups extends StatelessWidget {
  const WorkoutSettingsGroups({super.key});

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
    return SettingsColumn(
      children: [
        SettingsGroup(
          title: l10n.settingsUnits,
          rows: [
            ChoiceSettingRow(
              title: l10n.settingsWeight,
              values: WeightUnit.values,
              selected: settings.weightUnit,
              labelOf: l10n.weightUnitLabel,
              onChanged: (unit) =>
                  cubit.update(settings.copyWith(weightUnit: unit)),
            ),
            ChoiceSettingRow(
              title: l10n.settingsLength,
              values: LengthUnit.values,
              selected: settings.lengthUnit,
              labelOf: (unit) => switch (unit) {
                LengthUnit.cm => l10n.unitCm,
                LengthUnit.inch => l10n.unitIn,
              },
              onChanged: (unit) =>
                  cubit.update(settings.copyWith(lengthUnit: unit)),
            ),
          ],
        ),
        SettingsGroup(
          title: l10n.settingsWorkout,
          rows: [
            ChoiceSettingRow(
              title: l10n.settingsEffort,
              values: EffortScale.values,
              selected: settings.effortScale,
              labelOf: (scale) => switch (scale) {
                EffortScale.byFeel => l10n.effortByFeel,
                EffortScale.rir => l10n.effortRir,
                EffortScale.rpe => l10n.effortRpe,
              },
              onChanged: (scale) =>
                  cubit.update(settings.copyWith(effortScale: scale)),
            ),
            ListRow(
              title: l10n.settingsAutoWarmups,
              detail: l10n.warmupSettingsSummary(settings.warmups),
              end: ListRowEnd.chevron,
              onTap: () => context.push(Routes.warmupSettings),
            ),
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
                values: ({...RestTimerSettings.choicesS, rest.defaultS}.toList()
                  ..sort()),
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
                labelOf: l10n.restAlertLabel,
                onChanged: (alert) => updateRest(rest.copyWith(alert: alert)),
              ),
            ],
            ListRow(
              title: l10n.settingsBarPlates,
              detail: l10n.barPlatesSummary(settings),
              end: ListRowEnd.chevron,
              onTap: () => context.push(Routes.barPlates),
            ),
            ListRow(
              title: l10n.settingsKeepScreenOn,
              detail: l10n.settingsKeepScreenOnInfo,
              trailing: ForgeSwitch(
                value: settings.keepScreenOn,
                onChanged: (on) =>
                    cubit.update(settings.copyWith(keepScreenOn: on)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The Appearance group: light, dark or the system's, and the first day
/// of the week. Needs [SettingsCubit] above it.
class AppearanceGroup extends StatelessWidget {
  const AppearanceGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final cubit = context.read<SettingsCubit>();
    final phoneFirstWeekday = context.watchDeviceFirstWeekday();
    return SettingsGroup(
      title: l10n.settingsAppearance,
      rows: [
        AppearanceSetting(
          label: l10n.settingsAppearance,
          lightLabel: l10n.themeLight,
          darkLabel: l10n.themeDark,
          systemLabel: l10n.themeSystem,
          value: switch (settings.themePreference) {
            ThemePreference.system => ThemeMode.system,
            ThemePreference.light => ThemeMode.light,
            ThemePreference.dark => ThemeMode.dark,
          },
          onChanged: (mode) => cubit.update(
            settings.copyWith(
              themePreference: switch (mode) {
                ThemeMode.system => ThemePreference.system,
                ThemeMode.light => ThemePreference.light,
                ThemeMode.dark => ThemePreference.dark,
              },
            ),
          ),
        ),
        ChoiceSettingRow(
          title: l10n.settingsWeekStart,
          values: WeekStart.values,
          selected: settings.weekStart,
          labelOf: (start) => switch (start) {
            WeekStart.automatic => l10n.weekStartAutomatic(
              l10n.weekdayLong(phoneFirstWeekday),
            ),
            WeekStart.monday => l10n.weekdayLong(DateTime.monday),
            WeekStart.sunday => l10n.weekdayLong(DateTime.sunday),
            WeekStart.saturday => l10n.weekdayLong(DateTime.saturday),
          },
          onChanged: (start) =>
              cubit.update(settings.copyWith(weekStart: start)),
        ),
      ],
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

extension SettingsText on AppLocalizations {
  String restAlertLabel(RestAlert alert) => switch (alert) {
    RestAlert.chimeVibrate => restAlertChimeVibrate,
    RestAlert.chime => restAlertChime,
    RestAlert.vibrate => restAlertVibrate,
    RestAlert.off => restAlertOff,
  };

  /// `20 kg bar · 25, 20, 15, 10, 5, 2.5, 1.25`: the barbell and the plate
  /// sizes, largest first.
  String barPlatesSummary(UserSettings settings) {
    final unit = settings.weightUnit;
    final number = NumberFormat.decimalPattern(localeName)
      ..maximumFractionDigits = 2;
    return settingsBarPlatesSummary(
      liftedWeightText(settings.barWeightKg, unit),
      settings.plates
          .map((plate) => number.format(unit.fromKg(plate.weightKg)))
          .join(', '),
    );
  }
}
