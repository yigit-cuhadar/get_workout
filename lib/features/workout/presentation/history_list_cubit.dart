import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/history_usecases.dart';
import '../domain/workout.dart';
import '../domain/workout_repository.dart';

enum HistoryListStatus { loading, ready, failure }

class HistoryListState extends Equatable {
  const HistoryListState({
    this.status = HistoryListStatus.loading,
    this.workouts = const [],
    this.more = false,
    this.loadingMore = false,
    this.failure,
    this.writeRejected = false,
  });

  final HistoryListStatus status;

  /// Newest first.
  final List<Workout> workouts;

  /// Older workouts may follow; see [HistoryListCubit.loadMore].
  final bool more;
  final bool loadingMore;
  final Failure? failure;

  /// The server refused an edit or deletion that already looked done; tell
  /// the user, then call [HistoryListCubit.rejectionShown].
  final bool writeRejected;

  HistoryListState copyWith({bool? writeRejected}) => HistoryListState(
    status: status,
    workouts: workouts,
    more: more,
    loadingMore: loadingMore,
    failure: failure,
    writeRejected: writeRejected ?? this.writeRejected,
  );

  @override
  List<Object?> get props => [
    status,
    workouts,
    more,
    loadingMore,
    failure,
    writeRejected,
  ];
}

/// One page of the history: where it starts and, once a later page is
/// loaded, where it ends.
class _Page {
  _Page({this.after});

  final HistoryCursor? after;
  HistoryCursor? through;

  /// Kept while the page is followed again with an end.
  HistoryPage? data;
  StreamSubscription<HistoryPage>? subscription;
}

/// The finished workouts of whoever is signed in, newest first, a page at a
/// time. Each page is followed live, so edits, deletions and new workouts
/// show at once; a page gets a fixed end once the next one loads, so pages
/// never skip or repeat a workout. Resets to loading on every user change.
class HistoryListCubit extends Cubit<HistoryListState> {
  HistoryListCubit({
    required WatchAuthUser watchAuthUser,
    required this._watchHistory,
    required WatchRejectedWorkoutEdits watchRejectedEdits,
  }) : super(const HistoryListState()) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
    _rejectedSubscription = watchRejectedEdits().listen(
      (_) => emit(state.copyWith(writeRejected: true)),
    );
  }

  final WatchHistory _watchHistory;
  late final StreamSubscription<String?> _userSubscription;
  late final StreamSubscription<Failure> _rejectedSubscription;
  final _pages = <_Page>[];
  String? _uid;

  void _onUser(String? uid) {
    _uid = uid;
    _restart();
  }

  /// Follows the first page again after a failure.
  void retry() => _restart();

  void rejectionShown() => emit(state.copyWith(writeRejected: false));

  /// Loads the next older page, once the last one is full.
  void loadMore() {
    final last = _pages.lastOrNull;
    final end = last?.data?.end;
    if (last == null || end == null || !last.data!.more) return;
    last.through = end;
    _follow(last);
    _follow(_Page(after: end));
    _publish();
  }

  void _restart() {
    _stop();
    emit(HistoryListState(writeRejected: state.writeRejected));
    if (_uid != null) _follow(_Page());
  }

  void _follow(_Page page) {
    final uid = _uid;
    if (uid == null) return;
    if (!_pages.contains(page)) _pages.add(page);
    unawaited(page.subscription?.cancel());
    page.subscription =
        _watchHistory((uid: uid, after: page.after, through: page.through))
            .listen(
              (data) {
                page.data = data;
                _publish();
              },
              onError: (Object error) {
                _stop();
                emit(
                  HistoryListState(
                    status: HistoryListStatus.failure,
                    failure: error is Failure
                        ? error
                        : UnknownFailure('$error', error),
                    writeRejected: state.writeRejected,
                  ),
                );
              },
            );
  }

  void _publish() {
    final first = _pages.firstOrNull?.data;
    if (first == null) return;
    final last = _pages.last.data;
    // A workout moved to another page by an edit may briefly be in both.
    final seen = <String>{};
    emit(
      HistoryListState(
        status: HistoryListStatus.ready,
        workouts: [
          for (final page in _pages)
            for (final workout in page.data?.workouts ?? const <Workout>[])
              if (seen.add(workout.id)) workout,
        ],
        more: last?.more ?? false,
        loadingMore: last == null,
        writeRejected: state.writeRejected,
      ),
    );
  }

  void _stop() {
    for (final page in _pages) {
      unawaited(page.subscription?.cancel());
    }
    _pages.clear();
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _rejectedSubscription.cancel();
    _stop();
    return super.close();
  }
}
