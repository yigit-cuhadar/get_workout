import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../../features/exercises/domain/vocabulary.dart';
import '../../../features/programs/domain/catalogue_program.dart';
import '../../exercises/domain/exercise_admin_usecases.dart';
import '../../exercises/domain/exercise_draft.dart';
import '../../shell/admin_text.dart';
import '../../shell/retrying_listener.dart';
import '../../shell/table_sort.dart';
import '../domain/program_admin_usecases.dart';
import '../domain/program_draft.dart';

/// The columns of the table, each of which it can be sorted by.
enum ProgramColumn {
  order,
  name,
  id,
  status,
  access,
  days,
  level,
  goal,
  equipmentProfile,
  updated,
}

class ProgramListState extends Equatable {
  const ProgramListState({
    this.records,
    this.failure,
    this.health,
    this.exercises,
    this.exercisesFailure,
    this.problemIds = const {},
    this.query = '',
    this.status,
    this.premium,
    this.level,
    this.goal,
    this.daysPerWeek,
    this.equipmentProfile,
    this.problemsOnly = false,
    this.sortColumn,
    this.ascending = true,
  });

  /// Every program with its days; null until they first arrive.
  final List<ProgramRecord>? records;

  /// Set when the stream failed; [records] keep the last list.
  final Failure? failure;
  final CatalogueHealth? health;

  /// Every exercise by id, as the catalogue rules take them; null until
  /// they first arrive.
  final Map<String, ExerciseEntry>? exercises;

  /// Set when the exercises' stream failed; [exercises] keep the last ones.
  final Failure? exercisesFailure;

  /// Programs that break a catalogue rule or get a weekly-sets warning;
  /// empty until the programs and the exercises arrived.
  final Set<String> problemIds;
  final String query;
  final ExerciseStatus? status;

  /// The access: true for premium, false for free.
  final bool? premium;
  final Level? level;
  final Goal? goal;

  /// Matches the `daysPerWeek` stored on the card.
  final int? daysPerWeek;
  final EquipmentProfile? equipmentProfile;

  /// Only programs in [problemIds].
  final bool problemsOnly;

  /// The column the table is sorted by; null for the default order, by
  /// `order`.
  final ProgramColumn? sortColumn;
  final bool ascending;

  /// Cards per status, before filtering.
  Map<ExerciseStatus, int> get counts => {
    for (final status in ExerciseStatus.values)
      status: records?.where((r) => r.draft.status == status).length ?? 0,
  };

  /// Free programs (false) and premium ones (true), before filtering.
  Map<bool, int> get accessCounts => {
    for (final premium in [false, true])
      premium: records?.where((r) => r.draft.premium == premium).length ?? 0,
  };

  /// Every stored days per week, from fewest.
  List<int> get daysPerWeekValues => {
    for (final record in records ?? const <ProgramRecord>[])
      ?record.daysPerWeek,
  }.toList()..sort();

  bool get hasFilters =>
      status != null ||
      premium != null ||
      level != null ||
      goal != null ||
      daysPerWeek != null ||
      equipmentProfile != null ||
      problemsOnly;

  /// [records] matching the search and every filter, sorted by
  /// [sortColumn], ties and the default by `order` (unset last), then id.
  List<ProgramRecord> get visible {
    final needle = query.trim().toLowerCase();
    bool matches(ProgramRecord record) {
      final draft = record.draft;
      if (status != null && draft.status != status) return false;
      if (premium != null && draft.premium != premium) return false;
      if (level != null && draft.level != level) return false;
      if (goal != null && draft.goal != goal) return false;
      if (daysPerWeek != null && record.daysPerWeek != daysPerWeek) {
        return false;
      }
      if (equipmentProfile != null &&
          draft.equipmentProfile != equipmentProfile) {
        return false;
      }
      if (problemsOnly && !problemIds.contains(record.id)) return false;
      if (needle.isEmpty) return true;
      return [
        draft.id,
        for (final text in draft.text.values) text.name,
      ].any((text) => text.toLowerCase().contains(needle));
    }

    return (records ?? const <ProgramRecord>[]).where(matches).toList()
      ..sort(_compare);
  }

  int _compare(ProgramRecord a, ProgramRecord b) {
    int by<T extends Comparable<Object?>>(T? Function(ProgramRecord) key) =>
        compareBlanksLast(key(a), key(b), ascending: ascending);
    final sorted = switch (sortColumn) {
      null => 0,
      ProgramColumn.order => by((r) => r.draft.order),
      ProgramColumn.name => by(
        (r) => _text(r.draft.textOf(CatalogueProgram.fallbackLanguage).name),
      ),
      ProgramColumn.id => by((r) => _text(r.id)),
      ProgramColumn.status => by((r) => _label(r.draft.status)),
      ProgramColumn.access => by((r) => r.draft.premium ? 'premium' : 'free'),
      ProgramColumn.days => by((r) => r.daysPerWeek),
      ProgramColumn.level => by((r) => _label(r.draft.level)),
      ProgramColumn.goal => by((r) => _label(r.draft.goal)),
      ProgramColumn.equipmentProfile => by(
        (r) => _label(r.draft.equipmentProfile),
      ),
      ProgramColumn.updated => by((r) => r.version.card),
    };
    if (sorted != 0) return sorted;
    final orders = compareBlanksLast(
      a.draft.order,
      b.draft.order,
      ascending: true,
    );
    return orders != 0 ? orders : a.id.compareTo(b.id);
  }

