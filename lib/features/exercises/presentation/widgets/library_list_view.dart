import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise.dart';
import '../../domain/exercise_queries.dart';
import '../../domain/vocabulary.dart';
import '../library_cubit.dart';
import '../vocabulary_labels.dart';
import 'exercise_tile.dart';
import 'filter_sheet.dart';

/// Search, filters, sort and the resulting exercises. Everything the model
/// offers is reachable here too, which makes it the screen reader's path.
///
/// Each result is an [ExerciseTile] opening its detail, or what [tileBuilder]
/// builds, e.g. to select exercises instead.
class LibraryListView extends StatefulWidget {
  const LibraryListView({
    super.key,
    this.tileBuilder,
    this.focusSearch = false,
    this.sectionsFor,
  });

  final Widget Function(BuildContext context, Exercise exercise)? tileBuilder;

  /// Whether the search field takes focus once the page's route is in.
  final bool focusSearch;

  /// While this is the only muscle filtered, the results split into the
  /// exercises working it as a main muscle and those working it as a
  /// secondary one.
  final Muscle? sectionsFor;

  @override
  State<LibraryListView> createState() => _LibraryListViewState();
}

class _LibraryListViewState extends State<LibraryListView> {
  late final _search = TextEditingController(
    text: context.read<LibraryCubit>().state.query,
  );

  /// Whether the search field may take focus: the page's route is in, so
  /// the keyboard comes up once, after any transition and Hero flight.
  var _routeIn = false;

  /// The route animation awaited for [_routeIn].
  Animation<double>? _entering;
  var _watching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.focusSearch || _watching) return;
    _watching = true;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.isCompleted) {
      _routeIn = true;
    } else {
      _entering = animation..addStatusListener(_onEntering);
    }
  }

  void _onEntering(AnimationStatus status) {
    if (!status.isCompleted) return;
    _entering?.removeStatusListener(_onEntering);
    _entering = null;
    setState(() => _routeIn = true);
  }

  @override
  void dispose() {
    _entering?.removeStatusListener(_onEntering);
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = context.read<LibraryCubit>();
    return BlocConsumer<LibraryCubit, LibraryState>(
      // The query also changes without typing: a user change clears it.
      listenWhen: (_, current) => current.query != _search.text,
      listener: (_, state) => _search.text = state.query,
      builder: (context, state) {
        final results = state.results;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              child: Row(
                children: [
                  Expanded(
                    child: LibrarySearchHero(
                      child: TextField(
                        // A new field once the route is in, autofocusing
                        // then.
                        key: ValueKey(_routeIn),
                        autofocus: _routeIn,
                        controller: _search,
                        onChanged: library.setQuery,
                        textInputAction: TextInputAction.search,
                        decoration: InputDecoration(
                          labelText: l10n.librarySearch,
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: state.query.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: MaterialLocalizations.of(context)
                                      .deleteButtonTooltip,
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    _search.clear();
                                    library.setQuery('');
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.libraryFilters,
                    isSelected: !state.filter.isEmpty,
                    icon: const Icon(Icons.filter_list),
                    onPressed: () => showFilterSheet(context),
                  ),
                  PopupMenuButton<ExerciseSort>(
                    tooltip: l10n.librarySort,
                    icon: const Icon(Icons.sort),
                    initialValue: state.sort,
                    onSelected: library.setSort,
                    itemBuilder: (_) => [
                      for (final sort in ExerciseSort.values)
                        CheckedPopupMenuItem(
                          value: sort,
                          checked: sort == state.sort,
                          child: Text(switch (sort) {
                            ExerciseSort.popularity =>
                              l10n.librarySortPopularity,
                            ExerciseSort.alphabetical =>
                              l10n.librarySortAlphabetical,
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!state.filter.isEmpty) _ActiveFilters(state.filter),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Gap.md,
                vertical: Gap.sm,
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(l10n.libraryResultCount(results.length)),
              ),
            ),
            Expanded(
              child: switch (state.muscleExercises) {
                _ when results.isEmpty => EmptyView(
                  message: l10n.libraryNoResults,
                ),
                final sections?
                    when widget.sectionsFor != null &&
                        state.muscle == widget.sectionsFor =>
                  _Sections(sections, tile: _tile),
                _ => ListView.builder(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: results.length,
                  itemBuilder: (context, index) =>
                      _tile(context, results[index]),
                ),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _tile(BuildContext context, Exercise exercise) =>
      widget.tileBuilder?.call(context, exercise) ??
      ExerciseTile(exercise, showFavorite: true);
}

/// The results of one muscle under "Main" and "Also works".
class _Sections extends StatelessWidget {
  const _Sections(this.sections, {required this.tile});

  final MuscleExercises sections;
  final Widget Function(BuildContext context, Exercise exercise) tile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    List<Widget> section(String title, List<Exercise> exercises) => [
      if (exercises.isNotEmpty) ...[
        Semantics(
          header: true,
          child: ListTile(dense: true, title: Text(title)),
        ),
        for (final exercise in exercises) tile(context, exercise),
      ],
    ];
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        ...section(l10n.libraryMuscleMain, sections.main),
        ...section(l10n.libraryMuscleAlsoWorks, sections.alsoWorks),
      ],
    );
  }
}

/// The search field flying between the Exercises view's
/// [LibrarySearchEntry] and the list page. In flight it is drawn as the
/// entry; the page's field takes focus only once its route is in.
class LibrarySearchHero extends StatelessWidget {
  const LibrarySearchHero({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(
    tag: LibrarySearchHero,
    flightShuttleBuilder: (_, _, _, from, _) =>
        LibrarySearchEntry(query: from.read<LibraryCubit>().state.query),
    child: child,
  );
}

/// Looks like the list's search field showing [query]; [onTap] opens it.
class LibrarySearchEntry extends StatelessWidget {
  const LibrarySearchEntry({super.key, required this.query, this.onTap});

  final String query;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Semantics(
        button: true,
        child: InkWell(
          onTap: onTap,
          child: InputDecorator(
            isEmpty: query.isEmpty,
            decoration: InputDecoration(
              labelText: l10n.librarySearch,
              prefixIcon: const Icon(Icons.search),
            ),
            child: Text(
              query,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
  }
}

/// One removable chip per active filter value, then "Clear all".
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters(this.filter);

  final LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final library = context.read<LibraryCubit>();
    Widget chip(String label, VoidCallback onDeleted) => Padding(
      padding: const EdgeInsets.only(right: Gap.sm),
      child: InputChip(label: Text(label), onDeleted: onDeleted),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: Gap.md),
      child: Row(
        children: [
          if (filter.onlyFavorites)
            chip(
              l10n.libraryOnlyFavorites,
              () => library.setOnlyFavorites(false),
            ),
          if (filter.onlyDoable)
            chip(l10n.libraryOnlyDoable, () => library.setOnlyDoable(false)),
          for (final muscle in filter.muscles)
            chip(l10n.muscleName(muscle), () => library.toggleMuscle(muscle)),
          for (final item in filter.equipment)
            chip(l10n.equipmentName(item), () => library.toggleEquipment(item)),
          for (final level in filter.levels)
            chip(l10n.levelName(level), () => library.toggleLevel(level)),
          for (final pattern in filter.movementPatterns)
            chip(
              l10n.movementPatternName(pattern),
              () => library.toggleMovementPattern(pattern),
            ),
          TextButton(
            onPressed: library.clearFilters,
            child: Text(l10n.libraryClearFilters),
          ),
        ],
      ),
    );
  }
}
