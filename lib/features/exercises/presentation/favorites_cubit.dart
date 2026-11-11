import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise_usecases.dart';
import 'user_stream_follower.dart';

class FavoritesState extends Equatable {
  const FavoritesState(this.ids, {this.failure});

  final Set<String> ids;

  /// Set when the last change failed; [ids] then still hold the values from
  /// before it.
  final Failure? failure;

  bool contains(String exerciseId) => ids.contains(exerciseId);

  @override
  List<Object?> get props => [ids, failure];
}

/// The favourite exercises of whoever is signed in. Empty until the current
/// user's favourites arrive, also after every user change.
class FavoritesCubit extends Cubit<FavoritesState> {
  FavoritesCubit({
    required WatchAuthUser watchAuthUser,
    required WatchFavorites watchFavorites,
    required this._setFavorite,
    Duration retryDelay = const Duration(seconds: 1),
  }) : super(const FavoritesState({})) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchFavorites.call,
      // Never show the previous user's favourites.
      onUser: (_) {
        const reset = FavoritesState({});
        if (state != reset) emit(reset);
      },
      onData: (ids) => emit(FavoritesState(ids)),
      logTag: 'favorites',
      retryDelay: retryDelay,
    );
  }

  final SetFavorite _setFavorite;
  late final UserStreamFollower<Set<String>> _follower;

  /// Adds or removes [exerciseId] based on the last known favourites. The
  /// change shows up through the favourites stream (immediately, from
  /// Firestore's local cache); only a failure is emitted here.
  Future<void> toggle(String exerciseId) async {
    final uid = _follower.uid;
    if (uid == null) return;
    _follower.resume();
    final result = await _setFavorite((
      uid: uid,
      exerciseId: exerciseId,
      favorite: !state.contains(exerciseId),
    ));
    // A write for a previous user says nothing about the current one.
    if (isClosed || _follower.uid != uid) return;
    if (result.failureOrNull case final failure?) {
      emit(FavoritesState(state.ids, failure: failure));
    }
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    return super.close();
  }
}
