import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/question_page.dart';
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
    final cubit = context.read<GeneratorQuestionsCubit>();
    return BlocBuilder<GeneratorQuestionsCubit, GeneratorQuestionsState>(
      builder: (context, state) {
        final answers = state.answers;
        final step = state.step.index;
        final count = GeneratorStep.values.length;
        // The route itself always pops (tab re-tap, back swipe, Back on the
        // first question); Back steps back through the questions.
        return QuestionScaffold(
          step: step,
          count: count,
          progress: l10n.questionProgress(step + 1, count),
          onBack: step == 0 ? null : cubit.back,
          body: QuestionLayout(
            key: ValueKey(state.step),
            caption: l10n.generatorTitle,
            title: l10n.generatorQuestion(state.step),
            info: l10n.generatorQuestionInfo(state.step),
            answer: _Answer(state),
          ),
          action: state.isLast
              ? ForgeButton(
                  label: l10n.generatorCreate,
                  onPressed: state.answered && answers != null && !_previewing
                      ? () => _preview(answers)
                      : null,
                )
              : ForgeButton(
                  label: l10n.generatorNext,
                  onPressed: state.answered ? cubit.next : null,
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
      GeneratorStep.goal => ChoiceAnswer(
        values: Goal.values,
        selected: state.goal,
        title: l10n.goalName,
        onChanged: cubit.setGoal,
      ),
      GeneratorStep.level => ChoiceAnswer(
        values: Level.values,
        selected: state.level,
        title: l10n.levelName,
        subtitle: l10n.levelInfo,
        onChanged: cubit.setLevel,
      ),
      GeneratorStep.days => ChoiceAnswer(
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
      GeneratorStep.session => ChoiceAnswer(
        values: GeneratorLimits.sessionMinutes,
        selected: state.sessionMinutes,
        title: l10n.generatorMinutes,
        onChanged: cubit.setSessionMinutes,
      ),
      GeneratorStep.equipment => EquipmentAnswer(
        owned: state.equipment,
        onPreset: cubit.applyPreset,
        onToggle: cubit.toggleEquipment,
      ),
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
      GeneratorStep.easyArea => ChoiceAnswer<EasyArea?>(
        values: const [null, ...EasyArea.values],
        selected: state.easyArea,
        title: (area) =>
            area == null ? l10n.generatorAreaNone : l10n.easyAreaName(area),
        onChanged: cubit.setEasyArea,
      ),
      GeneratorStep.split => ChoiceAnswer<TrainingSplit?>(
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
          padding: const EdgeInsets.only(top: Gap.md),
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
