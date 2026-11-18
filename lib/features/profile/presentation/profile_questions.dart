import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/onboarding_question.dart';
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

  String goalInfo(Goal goal) => switch (goal) {
    Goal.buildMuscle => goalBuildMuscleInfo,
    Goal.getStronger => goalGetStrongerInfo,
    Goal.loseFat => goalLoseFatInfo,
    Goal.generalFitness => goalGeneralFitnessInfo,
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
    ProfileField.goal => profileQuestionGoal,
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
      ProfileField.daysPerWeek => profileDaysAWeek(profile.daysPerWeek!),
      ProfileField.equipment => switch (EquipmentProfile.matching(
        profile.equipment!,
      )) {
        final preset? => presetName(preset),
        null => profileEquipmentCustom,
      },
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
/// it: the question at the top and its answer at the bottom, just above
/// the page's action, near the thumb. Heights and weights are
/// entered in the units of [SettingsCubit]; their unit switch changes that
/// setting, and a tap on the value opens a sheet to type it.
class ProfileQuestion extends StatelessWidget {
  const ProfileQuestion(this.field, {super.key, this.onboarding = false});

  final ProfileField field;

  /// In onboarding the goal says what it is for: the first program.
  final bool onboarding;

  /// The goals in the order the question lists them.
  static const goals = [
    Goal.loseFat,
    Goal.buildMuscle,
    Goal.getStronger,
    Goal.generalFitness,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final answer = BlocBuilder<ProfileFormCubit, ProfileFormState>(
      builder: (context, state) {
        final cubit = context.read<ProfileFormCubit>();
        return switch (field) {
          ProfileField.goal => OnboardingChoices(
            values: ProfileQuestion.goals,
            selected: state.answers.goal,
            title: l10n.goalName,
            subtitle: l10n.goalInfo,
            onChanged: cubit.setGoal,
          ),
          ProfileField.level => OnboardingChoices(
            values: Level.values,
            selected: state.answers.level,
            title: l10n.levelName,
            subtitle: l10n.levelInfo,
            onChanged: cubit.setLevel,
          ),
          ProfileField.daysPerWeek => OnboardingChoices(
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
            onChanged: cubit.setDaysPerWeek,
          ),
          ProfileField.equipment => EquipmentAnswer(
            owned: state.answers.equipment,
            onPreset: cubit.applyPreset,
            onEquipment: cubit.setEquipment,
          ),
          ProfileField.sex => OnboardingChoices(
            values: Sex.values,
            selected: state.answers.sex,
            title: l10n.sexName,
            onChanged: cubit.setSex,
          ),
          ProfileField.birthYear => _BirthYearAnswer(state.answers.birthYear),
          ProfileField.height => _HeightAnswer(state.answers.heightCm),
          ProfileField.weight => _WeightAnswer(field, state.answers.weightKg),
          ProfileField.targetWeight => _WeightAnswer(
            field,
            state.answers.targetWeightKg,
            nowKg: state.answers.weightKg,
          ),
        };
      },
    );
    // In onboarding the target weight follows the weight with the same
    // ruler, so it says plainly that this is another question.
    final weightKg = context.select(
      (ProfileFormCubit cubit) => cubit.state.answers.weightKg,
    );
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final goalWeight =
        onboarding && field == ProfileField.targetWeight && weightKg != null;
    return OnboardingQuestionBody(
      eyebrow: goalWeight ? l10n.onboardingTargetWeightEyebrow : null,
      title: goalWeight
          ? l10n.onboardingTargetWeightTitle
          : l10n.question(field),
      info: switch (field) {
        ProfileField.goal when onboarding => l10n.onboardingGoalInfo,
        _ when goalWeight => l10n.onboardingTargetWeightInfo(
          l10n.weightText(weightKg, unit),
        ),
        _ => l10n.questionInfo(field),
      },
      answer: answer,
      scrolls: switch (field) {
        ProfileField.goal ||
        ProfileField.level ||
        ProfileField.daysPerWeek ||
        ProfileField.equipment ||
        ProfileField.sex => true,
        ProfileField.birthYear ||
        ProfileField.height ||
        ProfileField.weight ||
        ProfileField.targetWeight => false,
      },
    );
  }
}

/// The equipment owned, as the closest set: one radio row per preset, like
/// the goal question. A tap picks the set; its info button opens the set's
/// items as checkboxes ([showEquipmentSheet]), and Done there picks the set
/// with the items ticked, so the opened row stays selected. Equipment that
/// matches no set when the question opens selects no row; a muted line
/// under the list counts it, and its Edit opens the items as checkboxes.
/// Bodyweight is always owned, so it is not offered.
class EquipmentAnswer extends StatefulWidget {
  const EquipmentAnswer({
    super.key,
    required this.owned,
    required this.onPreset,
    required this.onEquipment,
  });

  /// Null until answered.
  final Set<Equipment>? owned;
  final ValueChanged<EquipmentProfile> onPreset;
  final ValueChanged<Set<Equipment>> onEquipment;

  @override
  State<EquipmentAnswer> createState() => _EquipmentAnswerState();
}

class _EquipmentAnswerState extends State<EquipmentAnswer> {
  /// The set picked; a set tuned in its sheet no longer matches a preset
  /// but stays the one picked.
  late EquipmentProfile? _picked = switch (widget.owned) {
    final owned? => EquipmentProfile.matching(owned),
    null => null,
  };

  void _pick(EquipmentProfile preset) {
    setState(() => _picked = preset);
    widget.onPreset(preset);
  }

  Future<void> _details(EquipmentProfile preset) async {
    final owned = widget.owned;
    final picked = await showEquipmentSheet(
      context,
      title: AppLocalizations.of(context).presetName(preset),
      owned: preset == _picked && owned != null ? owned : preset.equipment,
    );
    if (picked == null || !mounted) return;
    setState(() => _picked = preset);
    widget.onEquipment(picked);
  }

  Future<void> _editCustom(Set<Equipment> owned) async {
    final picked = await showEquipmentSheet(
      context,
      title: AppLocalizations.of(context).equipmentCustomTitle,
      owned: owned,
    );
    if (picked == null || !mounted) return;
    setState(() => _picked = EquipmentProfile.matching(picked));
    widget.onEquipment(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const presets = EquipmentProfile.values;
    final picked = _picked;
    final owned = widget.owned;
    final grid = ChoiceGrid.list(
      form: ChoiceListForm.stacked,
      options: [
        for (final preset in presets)
          ChoiceOption(
            label: l10n.presetName(preset),
            onInfo: () => _details(preset),
            infoLabel: l10n.equipmentPresetDetails(l10n.presetName(preset)),
          ),
      ],
      selected: picked == null ? null : presets.indexOf(picked),
      onSelected: (i) => _pick(presets[i]),
    );
    if (picked != null ||
        owned == null ||
        EquipmentProfile.matching(owned) != null) {
      return grid;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        grid,
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 12, top: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.equipmentCustom(owned.length),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              ForgeButton(
                label: l10n.equipmentCustomEdit,
                variant: ForgeButtonVariant.text,
                size: ForgeButtonSize.small,
                onPressed: () => _editCustom(owned),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The equipment as checkboxes under [title], [owned] ticked: the common
/// items and every item ticked, then More equipment, which lists every
/// item. Done closes it with the items ticked; null when closed without
/// Done.
Future<Set<Equipment>?> showEquipmentSheet(
  BuildContext context, {
  required String title,
  required Set<Equipment> owned,
}) => showForgeBottomSheet<Set<Equipment>>(
  context: context,
  builder: (_) => _EquipmentSheet(title: title, owned: owned),
);

class _EquipmentSheet extends StatefulWidget {
  const _EquipmentSheet({required this.title, required this.owned});

  final String title;
  final Set<Equipment> owned;

  /// The items listed before More equipment.
  static const common = [
    Equipment.barbell,
    Equipment.plate,
    Equipment.dumbbell,
    Equipment.bench,
    Equipment.pullUpBar,
    Equipment.cable,
    Equipment.kettlebell,
  ];

  @override
  State<_EquipmentSheet> createState() => _EquipmentSheetState();
}

class _EquipmentSheetState extends State<_EquipmentSheet> {
  late final Set<Equipment> _ticked = {...widget.owned};
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Collapsed, the common items and everything owned, in vocabulary
    // order after the common ones.
    final items = [
      ..._EquipmentSheet.common,
      for (final item in Equipment.values)
        if (item != Equipment.bodyweight &&
            !_EquipmentSheet.common.contains(item) &&
            (_all || widget.owned.contains(item)))
          item,
    ];
    return ForgeBottomSheet(
      title: widget.title,
      subtitle: l10n.equipmentSheetInfo,
      action: ForgeButton(
        label: l10n.equipmentSheetDone,
        onPressed: () => Navigator.pop(context, {
          for (final item in Equipment.values)
            if (_ticked.contains(item)) item,
        }),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, item) in items.indexed) ...[
              if (i > 0) const Divider(),
              ListRow.check(
                title: l10n.equipmentName(item),
                checked: _ticked.contains(item),
                onChanged: (checked) => setState(
                  () => checked ? _ticked.add(item) : _ticked.remove(item),
                ),
              ),
            ],
            if (items.length < Equipment.values.length - 1) ...[
              const Divider(),
              ListRow(
                title: l10n.equipmentShowAll,
                onTap: () => setState(() => _all = true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A wheel of the years [ProfileFormCubit.birthYearRange] allows.
class _BirthYearAnswer extends StatelessWidget {
  const _BirthYearAnswer(this.year);

  /// Answered as soon as the question shows.
  final int? year;

  @override
  Widget build(BuildContext context) {
    final year = this.year;
    if (year == null) return const SizedBox.shrink();
    final cubit = context.read<ProfileFormCubit>();
    final range = cubit.birthYearRange;
    return NumberPicker.wheel(
      label: AppLocalizations.of(context).profileBirthYear,
      min: range.min.toDouble(),
      max: range.max.toDouble(),
      step: 1,
      value: year.toDouble(),
      grouped: false,
      onChanged: (value) => cubit.setBirthYear(value.round()),
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
    final shown = displayRange(
      ProfileLimits.minHeightCm,
      ProfileLimits.maxHeightCm,
      unit.fromCm,
    );
    final title = l10n.fieldName(ProfileField.height);
    // The sheet starts at the whole step the ruler shows.
    final onRuler = value.roundToDouble().clamp(range.min, range.max);
    void type() => _openEntry(context, switch (unit) {
      LengthUnit.cm => (
        title: title,
        fields: [
          (
            label: l10n.calcHeight(l10n.unitCm),
            text: formatProfileNumber(onRuler),
          ),
        ],
        error: _outOfRange(l10n, shown),
        enter: (texts) => cubit.enterHeight(texts.single, unit),
      ),
      LengthUnit.inch => () {
        final (:feet, :inches) = feetAndInches(onRuler);
        return (
          title: title,
          fields: [
            (label: l10n.profileFeet, text: '$feet'),
            (label: l10n.profileInches, text: formatProfileNumber(inches)),
          ],
          error: l10n.calcOutOfRange(
            l10n.heightText(ProfileLimits.minHeightCm, unit),
            l10n.heightText(ProfileLimits.maxHeightCm, unit),
          ),
          enter: (List<String> texts) =>
              cubit.enterFeetAndInches(texts.first, texts.last),
        );
      }(),
    });
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
      picker: NumberPicker.ruler(
        key: ValueKey(unit),
        label: title,
        unit: unit == LengthUnit.cm ? l10n.unitCm : null,
        parts: unit == LengthUnit.inch
            ? (value) {
                final (:feet, :inches) = feetAndInches(value);
                return [
                  ('$feet', l10n.unitFt),
                  (formatProfileNumber(inches), l10n.unitIn),
                ];
              }
            : null,
        min: range.min,
        max: range.max,
        step: 1,
        value: value,
        onChanged: (value) => cubit.setHeight(value, unit),
        onValueTap: type,
      ),
    );
  }
}

/// [inches] as whole feet and the inches left, to the one decimal shown.
({int feet, double inches}) feetAndInches(double inches) {
  final tenths = (inches * 10).round();
  final feet = tenths ~/ 120;
  return (feet: feet, inches: (tenths - feet * 120) / 10);
}

/// The body weight or the target weight, the target's ruler marking the
/// weight [nowKg] when known ("Now 70 kg").
class _WeightAnswer extends StatelessWidget {
  const _WeightAnswer(this.field, this.kg, {this.nowKg});

  final ProfileField field;

  /// Answered as soon as the question shows.
  final double? kg;
  final double? nowKg;

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
    final title = l10n.fieldName(field);
    return _NumberAnswer(
      unitSwitch: _UnitSwitch<WeightUnit>(
        values: WeightUnit.values,
        selected: unit,
        label: l10n.weightUnitName,
        onChanged: (unit) => context.read<SettingsCubit>().update(
          settings.copyWith(weightUnit: unit),
        ),
      ),
      picker: NumberPicker.ruler(
        key: ValueKey(unit),
        label: title,
        unit: unitName,
        min: range.min,
        max: range.max,
        step: _step,
        value: value,
        marker: switch (nowKg) {
          final now? => (
            value: unit.fromKg(now),
            label: l10n.onboardingTargetWeightNow(l10n.weightText(now, unit)),
          ),
          null => null,
        },
        onChanged: (value) => target
            ? cubit.setTargetWeight(value, unit)
            : cubit.setWeight(value, unit),
        onValueTap: () => _openEntry(context, (
          title: title,
          fields: [
            (
              label: target
                  ? l10n.calcTargetWeight(unitName)
                  : l10n.calcBodyWeight(unitName),
              text: formatProfileNumber(value),
            ),
          ],
          error: _outOfRange(
            l10n,
            displayRange(
              ProfileLimits.minWeightKg,
              ProfileLimits.maxWeightKg,
              unit.fromKg,
            ),
          ),
          enter: (texts) => target
              ? cubit.enterTargetWeight(texts.single, unit)
              : cubit.enterWeight(texts.single, unit),
        )),
      ),
    );
  }
}

String _outOfRange(AppLocalizations l10n, ({double min, double max}) range) =>
    l10n.calcOutOfRange(
      formatProfileNumber(range.min),
      formatProfileNumber(range.max),
    );

/// What typing a number answer needs: its [title], one field or a pair
/// side by side, each with its label and starting text; [enter] tells
/// whether the texts were accepted, and [error] is shown when not.
typedef _Entry = ({
  String title,
  List<({String label, String text})> fields,
  String error,
  bool Function(List<String> texts) enter,
});

void _openEntry(BuildContext context, _Entry entry) =>
    showForgeBottomSheet<void>(
      context: context,
      builder: (_) => _EntrySheet(entry),
    );

/// The unit switch, narrow and centred, over the [picker] and the hint
/// that its value can be typed.
class _NumberAnswer extends StatelessWidget {
  const _NumberAnswer({required this.unitSwitch, required this.picker});

  final Widget unitSwitch;
  final Widget picker;

  static const _switchWidth = 180.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.md,
      children: [
        Center(
          child: SizedBox(width: _switchWidth, child: unitSwitch),
        ),
        picker,
        Text(
          l10n.profileRulerHint,
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
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
  Widget build(BuildContext context) => ForgeSegmentedControl<T>(
    segments: [
      for (final value in values)
        ForgeSegment(value: value, label: label(value)),
    ],
    selected: selected,
    onChanged: onChanged,
  );
}

/// Types a number answer in a sheet titled with its field; closes once it
/// is accepted.
class _EntrySheet extends StatefulWidget {
  const _EntrySheet(this.entry);

  final _Entry entry;

  @override
  State<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends State<_EntrySheet> {
  late final _controllers = [
    for (final field in widget.entry.fields)
      TextEditingController(text: field.text),
  ];
  String? _error;

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (widget.entry.enter([
      for (final controller in _controllers) controller.text,
    ])) {
      Navigator.of(context).pop();
    } else {
      setState(() => _error = widget.entry.error);
    }
  }

  static const _keyboard = TextInputType.numberWithOptions(decimal: true);

  // Plain numbers only; the length fits every valid answer.
  static final _formatters = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
    LengthLimitingTextInputFormatter(6),
  ];

  /// Two fields side by side; when the entry is refused both take the
  /// danger border and one message sits under the pair.
  Widget _pair(List<({String label, String text})> fields) {
    final error = _error;
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.sm,
      children: [
        for (final (i, field) in fields.indexed)
          Expanded(
            child: ForgeTextField(
              label: field.label,
              controller: _controllers[i],
              autofocus: i == 0,
              keyboardType: _keyboard,
              inputFormatters: _formatters,
              textInputAction: i == fields.length - 1
                  ? TextInputAction.done
                  : TextInputAction.next,
              onSubmitted: i == fields.length - 1 ? (_) => _submit() : null,
              // The danger border alone; the message is the pair's.
              errorText: error == null ? null : '',
            ),
          ),
      ],
    );
    if (error == null) return row;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        row,
        Text(
          error,
          style: Theme.of(context).textTheme.labelMedium!.copyWith(
            color: ForgeStyle.of(context).colors.danger,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fields = widget.entry.fields;
    return ForgeBottomSheet(
      title: widget.entry.title,
      action: ForgeButton(label: l10n.save, onPressed: _submit),
      child: fields.length == 1
          ? ForgeTextField(
              label: fields.single.label,
              controller: _controllers.single,
              autofocus: true,
              keyboardType: _keyboard,
              inputFormatters: _formatters,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              errorText: _error,
            )
          : _pair(fields),
    );
  }
}
