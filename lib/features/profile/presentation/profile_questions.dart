import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/user_profile.dart';
import 'profile_form_cubit.dart';

/// Display names of the profile answers. Level and equipment names come
/// from [VocabularyLabels].
extension ProfileLabels on AppLocalizations {
  String goalName(Goal goal) => switch (goal) {
    Goal.buildMuscle => goalBuildMuscle,
    Goal.getStronger => goalGetStronger,
    Goal.loseFat => goalLoseFat,
    Goal.generalFitness => goalGeneralFitness,
  };

  String levelInfo(Level level) => switch (level) {
    Level.beginner => levelBeginnerInfo,
    Level.intermediate => levelIntermediateInfo,
    Level.advanced => levelAdvancedInfo,
  };

  String sexName(Sex sex) => switch (sex) {
    Sex.male => calcSexMale,
    Sex.female => calcSexFemale,
  };

  String presetName(EquipmentPreset preset) => switch (preset) {
    EquipmentPreset.fullGym => presetFullGym,
    EquipmentPreset.homeGym => presetHomeGym,
    EquipmentPreset.dumbbellsOnly => presetDumbbellsOnly,
    EquipmentPreset.bodyweight => presetBodyweight,
  };

  String fieldName(ProfileField field) => switch (field) {
    ProfileField.goal => profileGoal,
    ProfileField.level => profileLevel,
    ProfileField.daysPerWeek => profileDaysPerWeek,
    ProfileField.equipment => profileEquipment,
    ProfileField.sex => profileSex,
    ProfileField.birthYear => profileBirthYear,
    ProfileField.height => profileHeight,
    ProfileField.weight => profileWeight,
    ProfileField.targetWeight => profileTargetWeight,
  };

  String question(ProfileField field) => switch (field) {
    ProfileField.goal => questionGoal,
    ProfileField.level => questionLevel,
    ProfileField.daysPerWeek => questionDaysPerWeek,
    ProfileField.equipment => questionEquipment,
    ProfileField.sex => questionSex,
    ProfileField.birthYear => questionBirthYear,
    ProfileField.height => questionHeight,
    ProfileField.weight => questionWeight,
    ProfileField.targetWeight => questionTargetWeight,
  };

  String? questionInfo(ProfileField field) => switch (field) {
    ProfileField.equipment => questionEquipmentInfo,
    ProfileField.sex => questionSexInfo,
    ProfileField.targetWeight => questionTargetWeightInfo,
    _ => null,
  };

  String weightUnitName(WeightUnit unit) => switch (unit) {
    WeightUnit.kg => unitKg,
    WeightUnit.lb => unitLb,
  };

  String lengthUnitName(LengthUnit unit) => switch (unit) {
    LengthUnit.cm => unitCm,
    LengthUnit.inch => unitIn,
  };

  /// The answer to [field] in [settings]' units, or null when unanswered.
  String? answerText(
    UserProfile profile,
    ProfileField field,
    UserSettings settings,
  ) {
    String weight(double? kg) => profileValueWithUnit(
      formatProfileNumber(settings.weightUnit.fromKg(kg!)),
      weightUnitName(settings.weightUnit),
    );
    if (!profile.answered(field)) return null;
    return switch (field) {
      ProfileField.goal => goalName(profile.goal!),
      ProfileField.level => levelName(profile.level!),
      ProfileField.daysPerWeek => profileDays(profile.daysPerWeek!),
      ProfileField.equipment => profileEquipmentCount(
        profile.equipment!.length,
      ),
      ProfileField.sex => sexName(profile.sex!),
      ProfileField.birthYear => '${profile.birthYear}',
      ProfileField.height => profileValueWithUnit(
        formatProfileNumber(settings.lengthUnit.fromCm(profile.heightCm!)),
        lengthUnitName(settings.lengthUnit),
      ),
      ProfileField.weight => weight(profile.weightKg),
      ProfileField.targetWeight => weight(profile.targetWeightKg),
    };
  }
}

