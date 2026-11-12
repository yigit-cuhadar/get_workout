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

  /// From the catalogue, custom exercises included; null while it is not
  /// known and once the exercise is [removed].
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
/// first, searchable by name. A user change starts over at loading; a
/// failed stream is followed again by itself, or at once on [retry].
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
        emit(const StrengthListState());
      },
      onData: (stats) {
        _trained = byLastTrained(stats);
        _publish();
      },
      onError: (_) => emit(
        StrengthListState(status: StrengthListStatus.failure, query: _query),
      ),
      logTag: 'strength',
    );
    _catalogueSubscription = _catalogue.stream.listen((_) => _publish());
  }

  final ExerciseCatalogueCubit _catalogue;
  late final UserStreamFollower<Map<String, ExerciseStats>> _follower;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  List<TrainedExercise>? _trained;
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

  void retry() => _follower.resume();

  void _publish() {
    final trained = _trained;
    if (trained == null) {
      if (state.query != _query) {
        emit(StrengthListState(status: state.status, query: _query));
      }
      return;
    }
    final catalogue = _catalogue.state;
    final known = catalogue is CatalogueReady
        ? {for (final exercise in catalogue.exercises) exercise.id: exercise}
        : const <String, Exercise>{};
    final items = [
      for (final (:exerciseId, :lastTrained) in trained)
        StrengthItem(
          exerciseId: exerciseId,
          lastTrained: lastTrained,
          exercise: known[exerciseId],
          removed:
              catalogue is CatalogueReady &&
              catalogue.knows(exerciseId) &&
              !known.containsKey(exerciseId),
        ),
    ];
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
