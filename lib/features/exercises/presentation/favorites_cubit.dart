import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise_usecases.dart';

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
    required this._watchFavorites,
    required this._setFavorite,
  }) : super(const FavoritesState({})) {
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen(_onUser);
  }

  final WatchFavorites _watchFavorites;
  final SetFavorite _setFavorite;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<Set<String>>? _favoritesSubscription;
  String? _uid;

  void _onUser(String? uid) {
    _uid = uid;
    unawaited(_favoritesSubscription?.cancel());
    // Never show the previous user's favourites.
    const reset = FavoritesState({});
    if (state != reset) emit(reset);
    _favoritesSubscription = uid == null
        ? null
        : _watchFavorites(uid).listen(
            (ids) => emit(FavoritesState(ids)),
            // The repository logs it; the last known favourites stay.
            onError: (Object _) {},
          );
  }

  /// The change shows up through the favourites stream (immediately, from
  /// Firestore's local cache); only a failure is emitted here.
  Future<void> toggle(String exerciseId) async {
    final uid = _uid;
    if (uid == null) return;
    final result = await _setFavorite((
      uid: uid,
      exerciseId: exerciseId,
      favorite: !state.contains(exerciseId),
    ));
    final failure = result.failureOrNull;
    if (failure != null && !isClosed) {
      emit(FavoritesState(state.ids, failure: failure));
    }
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _favoritesSubscription?.cancel();
    return super.close();
  }
}
