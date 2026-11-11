import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise.dart';
import '../domain/exercise_queries.dart';
import '../domain/exercise_usecases.dart';
import '../domain/vocabulary.dart';
import 'equipment_cubit.dart';
import 'exercise_catalogue_cubit.dart';
import 'favorites_cubit.dart';

enum LibraryView { body, list }

/// The filters of the list. Within one criterion any selected value matches;
/// every criterion must match.
class LibraryFilter extends Equatable {
  const LibraryFilter({
    this.muscles = const {},
    this.equipment = const {},
    this.levels = const {},
    this.movementPatterns = const {},
    this.onlyDoable = false,
    this.onlyFavorites = false,
  });

  final Set<Muscle> muscles;
  final Set<Equipment> equipment;
  final Set<Level> levels;
  final Set<MovementPattern> movementPatterns;

  /// Only exercises doable with the user's equipment.
  final bool onlyDoable;
  final bool onlyFavorites;

  bool get isEmpty => this == const LibraryFilter();

  LibraryFilter copyWith({
    Set<Muscle>? muscles,
    Set<Equipment>? equipment,
    Set<Level>? levels,
    Set<MovementPattern>? movementPatterns,
    bool? onlyDoable,
    bool? onlyFavorites,
  }) => LibraryFilter(
    muscles: muscles ?? this.muscles,
    equipment: equipment ?? this.equipment,
    levels: levels ?? this.levels,
    movementPatterns: movementPatterns ?? this.movementPatterns,
    onlyDoable: onlyDoable ?? this.onlyDoable,
    onlyFavorites: onlyFavorites ?? this.onlyFavorites,
  );

  @override
  List<Object?> get props => [
    muscles,
    equipment,
    levels,
    movementPatterns,
    onlyDoable,
    onlyFavorites,
  ];
}

class LibraryState extends Equatable {
  const LibraryState({
    this.view = LibraryView.body,
    this.query = '',
    this.filter = const LibraryFilter(),
    this.sort = ExerciseSort.popularity,
    this.results = const [],
    this.equipmentChosen = false,
    this.selectedMuscle,
    this.muscleExercises,
    this.customWriteRejected = false,
  });

  final LibraryView view;
  final String query;
  final LibraryFilter filter;
  final ExerciseSort sort;

  /// The list view's exercises: the catalogue searched, filtered and sorted.
  final List<Exercise> results;

  /// Whether the user has picked their equipment; until then the page asks
  /// them to, before turning [LibraryFilter.onlyDoable] on.
  final bool equipmentChosen;

  /// The muscle picked on the model, whose sheet is open.
  final Muscle? selectedMuscle;

  /// The exercises of [selectedMuscle]; null when none is selected.
  final MuscleExercises? muscleExercises;

  /// The server refused a save or delete of a custom exercise that already
  /// looked done; tell the user, then call [LibraryCubit.rejectionShown].
  final bool customWriteRejected;

  LibraryState copyWith({
    LibraryView? view,
    String? query,
    LibraryFilter? filter,
    ExerciseSort? sort,
    List<Exercise>? results,
    bool? equipmentChosen,
    Muscle? Function()? selectedMuscle,
    MuscleExercises? Function()? muscleExercises,
    bool? customWriteRejected,
  }) => LibraryState(
    view: view ?? this.view,
    query: query ?? this.query,
    filter: filter ?? this.filter,
    sort: sort ?? this.sort,
    results: results ?? this.results,
    equipmentChosen: equipmentChosen ?? this.equipmentChosen,
    selectedMuscle: selectedMuscle != null
        ? selectedMuscle()
        : this.selectedMuscle,
    muscleExercises: muscleExercises != null
        ? muscleExercises()
        : this.muscleExercises,
    customWriteRejected: customWriteRejected ?? this.customWriteRejected,
  );

  @override
  List<Object?> get props => [
    view,
    query,
    filter,
    sort,
    results,
    equipmentChosen,
    selectedMuscle,
    // Records compare their lists by identity; these compare by content.
    muscleExercises?.main,
    muscleExercises?.alsoWorks,
    customWriteRejected,
  ];
}

