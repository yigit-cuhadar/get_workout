import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/onboarding_question.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
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
        return OnboardingQuestion(
          step: step,
          count: count,
          onBack: step == 0 ? null : cubit.back,
          body: OnboardingQuestionBody(
            key: ValueKey(state.step),
            eyebrow: l10n.generatorTitle,
            title: l10n.generatorQuestion(state.step),
            info: l10n.generatorQuestionInfo(state.step),
            answer: _Answer(state),
          ),
          actionLabel: state.isLast ? l10n.generatorCreate : l10n.generatorNext,
          onAction: !state.answered
              ? null
              : !state.isLast
              ? cubit.next
              : answers != null && !_previewing
              ? () => _preview(answers)
              : null,
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
      GeneratorStep.goal => OnboardingChoices(
        values: ProfileQuestion.goals,
        selected: state.goal,
        title: l10n.goalName,
        subtitle: l10n.goalInfo,
        onChanged: cubit.setGoal,
      ),
      GeneratorStep.level => OnboardingChoices(
        values: Level.values,
        selected: state.level,
        title: l10n.levelName,
        subtitle: l10n.levelInfo,
        onChanged: cubit.setLevel,
      ),
      GeneratorStep.days => OnboardingChoices(
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
      GeneratorStep.session => OnboardingChoices(
        values: GeneratorLimits.sessionMinutes,
        selected: state.sessionMinutes,
        title: l10n.generatorMinutes,
        onChanged: cubit.setSessionMinutes,
      ),
      GeneratorStep.equipment => EquipmentAnswer(
        owned: state.equipment,
        onPreset: cubit.applyPreset,
        onEquipment: cubit.setEquipment,
      ),
      GeneratorStep.focus => _FocusAnswer(state),
      GeneratorStep.excluded => _ExcludedAnswer(state.excluded),
      GeneratorStep.easyArea => OnboardingChoices<EasyArea?>(
        values: const [null, ...EasyArea.values],
        selected: state.easyArea,
        title: (area) =>
            area == null ? l10n.generatorAreaNone : l10n.easyAreaName(area),
        onChanged: cubit.setEasyArea,
      ),
      GeneratorStep.split => OnboardingChoices<TrainingSplit?>(
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

/// Up to three muscles to focus on, as chips under their count.
class _FocusAnswer extends StatelessWidget {
  const _FocusAnswer(this.state);

  final GeneratorQuestionsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorQuestionsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        SectionLabel(
          l10n.generatorFocusCount(
            state.focus.length,
            GeneratorLimits.maxFocusMuscles,
          ),
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final muscle in musclePriority)
              if (!(state.easyArea?.muscles.contains(muscle) ?? false))
                ForgeChip(
                  label: l10n.muscleName(muscle),
                  selected: state.focus.contains(muscle),
                  showCheck: false,
                  onPressed: () => cubit.toggleFocus(muscle),
                ),
          ],
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
      spacing: Gap.sm,
      children: [
        if (excluded.isNotEmpty)
          ListRowCard(
            children: [
              for (final id in excluded)
                ListRow(
                  title:
                      exercises[id]?.localized(context).name ??
                      l10n.programExerciseUnavailable,
                  trailing: ForgeIconButton(
                    icon: ForgeIcons.close,
                    label: l10n.generatorExcludedRemove,
                    onPressed: () => cubit.include(id),
                  ),
                ),
            ],
          ),
        ForgeButton(
          label: l10n.generatorExcludedAdd,
          variant: ForgeButtonVariant.secondary,
          leadingIcon: ForgeIcons.add,
          onPressed: () async {
            final picked = await context.push<List<Exercise>>(
              Routes.exerciseLeaveOutPicker(_pickAtOnce),
            );
            if (picked != null) cubit.exclude(picked.map((e) => e.id));
          },
        ),
      ],
    );
  }
}
