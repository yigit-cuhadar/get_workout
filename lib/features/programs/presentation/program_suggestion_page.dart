import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/catalogue_program.dart';
import '../domain/catalogue_queries.dart';
import '../domain/program_schedule.dart';
import 'catalogue_detail_cubit.dart';
import 'catalogue_text.dart';
import 'program_catalogue_cubit.dart';
import 'program_text.dart';

/// After onboarding: the free ready-made program that suits the user best,
/// with why, to save among the user's programs, or the catalogue.
/// Straight to Today when there is nothing to suggest.
class ProgramSuggestionPage extends StatelessWidget {
  const ProgramSuggestionPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramCatalogueCubit>(),
    child: const _SuggestionView(),
  );
}

class _SuggestionView extends StatefulWidget {
  const _SuggestionView();

  @override
  State<_SuggestionView> createState() => _SuggestionViewState();
}

class _SuggestionViewState extends State<_SuggestionView> {
  /// Kept once shown, so later profile or catalogue changes never swap it.
  Recommendation? _suggestion;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _decide(context.read<ProgramCatalogueCubit>().state),
    );
  }

  void _decide(ProgramCatalogueState state) {
    if (!mounted || _suggestion != null || _left) return;
    switch (state.status) {
      case ProgramCatalogueStatus.loading:
        return;
      case ProgramCatalogueStatus.offline || ProgramCatalogueStatus.failure:
        return _leave();
      case ProgramCatalogueStatus.ready:
    }
    // Recommendations would not yet be judged by the equipment.
    if (state.programs.isNotEmpty && state.profile.equipment == null) return;
    final free = state.recommended.where((r) => !r.program.premium).firstOrNull;
    if (free == null) return _leave();
    setState(() => _suggestion = free);
  }

  void _leave() {
    _left = true;
    context.go(Routes.today);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final suggestion = _suggestion;
    return BlocListener<ProgramCatalogueCubit, ProgramCatalogueState>(
      listener: (context, state) => _decide(state),
      child: suggestion == null
          ? _Layout(
              title: const SkeletonBar(widthFactor: 0.6, height: 22),
              card: FeaturedCard.loading(eyebrow: l10n.suggestionEyebrow),
              start: ForgeButton(
                label: l10n.catalogueStart,
                onPressed: null,
                size: ForgeButtonSize.large,
              ),
            )
          : BlocProvider(
              create: (_) => sl<CatalogueDetailCubit>(
                param1: suggestion.program.id,
                param2: Localizations.localeOf(context).languageCode,
              ),
              child: _Suggestion(suggestion),
            ),
    );
  }
}

/// The page around what it suggests: the [title], the [card] and [why],
/// with [start] and See other programs fixed at the bottom.
class _Layout extends StatelessWidget {
  const _Layout({
    required this.title,
    required this.card,
    this.why,
    required this.start,
  });

  final Widget title;
  final Widget card;
  final Widget? why;
  final Widget start;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, 40, Gap.md, Gap.md),
          children: [
            title,
            const SizedBox(height: 10),
            card,
            if (why case final why?) ...[const SizedBox(height: 10), why],
          ],
        ),
      ),
      // In the bar, so a snackbar shows above it rather than over it.
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(top: BorderSide(color: colors.line)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, 12, Gap.md, Gap.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Gap.sm,
              children: [
                start,
                ForgeButton(
                  label: l10n.suggestionSeeOthers,
                  onPressed: () => context.go(Routes.catalogue),
                  variant: ForgeButtonVariant.text,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The suggested program, why, and Start this program.
class _Suggestion extends StatelessWidget {
  const _Suggestion(this.suggestion);

  final Recommendation suggestion;

  /// Saves a copy among the user's programs without starting it; the
  /// program page it opens starts it.
  void _start(BuildContext context) {
    final cubit = context.read<CatalogueDetailCubit>();
    // The user's copy opens rather than another one.
    if (cubit.existingCopyId case final id?) {
      return context.go(Routes.program(id));
    }
    cubit.copy(CopyIntent.keep);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final program = suggestion.program;
    final language = Localizations.localeOf(context).languageCode;
    final profile = context.select(
      (ProgramCatalogueCubit cubit) => cubit.state.profile,
    );
    return BlocConsumer<CatalogueDetailCubit, CatalogueDetailState>(
      listenWhen: (previous, current) =>
          previous.copyStatus != current.copyStatus,
      listener: (context, state) {
        final cubit = context.read<CatalogueDetailCubit>();
        switch (state.copyStatus) {
          case CopyStatus.copied:
            cubit.copyHandled();
            context.go(Routes.program(state.copyId!, created: true));
          case CopyStatus.failed:
            cubit.copyHandled();
            showForgeSnackbar(
              context,
              message: state.copyFailure is NetworkFailure
                  ? l10n.errorNetwork
                  : l10n.catalogueCopyFailed,
              error: true,
            );
          case CopyStatus.startFailed:
            cubit.copyHandled();
            showForgeSnackbar(
              context,
              message: l10n.catalogueStartFailed,
              error: true,
            );
          case CopyStatus.idle || CopyStatus.copying:
        }
      },
      builder: (context, state) {
        final ready =
            state.status == CatalogueDetailStatus.ready &&
            state.useStatus == UseStatus.ready;
        return _Layout(
          title: Text(
            l10n.suggestionTitle,
            style: text.headlineMedium!.copyWith(
              fontSize: 26,
              letterSpacing: -0.52,
            ),
          ),
          card: FeaturedCard(
            form: FeaturedCardForm.outline,
            eyebrow: l10n.suggestionEyebrow,
            title: program.text(language).name,
            line: FeaturedLine(
              l10n.catalogueRowFacts(program),
              data: switch (program.minutes) {
                null => null,
                final minutes when minutes.min == minutes.max =>
                  l10n.programEstimate(minutes.min),
                final minutes => l10n.catalogueMinutesSpan(
                  minutes.min,
                  minutes.max,
                ),
              },
            ),
            rows: _dayRows(l10n, program, state),
          ),
          why: SectionCard.plain(
            title: l10n.suggestionWhy,
            child: Text(
              l10n.suggestionReason(
                profile,
                suggestion.reasons,
                program.text(language).summary,
              ),
              style: text.bodyMedium,
            ),
          ),
          start: ForgeButton(
            label: l10n.catalogueStart,
            size: ForgeButtonSize.large,
            loading:
                state.copyStatus == CopyStatus.copying ||
                (state.status == CatalogueDetailStatus.ready &&
                    state.useStatus == UseStatus.waiting),
            onPressed: ready ? () => _start(context) : null,
          ),
        );
      },
    );
  }

  /// Each day on the weekday it starts on, its name and exercise count:
  /// from the days once read, else from the card's list.
  List<Widget> _dayRows(
    AppLocalizations l10n,
    CatalogueProgram program,
    CatalogueDetailState state,
  ) {
    final days = state.status == CatalogueDetailStatus.ready
        ? [
            for (final (index, day) in state.days.indexed)
              (l10n.dayName(day, index), day.items.length),
          ]
        : [
            for (final (index, day) in (program.dayList ?? []).indexed)
              (
                day.name.trim().isEmpty
                    ? l10n.programDayDefault(index + 1)
                    : day.name.trim(),
                day.exercises,
              ),
          ];
    final weekdays = ProgramSchedule.suggestedWeekdays(days.length);
    return [
      for (final (index, (name, exercises)) in days.indexed)
        ListRow(
          leading: ForgeTag(l10n.weekdayShort(weekdays[index])),
          title: '$name · ${l10n.programExerciseCount(exercises)}',
        ),
    ];
  }
}
