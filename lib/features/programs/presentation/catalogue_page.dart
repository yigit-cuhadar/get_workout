import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../exercises/presentation/widgets/choice_section.dart';
import '../../profile/presentation/profile_questions.dart';
import '../domain/catalogue_program.dart';
import '../domain/catalogue_queries.dart';
import 'catalogue_text.dart';
import 'program_catalogue_cubit.dart';

/// The ready-made programs as cards: what suits the user first, then all
/// of them, with the filters as chips above.
class CataloguePage extends StatelessWidget {
  const CataloguePage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ProgramCatalogueCubit>(),
    child: const _CatalogueView(),
  );
}

class _CatalogueView extends StatelessWidget {
  const _CatalogueView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramCatalogueCubit>();
    return BlocBuilder<ProgramCatalogueCubit, ProgramCatalogueState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(l10n.catalogueTitle),
          actions: [
            if (state.status == ProgramCatalogueStatus.ready)
              IconButton(
                tooltip: l10n.catalogueFilters,
                icon: Badge(
                  isLabelVisible: state.filtering,
                  child: const Icon(Icons.filter_list),
                ),
                onPressed: () => _showFilterSheet(context),
              ),
          ],
        ),
        body: switch (state.status) {
          ProgramCatalogueStatus.loading => const LoadingView(),
          ProgramCatalogueStatus.offline => ErrorView(
            message: l10n.catalogueOffline,
            retryLabel: l10n.retry,
            onRetry: cubit.retry,
          ),
          ProgramCatalogueStatus.failure => ErrorView(
            message: l10n.catalogueLoadFailed,
            retryLabel: l10n.retry,
            onRetry: cubit.retry,
          ),
          ProgramCatalogueStatus.ready => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FilterChips(state),
              if (state.filtering) _FilterCount(state.filterCount),
              Expanded(child: _Programs(state)),
            ],
          ),
        },
      ),
    );
  }
}

/// The filters as chips: fits my equipment, then each chosen value,
/// removable, or the filter's name while none is chosen. A chip opens the
/// filters sheet.
class _FilterChips extends StatelessWidget {
  const _FilterChips(this.state);
  final ProgramCatalogueState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramCatalogueCubit>();
    final filter = state.filter;
    final equipmentKnown = state.profile.equipment != null;
    void open() => _showFilterSheet(context);
    List<Widget> chips<T>({
      required String name,
      required List<T> chosen,
      required String Function(T value) labelOf,
      required ValueChanged<T> onRemove,
    }) => chosen.isEmpty
        ? [
            ActionChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [Text(name), const Icon(Icons.arrow_drop_down)],
              ),
              onPressed: open,
            ),
          ]
        : [
            for (final value in chosen)
              InputChip(
                label: Text(labelOf(value)),
                selected: true,
                showCheckmark: false,
                onPressed: open,
                onDeleted: () => onRemove(value),
              ),
          ];
    final all = [
      // Unknown equipment fits nothing yet; the sheet says why.
      FilterChip(
        label: Text(l10n.catalogueFitsMyEquipment),
        selected: filter.fitsMyEquipment && equipmentKnown,
        onSelected: equipmentKnown ? cubit.setFitsMyEquipment : (_) => open(),
      ),
      ...chips(
        name: l10n.catalogueFilterLevel,
        chosen: [...Level.values.where(filter.levels.contains)],
        labelOf: l10n.levelName,
        onRemove: cubit.toggleLevel,
      ),
      ...chips(
        name: l10n.catalogueFilterDays,
        chosen: [...filter.daysPerWeek]..sort(),
        labelOf: l10n.programDayCount,
        onRemove: cubit.toggleDays,
      ),
      ...chips(
        name: l10n.catalogueFilterGoal,
        chosen: [...Goal.values.where(filter.goals.contains)],
        labelOf: l10n.goalName,
        onRemove: cubit.toggleGoal,
      ),
      ...chips(
        name: l10n.catalogueFilterEquipment,
        chosen: [...EquipmentProfile.values.where(filter.profiles.contains)],
        labelOf: l10n.presetName,
        onRemove: cubit.toggleProfile,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      child: Row(
        children: [
          for (final (i, chip) in all.indexed) ...[
            if (i > 0) const SizedBox(width: Gap.sm),
            chip,
          ],
        ],
      ),
    );
  }
}

/// "2 filters on" and Clear.
class _FilterCount extends StatelessWidget {
  const _FilterCount(this.count);
  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      child: Row(
        children: [
          Expanded(child: Text(l10n.catalogueFiltersOn(count))),
          TextButton(
            onPressed: context.read<ProgramCatalogueCubit>().clearFilters,
            child: Text(l10n.catalogueClearFilters),
          ),
        ],
      ),
    );
  }
}

