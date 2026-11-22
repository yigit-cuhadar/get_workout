import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/onboarding_question.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/body_model_cubit.dart';
import '../../exercises/presentation/equipment_cubit.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../profile/presentation/profile_questions.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/generator_answers.dart';
import 'area_picker.dart';
import 'generator_questions_cubit.dart';
import 'generator_text.dart';

/// The generator's questions, a page at a time; the last one opens the
/// preview. Entered through `openGenerator`, which checks for premium.
/// What the profile and the equipment say prefills the first page, also
/// when they arrive after the page opened.
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

  /// How the area pages show the areas; each opens on the model.
  AreaView _areaView = AreaView.model;

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

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
    return BlocConsumer<GeneratorQuestionsCubit, GeneratorQuestionsState>(
      listenWhen: (previous, current) => previous.step != current.step,
      listener: (_, _) => setState(() => _areaView = AreaView.model),
      builder: (context, state) {
        if (state.status != OptionsStatus.ready) return _Unloaded(state.status);
        final answers = state.answers;
        final steps = state.steps;
        final step = steps.indexOf(state.step);
        // The route itself always pops (tab re-tap, back swipe, Back on the
        // first page); Back steps back through the pages.
        return OnboardingQuestion(
          step: step,
          count: steps.length,
          onBack: step == 0 ? null : cubit.back,
          body: _Page(
            key: ValueKey(state.step),
            state: state,
            areaView: _areaView,
            onAreaView: (view) => setState(() => _areaView = view),
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

/// The options are loading, or could not be loaded: no questions yet.
class _Unloaded extends StatelessWidget {
  const _Unloaded(this.status);

  final OptionsStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final retry = context.read<GeneratorQuestionsCubit>().retry;
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.generatorTitle),
      body: switch (status) {
        OptionsStatus.loading || OptionsStatus.ready => const LoadingView(),
        OptionsStatus.offline => ErrorView(
          title: l10n.offlineTitle,
          message: l10n.generatorOffline,
          retryLabel: l10n.retry,
          onRetry: retry,
        ),
        OptionsStatus.unavailable => ErrorView(
          title: l10n.generatorNotYetTitle,
          message: l10n.generatorNotYet,
          retryLabel: l10n.retry,
          onRetry: retry,
        ),
        OptionsStatus.failure => ErrorView(
          title: l10n.generatorOptionsFailed,
          message: l10n.loadFailedDetail,
          retryLabel: l10n.retry,
          onRetry: retry,
        ),
      },
    );
  }
}

/// The page on screen: its question and answer.
class _Page extends StatelessWidget {
  const _Page({
    super.key,
    required this.state,
    required this.areaView,
    required this.onAreaView,
  });

  final GeneratorQuestionsState state;
  final AreaView areaView;
  final ValueChanged<AreaView> onAreaView;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorQuestionsCubit>();
    final options = state.options!;
    final eyebrow = l10n.generatorTitle;
    final model = context.watch<BodyModelCubit>();
    OnboardingQuestionBody areas({
      required String title,
      required String info,
      required AreaPicker picker,
    }) => areaView == AreaView.model
        ? OnboardingQuestionBody.filled(
            eyebrow: eyebrow,
            title: title,
            info: info,
            answer: picker,
          )
        : OnboardingQuestionBody(
            eyebrow: eyebrow,
            title: title,
            info: info,
            answer: picker,
          );
    return switch (state.step) {
      GeneratorStep.profile => OnboardingQuestionBody(
        eyebrow: eyebrow,
        title: l10n.generatorProfileTitle,
        info: l10n.generatorProfileInfo,
        answer: _ProfileSummary(state),
      ),
      GeneratorStep.session => OnboardingQuestionBody(
        eyebrow: eyebrow,
        title: l10n.generatorQuestionSession,
        answer: OnboardingChoices(
          values: options.sessionMinutes,
          selected: state.sessionMinutes,
          title: l10n.generatorMinutes,
          onChanged: cubit.setSessionMinutes,
        ),
      ),
      GeneratorStep.focus => areas(
        title: l10n.generatorQuestionFocus,
        info: areaView == AreaView.model
            ? l10n.generatorFocusModelInfo(options.maxFocusAreas)
            : l10n.generatorFocusInfo(options.maxFocusAreas),
        picker: AreaPicker(
          view: areaView,
          onView: onAreaView,
          model: model.state,
          onRetryModel: model.load,
          picked: state.focus,
          max: options.maxFocusAreas,
          onToggle: cubit.toggleFocus,
        ),
      ),
      GeneratorStep.skip => areas(
        title: l10n.generatorQuestionSkip,
        info: areaView == AreaView.model
            ? l10n.generatorSkipModelInfo(options.maxSkipAreas)
            : l10n.generatorSkipInfo(options.maxSkipAreas),
        picker: AreaPicker.leaveOut(
          view: areaView,
          onView: onAreaView,
          model: model.state,
          onRetryModel: model.load,
          picked: state.skip,
          max: options.maxSkipAreas,
          onToggle: cubit.toggleSkip,
          focus: state.focus,
        ),
      ),
      GeneratorStep.sensitive => OnboardingQuestionBody(
        eyebrow: eyebrow,
        title: l10n.generatorQuestionSensitive,
        info: l10n.generatorSensitiveInfo,
        answer: _SensitiveAnswer(state.sensitive),
      ),
      GeneratorStep.style => OnboardingQuestionBody(
        eyebrow: eyebrow,
        title: l10n.generatorQuestionStyle,
        answer: OnboardingChoices(
          values: EquipmentStyle.values,
          selected: state.equipmentStyle,
          title: l10n.equipmentStyleName,
          subtitle: l10n.equipmentStyleInfo,
          onChanged: cubit.setEquipmentStyle,
        ),
      ),
      GeneratorStep.split => () {
        final language = Localizations.localeOf(context).languageCode;
        final splits = {
          for (final split in state.fittingSplits)
            split.id: split.text(language),
        };
        return OnboardingQuestionBody(
          eyebrow: eyebrow,
          title: l10n.generatorQuestionSplit,
          answer: OnboardingChoices<String?>(
            values: [null, ...splits.keys],
            selected: state.answers?.splitId,
            title: (id) =>
                id == null ? l10n.generatorSplitAuto : splits[id]!.name,
            subtitle: (id) => id == null ? null : splits[id]!.info,
            onChanged: cubit.setSplit,
          ),
        );
      }(),
    };
  }
}

