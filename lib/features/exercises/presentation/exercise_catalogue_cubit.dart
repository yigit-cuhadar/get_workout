import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../domain/exercise.dart';
import '../domain/exercise_queries.dart';
import '../domain/exercise_usecases.dart';

sealed class ExerciseCatalogueState extends Equatable {
  const ExerciseCatalogueState();

  @override
  List<Object?> get props => [];
}

/// No list yet; the first sync is pending or running.
final class CatalogueLoading extends ExerciseCatalogueState {
  const CatalogueLoading();
}

final class CatalogueReady extends ExerciseCatalogueState {
  const CatalogueReady(this.exercises, {this.customLoaded = true});

  /// Live exercises and the signed-in user's custom ones, by popularity.
  /// Stays after a later sync fails.
  final List<Exercise> exercises;

  /// Whether [exercises] hold the signed-in user's custom exercises. False
  /// right after a user change and while their stream fails; until it turns
  /// true, a missing custom id is not known to be gone.
  final bool customLoaded;

  /// Whether [exercises] knows if exercise [id] exists.
  bool knows(String id) => customLoaded || !Exercise.isCustomId(id);

  @override
  List<Object?> get props => [exercises, customLoaded];
}

/// The first sync failed and nothing is cached: there is nothing to show.
final class CatalogueFailed extends ExerciseCatalogueState {
  const CatalogueFailed(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

/// The exercise catalogue for the whole app, with the custom exercises of
/// whoever is signed in merged in, so everything listing exercises lists
/// those too. A change of user drops the previous user's at once.
///
/// The first list waits for the user's custom exercises (they come from
/// the local cache, so this is quick), or for their stream to fail; it is
/// then published without them, [CatalogueReady.customLoaded] false, while
/// the stream is retried.
///
/// Syncs once a user is signed in (the rules require a session, guests
/// included), on [retry], and when the app returns to the foreground at most
/// once per [resyncInterval].
class ExerciseCatalogueCubit extends Cubit<ExerciseCatalogueState> {
  ExerciseCatalogueCubit({
    required WatchAuthUser watchAuthUser,
    required WatchExercises watchExercises,
    required WatchCustomExercises watchCustomExercises,
    required this._syncExercises,
    this.resyncInterval = const Duration(minutes: 5),
    this._now = DateTime.now,
    Duration retryDelay = const Duration(seconds: 1),
  }) : super(const CatalogueLoading()) {
    _exercisesSubscription = watchExercises().listen((exercises) {
      _catalogue = exercises;
      _publish();
    });
    _customFollower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchCustomExercises.call,
      onUser: (uid) {
        _custom = const [];
        // Nobody signed in has none.
        _customLoaded = uid == null;
        _customFailed = false;
        _publish();
      },
      onData: (custom) {
        _custom = custom;
        _customLoaded = true;
        _publish();
      },
      onError: (_) {
        _customFailed = true;
        _publish();
      },
      logTag: 'customExercises',
      retryDelay: retryDelay,
    );
    _userSubscription = watchAuthUser()
        .where((user) => user != null)
        .take(1)
        .listen((_) {
          _signedIn = true;
          unawaited(_sync());
        });
  }

  final SyncExercises _syncExercises;
  final Duration resyncInterval;
  final DateTime Function() _now;
  late final StreamSubscription<List<Exercise>> _exercisesSubscription;
  late final UserStreamFollower<List<Exercise>> _customFollower;
  late final StreamSubscription<Object?> _userSubscription;
  List<Exercise>? _catalogue;
  List<Exercise> _custom = const [];
  bool _customLoaded = true;
  bool _customFailed = false;
  bool _signedIn = false;
  DateTime? _lastSync;

  /// Custom exercises alone are no catalogue: they wait for it. A first
  /// list waits for them too, unless their stream failed.
  void _publish() {
    final catalogue = _catalogue;
    if (catalogue == null || isClosed) return;
    if (!_customLoaded && !_customFailed && state is! CatalogueReady) return;
    emit(
      CatalogueReady(
        withCustomExercises(catalogue, _custom),
        customLoaded: _customLoaded,
      ),
    );
  }

  Future<void> retry() {
    _customFollower.resume();
    return _signedIn ? _sync() : Future.value();
  }

  /// Call when the app returns to the foreground.
  Future<void> appResumed() {
    final last = _lastSync;
    if (!_signedIn ||
        (last != null && _now().difference(last) < resyncInterval)) {
      return Future.value();
    }
    return _sync();
  }

  Future<void> _sync() async {
    _lastSync = _now();
    if (state is CatalogueFailed) emit(const CatalogueLoading());
    final failure = (await _syncExercises()).failureOrNull;
    // With a list on screen, a failed sync changes nothing; the repository
    // logs it.
    if (failure != null && !isClosed && state is! CatalogueReady) {
      emit(CatalogueFailed(failure));
    }
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _customFollower.cancel();
    await _exercisesSubscription.cancel();
    return super.close();
  }
}
