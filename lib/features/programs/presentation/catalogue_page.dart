import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/widgets/program_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../profile/presentation/profile_questions.dart';
import '../domain/catalogue_program.dart';
import '../domain/program.dart';
import 'catalogue_text.dart';
import 'program_catalogue_cubit.dart';
import 'program_list_cubit.dart';

/// The ready-made programs: a search by name, the filters as one sideways
/// line of chips, then while neither filters nor a search are on the
/// user's active program when it is a copy of one (which opens the copy),
/// the best match and the count; then every program as a list row.
class CataloguePage extends StatelessWidget {
  const CataloguePage({super.key});

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: sl<ProgramCatalogueCubit>()),
      BlocProvider.value(value: sl<ProgramListCubit>()),
    ],
    child: const _CatalogueView(),
  );
}

/// The user's active program when it is a copy of a ready-made one.
typedef _ActiveCopy = ({
  String id,
  String sourceId,
  int? week,
  int? weeks,
  bool finished,
});

_ActiveCopy? _activeCopyOf(ProgramListState list) {
  final program = list.activeProgram;
  if (program == null || program.origin != ProgramOrigin.catalog) return null;
  final (id, sourceId) = (program.id, program.sourceId);
  if (id == null || sourceId == null) return null;
  return (
    id: id,
    sourceId: sourceId,
    week: list.week,
    weeks: program.lengthWeeks,
    finished: list.finished,
  );
}

class _CatalogueView extends StatefulWidget {
  const _CatalogueView();

  @override
  State<_CatalogueView> createState() => _CatalogueViewState();
}

class _CatalogueViewState extends State<_CatalogueView> {
  late final _cubit = context.read<ProgramCatalogueCubit>();
  late final _search = TextEditingController(text: _cubit.state.query);

  @override
  void dispose() {
    // The search belongs to this visit of the page.
    _cubit.search('');
    _search.dispose();
    super.dispose();
  }