/// At most one decimal, without a trailing zero.
String formatProfileNumber(double value) => NumberFormat('0.#').format(value);

/// One question of the profile, answered into the [ProfileFormCubit] above
/// it. Heights and weights are entered in the units of [SettingsCubit]; their
/// unit switch changes that setting.
class ProfileQuestion extends StatelessWidget {
  const ProfileQuestion(this.field, {super.key});

  final ProfileField field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final info = l10n.questionInfo(field);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Text(l10n.question(field), style: theme.textTheme.headlineSmall),
        if (info != null) ...[
          const SizedBox(height: Gap.sm),
          Text(info, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Gap.md),
        BlocBuilder<ProfileFormCubit, ProfileFormState>(
          builder: (context, state) => switch (field) {
            ProfileField.goal => _Choice(
              values: Goal.values,
              selected: state.answers.goal,
              title: l10n.goalName,
              onChanged: context.read<ProfileFormCubit>().setGoal,
            ),
            ProfileField.level => _Choice(
              values: Level.values,
              selected: state.answers.level,
              title: l10n.levelName,
              subtitle: l10n.levelInfo,
              onChanged: context.read<ProfileFormCubit>().setLevel,
            ),
            ProfileField.daysPerWeek => _Choice(
              values: [
                for (
                  var days = ProfileLimits.minDaysPerWeek;
                  days <= ProfileLimits.maxDaysPerWeek;
                  days++
                )
                  days,
              ],
              selected: state.answers.daysPerWeek,
              title: l10n.profileDays,
              onChanged: context.read<ProfileFormCubit>().setDaysPerWeek,
            ),
            ProfileField.equipment => _EquipmentAnswer(state.answers.equipment),
            ProfileField.sex => _Choice(
              values: Sex.values,
              selected: state.answers.sex,
              title: l10n.sexName,
              onChanged: context.read<ProfileFormCubit>().setSex,
            ),
            ProfileField.birthYear => _BirthYearAnswer(state),
            ProfileField.height => _HeightAnswer(state),
            ProfileField.weight ||
            ProfileField.targetWeight => _WeightAnswer(field, state),
          },
        ),
      ],
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.values,
    required this.selected,
    required this.title,
    required this.onChanged,
    this.subtitle,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) title;
  final String Function(T value)? subtitle;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: selected,
    onChanged: (value) {
      if (value != null) onChanged(value);
    },
    child: Column(
      children: [
        for (final value in values)
          RadioListTile<T>(
            value: value,
            title: Text(title(value)),
            subtitle: subtitle == null ? null : Text(subtitle!(value)),
          ),
      ],
    ),
  );
}

class _EquipmentAnswer extends StatelessWidget {
  const _EquipmentAnswer(this.owned);

  final Set<Equipment>? owned;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    final owned = this.owned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final preset in EquipmentPreset.values)
              ChoiceChip(
                label: Text(l10n.presetName(preset)),
                selected:
                    owned != null &&
                    owned.length == preset.equipment.length &&
                    owned.containsAll(preset.equipment),
                onSelected: (_) => cubit.applyPreset(preset),
              ),
          ],
        ),
        const SizedBox(height: Gap.md),
        for (final item in Equipment.values)
          if (item != Equipment.bodyweight)
            CheckboxListTile(
              value: owned?.contains(item) ?? false,
              title: Text(l10n.equipmentName(item)),
              onChanged: (_) => cubit.toggleEquipment(item),
            ),
      ],
    );
  }
}

class _BirthYearAnswer extends StatelessWidget {
  const _BirthYearAnswer(this.state);

  final ProfileFormState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    final range = cubit.birthYearRange;
    return _NumberEntry(
      label: l10n.profileBirthYear,
      initialValue: state.answers.birthYear?.toString() ?? '',
      wholeNumber: true,
      errorText: state.invalid.contains(ProfileField.birthYear)
          ? l10n.profileYearOutOfRange(range.min, range.max)
          : null,
      onChanged: cubit.enterBirthYear,
    );
  }
}

