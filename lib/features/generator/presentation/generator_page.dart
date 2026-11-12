import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../exercises/presentation/widgets/choice_section.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../profile/presentation/profile_questions.dart';
import '../domain/generator_answers.dart';
import '../domain/program_generator.dart';
import 'generator_questions_cubit.dart';
import 'generator_text.dart';

/// The generator's questions, one at a time; the last one opens the
/// preview. Entered through `openGenerator`, which checks for premium.
/// What the profile and the equipment say prefills the questions not
/// answered yet, also when they arrive after the page opened.
class GeneratorPage extends StatelessWidget {
  const GeneratorPage({super.key});

  static GeneratorPrefill _prefill(BuildContext context) {
    final profile = context.read<ProfileCubit>().state.profile;
    return (
      goal: profile.goal,
      level: profile.level,
      daysPerWeek: profile.daysPerWeek,
      equipment: context.read<EquipmentCubit>().state.owned,
    );
  }

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<GeneratorQuestionsCubit>(param1: _prefill(context)),
    child: MultiBlocListener(
      listeners: [
        BlocListener<ProfileCubit, ProfileState>(
          listener: (context, _) => context
              .read<GeneratorQuestionsCubit>()
              .prefill(_prefill(context)),
        ),
        BlocListener<EquipmentCubit, EquipmentState>(
          listener: (context, _) => context
              .read<GeneratorQuestionsCubit>()
              .prefill(_prefill(context)),
        ),
      ],
      child: const _QuestionsView(),
    ),
  );
}

class _QuestionsView extends StatefulWidget {
  const _QuestionsView();

  @override
  State<_QuestionsView> createState() => _QuestionsViewState();
}

class _QuestionsViewState extends State<_QuestionsView> {
  /// The preview is opening or open; a second tap opens no second one.
  bool _previewing = false;

