import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/program_usecases.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/domain/workout_usecases.dart';
import '../domain/progress_usecases.dart';

enum ProgressStrengthStatus { loading, ready, failure }

class ProgressStrengthState extends Equatable {
  const ProgressStrengthState({
    this.status = ProgressStrengthStatus.loading,
    this.highlight,
    this.exercise,
    this.trained = false,
  });

  final ProgressStrengthStatus status;

  /// The most recently trained exercise with an estimated one-rep max.
  final StrengthHighlight? highlight;

  /// [highlight]'s exercise from the catalogue; null once it is no longer
  /// in it.
  final Exercise? exercise;

  /// The user has finished a workout, whether or not there is a
  /// [highlight].
  final bool trained;

  @override
  List<Object?> get props => [status, highlight, exercise, trained];
}

/// The [strengthHighlight] of whoever is signed in over [cardWeeks] (again
/// when Premium comes or goes), named from the catalogue, for the Progress
/// tab. Loading until its exercise is named or known to be gone; a user
/// change starts over. A failed stream shows as a failure until it
/// delivers again, by itself or at once on [retry].
class ProgressStrengthCubit extends Cubit<ProgressStrengthState> {
  ProgressStrengthCubit({
    required WatchAuthUser watchAuthUser,
    required WatchAllExerciseStats watchStats,
    required WatchPremium watchPremium,
    required this._catalogue,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const ProgressStrengthState()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: watchStats.call,
      onUser: (_) {
        _stats = null;
        _failed = false;
        _publish();
      },
      onData: (stats) {
        _stats = stats;
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
    _premiumSubscription = watchPremium().listen((premium) {
      _premium = premium;
      _publish();
    });
  }

  final ExerciseCatalogueCubit _catalogue;
  final DateTime Function() _clock;
  late final UserStreamFollower<Map<String, ExerciseStats>> _follower;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  late final StreamSubscription<bool?> _premiumSubscription;
  Map<String, ExerciseStats>? _stats;
  bool? _premium;
  bool _failed = false;

  void retry() {
    _follower.resume();
    if (_catalogue.state is CatalogueFailed) unawaited(_catalogue.retry());
  }

  void _publish() {
    final stats = _stats;
    final catalogue = _catalogue.state;
    if (_failed || catalogue is CatalogueFailed) {
      return emit(
        const ProgressStrengthState(status: ProgressStrengthStatus.failure),
      );
    }
    if (stats == null || catalogue is! CatalogueReady) {
      return emit(const ProgressStrengthState());
    }
    final highlight = strengthHighlight(
      stats,
      now: _clock(),
      weeks: cardWeeks(_premium),
    );
    final id = highlight?.exerciseId;
    final exercise = catalogue.exercises.where((e) => e.id == id).firstOrNull;
    // A custom exercise is not known to be gone before those load.
    if (id != null && exercise == null && !catalogue.knows(id)) {
      return emit(const ProgressStrengthState());
    }
    emit(
      ProgressStrengthState(
        status: ProgressStrengthStatus.ready,
        highlight: highlight,
        exercise: exercise,
        trained: stats.isNotEmpty,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    await _catalogueSubscription.cancel();
    await _premiumSubscription.cancel();
    return super.close();
  }
}
