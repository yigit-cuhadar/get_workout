import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/domain/exercise_queries.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/domain/workout_usecases.dart';
import '../domain/strength.dart';

enum StrengthListStatus { loading, ready, failure }

/// An exercise the user has stats for.
class StrengthItem extends Equatable {
  const StrengthItem({
    required this.exerciseId,
    required this.lastTrained,
    this.exercise,
    this.removed = false,
  });

  final String exerciseId;
  final DateTime lastTrained;

  /// From the catalogue, custom exercises included; null once the
  /// exercise is [removed].
  final Exercise? exercise;

  /// No longer in the library (retired, or a deleted custom exercise).
  final bool removed;

  @override
  List<Object?> get props => [exerciseId, lastTrained, exercise, removed];
}

class StrengthListState extends Equatable {
  const StrengthListState({
    this.status = StrengthListStatus.loading,
    this.items = const [],
    this.trainedCount = 0,
    this.query = '',
  });

  final StrengthListStatus status;

  /// The exercises matching [query], most recently trained first.
  final List<StrengthItem> items;

  /// How many exercises have stats, whatever the query.
  final int trainedCount;
  final String query;

  @override
  List<Object?> get props => [status, items, trainedCount, query];
}

/// The exercises whoever is signed in has done, most recently trained
/// first, searchable by name. Loading until every exercise is named or
/// known to be removed. A user change starts over at loading. A failed
/// stream shows as a failure until it delivers again: it is followed again
/// by itself, or at once on [retry].
class StrengthListCubit extends Cubit<StrengthListState> {
  StrengthListCubit({
    required WatchAuthUser watchAuthUser,
    required WatchAllExerciseStats watchAllStats,
    required this._catalogue,
  }) : super(const StrengthListState()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchAllStats.call,
      onUser: (uid) {
        _trained = null;
        _failed = false;
        _publish();
      },
      onData: (stats) {
        _trained = byLastTrained(stats);
        _failed = false;
        _publish();
      },
      onError: (_) {
        _failed = true;
        _publish();
      },
      logTag: 'strength',
    );
    _catalogueSubscription = _catalogue.stream.listen((_) => _publish());
  }

  final ExerciseCatalogueCubit _catalogue;
  late final UserStreamFollower<Map<String, ExerciseStats>> _follower;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  List<TrainedExercise>? _trained;

  /// The stats stream failed and has not delivered since.
  bool _failed = false;
  String _query = '';
  String _language = Exercise.fallbackLanguage;

  /// The language exercise names are searched in.
  void setLanguage(String language) {
    if (language == _language) return;
    _language = language;
    _publish();
  }

  void setQuery(String query) {
    _query = query;
    _publish();
  }

  void retry() {
    _follower.resume();
    if (_catalogue.state is CatalogueFailed) unawaited(_catalogue.retry());
  }

  void _publish() {
    final trained = _trained;
    final catalogue = _catalogue.state;
    if (_failed || catalogue is CatalogueFailed) {
      emit(
        StrengthListState(status: StrengthListStatus.failure, query: _query),
      );
      return;
    }
    final loading = StrengthListState(query: _query);
    if (trained == null || catalogue is! CatalogueReady) {
      emit(loading);
      return;
    }
    final known = {
      for (final exercise in catalogue.exercises) exercise.id: exercise,
    };
    final items = [
      for (final (:exerciseId, :lastTrained) in trained)
        StrengthItem(
          exerciseId: exerciseId,
          lastTrained: lastTrained,
          exercise: known[exerciseId],
          removed: !known.containsKey(exerciseId),
        ),
    ];
    // A custom exercise is not known to be gone before custom ones load.
    if (items.any(
      (item) => item.removed && !catalogue.knows(item.exerciseId),
    )) {
      emit(loading);
      return;
    }
    final matching = _query.trim().isEmpty
        ? null
        : {
            for (final exercise in searchExercises(
              [for (final item in items) ?item.exercise],
              _query,
              language: _language,
            ))
              exercise.id,
          };
    emit(
      StrengthListState(
        status: StrengthListStatus.ready,
        items: [
          for (final item in items)
            if (matching == null || matching.contains(item.exerciseId)) item,
        ],
        trainedCount: items.length,
        query: _query,
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
