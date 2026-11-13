import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/reminder_settings_changes.dart';
import 'notifications_cubit.dart';

/// The reminder rows of the settings. Needs [SettingsCubit] above it, and
/// [NotificationsCubit] once a reminder is on or being turned on.
class ReminderSettingsTiles extends StatelessWidget {
  const ReminderSettingsTiles({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select(
      (SettingsCubit cubit) => cubit.state.settings,
    );
    final workout = settings.workoutReminder;
    final measurement = settings.measurementReminder;
    // Applied to the settings as they are when the choice arrives.
    void update(UserSettings Function(UserSettings settings) change) {
      final cubit = context.read<SettingsCubit>();
      cubit.update(change(cubit.state.settings));
    }

    CalendarDate today() => CalendarDate.of(DateTime.now());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(dense: true, title: Text(l10n.settingsReminders)),
        SwitchListTile(
          title: Text(l10n.settingsWorkoutReminder),
          subtitle: workout.enabled
              ? Text(
                  l10n.settingsWorkoutReminderOn(
                    _time(context, workout.minute),
                  ),
                )
              : null,
          value: workout.enabled,
          onChanged: (on) => _switch(
            context,
            on,
            (settings) => settings.withWorkoutReminder(enabled: on),
          ),
        ),
        if (workout.enabled)
          _TimeTile(
            minute: workout.minute,
            onChanged: (minute) => update(
              (settings) => settings.withWorkoutReminder(minute: minute),
            ),
          ),
        SwitchListTile(
          title: Text(l10n.settingsMeasurementReminder),
          value: measurement.enabled,
          onChanged: (on) => _switch(
            context,
            on,
            (settings) =>
                settings.withMeasurementReminder(enabled: on, today: today()),
          ),
        ),
        if (measurement.enabled) ...[
          _PickTile(
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
          _PickTile(
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
          _TimeTile(
            minute: measurement.minute,
            onChanged: (minute) => update(
              (settings) => settings.withMeasurementReminder(
                minute: minute,
                today: today(),
              ),
            ),
          ),
        ],
        if (workout.enabled || measurement.enabled) const _BlockedTile(),
      ],
    );
  }
}

/// Turns a reminder off, or on after making sure the device lets the app
/// notify: asked in the app first with one line, and pointed to the system
/// settings when the device refuses. The reminder is stored on either way,
/// as the rest notification's wish is: it works once notifications are
/// allowed.
Future<void> _switch(
  BuildContext context,
  bool on,
  UserSettings Function(UserSettings settings) change,
) async {
  final settings = context.read<SettingsCubit>();
  if (!on) return settings.update(change(settings.state.settings));
  final notifications = context.read<NotificationsCubit>();
  if (notifications.state.allowed != true && !await _explain(context)) return;
  final allowed = await notifications.allow();
  await settings.update(change(settings.state.settings));
  if (!allowed && context.mounted) await _showBlocked(context, notifications);
}

Future<bool> _explain(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final allow = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l10n.remindersPermissionReason),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.remindersLater),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.remindersAllow),
        ),
      ],
    ),
  );
  return allow ?? false;
}

Future<void> _showBlocked(
  BuildContext context,
  NotificationsCubit notifications,
) async {
  final l10n = AppLocalizations.of(context);
  final open = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(l10n.remindersBlocked),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.remindersOpenSettings),
        ),
      ],
    ),
  );
  if (open ?? false) await notifications.openSettings();
}

String _time(BuildContext context, int minute) =>
    TimeOfDay(hour: minute ~/ 60, minute: minute % 60).format(context);

/// Says that the device does not let the app notify, while it does not.
class _BlockedTile extends StatelessWidget {
  const _BlockedTile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final allowed = context.select(
      (NotificationsCubit cubit) => cubit.state.allowed,
    );
    if (allowed != false) return const SizedBox.shrink();
    return ListTile(
      subtitle: Text(l10n.remindersBlocked),
      trailing: TextButton(
        onPressed: context.read<NotificationsCubit>().openSettings,
        child: Text(l10n.remindersOpenSettings),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  const _TimeTile({required this.minute, required this.onChanged});

  final int minute;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(AppLocalizations.of(context).settingsReminderTime),
      trailing: Text(_time(context, minute)),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
        );
        if (picked != null) onChanged(picked.hour * 60 + picked.minute);
      },
    );
  }
}

/// A row showing the current choice; tapping it offers the [values].
class _PickTile<T> extends StatelessWidget {
  const _PickTile({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: Text(labelOf(selected)),
      onTap: () async {
        final picked = await showDialog<T>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(title),
            children: [
              for (final value in values)
                ListTile(
                  title: Text(labelOf(value)),
                  selected: value == selected,
                  onTap: () => Navigator.pop(context, value),
                ),
            ],
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
