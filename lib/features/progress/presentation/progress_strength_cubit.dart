import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../domain/progress_usecases.dart';

enum ProgressStrengthStatus { loading, ready, failure }

/// One exercise's best estimated one-rep max.
class StrengthTile extends Equatable {
  const StrengthTile({
    required this.exerciseId,
    required this.e1rmKg,
    this.exercise,
  });

  final String exerciseId;
  final double e1rmKg;

  /// From the catalogue; null once the exercise is no longer in it.
  final Exercise? exercise;

  @override
  List<Object?> get props => [exerciseId, e1rmKg, exercise];
}

class ProgressStrengthState extends Equatable {
  const ProgressStrengthState({
    this.status = ProgressStrengthStatus.loading,
    this.tiles = const [],
    this.trained = false,
  });

  final ProgressStrengthStatus status;

  /// Most recently trained first.
  final List<StrengthTile> tiles;

  /// The user has finished a workout, whether or not [tiles] has any.
  final bool trained;

  @override
  List<Object?> get props => [status, tiles, trained];
}

/// The [strengthHighlights] of whoever is signed in, named from the
/// catalogue, for the Progress tab. Loading until every exercise is named
/// or known to be gone; a user change starts over. A failed stream shows
/// as a failure until it delivers again, by itself or at once on [retry].
class ProgressStrengthCubit extends Cubit<ProgressStrengthState> {
  ProgressStrengthCubit({
    required WatchAuthUser watchAuthUser,
    required WatchStrengthHighlights watchHighlights,
    required this._catalogue,
  }) : super(const ProgressStrengthState()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchHighlights.call,
      onUser: (_) {
        _highlights = null;
        _failed = false;
        _publish();
      },
      onData: (highlights) {
        _highlights = highlights;
        _failed = false;
        _publish();
      },
      onError: (_) {
        _failed = true;
        _publish();
      },
      logTag: 'progress',
    );
    _catalogueSubscription = _catalogue.stream.listen((_) => _publish());
  }

  final ExerciseCatalogueCubit _catalogue;
  late final UserStreamFollower<StrengthHighlights> _follower;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  StrengthHighlights? _highlights;
  bool _failed = false;

  void retry() {
    _follower.resume();
    if (_catalogue.state is CatalogueFailed) unawaited(_catalogue.retry());
  }

  void _publish() {
    final highlights = _highlights;
    final catalogue = _catalogue.state;
    if (_failed || catalogue is CatalogueFailed) {
      return emit(
        const ProgressStrengthState(status: ProgressStrengthStatus.failure),
      );
    }
    if (highlights == null || catalogue is! CatalogueReady) {
      return emit(const ProgressStrengthState());
    }
    final known = {
      for (final exercise in catalogue.exercises) exercise.id: exercise,
    };
    // A custom exercise is not known to be gone before those load.
    if (highlights.top.any(
      (h) => !known.containsKey(h.exerciseId) && !catalogue.knows(h.exerciseId),
    )) {
      return emit(const ProgressStrengthState());
    }
    emit(
      ProgressStrengthState(
        status: ProgressStrengthStatus.ready,
        tiles: [
          for (final (:exerciseId, :e1rmKg) in highlights.top)
            StrengthTile(
              exerciseId: exerciseId,
              e1rmKg: e1rmKg,
              exercise: known[exerciseId],
            ),
        ],
        trained: highlights.trained,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    await _catalogueSubscription.cancel();
    return super.close();
  }
}
