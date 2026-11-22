import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../core/widgets/choice_sheet.dart';
import '../../../core/widgets/settings_group.dart';
import '../../../l10n/app_localizations.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/reminder_settings_changes.dart';
import 'notification_permission.dart';
import 'notifications_cubit.dart';

/// The Reminders group of the settings, led by a notice while the device
/// does not let the app notify: it asks on a device never asked, else it
/// opens the system settings. Needs [SettingsCubit] and
/// [NotificationsCubit] above it.
class ReminderSettingsGroup extends StatelessWidget {
  const ReminderSettingsGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final access = context.select((NotificationsCubit cubit) => cubit.state);
    final workout = settings.workoutReminder;
    final measurement = settings.measurementReminder;
    // Applied to the settings as they are when the choice arrives.
    void update(UserSettings Function(UserSettings settings) change) {
      final cubit = context.read<SettingsCubit>();
      cubit.update(change(cubit.state.settings));
    }

    Future<void> turn(
      bool on,
      UserSettings Function(UserSettings settings) change,
    ) {
      if (!on) {
        update(change);
        return Future.value();
      }
      return turnOnNotifying(
        context,
        reason: l10n.remindersPermissionReason,
        store: () async => update(change),
      );
    }

    CalendarDate today() => CalendarDate.of(DateTime.now());
    return SettingsGroup(
      title: l10n.settingsReminders,
      notice: access.allowed == false
          ? NoticeBanner(
              icon: ForgeIcons.notificationsOff,
              title: l10n.notificationsOffTitle,
              message: l10n.notificationsOffMessage,
              // A device never asked has no notification settings yet.
              action: access.asked == false
                  ? ForgeButton(
                      label: l10n.notificationsAllow,
                      variant: ForgeButtonVariant.secondary,
                      onPressed: context.read<NotificationsCubit>().allow,
                    )
                  : ForgeButton(
                      label: l10n.remindersOpenSettings,
                      variant: ForgeButtonVariant.secondary,
                      onPressed: context
                          .read<NotificationsCubit>()
                          .openSettings,
                    ),
            )
          : null,
      rows: [
        ListRow(
          title: l10n.settingsWorkoutReminder,
          detail: l10n.settingsWorkoutReminderDays,
          trailing: ForgeSwitch(
            value: workout.enabled,
            onChanged: (on) => turn(
              on,
              (settings) => settings.withWorkoutReminder(enabled: on),
            ),
          ),
        ),
        if (workout.enabled)
          _TimeRow(
            minute: workout.minute,
            onChanged: (minute) => update(
              (settings) => settings.withWorkoutReminder(minute: minute),
            ),
          ),
        ListRow(
          title: l10n.settingsMeasurementReminder,
          trailing: ForgeSwitch(
            value: measurement.enabled,
            onChanged: (on) => turn(
              on,
              (settings) =>
                  settings.withMeasurementReminder(enabled: on, today: today()),
            ),
          ),
        ),
        if (measurement.enabled) ...[
          ChoiceSettingRow(
            title: l10n.settingsReminderRepeat,
            values: MeasurementReminderSettings.choicesWeeks,
            selected: measurement.everyWeeks,
            labelOf: l10n.settingsReminderEvery,
            onChanged: (weeks) => update(
              (settings) => settings.withMeasurementReminder(
                everyWeeks: weeks,
                today: today(),
              ),
            ),
          ),
          ChoiceSettingRow(
            title: l10n.settingsReminderDay,
            values: weekdaysFrom(context.watchFirstWeekday()),
            selected: measurement.from?.weekday ?? DateTime.now().weekday,
            labelOf: l10n.weekdayLong,
            onChanged: (weekday) => update(
              (settings) => settings.withMeasurementReminder(
                weekday: weekday,
                today: today(),
              ),
            ),
          ),
          _TimeRow(
            minute: measurement.minute,
            onChanged: (minute) => update(
              (settings) => settings.withMeasurementReminder(
                minute: minute,
                today: today(),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({required this.minute, required this.onChanged});

  final int minute;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay(hour: minute ~/ 60, minute: minute % 60);
    return ListRow(
      title: AppLocalizations.of(context).settingsReminderTime,
      value: time.format(context),
      end: ListRowEnd.chevron,
      // Each step of the wheel is saved as it turns.
      onTap: () => showForgeTimeWheel(
        context: context,
        initial: time,
        onChanged: (picked) => onChanged(picked.hour * 60 + picked.minute),
      ),
    );
  }
}
