import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/user_settings.dart';
import 'settings_cubit.dart';

/// Units, workout and appearance rows. Needs [SettingsCubit] above it.
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
                EffortScale.off => l10n.effortOff,
                EffortScale.rir => l10n.effortRir,
                EffortScale.rpe => l10n.effortRpe,
              },
              onChanged: (scale) =>
                  cubit.update(settings.copyWith(effortScale: scale)),
            ),
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
          ],
        );
      },
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