/// Browsing the catalogue: the view, search, filters and sort of the list,
/// and the muscle picked on the model. Follows the app-wide catalogue,
/// favourites and equipment, so results stay current as they change. A
/// change of user starts browsing afresh; only the view is kept.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({
    required WatchAuthUser watchAuthUser,
    required ExerciseCatalogueCubit catalogue,
    required FavoritesCubit favorites,
    required EquipmentCubit equipment,
    required WatchRejectedCustomExerciseWrites watchRejectedCustomWrites,
  }) : super(const LibraryState()) {
    _catalogue = _exercisesOf(catalogue.state) ?? const [];
    _favorites = favorites.state.ids;
    _owned = equipment.state.owned;
    _recompute();
    _subscriptions = [
      catalogue.stream.listen((state) {
        // Loading and failed keep the last list; the page shows those states.
        if (_exercisesOf(state) case final exercises?) {
          _catalogue = exercises;
          _recompute();
        }
      }),
      favorites.stream.map((state) => state.ids).distinct().listen((ids) {
        _favorites = ids;
        _recompute();
      }),
      equipment.stream.map((state) => state.owned).distinct().listen((owned) {
        _owned = owned;
        _recompute();
      }),
      // The first id is whoever was signed in when browsing started.
      watchAuthUser()
          .map((user) => user?.id)
          .distinct()
          .skip(1)
          .listen((_) => _reset()),
      watchRejectedCustomWrites().listen(
        (_) => emit(state.copyWith(customWriteRejected: true)),
      ),
    ];
  }

  late final List<StreamSubscription<Object?>> _subscriptions;
  late List<Exercise> _catalogue;
  late Set<String> _favorites;
  Set<Equipment>? _owned;
  String _language = Exercise.fallbackLanguage;

  static List<Exercise>? _exercisesOf(ExerciseCatalogueState state) =>
      state is CatalogueReady ? state.exercises : null;

  /// The language exercise text is searched and sorted in.
  void setLanguage(String language) {
    if (language == _language) return;
    _language = language;
    _recompute();
  }

  void setView(LibraryView view) => emit(state.copyWith(view: view));

  void rejectionShown() => emit(state.copyWith(customWriteRejected: false));

  void setQuery(String query) => _recompute(query: query);

  void setSort(ExerciseSort sort) => _recompute(sort: sort);

  void toggleMuscle(Muscle muscle) => _recompute(
    filter: state.filter.copyWith(
      muscles: _toggle(state.filter.muscles, muscle),
    ),
  );

  void toggleEquipment(Equipment item) => _recompute(
    filter: state.filter.copyWith(
      equipment: _toggle(state.filter.equipment, item),
    ),
  );

  void toggleLevel(Level level) => _recompute(
    filter: state.filter.copyWith(levels: _toggle(state.filter.levels, level)),
  );

  void toggleMovementPattern(MovementPattern pattern) => _recompute(
    filter: state.filter.copyWith(
      movementPatterns: _toggle(state.filter.movementPatterns, pattern),
    ),
  );

  /// While the user's equipment is unknown, only bodyweight counts.
  void setOnlyDoable(bool value) =>
      _recompute(filter: state.filter.copyWith(onlyDoable: value));

  void setOnlyFavorites(bool value) =>
      _recompute(filter: state.filter.copyWith(onlyFavorites: value));

  void clearFilters() => _recompute(filter: const LibraryFilter());

  void _reset() => _recompute(
    query: '',
    filter: const LibraryFilter(),
    sort: ExerciseSort.popularity,
  );

  /// Opens (or with null, closes) the sheet of [muscle].
  void selectMuscle(Muscle? muscle) => emit(
    state.copyWith(
      selectedMuscle: () => muscle,
      muscleExercises: () =>
          muscle == null ? null : exercisesWorking(muscle, _catalogue),
    ),
  );

  void _recompute({String? query, LibraryFilter? filter, ExerciseSort? sort}) {
    final nextFilter = filter ?? state.filter;
    final owned = _owned;
    final nextQuery = query ?? state.query;
    final nextSort = sort ?? state.sort;
    final muscle = state.selectedMuscle;
    emit(
      state.copyWith(
        query: nextQuery,
        filter: nextFilter,
        sort: nextSort,
        results: _results(nextQuery, nextFilter, nextSort, owned),
        equipmentChosen: owned != null,
        muscleExercises: () =>
            muscle == null ? null : exercisesWorking(muscle, _catalogue),
      ),
    );
  }

  List<Exercise> _results(
    String query,
    LibraryFilter filter,
    ExerciseSort sort,
    Set<Equipment>? owned,
  ) {
    var exercises = filterExercises(
      _catalogue,
      ExerciseFilter(
        muscles: filter.muscles,
        equipment: filter.equipment,
        levels: filter.levels,
        movementPatterns: filter.movementPatterns,
        doableWith: filter.onlyDoable ? owned ?? const {} : null,
      ),
    );
    if (filter.onlyFavorites) {
      exercises = [
        for (final exercise in exercises)
          if (_favorites.contains(exercise.id)) exercise,
      ];
    }
    if (query.trim().isEmpty) {
      return sortExercises(exercises, sort, language: _language);
    }
    // A search ranks names starting with the query first, then by
    // popularity; only A-Z overrides that.
    final found = searchExercises(exercises, query, language: _language);
    return sort == ExerciseSort.popularity
        ? found
        : sortExercises(found, sort, language: _language);
  }

  static Set<T> _toggle<T>(Set<T> set, T value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};

  @override
  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
