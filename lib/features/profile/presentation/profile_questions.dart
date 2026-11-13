import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  String presetName(EquipmentProfile preset) => switch (preset) {
    EquipmentProfile.fullGym => presetFullGym,
    EquipmentProfile.homeGym => presetHomeGym,
    EquipmentProfile.dumbbells => presetDumbbells,
    EquipmentProfile.bodyweight => presetBodyweight,
    EquipmentProfile.bands => presetBands,
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

  /// [cm] in centimetres, or in feet and inches.
  String heightText(double cm, LengthUnit unit) {
    final value = unit.fromCm(cm);
    return switch (unit) {
      LengthUnit.cm => profileValueWithUnit(formatProfileNumber(value), unitCm),
      LengthUnit.inch => () {
        final inches = (value * 10).round() / 10;
        final feet = inches ~/ 12;
        return profileFeetInches(feet, formatProfileNumber(inches - feet * 12));
      }(),
    };
  }

  String weightText(double kg, WeightUnit unit) => profileValueWithUnit(
    formatProfileNumber(unit.fromKg(kg)),
    weightUnitName(unit),
  );

  /// The answer to [field] in [settings]' units, or null when unanswered.
  String? answerText(
    UserProfile profile,
    ProfileField field,
    UserSettings settings,
  ) {
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
      ProfileField.height => heightText(profile.heightCm!, settings.lengthUnit),
      ProfileField.weight => weightText(profile.weightKg!, settings.weightUnit),
      ProfileField.targetWeight => weightText(
        profile.targetWeightKg!,
        settings.weightUnit,
      ),
    };
  }
}

/// At most one decimal, without a trailing zero.
String formatProfileNumber(double value) => NumberFormat('0.#').format(value);

/// The metric range [min]..[max] in a display unit, to the one decimal shown,
/// rounded inwards so a value at a shown bound is accepted.
({double min, double max}) displayRange(
  double min,
  double max,
  double Function(double metric) toUnit,
) =>
    (min: (toUnit(min) * 10).ceil() / 10, max: (toUnit(max) * 10).floor() / 10);

/// The metric range [min]..[max] in a display unit as a ruler in steps of
/// [step], rounded inwards so every tick is accepted.
({double min, double max}) rulerRange(
  double min,
  double max,
  double Function(double metric) toUnit,
  double step,
) {
  // Keeps a bound that is a whole step from being lost to rounding.
  const hair = 1e-6;
  return (
    min: (toUnit(min) / step - hair).ceil() * step,
    max: (toUnit(max) / step + hair).floor() * step,
  );
}

/// One question of the profile, answered into the [ProfileFormCubit] above
/// it: the question at the top and its answer at the bottom, near the
/// thumb. Heights and weights are entered in the units of [SettingsCubit];
/// their unit switch changes that setting.
class ProfileQuestion extends StatelessWidget {
  const ProfileQuestion(this.field, {super.key});

  final ProfileField field;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final info = l10n.questionInfo(field);
    final header = [
      Text(l10n.question(field), style: theme.textTheme.headlineSmall),
      if (info != null) ...[
        const SizedBox(height: Gap.sm),
        Text(info, style: theme.textTheme.bodyMedium),
      ],
      const SizedBox(height: Gap.md),
    ];
    final answer = BlocBuilder<ProfileFormCubit, ProfileFormState>(
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
        ProfileField.birthYear => _BirthYearAnswer(state.answers.birthYear),
        ProfileField.height => _HeightAnswer(state.answers.heightCm),
        ProfileField.weight => _WeightAnswer(field, state.answers.weightKg),
        ProfileField.targetWeight => _WeightAnswer(
          field,
          state.answers.targetWeightKg,
        ),
      },
    );
    const padding = EdgeInsets.all(Gap.md);
    return switch (field) {
      // Lists scroll when taller than the page, and sit at its bottom when
      // not.
      ProfileField.goal ||
      ProfileField.level ||
      ProfileField.daysPerWeek ||
      ProfileField.equipment ||
      ProfileField.sex => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: padding,
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...header, const Spacer(), answer],
              ),
            ),
          ),
        ],
      ),
      ProfileField.birthYear ||
      ProfileField.height ||
      ProfileField.weight ||
      ProfileField.targetWeight => Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [...header, const Spacer(), answer],
        ),
      ),
    };
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
            for (final preset in EquipmentProfile.values)
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

/// A wheel of the years [ProfileFormCubit.birthYearRange] allows.
class _BirthYearAnswer extends StatefulWidget {
  const _BirthYearAnswer(this.year);

  /// Answered as soon as the question shows.
  final int? year;

  @override
  State<_BirthYearAnswer> createState() => _BirthYearAnswerState();
}

class _BirthYearAnswerState extends State<_BirthYearAnswer> {
  static const _itemExtent = Gap.xl + Gap.sm;
  static const _visibleItems = 5;

  late final _range = context.read<ProfileFormCubit>().birthYearRange;
  late final _controller = FixedExtentScrollController(
    initialItem: ((widget.year ?? _range.max) - _range.min).clamp(
      0,
      _range.max - _range.min,
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.headlineSmall;
    final cubit = context.read<ProfileFormCubit>();
    return SizedBox(
      height: _itemExtent * _visibleItems,
      // Kept from the page: the app bar would take the wheel's scrolling
      // for content scrolling under it.
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: ListWheelScrollView.useDelegate(
          controller: _controller,
          itemExtent: _itemExtent,
          physics: const FixedExtentScrollPhysics(),
          overAndUnderCenterOpacity: 0.5,
          onSelectedItemChanged: (index) {
            HapticFeedback.selectionClick();
            cubit.setBirthYear(_range.min + index);
          },
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: _range.max - _range.min + 1,
            builder: (context, index) =>
                Center(child: Text('${_range.min + index}', style: style)),
          ),
        ),
      ),
    );
  }
}