class _HeightAnswer extends StatelessWidget {
  const _HeightAnswer(this.state);

  final ProfileFormState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    final settings = context.select((SettingsCubit c) => c.state.settings);
    final unit = settings.lengthUnit;
    final cm = state.answers.heightCm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnitSwitch<LengthUnit>(
          values: LengthUnit.values,
          selected: unit,
          label: l10n.lengthUnitName,
          onChanged: (unit) {
            context.read<SettingsCubit>().update(
              settings.copyWith(lengthUnit: unit),
            );
            cubit.unitChanged(ProfileField.height);
          },
        ),
        _NumberEntry(
          key: ValueKey(unit),
          label: l10n.calcHeight(l10n.lengthUnitName(unit)),
          initialValue: cm == null ? '' : formatProfileNumber(unit.fromCm(cm)),
          errorText: state.invalid.contains(ProfileField.height)
              ? l10n.calcOutOfRange(
                  formatProfileNumber(unit.fromCm(ProfileLimits.minHeightCm)),
                  formatProfileNumber(unit.fromCm(ProfileLimits.maxHeightCm)),
                )
              : null,
          onChanged: (text) => cubit.enterHeight(text, unit),
        ),
      ],
    );
  }
}

/// The body weight or the target weight.
class _WeightAnswer extends StatelessWidget {
  const _WeightAnswer(this.field, this.state);

  final ProfileField field;
  final ProfileFormState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    final settings = context.select((SettingsCubit c) => c.state.settings);
    final unit = settings.weightUnit;
    final target = field == ProfileField.targetWeight;
    final kg = target ? state.answers.targetWeightKg : state.answers.weightKg;
    final unitName = l10n.weightUnitName(unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _UnitSwitch<WeightUnit>(
          values: WeightUnit.values,
          selected: unit,
          label: l10n.weightUnitName,
          onChanged: (unit) {
            context.read<SettingsCubit>().update(
              settings.copyWith(weightUnit: unit),
            );
            cubit.unitChanged(field);
          },
        ),
        _NumberEntry(
          key: ValueKey(unit),
          label: target
              ? l10n.calcTargetWeight(unitName)
              : l10n.calcBodyWeight(unitName),
          initialValue: kg == null ? '' : formatProfileNumber(unit.fromKg(kg)),
          errorText: state.invalid.contains(field)
              ? l10n.calcOutOfRange(
                  formatProfileNumber(unit.fromKg(ProfileLimits.minWeightKg)),
                  formatProfileNumber(unit.fromKg(ProfileLimits.maxWeightKg)),
                )
              : null,
          onChanged: (text) => target
              ? cubit.enterTargetWeight(text, unit)
              : cubit.enterWeight(text, unit),
        ),
      ],
    );
  }
}

class _UnitSwitch<T> extends StatelessWidget {
  const _UnitSwitch({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: SegmentedButton<T>(
      segments: [
        for (final value in values)
          ButtonSegment(value: value, label: Text(label(value))),
      ],
      selected: {selected},
      onSelectionChanged: (selection) => onChanged(selection.single),
    ),
  );
}

/// A number input that reports every change. Its text starts from
/// [initialValue]; give it a new key to restart it.
class _NumberEntry extends StatefulWidget {
  const _NumberEntry({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onChanged,
    this.errorText,
    this.wholeNumber = false,
  });

  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;
  final String? errorText;
  final bool wholeNumber;

  @override
  State<_NumberEntry> createState() => _NumberEntryState();
}

class _NumberEntryState extends State<_NumberEntry> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    autofocus: true,
    onChanged: widget.onChanged,
    keyboardType: TextInputType.numberWithOptions(decimal: !widget.wholeNumber),
    decoration: InputDecoration(
      labelText: widget.label,
      errorText: widget.errorText,
      errorMaxLines: 3,
    ),
  );
}
