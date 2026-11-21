import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../analytics/domain/analytics.dart';
import '../domain/catalogue_program.dart';
import '../domain/catalogue_queries.dart';
import '../domain/program_schedule.dart';
import 'catalogue_detail_cubit.dart';
import 'catalogue_text.dart';
import 'premium_prompt.dart';
import 'program_catalogue_cubit.dart';
import 'program_text.dart';

/// After onboarding: the ready-made program that suits the user best, with
/// why, to save among the user's programs, or the catalogue. A premium one
/// a user without Premium starts through the paywall, and is saved once
/// subscribed; closing the paywall passes the suggestion. Straight to
/// Today when there is nothing to suggest. Whichever way it is left,
/// [beforeLeaving] runs first (the app's onboarding paywall), unless the
/// user has just closed the paywall.
class ProgramSuggestionPage extends StatelessWidget {
  const ProgramSuggestionPage({super.key, required this.beforeLeaving});

  final Future<void> Function(BuildContext context) beforeLeaving;

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramCatalogueCubit>(),
    child: RepositoryProvider.value(
      value: _Leave(beforeLeaving),
      child: _SuggestionView(sl<PremiumPrompt>()),
    ),
  );
}

/// Goes on from the suggestion once [_beforeLeaving] is done, which
/// completes onboarding: with the suggested [programId] when it was saved.
class _Leave {
  const _Leave(this._beforeLeaving);

  final Future<void> Function(BuildContext context) _beforeLeaving;

  /// Without [paywall], [_beforeLeaving] is skipped: the user has just
  /// closed the paywall.
  static Future<void> to(
    BuildContext context,
    String location, {
    String? programId,
    bool paywall = true,
  }) async {
    unawaited(
      context.read<Analytics>().onboardingComplete(programId: programId),
    );
    if (paywall) await context.read<_Leave>()._beforeLeaving(context);
    if (context.mounted) context.go(location);
  }
}

class _SuggestionView extends StatefulWidget {
  const _SuggestionView(this.premium);

  final PremiumPrompt premium;

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
    final best = state.recommended.firstOrNull;
    if (best == null) return _leave();
    setState(() => _suggestion = best);
    unawaited(context.read<Analytics>().onboardingStep(OnboardingStep.program));
  }

  void _leave() {
    _left = true;
    unawaited(_Leave.to(context, Routes.today));
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
              card: FeaturedCard.loading(eyebrow: l10n.catalogueRecommended),
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
              child: _Suggestion(suggestion, widget.premium),
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
                  onPressed: () =>
                      unawaited(_Leave.to(context, Routes.catalogue)),
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
class _Suggestion extends StatefulWidget {
  const _Suggestion(this.suggestion, this.premium);

  final Recommendation suggestion;
  final PremiumPrompt premium;

  @override
  State<_Suggestion> createState() => _SuggestionState();
}

class _SuggestionState extends State<_Suggestion> {
  /// Premium was bought from Start: it saves once the program unlocks.
  bool _startWhenReady = false;

  Recommendation get suggestion => widget.suggestion;

  /// The paywall for a locked program: subscribed, it saves once it
  /// unlocks; closed, the suggestion is passed.
  Future<void> _unlock() async {
    final unlocked = await widget.premium.show(context);
    if (!mounted) return;
    if (!unlocked) return _Leave.to(context, Routes.today, paywall: false);
    setState(() => _startWhenReady = true);
    _startIfReady(context.read<CatalogueDetailCubit>().state);
  }

  void _startIfReady(CatalogueDetailState state) {
    if (!_startWhenReady || !_ready(state)) return;
    setState(() => _startWhenReady = false);
    _start(context);
  }

  static bool _ready(CatalogueDetailState state) =>
      state.status == CatalogueDetailStatus.ready &&
      state.useStatus == UseStatus.ready &&
      state.copyStatus == CopyStatus.idle;

  /// Saves a copy among the user's programs without starting it; the
  /// program page it opens starts it.
  void _start(BuildContext context) {
    final cubit = context.read<CatalogueDetailCubit>();
    // The user's copy opens rather than another one.
    if (cubit.existingCopyId case final id?) {
      return unawaited(
        _Leave.to(
          context,
          Routes.program(id, onboarding: true),
          programId: suggestion.program.id,
        ),
      );
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
          previous.copyStatus != current.copyStatus ||
          previous.status != current.status ||
          previous.useStatus != current.useStatus,
      listener: (context, state) {
        _startIfReady(state);
        final cubit = context.read<CatalogueDetailCubit>();
        switch (state.copyStatus) {
          case CopyStatus.copied:
            cubit.copyHandled();
            unawaited(
              _Leave.to(
                context,
                Routes.program(state.copyId!, created: true, onboarding: true),
                programId: suggestion.program.id,
              ),
            );
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
        final locked = state.status == CatalogueDetailStatus.locked;
        return _Layout(
          title: Text(
            l10n.suggestionTitle,
            style: ForgeStyle.of(context).heading,
          ),
          card: FeaturedCard(
            form: FeaturedCardForm.outline,
            eyebrow: program.premium
                ? l10n.catalogueRecommended
                : l10n.suggestionEyebrow,
            title: program.text(language).name,
            premiumTag: locked ? l10n.cataloguePremium : null,
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
                _startWhenReady ||
                state.copyStatus == CopyStatus.copying ||
                (state.status == CatalogueDetailStatus.ready &&
                    state.useStatus == UseStatus.waiting),
            onPressed: locked
                ? () => unawaited(_unlock())
                : ready
                ? () => _start(context)
                : null,
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
