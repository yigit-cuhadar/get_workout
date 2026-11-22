import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../programs/domain/program_admin_usecases.dart';
import '../../programs/domain/program_draft.dart';
import '../../shell/admin_text.dart';
import '../../shell/retrying_listener.dart';
import '../../shell/table_sort.dart';
import '../domain/exercise_admin_usecases.dart';
import '../domain/exercise_draft.dart';

/// The columns of the table, each of which it can be sorted by.
enum ExerciseColumn {
  name,
  id,
  status,
  mainMuscles,
  equipment,
  family,
  generatorTier,
  popularity,
  updated,
}

/// A generator tier filter's value: a tier, or `(tier: null)` for an
/// exercise not rated.
typedef TierFilter = ({GeneratorTier? tier});

class ExerciseListState extends Equatable {
  const ExerciseListState({
    this.records,
    this.failure,
    this.health,
    this.usedIds,
    this.programsFailure,
    this.query = '',
    this.status,
    this.muscle,
    this.equipment,
    this.level,
    this.mechanic,
    this.movementPattern,
    this.loggingType,
    this.secondaryMuscle,
    this.family,
    this.generatorTier,
    this.problemsOnly = false,
    this.unusedOnly = false,
    this.sortColumn,
    this.ascending = true,
  });

  /// Every document; null until the first snapshot arrives.
  final List<ExerciseRecord>? records;

  /// Set when the stream failed; [records] keep the last list.
  final Failure? failure;
  final LibraryHealth? health;

  /// Every exercise some program uses; null until the programs arrive.
  final Set<String>? usedIds;

  /// Set when the programs' stream failed; [usedIds] keep the last set.
  final Failure? programsFailure;
  final String query;
  final ExerciseStatus? status;

  /// Matches a main muscle.
  final Muscle? muscle;

  /// Matches `equipment` or any alternative set.
  final Equipment? equipment;
  final Level? level;
  final Mechanic? mechanic;
  final MovementPattern? movementPattern;
  final LoggingType? loggingType;
  final Muscle? secondaryMuscle;
  final String? family;
  final TierFilter? generatorTier;

  /// Only exercises with a [hasProblem].
  final bool problemsOnly;

  /// Only exercises that are [isUnused].
  final bool unusedOnly;

  /// The column the table is sorted by; null for the default order, by
  /// popularity.
  final ExerciseColumn? sortColumn;
  final bool ascending;

  /// Documents per status, before filtering.
  Map<ExerciseStatus, int> get counts => {
    for (final status in ExerciseStatus.values)
      status: records?.where((r) => r.draft.status == status).length ?? 0,
  };

  /// Every family in use, by name.
  List<String> get families => {
    for (final record in records ?? const <ExerciseRecord>[])
      if (record.draft.family.isNotEmpty) record.draft.family,
  }.toList()..sort();

  /// Whether a finding of the library health concerns [record], which
  /// includes a missing required field.
  bool hasProblem(ExerciseRecord record) =>
      health?.flaggedIds.contains(record.id) ?? false;

  /// Whether no program, whatever its status, uses [record]; false until
  /// the programs arrive. A retired exercise is not expected in a program.
  bool isUnused(ExerciseRecord record) {
    final used = usedIds;
    return used != null &&
        record.draft.status != ExerciseStatus.retired &&
        !used.contains(record.id);
  }

  /// Documents with a [hasProblem], before filtering.
  int get problemCount => records?.where(hasProblem).length ?? 0;

  /// Documents that are [isUnused], before filtering.
  int get unusedCount => records?.where(isUnused).length ?? 0;

  bool get hasFilters =>
      status != null ||
      muscle != null ||
      equipment != null ||
      level != null ||
      mechanic != null ||
      movementPattern != null ||
      loggingType != null ||
      secondaryMuscle != null ||
      family != null ||
      generatorTier != null ||
      problemsOnly ||
      unusedOnly;

