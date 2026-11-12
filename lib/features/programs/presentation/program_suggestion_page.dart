import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/catalogue_queries.dart';
import 'catalogue_detail_cubit.dart';
import 'catalogue_page.dart';
import 'program_catalogue_cubit.dart';

/// After onboarding: the free ready-made program that suits the user best,
/// to use at once, or the catalogue, or Today. Straight to Today when there
/// is nothing to suggest.
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
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.suggestionTitle)),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: Gap.md),
          children: [
            if (suggestion == null)
              const Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: LoadingView(),
              )
            else
              _Suggestion(suggestion),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextButton(
                    onPressed: () => context.go(Routes.catalogue),
                    child: Text(l10n.catalogueBrowse),
                  ),
                  TextButton(
                    onPressed: _leave,
                    child: Text(l10n.suggestionNotNow),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The suggested program and its "Use this program".
class _Suggestion extends StatelessWidget {
  const _Suggestion(this.suggestion);

  final Recommendation suggestion;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return BlocProvider(
      create: (_) => sl<CatalogueDetailCubit>(
        param1: suggestion.program.id,
        param2: language,
      ),
      child: BlocConsumer<CatalogueDetailCubit, CatalogueDetailState>(
        listenWhen: (previous, current) =>
            previous.copyStatus != current.copyStatus,
        listener: (context, state) {
          final cubit = context.read<CatalogueDetailCubit>();
          switch (state.copyStatus) {
            case CopyStatus.copied:
              cubit.copyHandled();
              context.go(Routes.program(state.copyId!, created: true));
            case CopyStatus.alreadyCopied:
              cubit.copyHandled();
              context.go(Routes.program(state.copyId!));
            case CopyStatus.failed:
              cubit.copyHandled();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    state.copyFailure is NetworkFailure
                        ? l10n.errorNetwork
                        : l10n.catalogueCopyFailed,
                  ),
                ),
              );
            case CopyStatus.idle || CopyStatus.copying:
          }
        },
        builder: (context, state) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Text(l10n.suggestionBody),
            ),
            CatalogueProgramTile(
              suggestion.program,
              premium: false,
              reasons: suggestion.reasons,
            ),
            if (state.status == CatalogueDetailStatus.ready &&
                state.useStatus != UseStatus.exercisesMissing &&
                state.useStatus != UseStatus.exercisesFailed)
              Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: ForgeButton(
                  label: l10n.catalogueUse,
                  loading:
                      state.useStatus == UseStatus.waiting ||
                      state.copyStatus == CopyStatus.copying,
                  onPressed: context.read<CatalogueDetailCubit>().use,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