  Future<void> _preview(GeneratorAnswers answers) async {
    if (_previewing) return;
    setState(() => _previewing = true);
    await context.push(Routes.programGeneratorPreview, extra: answers);
    if (mounted) setState(() => _previewing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cubit = context.read<GeneratorQuestionsCubit>();
    return BlocBuilder<GeneratorQuestionsCubit, GeneratorQuestionsState>(
      builder: (context, state) {
        final info = l10n.generatorQuestionInfo(state.step);
        final answers = state.answers;
        final first = state.step.index == 0;
        // The route itself always pops (tab re-tap, back swipe); the
        // buttons step back through the questions.
        return Scaffold(
          appBar: AppBar(
            leading: first ? null : BackButton(onPressed: cubit.back),
            title: Text(l10n.generatorTitle),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(Gap.xs),
              child: LinearProgressIndicator(
                value: (state.step.index + 1) / GeneratorStep.values.length,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: Gap.md),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gap.md),
                child: Text(
                  l10n.generatorQuestion(state.step),
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              if (info != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
                  child: Text(info, style: theme.textTheme.bodyMedium),
                ),
              const SizedBox(height: Gap.md),
              _Answer(state),
            ],
          ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Row(
                children: [
                  if (!first) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: cubit.back,
                        child: Text(l10n.generatorBack),
                      ),
                    ),
                    const SizedBox(width: Gap.sm),
                  ],
                  Expanded(
                    child: state.isLast
                        ? ForgeButton(
                            label: l10n.generatorCreate,
                            onPressed:
                                state.answered &&
                                    answers != null &&
                                    !_previewing
                                ? () => _preview(answers)
                                : null,
                          )
                        : ForgeButton(
                            label: l10n.generatorNext,
                            onPressed: state.answered ? cubit.next : null,
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The answer to the question on screen.
class _Answer extends StatelessWidget {
  const _Answer(this.state);

  final GeneratorQuestionsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorQuestionsCubit>();
    return switch (state.step) {
      GeneratorStep.goal => _Choice(
        values: Goal.values,
        selected: state.goal,
        title: l10n.goalName,
        onChanged: cubit.setGoal,
      ),
      GeneratorStep.level => _Choice(
        values: Level.values,
        selected: state.level,
        title: l10n.levelName,
        subtitle: l10n.levelInfo,
        onChanged: cubit.setLevel,
      ),
      GeneratorStep.days => _Choice(
        values: [
          for (
            var days = GeneratorLimits.minDays;
            days <= GeneratorLimits.maxDays;
            days++
          )
            days,
        ],
        selected: state.daysPerWeek,
        title: l10n.profileDays,
        onChanged: cubit.setDays,
      ),
      GeneratorStep.session => _Choice(
        values: GeneratorLimits.sessionMinutes,
        selected: state.sessionMinutes,
        title: l10n.generatorMinutes,
        onChanged: cubit.setSessionMinutes,
      ),
      GeneratorStep.equipment => _EquipmentAnswer(state.equipment),
      GeneratorStep.focus => ChoiceSection<Muscle>(
        title: l10n.generatorFocusCount(
          state.focus.length,
          GeneratorLimits.maxFocusMuscles,
        ),
        values: [
          for (final muscle in musclePriority)
            if (!(state.easyArea?.muscles.contains(muscle) ?? false)) muscle,
        ],
        selected: state.focus,
        labelOf: l10n.muscleName,
        onToggle: cubit.toggleFocus,
      ),
      GeneratorStep.excluded => _ExcludedAnswer(state.excluded),
      GeneratorStep.easyArea => _Choice<EasyArea?>(
        values: const [null, ...EasyArea.values],
        selected: state.easyArea,
        title: (area) =>
            area == null ? l10n.generatorAreaNone : l10n.easyAreaName(area),
        onChanged: cubit.setEasyArea,
      ),
      GeneratorStep.split => _Choice<TrainingSplit?>(
        values: const [null, ...TrainingSplit.values],
        selected: state.split,
        title: (split) =>
            split == null ? l10n.generatorSplitAuto : l10n.splitName(split),
        subtitle: (split) => split == null
            ? switch (state.answers) {
                final answers? => l10n.generatorSplitAutoInfo(
                  l10n.splitName(splitFor(answers)),
                ),
                null => null,
              }
            : state.splitFits(split)
            ? null
            : l10n.generatorIssueSplit(split.minDays),
        enabled: (split) => split == null || state.splitFits(split),
        onChanged: cubit.setSplit,
      ),
    };
  }
}

/// One answer of [values]. Null may be one of them, e.g. "none".
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.values,
    required this.selected,
    required this.title,
    required this.onChanged,
    this.subtitle,
    this.enabled,
  });

  final List<T> values;
  final T? selected;
  final String Function(T value) title;
  final String? Function(T value)? subtitle;
  final bool Function(T value)? enabled;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => RadioGroup<T>(
    groupValue: selected,
    // Nothing is toggleable, so a null value is the answer "none".
    onChanged: (value) => onChanged(value as T),
    child: Column(
      children: [
        for (final value in values)
          RadioListTile<T>(
            value: value,
            enabled: enabled?.call(value) ?? true,
            title: Text(title(value)),
            subtitle: switch (subtitle?.call(value)) {
              final text? => Text(text),
              null => null,
            },
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
    final cubit = context.read<GeneratorQuestionsCubit>();
    final owned = this.owned;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Wrap(
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

/// The exercises to leave out, and picking more from the library.
class _ExcludedAnswer extends StatelessWidget {
  const _ExcludedAnswer(this.excluded);

  /// At most this many are picked at once.
  static const _pickAtOnce = 20;

  final Set<String> excluded;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorQuestionsCubit>();
    final library = context.select(
      (ExerciseCatalogueCubit cubit) => cubit.state,
    );
    final exercises = library is CatalogueReady
        ? {for (final e in library.exercises) e.id: e}
        : const <String, Exercise>{};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final id in excluded)
          ListTile(
            title: Text(
              exercises[id]?.localized(context).name ??
                  l10n.programExerciseUnavailable,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              tooltip: l10n.generatorExcludedRemove,
              onPressed: () => cubit.include(id),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(l10n.generatorExcludedAdd),
            onPressed: () async {
              final picked = await context.push<List<Exercise>>(
                Routes.exercisePicker(max: _pickAtOnce, multiple: true),
              );
              if (picked != null) cubit.exclude(picked.map((e) => e.id));
            },
          ),
        ),
      ],
    );
  }
}
