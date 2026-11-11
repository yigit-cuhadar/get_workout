import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/exercise.dart';
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
  const CatalogueReady(this.exercises);

  /// Live exercises by popularity. Stays after a later sync fails.
  final List<Exercise> exercises;

  @override
  List<Object?> get props => [exercises];
}

/// The first sync failed and nothing is cached: there is nothing to show.
final class CatalogueFailed extends ExerciseCatalogueState {
  const CatalogueFailed(this.failure);

  final Failure failure;

  @override
  List<Object?> get props => [failure];
}

/// The exercise catalogue for the whole app. Syncs once a user is signed in
/// (the rules require a session, guests included), on [retry], and when the
/// app returns to the foreground at most once per [resyncInterval].
class ExerciseCatalogueCubit extends Cubit<ExerciseCatalogueState> {
  ExerciseCatalogueCubit({
    required WatchAuthUser watchAuthUser,
    required WatchExercises watchExercises,
    required this._syncExercises,
    this.resyncInterval = const Duration(minutes: 5),
    this._now = DateTime.now,
  }) : super(const CatalogueLoading()) {
    _exercisesSubscription = watchExercises().listen(
      (exercises) => emit(CatalogueReady(exercises)),
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
  late final StreamSubscription<Object?> _userSubscription;
  bool _signedIn = false;
  DateTime? _lastSync;

  Future<void> retry() => _signedIn ? _sync() : Future.value();

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
    await _exercisesSubscription.cancel();
    return super.close();
  }
}