/// Goal, level, days per week and equipment as one card, each row opening
/// its question to change it for this program.
class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary(this.state);

  final GeneratorQuestionsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = context.select((SettingsCubit c) => c.state.settings);
    final answers = UserProfile(
      goal: state.goal,
      level: state.level,
      daysPerWeek: state.daysPerWeek,
      equipment: state.equipment,
    );
    Future<void> change(ProfileField field) async {
      final cubit = context.read<GeneratorQuestionsCubit>();
      final changed = await context.push<UserProfile>(
        Routes.generatorProfileQuestion(field),
        extra: answers,
      );
      if (changed != null) cubit.changeProfile(changed);
    }

    return ListRowCard(
      children: [
        for (final field in const [
          ProfileField.goal,
          ProfileField.level,
          ProfileField.daysPerWeek,
          ProfileField.equipment,
        ])
          ListRow(
            title: field == ProfileField.daysPerWeek
                ? l10n.generatorDaysPerWeek
                : l10n.fieldName(field),
            value: l10n.answerText(answers, field, settings),
            missing: !answers.answered(field),
            trailing: ForgeButton(
              label: l10n.generatorChange,
              variant: ForgeButtonVariant.text,
              size: ForgeButtonSize.small,
              onPressed: () => change(field),
            ),
            onTap: () => change(field),
          ),
      ],
    );
  }
}

/// "No sensitive areas", selected while no area is ticked, then the areas
/// as tick boxes.
class _SensitiveAnswer extends StatelessWidget {
  const _SensitiveAnswer(this.sensitive);

  final Set<SensitiveArea> sensitive;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<GeneratorQuestionsCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListRow(
          title: l10n.generatorSensitiveNone,
          leading: RadioMark(selected: sensitive.isEmpty),
          onTap: cubit.clearSensitive,
        ),
        const Divider(),
        for (final area in SensitiveArea.values)
          ListRow(
            title: l10n.sensitiveAreaName(area),
            checked: sensitive.contains(area),
            onTap: () => cubit.toggleSensitive(area),
          ),
      ],
    );
  }
}
