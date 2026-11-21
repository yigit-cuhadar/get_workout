import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/admin_user.dart';
import '../domain/user_admin_usecases.dart';

class UsersState extends Equatable {
  const UsersState({
    this.users,
    this.next,
    this.loadingMore = false,
    this.failure,
    this.finding = false,
    this.findFailure,
  });

  /// The latest sign-ups loaded so far, newest first; null until loaded.
  final List<UserRow>? users;

  /// Where Load more continues; null on the last page.
  final UserCursor? next;
  final bool loadingMore;

  /// Why the first page or the last Load more failed.
  final Failure? failure;
  final bool finding;

  /// Why the last search found nobody or failed.
  final Failure? findFailure;

  bool get canLoadMore => next != null && !loadingMore;

  @override
  List<Object?> get props => [
    users,
    next,
    loadingMore,
    failure,
    finding,
    findFailure,
  ];
}

/// The Users page: a search by email or uid over the latest sign-ups,
/// a page at a time. It lives while any user's page is open, so the pages
/// loaded survive a trip to one.
class UsersCubit extends Cubit<UsersState> {
  UsersCubit({required this._listLatestUsers, required this._findUser})
    : super(const UsersState());

  final ListLatestUsers _listLatestUsers;
  final FindUser _findUser;

  /// Loads the first page again.
  Future<void> load() async {
    emit(const UsersState(loadingMore: true));
    await _page(null);
  }

  Future<void> loadMore() async {
    if (!state.canLoadMore) return;
    emit(_copy(loadingMore: true, failure: null));
    await _page(state.next);
  }

  Future<void> _page(UserCursor? after) async {
    final result = await _listLatestUsers(after);
    if (isClosed) return;
    switch (result) {
      case Ok(value: final page):
        emit(
          UsersState(users: [...?state.users, ...page.users], next: page.next),
        );
      case Err(:final failure):
        emit(_copy(loadingMore: false, failure: failure));
    }
  }

  /// The uid of the user with [query] as email or uid, for the page to
  /// open; null when nobody has it ([UsersState.findFailure]).
  Future<String?> find(String query) async {
    if (state.finding) return null;
    emit(_copy(finding: true, findFailure: null));
    final result = await _findUser(query);
    if (isClosed) return null;
    emit(_copy(finding: false, findFailure: result.failureOrNull));
    return result.valueOrNull;
  }

  /// Drops a deleted user from the rows loaded.
  void removed(String uid) {
    final users = state.users;
    if (users == null) return;
    emit(
      _copy(
        users: [
          for (final u in users)
            if (u.uid != uid) u,
        ],
      ),
    );
  }

  UsersState _copy({
    List<UserRow>? users,
    bool? loadingMore,
    Object? failure = _keep,
    bool? finding,
    Object? findFailure = _keep,
  }) => UsersState(
    users: users ?? state.users,
    next: state.next,
    loadingMore: loadingMore ?? state.loadingMore,
    failure: failure == _keep ? state.failure : failure as Failure?,
    finding: finding ?? state.finding,
    findFailure: findFailure == _keep
        ? state.findFailure
        : findFailure as Failure?,
  );
}

const _keep = Object();
