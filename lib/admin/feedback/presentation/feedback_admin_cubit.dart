import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../shell/retrying_listener.dart';
import '../domain/feedback_admin_usecases.dart';
import '../domain/feedback_entry.dart';

class FeedbackAdminState extends Equatable {
  const FeedbackAdminState({
    this.filter = FeedbackEntryStatus.open,
    this.entries,
    this.failure,
    this.updating = const {},
    this.updateFailure,
  });

  /// The status shown.
  final FeedbackEntryStatus filter;

  /// The latest messages with [filter], newest first; null until loaded.
  final List<FeedbackEntry>? entries;

  /// Set when the stream failed; [entries] keep the last list.
  final Failure? failure;

  /// Paths of messages whose status is being changed.
  final Set<String> updating;

  /// Why the last status change failed; cleared by the next one.
  final Failure? updateFailure;

  FeedbackAdminState copyWith({
    FeedbackEntryStatus? filter,
    List<FeedbackEntry>? Function()? entries,
    Failure? Function()? failure,
    Set<String>? updating,
    Failure? Function()? updateFailure,
  }) => FeedbackAdminState(
    filter: filter ?? this.filter,
    entries: entries != null ? entries() : this.entries,
    failure: failure != null ? failure() : this.failure,
    updating: updating ?? this.updating,
    updateFailure: updateFailure != null ? updateFailure() : this.updateFailure,
  );

  @override
  List<Object?> get props => [
    filter,
    entries,
    failure,
    updating,
    updateFailure,
  ];
}

/// The users' feedback, open or closed, live; a message is closed or
/// reopened in place and moves to the other list.
class FeedbackAdminCubit extends Cubit<FeedbackAdminState> {
  FeedbackAdminCubit({
    required this._watchFeedback,
    required this._setFeedbackStatus,
    this.firstRetryDelay = const Duration(seconds: 1),
  }) : super(const FeedbackAdminState()) {
    _listen();
  }

  final WatchFeedback _watchFeedback;
  final SetFeedbackStatus _setFeedbackStatus;
  final Duration firstRetryDelay;
  RetryingListener<List<FeedbackEntry>>? _listener;

  void _listen() {
    final filter = state.filter;
    _listener?.cancel();
    _listener = RetryingListener(
      watch: () => _watchFeedback(filter),
      onData: (entries) {
        if (isClosed || state.filter != filter) return;
        emit(state.copyWith(entries: () => entries, failure: () => null));
      },
      onFailure: (failure) {
        if (isClosed || state.filter != filter) return;
        emit(state.copyWith(failure: () => failure));
      },
      firstRetryDelay: firstRetryDelay,
    );
  }

  /// Shows the messages with [status].
  void filter(FeedbackEntryStatus status) {
    if (status == state.filter) return;
    emit(
      state.copyWith(filter: status, entries: () => null, failure: () => null),
    );
    _listen();
  }

  /// Listens again now.
  void retry() => _listener?.retry();

  /// Closes an open message or reopens a closed one.
  Future<void> toggle(FeedbackEntry entry) async {
    if (state.updating.contains(entry.path)) return;
    emit(
      state.copyWith(
        updating: {...state.updating, entry.path},
        updateFailure: () => null,
      ),
    );
    final result = await _setFeedbackStatus((
      path: entry.path,
      status: entry.status == FeedbackEntryStatus.open
          ? FeedbackEntryStatus.closed
          : FeedbackEntryStatus.open,
    ));
    if (isClosed) return;
    emit(
      state.copyWith(
        updating: {...state.updating}..remove(entry.path),
        updateFailure: () => result.failureOrNull,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _listener?.cancel();
    return super.close();
  }
}