  void _clearSearch() {
    _search.clear();
    _cubit.search('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.catalogueTitle),
      body: BlocBuilder<ProgramCatalogueCubit, ProgramCatalogueState>(
        builder: (context, state) => ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: [
            ForgeSearchField(
              hint: l10n.catalogueSearchHint,
              clearLabel: l10n.catalogueClearSearch,
              controller: _search,
              onChanged: _cubit.search,
            ),
            const SizedBox(height: Gap.sm),
            ...switch (state.status) {
              ProgramCatalogueStatus.loading => [
                _FilterChips(state),
                const SizedBox(height: Gap.sm),
                const LoadingView(),
              ],
              ProgramCatalogueStatus.offline => [
                ErrorView(
                  title: l10n.catalogueOfflineTitle,
                  message: l10n.catalogueOfflineDetail,
                  retryLabel: l10n.retry,
                  onRetry: _cubit.retry,
                ),
              ],
              ProgramCatalogueStatus.failure => [
                ErrorView(
                  title: l10n.catalogueLoadFailedTitle,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: _cubit.retry,
                ),
              ],
              ProgramCatalogueStatus.ready => _programs(context, state),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _programs(BuildContext context, ProgramCatalogueState state) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final plain = !state.filtering && !state.searching;
    final active = context.select(
      (ProgramListCubit cubit) => _activeCopyOf(cubit.state),
    );
    final copy = plain ? active : null;
    final source = copy == null ? null : state.program(copy.sourceId);
    final shown = [
      for (final program in state.shown(language))
        if (program != source) program,
    ];
    final best = plain ? state.recommended.firstOrNull : null;
    final free = state.programs.where((program) => !program.premium).length;
    return [
      _FilterChips(state),
      if (state.filtering)
        Padding(
          padding: const EdgeInsets.only(left: Gap.xs, top: Gap.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.catalogueFiltersOn(state.filterCount),
                  style: Theme.of(context).textTheme.bodyMedium!
                      .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
                ),
              ),
              ForgeButton(
                label: l10n.catalogueClearFilters,
                variant: ForgeButtonVariant.text,
                size: ForgeButtonSize.small,
                onPressed: _cubit.clearFilters,
              ),
            ],
          ),
        ),
      const SizedBox(height: Gap.sm),
      if (copy != null && source != null) ...[
        SectionLabel(l10n.catalogueActiveProgram),
        ListRowCard(
          children: [
            _row(
              context,
              state,
              source,
              facts: copy.finished
                  ? l10n.programFinished
                  : switch ((copy.week, copy.weeks)) {
                      (final week?, final weeks?) => l10n.programWeekOf(
                        week,
                        weeks,
                      ),
                      (final week?, null) => l10n.programWeekNumber(week),
                      _ => null,
                    },
              copyId: copy.id,
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
      ],
      if (best != null) ...[
        ListRowCard(
          children: [
            _row(
              context,
              state,
              best.program,
              recommended: true,
              match: best.reasons.isEmpty ? null : l10n.matchText(best.reasons),
            ),
          ],
        ),
        const SizedBox(height: Gap.sm),
      ],
      if (plain)
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.xs, 0, Gap.xs, Gap.sm),
          child: Text(
            state.premium == true
                ? l10n.catalogueCount(state.programs.length)
                : l10n.catalogueCountFree(state.programs.length, free),
            style: Theme.of(context).textTheme.bodySmall!
                .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
          ),
        ),
      if (source != null) SectionLabel(l10n.catalogueAllPrograms),
      if (shown.isEmpty)
        EmptyView(
          icon: ForgeIcons.search,
          title: l10n.catalogueNoMatch,
          message: state.searching
              ? l10n.catalogueNoMatchSearch
              : l10n.catalogueNoMatchDetail,
          actions: [
            if (state.searching)
              ForgeButton(
                label: l10n.catalogueClearSearch,
                variant: ForgeButtonVariant.secondary,
                onPressed: _clearSearch,
              ),
            if (state.filtering)
              ForgeButton(
                label: l10n.catalogueClearAllFilters,
                variant: ForgeButtonVariant.secondary,
                onPressed: _cubit.clearFilters,
              ),
          ],
        )
      else
        ListRowCard(
          children: [
            for (final program in shown) _row(context, state, program),
          ],
        ),
    ];
  }

  /// A program's row; with a [copyId] the user's active copy of it, whose
  /// row says how far it has run ([facts]) and opens the copy.
  Widget _row(
    BuildContext context,
    ProgramCatalogueState state,
    CatalogueProgram program, {
    bool recommended = false,
    String? match,
    String? facts,
    String? copyId,
  }) {
    final l10n = AppLocalizations.of(context);
    final language = Localizations.localeOf(context).languageCode;
    return ProgramCard.row(
      name: program.text(language).name,
      facts: copyId == null
          ? l10n.catalogueRowFacts(program)
          : facts == null
          ? l10n.catalogueOpensCopy
          : l10n.catalogueActiveCopy(facts),
      fits: state.profile.suits(program),
      locked: program.premium && state.premium == false,
      recommended: recommended,
      match: match,
      onTap: () => context.go(
        copyId == null
            ? Routes.catalogueProgram(program.id)
            : Routes.program(copyId),
      ),
    );
  }
}

/// The filters as one sideways line: Only my equipment, then for Level,
/// Days per week, Goal and Equipment each chosen value, removable, or the
/// filter's name with ▾ while none is chosen, which opens the sheet.
class _FilterChips extends StatelessWidget {
  const _FilterChips(this.state);

  final ProgramCatalogueState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ProgramCatalogueCubit>();
    final filter = state.filter;
    final equipmentKnown = state.profile.equipment != null;
    void open() => showCatalogueFilters(context);
    List<Widget> chips<T>({
      required String name,
      required List<T> chosen,
      required String Function(T value) labelOf,
      required ValueChanged<T> onRemove,
    }) => chosen.isEmpty
        ? [ForgeChip.menu(label: name, onPressed: open)]
        : [
            for (final value in chosen)
              ForgeChip.removable(
                label: labelOf(value),
                removeHint: l10n.catalogueRemoveFilter,
                onRemoved: () => onRemove(value),
              ),
          ];
    final all = [
      // Unknown equipment fits nothing yet; the sheet says why.
      ForgeChip(
        label: l10n.catalogueFitsMyEquipment,
        selected: filter.fitsMyEquipment && equipmentKnown,
        showCheck: false,
        onPressed: equipmentKnown
            ? () => cubit.setFitsMyEquipment(!filter.fitsMyEquipment)
            : open,
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
    // The line runs to the screen's edge.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(spacing: 6, children: all),
    );
  }
}

/// The filters sheet: Only my equipment, then Level, Days per week, Goal
/// and Equipment as chips; Clear and Done.
Future<void> showCatalogueFilters(BuildContext context) {
  final cubit = context.read<ProgramCatalogueCubit>();
  return showForgeBottomSheet<void>(
    context: context,
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const _FilterSheet()),
  );
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocBuilder<ProgramCatalogueCubit, ProgramCatalogueState>(
      builder: (context, state) {
        final cubit = context.read<ProgramCatalogueCubit>();
        final filter = state.filter;
        final equipmentKnown = state.profile.equipment != null;
        return ForgeBottomSheet(
          title: l10n.catalogueFilters,
          headerAction: ForgeButton(
            label: l10n.catalogueClearFilters,
            variant: ForgeButtonVariant.text,
            size: ForgeButtonSize.small,
            onPressed: state.filtering ? cubit.clearFilters : null,
          ),
          action: ForgeButton(
            label: l10n.catalogueFiltersDone,
            onPressed: () => Navigator.pop(context),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                ListRowCard(
                  children: [
                    ListRow(
                      title: l10n.catalogueFitsMyEquipment,
                      detail: equipmentKnown
                          ? null
                          : l10n.catalogueSetEquipmentFirst,
                      disabled: !equipmentKnown,
                      trailing: ForgeSwitch(
                        value: filter.fitsMyEquipment && equipmentKnown,
                        onChanged: equipmentKnown
                            ? cubit.setFitsMyEquipment
                            : null,
                      ),
                    ),
                  ],
                ),
                _SheetChips(
                  title: l10n.catalogueFilterLevel,
                  values: Level.values,
                  selected: filter.levels,
                  labelOf: l10n.levelName,
                  onToggle: cubit.toggleLevel,
                ),
                _SheetChips(
                  title: l10n.catalogueFilterDays,
                  values: state.dayOptions,
                  selected: filter.daysPerWeek,
                  labelOf: l10n.programDayCount,
                  onToggle: cubit.toggleDays,
                ),
                _SheetChips(
                  title: l10n.catalogueFilterGoal,
                  values: Goal.values,
                  selected: filter.goals,
                  labelOf: l10n.goalName,
                  onToggle: cubit.toggleGoal,
                ),
                _SheetChips(
                  title: l10n.catalogueFilterEquipment,
                  values: EquipmentProfile.values,
                  selected: filter.profiles,
                  labelOf: l10n.presetName,
                  onToggle: cubit.toggleProfile,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A filter of the sheet: its name in muted text over its values as
/// chips, any number chosen.
class _SheetChips<T> extends StatelessWidget {
  const _SheetChips({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
  });

  final String title;
  final List<T> values;
  final Set<T> selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Gap.sm,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.bodySmall!
            .copyWith(color: ForgeStyle.of(context).colors.inkMuted),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final value in values)
            ForgeChip(
              label: labelOf(value),
              selected: selected.contains(value),
              showCheck: false,
              onPressed: () => onToggle(value),
            ),
        ],
      ),
    ],
  );
}
