import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../domain/program_admin_usecases.dart';
import '../domain/program_draft.dart';

class ProgramListState extends Equatable {
  const ProgramListState({
    this.records,
    this.failure,
    this.health,
    this.query = '',
    this.status,
  });

  /// Every card; null until the first snapshot arrives.
  final List<ProgramRecord>? records;

  /// Set when the stream failed; [records] keep the last list.
  final Failure? failure;
  final CatalogueHealth? health;
  final String query;
  final ExerciseStatus? status;

  /// Cards per status, before filtering.
  Map<ExerciseStatus, int> get counts => {
    for (final status in ExerciseStatus.values)
      status: records?.where((r) => r.draft.status == status).length ?? 0,
  };

  /// [records] matching the search and filter, by `order` (unset last),
  /// then id.
  List<ProgramRecord> get visible {
    final needle = query.trim().toLowerCase();
    bool matches(ProgramRecord record) {
      final draft = record.draft;
      if (status != null && draft.status != status) return false;
      if (needle.isEmpty) return true;
      return [
        draft.id,
        for (final text in draft.text.values) text.name,
      ].any((text) => text.toLowerCase().contains(needle));
    }

    int byOrder(ProgramRecord a, ProgramRecord b) {
      final orders = switch ((a.draft.order, b.draft.order)) {
        (final int x, final int y) => x.compareTo(y),
        (null, null) => 0,
        (null, _) => 1,
        (_, null) => -1,
      };
      return orders != 0 ? orders : a.id.compareTo(b.id);
    }

    return (records ?? const <ProgramRecord>[]).where(matches).toList()
      ..sort(byOrder);
  }

  ProgramListState copyWith({
    List<ProgramRecord>? records,
    Failure? Function()? failure,
    CatalogueHealth? health,
    String? query,
    ExerciseStatus? Function()? status,
  }) => ProgramListState(
    records: records ?? this.records,
    failure: failure != null ? failure() : this.failure,
    health: health ?? this.health,
    query: query ?? this.query,
    status: status != null ? status() : this.status,
  );

  @override
  List<Object?> get props => [records, failure, health, query, status];
}

/// Every ready-made program's card, live from Firestore, with search, a
/// status filter and the catalogue-wide health. After a stream error it
/// listens again, waiting longer after each failure in a row.
class ProgramListCubit extends Cubit<ProgramListState> {
  ProgramListCubit({
    required this._watchProgramCards,
    this.firstRetryDelay = const Duration(seconds: 1),
  }) : super(const ProgramListState()) {
    _listen();
  }

  final WatchProgramCards _watchProgramCards;

  /// Doubles with each failure in a row, up to [maxRetryDelay].
  final Duration firstRetryDelay;
  static const maxRetryDelay = Duration(seconds: 30);

  StreamSubscription<List<ProgramRecord>>? _subscription;
  Timer? _retryTimer;
  int _failures = 0;

  void _listen() {
    unawaited(_subscription?.cancel());
    _subscription = _watchProgramCards().listen(
      (records) {
        _failures = 0;
        emit(
          state.copyWith(
            records: records,
            health: CatalogueHealth.of(records),
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

  @override
  Future<void> close() async {
    _retryTimer?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