  /// [records] matching the search and every filter, sorted by
  /// [sortColumn], ties and the default by popularity.
  List<ExerciseRecord> get visible {
    final needle = query.trim().toLowerCase();
    bool matches(ExerciseRecord record) {
      final draft = record.draft;
      if (status != null && draft.status != status) return false;
      if (muscle != null && !draft.mainMuscles.contains(muscle)) return false;
      if (equipment != null &&
          !draft.equipment.contains(equipment) &&
          !draft.equipmentAlternatives.any((set) => set.contains(equipment))) {
        return false;
      }
      if (level != null && draft.level != level) return false;
      if (mechanic != null && draft.mechanic != mechanic) return false;
      if (movementPattern != null && draft.movementPattern != movementPattern) {
        return false;
      }
      if (loggingType != null && draft.loggingType != loggingType) {
        return false;
      }
      if (secondaryMuscle != null &&
          !draft.secondaryMuscles.contains(secondaryMuscle)) {
        return false;
      }
      if (family != null && draft.family != family) return false;
      if (generatorTier case (:final tier) when draft.generatorTier != tier) {
        return false;
      }
      if (problemsOnly && !hasProblem(record)) return false;
      if (unusedOnly && !isUnused(record)) return false;
      if (needle.isEmpty) return true;
      return [
        draft.id,
        draft.name,
        ...draft.aliases,
      ].any((text) => text.toLowerCase().contains(needle));
    }

    return (records ?? const <ExerciseRecord>[]).where(matches).toList()
      ..sort(_compare);
  }

  int _compare(ExerciseRecord a, ExerciseRecord b) {
    final x = a.draft, y = b.draft;
    int by<T extends Comparable<Object?>>(T? Function(ExerciseDraft) key) =>
        compareBlanksLast(key(x), key(y), ascending: ascending);
    final sorted = switch (sortColumn) {
      null => 0,
      ExerciseColumn.name => by((d) => _text(d.name)),
      ExerciseColumn.id => by((d) => _text(d.id)),
      ExerciseColumn.status => by((d) => _label(d.status)),
      ExerciseColumn.mainMuscles => by(
        (d) => _label(d.mainMuscles.firstOrNull),
      ),
      ExerciseColumn.equipment => by((d) => _label(d.equipment.firstOrNull)),
      ExerciseColumn.family => switch (by((d) => _text(d.family))) {
        0 => by((d) => d.familyRank),
        final families => families,
      },
      // By the tier's order, staple first.
      ExerciseColumn.generatorTier => by((d) => d.generatorTier?.index),
      ExerciseColumn.popularity => by((d) => d.popularity),
      ExerciseColumn.updated => compareBlanksLast(
        a.updatedAt,
        b.updatedAt,
        ascending: ascending,
      ),
    };
    if (sorted != 0) return sorted;
    // The default: by popularity, an exercise without one last, then name.
    final ranks = compareBlanksLast(
      x.popularity,
      y.popularity,
      ascending: true,
    );
    if (ranks != 0) return ranks;
    final names = x.name.toLowerCase().compareTo(y.name.toLowerCase());
    return names != 0 ? names : a.id.compareTo(b.id);
  }

  static String? _text(String value) =>
      value.isEmpty ? null : value.toLowerCase();

  static String? _label(Coded? value) =>
      value == null ? null : codeLabel(value).toLowerCase();

  ExerciseListState copyWith({
    List<ExerciseRecord>? records,
    Failure? Function()? failure,
    LibraryHealth? health,
    Set<String>? usedIds,
    Failure? Function()? programsFailure,
    String? query,
    ExerciseStatus? Function()? status,
    Muscle? Function()? muscle,
    Equipment? Function()? equipment,
    Level? Function()? level,
    Mechanic? Function()? mechanic,
    MovementPattern? Function()? movementPattern,
    LoggingType? Function()? loggingType,
    Muscle? Function()? secondaryMuscle,
    String? Function()? family,
    TierFilter? Function()? generatorTier,
    bool? problemsOnly,
    bool? unusedOnly,
    ExerciseColumn? sortColumn,
    bool? ascending,
  }) => ExerciseListState(
    records: records ?? this.records,
    failure: failure != null ? failure() : this.failure,
    health: health ?? this.health,
    usedIds: usedIds ?? this.usedIds,
    programsFailure: programsFailure != null
        ? programsFailure()
        : this.programsFailure,
    query: query ?? this.query,
    status: status != null ? status() : this.status,
    muscle: muscle != null ? muscle() : this.muscle,
    equipment: equipment != null ? equipment() : this.equipment,
    level: level != null ? level() : this.level,
    mechanic: mechanic != null ? mechanic() : this.mechanic,
    movementPattern: movementPattern != null
        ? movementPattern()
        : this.movementPattern,
    loggingType: loggingType != null ? loggingType() : this.loggingType,
    secondaryMuscle: secondaryMuscle != null
        ? secondaryMuscle()
        : this.secondaryMuscle,
    family: family != null ? family() : this.family,
    generatorTier: generatorTier != null ? generatorTier() : this.generatorTier,
    problemsOnly: problemsOnly ?? this.problemsOnly,
    unusedOnly: unusedOnly ?? this.unusedOnly,
    sortColumn: sortColumn ?? this.sortColumn,
    ascending: ascending ?? this.ascending,
  );