class _HeightAnswer extends StatelessWidget {
  const _HeightAnswer(this.cm);

  /// Answered as soon as the question shows.
  final double? cm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    final settings = context.select((SettingsCubit c) => c.state.settings);
    final unit = settings.lengthUnit;
    final cm = this.cm;
    if (cm == null) return const SizedBox.shrink();
    final value = unit.fromCm(cm);
    final range = rulerRange(
      ProfileLimits.minHeightCm,
      ProfileLimits.maxHeightCm,
      unit.fromCm,
      1,
    );
    return _NumberAnswer(
      unitSwitch: _UnitSwitch<LengthUnit>(
        values: LengthUnit.values,
        selected: unit,
        label: (unit) => switch (unit) {
          LengthUnit.cm => l10n.unitCm,
          LengthUnit.inch => l10n.unitFtIn,
        },
        onChanged: (unit) => context.read<SettingsCubit>().update(
          settings.copyWith(lengthUnit: unit),
        ),
      ),
      text: l10n.heightText(cm, unit),
      ruler: RulerPicker(
        key: ValueKey(unit),
        min: range.min,
        max: range.max,
        step: 1,
        value: value,
        onChanged: (value) => cubit.setHeight(value, unit),
      ),
      entry: (
        label: l10n.calcHeight(l10n.lengthUnitName(unit)),
        initialValue: formatProfileNumber(value),
        error: _outOfRange(
          l10n,
          displayRange(
            ProfileLimits.minHeightCm,
            ProfileLimits.maxHeightCm,
            unit.fromCm,
          ),
        ),
        enter: (text) => cubit.enterHeight(text, unit),
      ),
    );
  }
}

/// The body weight or the target weight.
class _WeightAnswer extends StatelessWidget {
  const _WeightAnswer(this.field, this.kg);

  final ProfileField field;

  /// Answered as soon as the question shows.
  final double? kg;

  static const _step = 0.1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProfileFormCubit>();
    final settings = context.select((SettingsCubit c) => c.state.settings);
    final unit = settings.weightUnit;
    final target = field == ProfileField.targetWeight;
    final kg = this.kg;
    if (kg == null) return const SizedBox.shrink();
    final value = unit.fromKg(kg);
    final unitName = l10n.weightUnitName(unit);
    final range = rulerRange(
      ProfileLimits.minWeightKg,
      ProfileLimits.maxWeightKg,
      unit.fromKg,
      _step,
    );
    return _NumberAnswer(
      unitSwitch: _UnitSwitch<WeightUnit>(
        values: WeightUnit.values,
        selected: unit,
        label: l10n.weightUnitName,
        onChanged: (unit) => context.read<SettingsCubit>().update(
          settings.copyWith(weightUnit: unit),
        ),
      ),
      text: l10n.weightText(kg, unit),
      ruler: RulerPicker(
        key: ValueKey(unit),
        min: range.min,
        max: range.max,
        step: _step,
        value: value,
        onChanged: (value) => target
            ? cubit.setTargetWeight(value, unit)
            : cubit.setWeight(value, unit),
      ),
      entry: (
        label: target
            ? l10n.calcTargetWeight(unitName)
            : l10n.calcBodyWeight(unitName),
        initialValue: formatProfileNumber(value),
        error: _outOfRange(
          l10n,
          displayRange(
            ProfileLimits.minWeightKg,
            ProfileLimits.maxWeightKg,
            unit.fromKg,
          ),
        ),
        enter: (text) => target
            ? cubit.enterTargetWeight(text, unit)
            : cubit.enterWeight(text, unit),
      ),
    );
  }
}

String _outOfRange(AppLocalizations l10n, ({double min, double max}) range) =>
    l10n.calcOutOfRange(
      formatProfileNumber(range.min),
      formatProfileNumber(range.max),
    );

/// What typing a number answer needs: [enter] tells whether the text was
/// accepted, and [error] is shown when not.
typedef _Entry = ({
  String label,
  String initialValue,
  String error,
  bool Function(String text) enter,
});

/// A unit switch, the value in large type, which opens a field to type it,
/// and a ruler to drag.
class _NumberAnswer extends StatelessWidget {
  const _NumberAnswer({
    required this.unitSwitch,
    required this.text,
    required this.ruler,
    required this.entry,
  });

  final Widget unitSwitch;
  final String text;
  final Widget ruler;
  final _Entry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: unitSwitch),
        const SizedBox(height: Gap.md),
        Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _EntryDialog(entry),
            ),
            child: Text(text, style: theme.textTheme.displaySmall),
          ),
        ),
        const SizedBox(height: Gap.sm),
        NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: ruler,
        ),
        const SizedBox(height: Gap.sm),
        Text(
          l10n.profileRulerHint,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
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
  Widget build(BuildContext context) => SegmentedButton<T>(
    segments: [
      for (final value in values)
        ButtonSegment(value: value, label: Text(label(value))),
    ],
    selected: {selected},
    onSelectionChanged: (selection) => onChanged(selection.single),
  );
}

/// Types a number answer; closes once it is accepted.
class _EntryDialog extends StatefulWidget {
  const _EntryDialog(this.entry);

  final _Entry entry;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late final _controller = TextEditingController(
    text: widget.entry.initialValue,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.entry.enter(_controller.text)) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.entry.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        // Plain numbers only; the length fits every valid answer.
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          LengthLimitingTextInputFormatter(6),
        ],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: widget.entry.label,
          errorText: _error,
          errorMaxLines: 3,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
