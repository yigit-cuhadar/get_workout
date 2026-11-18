import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise.dart';
import '../../domain/exercise_queries.dart';
import '../../domain/vocabulary.dart';
import '../exercise_catalogue_cubit.dart';
import '../library_cubit.dart';
import '../vocabulary_labels.dart';
import 'exercise_tile.dart';
import 'filter_sheet.dart';

/// Search, filters, sort and the resulting exercises. Everything the model
/// offers is reachable here too, which makes it the screen reader's path.
///
/// Each result is an [ExerciseTile] opening its detail, or what [tileBuilder]
/// builds, e.g. to select exercises instead. While the catalogue loads or
/// failed, the search stays only with [searchWhileLoading].
class LibraryListView extends StatefulWidget {
  const LibraryListView({
    super.key,
    this.tileBuilder,
    this.focusSearch = false,
    this.searchWhileLoading = false,
    this.sectionsFor,
    this.similar,
    this.replacing,
    this.onCreate,
  });

  final Widget Function(BuildContext context, Exercise exercise)? tileBuilder;

  /// Whether the search field takes focus once the page's route is in.
  final bool focusSearch;

  final bool searchWhileLoading;

  /// While this is the only muscle filtered, the results switch between
  /// the exercises working it as a main muscle and those working it as a
  /// secondary one.
  final Muscle? sectionsFor;

  /// Listed first under "Similar", as far as the search and filters keep
  /// them, with the other results under "All exercises"; no count or sort.
  final List<Exercise>? similar;

  /// With [similar]: the id of the exercise being swapped or replaced,
  /// which is not offered as its own replacement.
  final String? replacing;

  /// With it, a search matching nothing offers to create the searched
  /// exercise; it gets the search text.
  final ValueChanged<String>? onCreate;

  @override
  State<LibraryListView> createState() => _LibraryListViewState();
}

class _LibraryListViewState extends State<LibraryListView> {
  late final _search = TextEditingController(
    text: context.read<LibraryCubit>().state.query,
  );
  final _focus = FocusNode();

  /// The route animation awaited before focusing the search.
  Animation<double>? _entering;
  var _watching = false;

