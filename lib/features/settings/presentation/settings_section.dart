import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../notifications/presentation/reminder_settings_tiles.dart';
import '../../programs/presentation/program_text.dart';
import '../../workout/presentation/rest_timer_cubit.dart';
import '../domain/user_settings.dart';
import 'settings_cubit.dart';
import 'warmup_settings_page.dart';

/// Units, workout, reminder and appearance rows. Needs [SettingsCubit] and
/// [RestTimerCubit] above it, and what [ReminderSettingsTiles] needs.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          current.failure != null && current.failure != previous.failure,
      listener: (context, _) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(l10n.settingsSaveFailed))),
      builder: (context, state) {
        final cubit = context.read<SettingsCubit>();
        final settings = state.settings;
        final rest = settings.restTimer;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(l10n.settingsUnits),
            _ChoiceTile(
              title: l10n.settingsWeight,
              values: WeightUnit.values,
              selected: settings.weightUnit,
              labelOf: (unit) => switch (unit) {
                WeightUnit.kg => l10n.unitKg,
                WeightUnit.lb => l10n.unitLb,
              },
              onChanged: (unit) =>
                  cubit.update(settings.copyWith(weightUnit: unit)),
            ),
            _ChoiceTile(
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
            _Header(l10n.settingsWorkout),
            _ChoiceTile(
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
            ListTile(
              title: Text(l10n.settingsAutoWarmups),
              subtitle: Text(l10n.warmupSettingsSummary(settings.warmups)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.warmupSettings),
            ),
            SwitchListTile(
              title: Text(l10n.settingsRestTimer),
              subtitle: Text(l10n.settingsRestTimerOn),
              value: rest.enabled,
              onChanged: (enabled) => cubit.update(
                settings.copyWith(restTimer: rest.copyWith(enabled: enabled)),
              ),
            ),
            _ChoiceTile(
              title: l10n.settingsRestDefault,
              values: ({...RestTimerSettings.choicesS, rest.defaultS}.toList()
                ..sort()),
              selected: rest.defaultS,
              labelOf: l10n.programSeconds,
              onChanged: (seconds) => cubit.update(
                settings.copyWith(restTimer: rest.copyWith(defaultS: seconds)),
              ),
            ),
            SwitchListTile(
              title: Text(l10n.settingsRestNotify),
              value: rest.notify ?? false,
              onChanged: (on) => _setNotify(context, on),
            ),
            const ReminderSettingsTiles(),
            _Header(l10n.settingsAppearance),
            _ChoiceTile(
              title: l10n.settingsTheme,
              values: ThemePreference.values,
              selected: settings.themePreference,
              labelOf: (theme) => switch (theme) {
                ThemePreference.system => l10n.themeSystem,
                ThemePreference.light => l10n.themeLight,
                ThemePreference.dark => l10n.themeDark,
              },
              onChanged: (theme) =>
                  cubit.update(settings.copyWith(themePreference: theme)),
            ),
            _ChoiceTile(
              title: l10n.settingsWeekStart,
              values: WeekStart.values,
              selected: settings.weekStart,
              labelOf: (start) => switch (start) {
                WeekStart.automatic => l10n.weekStartAutomatic,
                WeekStart.monday => l10n.weekdayLong(DateTime.monday),
                WeekStart.sunday => l10n.weekdayLong(DateTime.sunday),
                WeekStart.saturday => l10n.weekdayLong(DateTime.saturday),
              },
              onChanged: (start) =>
                  cubit.update(settings.copyWith(weekStart: start)),
            ),
          ],
        );
      },
    );
  }
}

Future<void> _setNotify(BuildContext context, bool on) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final notifying = await context.read<RestTimerCubit>().setNotify(on);
  if (on && !notifying) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.settingsRestNotifyDenied)),
    );
  }
}

/// A section title: a dense list tile with the theme's default styling.
class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      ListTile(dense: true, title: Text(text));
}

/// A row showing the current choice; tapping it opens a single-choice dialog.
class _ChoiceTile<T> extends StatelessWidget {
  const _ChoiceTile({
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
      onTap: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showDialog<T>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(title),
        children: [
          RadioGroup<T>(
            groupValue: selected,
            onChanged: (value) => Navigator.pop(context, value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final value in values)
                  RadioListTile<T>(value: value, title: Text(labelOf(value))),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) onChanged(picked);
  }
}
