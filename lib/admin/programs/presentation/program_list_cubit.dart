import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../../features/exercises/domain/vocabulary.dart';
import '../../shell/retrying_listener.dart';
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
    required WatchProgramCards watchProgramCards,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(const ProgramListState()) {
    _listener = RetryingListener(
      watch: watchProgramCards.call,
      onData: (records) => emit(
        state.copyWith(
          records: records,
          health: CatalogueHealth.of(records),
          failure: () => null,
        ),
      ),
      onFailure: (failure) => emit(state.copyWith(failure: () => failure)),
      firstRetryDelay: firstRetryDelay,
    );
  }

  late final RetryingListener<List<ProgramRecord>> _listener;

  /// Listens again now, without waiting for the next automatic retry.
  void retry() => _listener.retry();

  void search(String query) => emit(state.copyWith(query: query));

  void filterStatus(ExerciseStatus? status) =>
      emit(state.copyWith(status: () => status));

  @override
  Future<void> close() async {
    await _listener.cancel();
    return super.close();
  }
}