  /// In the muscle's sections, whether "Also works" is shown.
  var _alsoWorks = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.focusSearch || _watching) return;
    _watching = true;
    final animation = ModalRoute.of(context)?.animation;
    // The keyboard comes up once, after any transition and Hero flight.
    if (animation == null || animation.isCompleted) {
      _focusSoon();
    } else {
      _entering = animation..addStatusListener(_onEntering);
    }
  }

  void _onEntering(AnimationStatus status) {
    if (!status.isCompleted) return;
    _entering?.removeStatusListener(_onEntering);
    _entering = null;
    _focusSoon();
  }

  /// For how many frames after the page is in the field keeps claiming
  /// focus: the route's own focus and the Hero's flight (which rebuilds
  /// the field) both land after the first request.
  static const _focusFrames = 48;
  var _framesLeft = 0;

  void _focusSoon() {
    _framesLeft = _focusFrames;
    _claimFocus();
  }

  void _claimFocus() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || _framesLeft-- <= 0) return;
    // Never from under a page pushed meanwhile.
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (_focus.context != null && !_focus.hasFocus) _focus.requestFocus();
    WidgetsBinding.instance.scheduleFrame();
    _claimFocus();
  });

  @override
  void didUpdateWidget(LibraryListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectionsFor != widget.sectionsFor) _alsoWorks = false;
  }

  @override
  void dispose() {
    _entering?.removeStatusListener(_onEntering);
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = context.read<LibraryCubit>();
    final catalogue = context.watch<ExerciseCatalogueCubit>().state;
    final ready = catalogue is CatalogueReady;
    return BlocConsumer<LibraryCubit, LibraryState>(
      // The query also changes without typing: a user change clears it.
      listenWhen: (_, current) => current.query != _search.text,
      listener: (_, state) => _search.text = state.query,
      builder: (context, state) {
        final sections = switch (state.muscleExercises) {
          final sections?
              when widget.sectionsFor != null &&
                  state.muscle == widget.sectionsFor =>
            sections,
          _ => null,
        };
        final results = switch (sections) {
          null => state.results,
          _ when _alsoWorks => sections.alsoWorks,
          _ => sections.main,
        };
        final onCreate = widget.onCreate;
        final create = onCreate == null || state.query.isEmpty
            ? null
            : () => onCreate(state.query);
        final filtered = state.results.isEmpty && !state.filter.isEmpty;
        final searched =
            state.results.isEmpty && state.filter.isEmpty && create != null;
        final noMatch = filtered || searched;
        final similar = widget.similar;
        final Widget body;
        if (catalogue is CatalogueLoading) {
          body = const _Loading();
        } else if (catalogue is CatalogueFailed) {
          body = _StateList(
            ErrorView(
              title: l10n.libraryLoadFailed,
              message: l10n.loadFailedDetail,
              retryLabel: l10n.retry,
              onRetry: context.read<ExerciseCatalogueCubit>().retry,
              card: true,
            ),
          );
        } else if (filtered) {
          body = _StateList(
            EmptyView(
              icon: ForgeIcons.tune,
              title: l10n.libraryNoResultsTitle,
              message: l10n.libraryFilteredNoResults,
              actions: [
                ForgeButton(
                  label: l10n.libraryClearFilters,
                  variant: ForgeButtonVariant.secondary,
                  onPressed: library.clearFilters,
                ),
                if (create != null) _CreateButton(create),
              ],
              card: true,
            ),
          );
        } else if (searched) {
          body = _StateList(
            EmptyView(
              icon: ForgeIcons.search,
              title: l10n.librarySearchNoResultsTitle(state.query),
              message: widget.tileBuilder == null
                  ? l10n.librarySearchNoResults
                  : l10n.pickerSearchNoResults,
              actions: [_CreateButton(create)],
              card: true,
            ),
          );
        } else if (state.results.isEmpty) {
          body = _StateList(
            EmptyView(
              title: l10n.libraryNoResultsTitle,
              message: l10n.libraryNoResults,
              card: true,
            ),
          );
        } else if (similar != null) {
          body = _SimilarFirst(
            similar: similar,
            results: [
              for (final exercise in results)
                if (exercise.id != widget.replacing) exercise,
            ],
            tile: _tile,
          );
        } else {
          body = CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [_rows(results)],
          );
        }
        if (!ready && !widget.searchWhileLoading) return body;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
              child: LibrarySearchHero(
                child: ForgeSearchField(
                  hint: l10n.librarySearch,
                  clearLabel: l10n.librarySearchClear,
                  onChanged: library.setQuery,
                  controller: _search,
                  focusNode: _focus,
                  onFilters: () => showFilterSheet(context),
                  filtersLabel: l10n.libraryFilters,
                  activeFilters: _activeCount(state.filter),
                ),
              ),
            ),
            if (ready && !state.filter.isEmpty) _ActiveFilters(state.filter),
            if (ready && sections != null && !noMatch)
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
                child: ForgeSegmentedControl<bool>(
                  segments: [
                    ForgeSegment(
                      value: false,
                      label: l10n.libraryMuscleMainCount(sections.main.length),
                    ),
                    ForgeSegment(
                      value: true,
                      label: l10n.libraryMuscleAlsoWorksCount(
                        sections.alsoWorks.length,
                      ),
                    ),
                  ],
                  selected: _alsoWorks,
                  onChanged: (alsoWorks) =>
                      setState(() => _alsoWorks = alsoWorks),
                ),
              ),
            if (ready && !noMatch && similar == null)
              _CountAndSort(count: results.length, sort: state.sort),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _rows(List<Exercise> exercises) => SliverPadding(
    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
    sliver: ListRowCard.sliver(
      itemCount: exercises.length,
      itemBuilder: (context, index) => _tile(context, exercises[index]),
    ),
  );

  Widget _tile(BuildContext context, Exercise exercise) =>
      widget.tileBuilder?.call(context, exercise) ??
      ExerciseTile(exercise, showFavorite: true);

  /// One per removable chip.
  static int _activeCount(LibraryFilter filter) =>
      (filter.onlyFavorites ? 1 : 0) +
      (filter.onlyDoable ? 1 : 0) +
      filter.muscles.length +
      filter.equipment.length +
      filter.levels.length +
      filter.movementPatterns.length;
}

/// The result count, then the sort as a small text button opening a menu
/// with the current sort ticked.
class _CountAndSort extends StatelessWidget {
  const _CountAndSort({required this.count, required this.sort});

  final int count;
  final ExerciseSort sort;

