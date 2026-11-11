import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/exercise_queries.dart';
import '../library_cubit.dart';
import '../vocabulary_labels.dart';
import 'exercise_tile.dart';
import 'filter_sheet.dart';

/// Search, filters, sort and the resulting exercises. Everything the model
/// offers is reachable here too, which makes it the screen reader's path.
class LibraryListView extends StatefulWidget {
  const LibraryListView({super.key});

  @override
  State<LibraryListView> createState() => _LibraryListViewState();
}

class _LibraryListViewState extends State<LibraryListView> {
  late final _search = TextEditingController(
    text: context.read<LibraryCubit>().state.query,
  );

  @override
  void dispose() {
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
                    child: TextField(
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
              child: results.isEmpty
                  ? EmptyView(message: l10n.libraryNoResults)
                  : ListView.builder(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemCount: results.length,
                      itemBuilder: (_, index) =>
                          ExerciseTile(results[index], showFavorite: true),
                    ),
            ),
          ],
        );
      },
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
