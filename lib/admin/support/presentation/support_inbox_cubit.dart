import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../shell/retrying_listener.dart';
import '../domain/support_inbox_usecases.dart';
import '../domain/support_thread.dart';

class SupportInboxState extends Equatable {
  const SupportInboxState({
    this.filter = ThreadFilter.open,
    this.threads = const {},
    this.failures = const {},
    this.selectedPath,
    this.updating = const {},
    this.updateFailure,
  });

  /// The list shown on the left.
  final ThreadFilter filter;

  /// The latest threads of each list, newest first; a list is absent until
  /// loaded.
  final Map<ThreadFilter, List<SupportThread>> threads;

  /// Why a list's stream failed; the list keeps its last threads.
  final Map<ThreadFilter, Failure> failures;

  /// The thread open on the right.
  final String? selectedPath;

  /// Paths of threads being closed or reopened.
  final Set<String> updating;

  /// Why the last close or reopen failed; cleared by the next one.
  final Failure? updateFailure;

  /// The open thread, from whichever list holds it now (closing one moves
  /// it to Closed while it stays open); null when none is or it is gone.
  SupportThread? get selected {
    for (final list in threads.values) {
      for (final thread in list) {
        if (thread.path == selectedPath) return thread;
      }
    }
    return null;
  }

  SupportInboxState copyWith({
    ThreadFilter? filter,
    Map<ThreadFilter, List<SupportThread>>? threads,
    Map<ThreadFilter, Failure>? failures,
    String? selectedPath,
    Set<String>? updating,
    Failure? Function()? updateFailure,
  }) => SupportInboxState(
    filter: filter ?? this.filter,
    threads: threads ?? this.threads,
    failures: failures ?? this.failures,
    selectedPath: selectedPath ?? this.selectedPath,
    updating: updating ?? this.updating,
    updateFailure: updateFailure != null ? updateFailure() : this.updateFailure,
  );

  @override
  List<Object?> get props => [
    filter,
    threads,
    failures,
    selectedPath,
    updating,
    updateFailure,
  ];
}

/// Both lists of threads, live, the one picked from them, and closing or
/// reopening it in place.
class SupportInboxCubit extends Cubit<SupportInboxState> {
  SupportInboxCubit({
    required WatchThreads watchThreads,
    required this._closeThread,
    required this._reopenThread,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(const SupportInboxState()) {
    _listeners = [
      for (final filter in ThreadFilter.values)
        RetryingListener(
          watch: () => watchThreads(filter),
          onData: (threads) => emit(
            state.copyWith(
              threads: {...state.threads, filter: threads},
              failures: {...state.failures}..remove(filter),
            ),
          ),
          onFailure: (failure) => emit(
            state.copyWith(failures: {...state.failures, filter: failure}),
          ),
          firstRetryDelay: firstRetryDelay,
        ),
    ];
  }

  final CloseThread _closeThread;
  final ReopenThread _reopenThread;
  late final List<RetryingListener<List<SupportThread>>> _listeners;

  /// Shows the threads of [filter] on the left; the open thread stays.
  void filter(ThreadFilter filter) => emit(state.copyWith(filter: filter));

  /// Opens [thread] on the right.
  void select(SupportThread thread) =>
      emit(state.copyWith(selectedPath: thread.path));

  /// Listens to both lists again now.
  void retry() {
    for (final listener in _listeners) {
      listener.retry();
    }
  }

  /// Closes an open thread or reopens a closed one.
  Future<void> toggle(SupportThread thread) async {
    if (state.updating.contains(thread.path)) return;
    emit(
      state.copyWith(
        updating: {...state.updating, thread.path},
        updateFailure: () => null,
      ),
    );
    final result = thread.status == ThreadStatus.closed
        ? await _reopenThread(thread)
        : await _closeThread(thread);
    if (isClosed) return;
    emit(
      state.copyWith(
        updating: {...state.updating}..remove(thread.path),
        updateFailure: () => result.failureOrNull,
      ),
    );
  }

  @override
  Future<void> close() async {
    await Future.wait([for (final listener in _listeners) listener.cancel()]);
    return super.close();
  }
}