  /// This state without any filter; the search and the sort stay.
  ExerciseListState withoutFilters() => ExerciseListState(
    records: records,
    failure: failure,
    health: health,
    usedIds: usedIds,
    programsFailure: programsFailure,
    query: query,
    sortColumn: sortColumn,
    ascending: ascending,
  );

  @override
  List<Object?> get props => [
    records,
    failure,
    health,
    usedIds,
    programsFailure,
    query,
    status,
    muscle,
    equipment,
    level,
    mechanic,
    movementPattern,
    loggingType,
    secondaryMuscle,
    family,
    generatorTier,
    problemsOnly,
    unusedOnly,
    sortColumn,
    ascending,
  ];
}

/// The whole library, live from Firestore, with search, filters, sorting
/// and the library-wide health of what is loaded; the programs, also live,
/// tell which exercises no program uses. After a stream error it listens
/// again, waiting longer after each failure in a row.
class ExerciseListCubit extends Cubit<ExerciseListState> {
  ExerciseListCubit({
    required WatchExerciseRecords watchExerciseRecords,
    required WatchPrograms watchPrograms,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(const ExerciseListState()) {
    _listener = RetryingListener(
      watch: watchExerciseRecords.call,
      onData: (records) => emit(
        state.copyWith(
          records: records,
          health: LibraryHealth.of(records),
          failure: () => null,
        ),
      ),
      onFailure: (failure) => emit(state.copyWith(failure: () => failure)),
      firstRetryDelay: firstRetryDelay,
    );
    _programs = RetryingListener(
      watch: watchPrograms.call,
      onData: (programs) => emit(
        state.copyWith(
          usedIds: exerciseIdsInPrograms(programs),
          programsFailure: () => null,
        ),
      ),
      onFailure: (failure) =>
          emit(state.copyWith(programsFailure: () => failure)),
      firstRetryDelay: firstRetryDelay,
    );
  }

  late final RetryingListener<List<ExerciseRecord>> _listener;
  late final RetryingListener<List<ProgramRecord>> _programs;

  /// Listens again now, without waiting for the next automatic retry.
  void retry() {
    _listener.retry();
    _programs.retry();
  }

  void search(String query) => emit(state.copyWith(query: query));

  void filterStatus(ExerciseStatus? status) =>
      emit(state.copyWith(status: () => status));

  void filterMuscle(Muscle? muscle) =>
      emit(state.copyWith(muscle: () => muscle));

  void filterEquipment(Equipment? equipment) =>
      emit(state.copyWith(equipment: () => equipment));

  void filterLevel(Level? level) => emit(state.copyWith(level: () => level));

  void filterMechanic(Mechanic? mechanic) =>
      emit(state.copyWith(mechanic: () => mechanic));

  void filterMovementPattern(MovementPattern? pattern) =>
      emit(state.copyWith(movementPattern: () => pattern));

  void filterLoggingType(LoggingType? type) =>
      emit(state.copyWith(loggingType: () => type));

  void filterSecondaryMuscle(Muscle? muscle) =>
      emit(state.copyWith(secondaryMuscle: () => muscle));

  void filterFamily(String? family) =>
      emit(state.copyWith(family: () => family));

  void filterGeneratorTier(TierFilter? filter) =>
      emit(state.copyWith(generatorTier: () => filter));

  void showProblemsOnly(bool on) => emit(state.copyWith(problemsOnly: on));

  void showUnusedOnly(bool on) => emit(state.copyWith(unusedOnly: on));

  void clearFilters() => emit(state.withoutFilters());

  /// Sorts by [column], ascending; again on the same column flips the
  /// direction.
  void sortBy(ExerciseColumn column) => emit(
    state.copyWith(
      sortColumn: column,
      ascending: column != state.sortColumn || !state.ascending,
    ),
  );

  @override
  Future<void> close() async {
    await Future.wait([_listener.cancel(), _programs.cancel()]);
    return super.close();
  }
}
