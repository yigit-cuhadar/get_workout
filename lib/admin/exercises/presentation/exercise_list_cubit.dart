import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../domain/exercise_admin_usecases.dart';
import '../domain/exercise_draft.dart';

enum ExerciseSort { popularity, name }

class ExerciseListState extends Equatable {
  const ExerciseListState({
    this.records,
    this.failure,
    this.health,
    this.query = '',
    this.status,
    this.muscle,
    this.equipment,
    this.sort = ExerciseSort.popularity,
  });

  /// Every document; null until the first snapshot arrives.
  final List<ExerciseRecord>? records;

  /// Set when the stream failed; [records] keep the last list.
  final Failure? failure;
  final LibraryHealth? health;
  final String query;
  final ExerciseStatus? status;

  /// Matches a main muscle.
  final Muscle? muscle;

  /// Matches `equipment` or any alternative set.
  final Equipment? equipment;
  final ExerciseSort sort;

  /// Documents per status, before filtering.
  Map<ExerciseStatus, int> get counts => {
    for (final status in ExerciseStatus.values)
      status: records?.where((r) => r.draft.status == status).length ?? 0,
  };

  /// [records] matching the search and filters, in [sort] order.
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
      if (needle.isEmpty) return true;
      return [
        draft.id,
        draft.name,
        ...draft.aliases,
      ].any((text) => text.toLowerCase().contains(needle));
    }

    int byName(ExerciseRecord a, ExerciseRecord b) {
      final names = a.draft.name.toLowerCase().compareTo(
        b.draft.name.toLowerCase(),
      );
      return names != 0 ? names : a.id.compareTo(b.id);
    }

    // Without a popularity, an exercise sorts last.
    int byPopularity(ExerciseRecord a, ExerciseRecord b) {
      final ranks = switch ((a.draft.popularity, b.draft.popularity)) {
        (final int x, final int y) => x.compareTo(y),
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
      };
      return ranks != 0 ? ranks : byName(a, b);
    }

    return (records ?? const <ExerciseRecord>[]).where(matches).toList()
      ..sort(switch (sort) {
        ExerciseSort.popularity => byPopularity,
        ExerciseSort.name => byName,
      });
  }

  ExerciseListState copyWith({
    List<ExerciseRecord>? records,
    Failure? Function()? failure,
    LibraryHealth? health,
    String? query,
    ExerciseStatus? Function()? status,
    Muscle? Function()? muscle,
    Equipment? Function()? equipment,
    ExerciseSort? sort,
  }) => ExerciseListState(
    records: records ?? this.records,
    failure: failure != null ? failure() : this.failure,
    health: health ?? this.health,
    query: query ?? this.query,
    status: status != null ? status() : this.status,
    muscle: muscle != null ? muscle() : this.muscle,
    equipment: equipment != null ? equipment() : this.equipment,
    sort: sort ?? this.sort,
  );

  @override
  List<Object?> get props => [
    records,
    failure,
    health,
    query,
    status,
    muscle,
    equipment,
    sort,
  ];
}

/// The whole library, live from Firestore, with search, filters and the
/// library-wide health of what is loaded. After a stream error it listens
/// again, waiting longer after each failure in a row.
class ExerciseListCubit extends Cubit<ExerciseListState> {
  ExerciseListCubit({
    required this._watchExerciseRecords,
    this.firstRetryDelay = const Duration(seconds: 1),
  }) : super(const ExerciseListState()) {
    _listen();
  }

  final WatchExerciseRecords _watchExerciseRecords;

  /// Doubles with each failure in a row, up to [maxRetryDelay].
  final Duration firstRetryDelay;
  static const maxRetryDelay = Duration(seconds: 30);

  StreamSubscription<List<ExerciseRecord>>? _subscription;
  Timer? _retryTimer;
  int _failures = 0;

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = _watchExerciseRecords().listen(
      (records) {
        _failures = 0;
        emit(
          state.copyWith(
            records: records,
            health: LibraryHealth.of(records),
            failure: () => null,
          ),
        );
      },
      onError: (Object error) {
        emit(
          state.copyWith(
            failure: () =>
                error is Failure ? error : UnknownFailure('$error', error),
          ),
        );
        final delay = firstRetryDelay * (1 << _failures.clamp(0, 10));
        _failures++;
        _retryTimer?.cancel();
        _retryTimer = Timer(
          delay < maxRetryDelay ? delay : maxRetryDelay,
          _listen,
        );
      },
    );
  }

  /// Listens again now, without waiting for the next automatic retry.
  void retry() {
    _retryTimer?.cancel();
    _listen();
  }

  void search(String query) => emit(state.copyWith(query: query));

  void filterStatus(ExerciseStatus? status) =>
      emit(state.copyWith(status: () => status));

  void filterMuscle(Muscle? muscle) =>
      emit(state.copyWith(muscle: () => muscle));

  void filterEquipment(Equipment? equipment) =>
      emit(state.copyWith(equipment: () => equipment));

  void sortBy(ExerciseSort sort) => emit(state.copyWith(sort: sort));

  @override
  Future<void> close() async {
    _retryTimer?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