  static String? _text(String value) =>
      value.isEmpty ? null : value.toLowerCase();

  static String? _label(Coded? value) =>
      value == null ? null : codeLabel(value).toLowerCase();

  ProgramListState copyWith({
    List<ProgramRecord>? records,
    Failure? Function()? failure,
    CatalogueHealth? health,
    Map<String, ExerciseEntry>? exercises,
    Failure? Function()? exercisesFailure,
    Set<String>? problemIds,
    String? query,
    ExerciseStatus? Function()? status,
    bool? Function()? premium,
    Level? Function()? level,
    Goal? Function()? goal,
    int? Function()? daysPerWeek,
    EquipmentProfile? Function()? equipmentProfile,
    bool? problemsOnly,
    ProgramColumn? sortColumn,
    bool? ascending,
  }) => ProgramListState(
    records: records ?? this.records,
    failure: failure != null ? failure() : this.failure,
    health: health ?? this.health,
    exercises: exercises ?? this.exercises,
    exercisesFailure: exercisesFailure != null
        ? exercisesFailure()
        : this.exercisesFailure,
    problemIds: problemIds ?? this.problemIds,
    query: query ?? this.query,
    status: status != null ? status() : this.status,
    premium: premium != null ? premium() : this.premium,
    level: level != null ? level() : this.level,
    goal: goal != null ? goal() : this.goal,
    daysPerWeek: daysPerWeek != null ? daysPerWeek() : this.daysPerWeek,
    equipmentProfile: equipmentProfile != null
        ? equipmentProfile()
        : this.equipmentProfile,
    problemsOnly: problemsOnly ?? this.problemsOnly,
    sortColumn: sortColumn ?? this.sortColumn,
    ascending: ascending ?? this.ascending,
  );

  /// This state without any filter; the search and the sort stay.
  ProgramListState withoutFilters() => ProgramListState(
    records: records,
    failure: failure,
    health: health,
    exercises: exercises,
    exercisesFailure: exercisesFailure,
    problemIds: problemIds,
    query: query,
    sortColumn: sortColumn,
    ascending: ascending,
  );

  @override
  List<Object?> get props => [
    records,
    failure,
    health,
    exercises,
    exercisesFailure,
    problemIds,
    query,
    status,
    premium,
    level,
    goal,
    daysPerWeek,
    equipmentProfile,
    problemsOnly,
    sortColumn,
    ascending,
  ];
}

/// Every ready-made program with its days, live from Firestore, with
/// search, filters, sorting and the catalogue-wide health; the exercise
/// library, also live, lets the rules of each program be checked. After a
/// stream error it listens again, waiting longer after each failure in a
/// row.
class ProgramListCubit extends Cubit<ProgramListState> {
  ProgramListCubit({
    required WatchPrograms watchPrograms,
    required WatchExerciseRecords watchExerciseRecords,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(const ProgramListState()) {
    _listener = RetryingListener(
      watch: watchPrograms.call,
      onData: (records) => emit(
        state.copyWith(
          records: records,
          health: CatalogueHealth.of(records),
          problemIds: _problems(records, state.exercises),
          failure: () => null,
        ),
      ),
      onFailure: (failure) => emit(state.copyWith(failure: () => failure)),
      firstRetryDelay: firstRetryDelay,
    );
    _exercises = RetryingListener(
      watch: watchExerciseRecords.call,
      onData: (records) {
        final exercises = exerciseEntries(records);
        emit(
          state.copyWith(
            exercises: exercises,
            problemIds: _problems(state.records, exercises),
            exercisesFailure: () => null,
          ),
        );
      },
      onFailure: (failure) =>
          emit(state.copyWith(exercisesFailure: () => failure)),
      firstRetryDelay: firstRetryDelay,
    );
  }

  late final RetryingListener<List<ProgramRecord>> _listener;
  late final RetryingListener<List<ExerciseRecord>> _exercises;

  static Set<String> _problems(
    List<ProgramRecord>? records,
    Map<String, ExerciseEntry>? exercises,
  ) => records == null || exercises == null
      ? const {}
      : programsWithProblems(records, exercises);

  /// Listens again now, without waiting for the next automatic retry.
  void retry() {
    _listener.retry();
    _exercises.retry();
  }

  void search(String query) => emit(state.copyWith(query: query));

  void filterStatus(ExerciseStatus? status) =>
      emit(state.copyWith(status: () => status));

  void filterAccess(bool? premium) =>
      emit(state.copyWith(premium: () => premium));

  void filterLevel(Level? level) => emit(state.copyWith(level: () => level));

  void filterGoal(Goal? goal) => emit(state.copyWith(goal: () => goal));

  void filterDaysPerWeek(int? days) =>
      emit(state.copyWith(daysPerWeek: () => days));

  void filterEquipmentProfile(EquipmentProfile? profile) =>
      emit(state.copyWith(equipmentProfile: () => profile));

  void showProblemsOnly(bool on) => emit(state.copyWith(problemsOnly: on));

  void clearFilters() => emit(state.withoutFilters());

  /// Sorts by [column], ascending; again on the same column flips the
  /// direction.
  void sortBy(ProgramColumn column) => emit(
    state.copyWith(
      sortColumn: column,
      ascending: column != state.sortColumn || !state.ascending,
    ),
  );

  @override
  Future<void> close() async {
    await Future.wait([_listener.cancel(), _exercises.cancel()]);
    return super.close();
  }
}