class _Programs extends StatelessWidget {
  const _Programs(this.state);
  final ProgramCatalogueState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final visible = state.visible;
    // Recommendations would hide what the filters ask for.
    final recommended = !state.filtering
        ? state.recommended
        : const <Recommendation>[];
    Widget card(CatalogueProgram program, [List<MatchReason>? reasons]) =>
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
          child: CatalogueProgramCard(
            program,
            premium: state.premium,
            reasons: reasons,
          ),
        );
    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      children: [
        if (recommended.isNotEmpty) ...[
          _Header(l10n.catalogueRecommended),
          for (final recommendation in recommended)
            card(recommendation.program, recommendation.reasons),
          _Header(l10n.catalogueAll),
        ],
        if (visible.isEmpty)
          EmptyView(
            message: l10n.catalogueNoMatch,
            action: TextButton(
              onPressed: context.read<ProgramCatalogueCubit>().clearFilters,
              child: Text(l10n.catalogueClearFilters),
            ),
          ),
        for (final program in visible) card(program),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    title: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

/// A ready-made program's card, opening its page: its name with Free,
/// Premium or the lock when [premium] is false, its facts as tags, and why
/// it suits the user when [reasons] are given.
class CatalogueProgramCard extends StatelessWidget {
  const CatalogueProgramCard(
    this.program, {
    super.key,
    required this.premium,
    this.reasons,
  });

  final CatalogueProgram program;

  /// Whether the user has premium; null while unknown.
  final bool? premium;
  final List<MatchReason>? reasons;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final reasons = this.reasons;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.catalogueProgram(program.id)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      program.text(language).name,
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  if (!program.premium)
                    Text(
                      l10n.catalogueFree,
                      style: TextStyle(color: theme.colorScheme.primary),
                    )
                  else if (premium == false)
                    Icon(
                      Icons.lock_outline,
                      semanticLabel: l10n.catalogueLockedLabel,
                    )
                  else
                    Text(l10n.cataloguePremium),
                ],
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.xs,
                children: [
                  for (final tag in l10n.catalogueTags(program))
                    Chip(label: Text(tag)),
                ],
              ),
              if (reasons != null && reasons.isNotEmpty) ...[
                const SizedBox(height: Gap.sm),
                Text(l10n.matchText(reasons)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showFilterSheet(BuildContext context) {
  final cubit = context.read<ProgramCatalogueCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        builder: (context, scrollController) =>
            _FilterSheet(scrollController: scrollController),
      ),
    ),
  );
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<ProgramCatalogueCubit, ProgramCatalogueState>(
      builder: (context, state) {
        final cubit = context.read<ProgramCatalogueCubit>();
        final filter = state.filter;
        final equipmentKnown = state.profile.equipment != null;
        return ListView(
          controller: scrollController,
          children: [
            ListTile(
              title: Text(
                l10n.catalogueFilters,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              trailing: TextButton(
                onPressed: state.filtering ? cubit.clearFilters : null,
                child: Text(l10n.catalogueClearFilters),
              ),
            ),
            SwitchListTile(
              title: Text(l10n.catalogueFitsMyEquipment),
              subtitle: equipmentKnown
                  ? null
                  : Text(l10n.catalogueSetEquipmentFirst),
              value: filter.fitsMyEquipment && equipmentKnown,
              onChanged: equipmentKnown ? cubit.setFitsMyEquipment : null,
            ),
            ChoiceSection(
              title: l10n.catalogueFilterLevel,
              values: Level.values,
              selected: filter.levels,
              labelOf: l10n.levelName,
              onToggle: cubit.toggleLevel,
            ),
            ChoiceSection(
              title: l10n.catalogueFilterDays,
              values: state.dayOptions,
              selected: filter.daysPerWeek,
              labelOf: l10n.programDayCount,
              onToggle: cubit.toggleDays,
            ),
            ChoiceSection(
              title: l10n.catalogueFilterGoal,
              values: Goal.values,
              selected: filter.goals,
              labelOf: l10n.goalName,
              onToggle: cubit.toggleGoal,
            ),
            ChoiceSection(
              title: l10n.catalogueFilterEquipment,
              values: EquipmentProfile.values,
              selected: filter.profiles,
              labelOf: l10n.presetName,
              onToggle: cubit.toggleProfile,
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: ForgeButton(
                  label: l10n.catalogueFiltersDone,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