  static String _label(AppLocalizations l10n, ExerciseSort sort) =>
      switch (sort) {
        ExerciseSort.popularity => l10n.librarySortPopularity,
        ExerciseSort.alphabetical => l10n.librarySortAlphabetical,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = context.read<LibraryCubit>();
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.sm, Gap.xs),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                l10n.libraryResultCount(count),
                style: text.bodyMedium!.copyWith(
                  color: ForgeStyle.of(context).colors.inkMuted,
                ),
              ),
            ),
          ),
          Builder(
            builder: (context) => Semantics(
              hint: l10n.librarySort,
              child: ForgeButton(
                label: _label(l10n, sort),
                variant: ForgeButtonVariant.text,
                size: ForgeButtonSize.small,
                trailingIcon: ForgeIcons.expandMore,
                onPressed: () => showForgeMenu(
                  context: context,
                  items: [
                    for (final option in ExerciseSort.values)
                      ForgeMenuItem(
                        label: _label(l10n, option),
                        icon: switch (option) {
                          ExerciseSort.popularity => ForgeIcons.trendingUp,
                          ExerciseSort.alphabetical => ForgeIcons.list,
                        },
                        selected: option == sort,
                        onTap: () => library.setSort(option),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The swap and replace forms' list: [similar] as far as the search and
/// filters keep them, then the other [results]; each part with its label
/// only while it has rows.
class _SimilarFirst extends StatelessWidget {
  const _SimilarFirst({
    required this.similar,
    required this.results,
    required this.tile,
  });

  final List<Exercise> similar;
  final List<Exercise> results;
  final Widget Function(BuildContext context, Exercise exercise) tile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final found = {for (final exercise in results) exercise.id};
    final first = [
      for (final exercise in similar)
        if (found.contains(exercise.id)) exercise,
    ];
    final firstIds = {for (final exercise in first) exercise.id};
    final rest = [
      for (final exercise in results)
        if (!firstIds.contains(exercise.id)) exercise,
    ];
    List<Widget> part(String label, List<Exercise> exercises) => [
      if (exercises.isNotEmpty) ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          sliver: SliverToBoxAdapter(child: SectionLabel(label)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
          sliver: ListRowCard.sliver(
            itemCount: exercises.length,
            itemBuilder: (context, index) => tile(context, exercises[index]),
          ),
        ),
      ],
    ];
    return CustomScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        ...part(l10n.pickerSimilar, first),
        ...part(l10n.pickerAllExercises, rest),
      ],
    );
  }
}

/// The rows' shimmering stand-ins while the catalogue loads.
class _Loading extends StatelessWidget {
  const _Loading();

  static const _rows = 7;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
    child: ListRowCard(
      children: [for (var i = 0; i < _rows; i++) ListRow.loading(index: i)],
    ),
  );
}

/// An empty or error state on its card under the search.
class _StateList extends StatelessWidget {
  const _StateList(this.view);

  final Widget view;

  @override
  Widget build(BuildContext context) => ListView(
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
    children: [Semantics(liveRegion: true, child: view)],
  );
}

/// Creates the searched exercise as the user's own.
class _CreateButton extends StatelessWidget {
  const _CreateButton(this.onPressed);

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ForgeButton(
    label: AppLocalizations.of(context).libraryCreateCustom,
    variant: ForgeButtonVariant.secondary,
    onPressed: onPressed,
  );
}

/// The search field flying between the Exercises tab's tap-only pill and
/// the list page. In flight it is drawn as the pill; the page's field takes
/// focus only once its route is in.
class LibrarySearchHero extends StatelessWidget {
  const LibrarySearchHero({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(
    tag: LibrarySearchHero,
    flightShuttleBuilder: (context, _, _, _, _) => ForgeSearchField.tapOnly(
      hint: AppLocalizations.of(context).librarySearch,
      onTap: () {},
    ),
    child: child,
  );
}

/// One removable chip per active filter value, then "Clear all" under them.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters(this.filter);

  final LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = context.read<LibraryCubit>();
    Widget chip(String label, VoidCallback onRemoved) => ForgeChip.removable(
      label: label,
      onRemoved: onRemoved,
      removeHint: l10n.libraryFilterRemoveHint,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Gap.xs,
        children: [
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              if (filter.onlyFavorites)
                chip(
                  l10n.libraryOnlyFavorites,
                  () => library.setOnlyFavorites(false),
                ),
              if (filter.onlyDoable)
                chip(
                  l10n.libraryOnlyDoable,
                  () => library.setOnlyDoable(false),
                ),
              for (final muscle in filter.muscles)
                chip(
                  l10n.muscleName(muscle),
                  () => library.toggleMuscle(muscle),
                ),
              for (final item in filter.equipment)
                chip(
                  l10n.equipmentName(item),
                  () => library.toggleEquipment(item),
                ),
              for (final level in filter.levels)
                chip(l10n.levelName(level), () => library.toggleLevel(level)),
              for (final pattern in filter.movementPatterns)
                chip(
                  l10n.movementPatternName(pattern),
                  () => library.toggleMovementPattern(pattern),
                ),
            ],
          ),
          ForgeButton(
            label: l10n.libraryClearFilters,
            variant: ForgeButtonVariant.text,
            size: ForgeButtonSize.small,
            onPressed: library.clearFilters,
          ),
        ],
      ),
    );
  }
}
