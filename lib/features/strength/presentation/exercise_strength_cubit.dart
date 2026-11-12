import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../programs/domain/premium_status.dart';
import '../../settings/domain/user_settings.dart';
import '../../workout/domain/exercise_stats.dart';
import '../../workout/domain/workout_usecases.dart';
import '../domain/strength.dart';

enum ExerciseStrengthStatus { loading, ready, failure }

class ExerciseStrengthState extends Equatable {
  const ExerciseStrengthState({
    this.status = ExerciseStrengthStatus.loading,
    this.records = const [],
    this.points = const [],
    this.trained = false,
    this.range = StrengthRange.free,
    this.olderLocked = false,
  });

  final ExerciseStrengthStatus status;
  final List<RecordEntry> records;

  /// The chart's e1RM points in [range], oldest first.
  final List<E1rmPoint> points;

  /// The exercise has stats; without them there is nothing to show.
  final bool trained;

  /// The range shown: the one chosen, as far as Premium allows.
  final StrengthRange range;

  /// A free user has e1RM results from before [StrengthRange.free]; tell
  /// them Premium shows those.
  final bool olderLocked;

  @override
  List<Object?> get props => [
    status,
    records,
    points,
    trained,
    range,
    olderLocked,
  ];
}

/// The records and e1RM chart of exercise [exerciseId] for whoever is
/// signed in, followed live. Ranges beyond [StrengthRange.free] show only
/// while the user is known to have Premium; the page asks for Premium
/// before choosing one.
class ExerciseStrengthCubit extends Cubit<ExerciseStrengthState> {
  ExerciseStrengthCubit({
    required this.exerciseId,
    required WatchAuthUser watchAuthUser,
    required WatchExerciseStats watchStats,
    required PremiumStatus premium,
    required this._unit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const ExerciseStrengthState()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: (uid) => watchStats((uid: uid, exerciseId: exerciseId)),
      onUser: (_) {
        _loaded = false;
        _stats = null;
        _chosen = StrengthRange.free;
        emit(const ExerciseStrengthState());
      },
      onData: (stats) {
        _loaded = true;
        _stats = stats;
        _publish();
      },
      onError: (_) {
        _loaded = false;
        emit(
          const ExerciseStrengthState(status: ExerciseStrengthStatus.failure),
        );
      },
      logTag: 'strength',
    );
    _premiumSubscription = premium.watch().listen((premium) {
      _premium = premium;
      _publish();
    });
  }

  final String exerciseId;
  final DateTime Function() _clock;
  late final UserStreamFollower<ExerciseStats?> _follower;
  late final StreamSubscription<bool?> _premiumSubscription;
  WeightUnit _unit;
  bool _loaded = false;
  ExerciseStats? _stats;
  bool? _premium;
  StrengthRange _chosen = StrengthRange.free;

  /// Shows [range]; a Premium one only once the user is known to have
  /// Premium, which may be after the paywall closed.
  void selectRange(StrengthRange range) {
    _chosen = range;
    _publish();
  }

  void setUnit(WeightUnit unit) {
    if (unit == _unit) return;
    _unit = unit;
    _publish();
  }

  void retry() => _follower.resume();

  void _publish() {
    if (!_loaded) return;
    final stats = _stats;
    final range = _chosen.allowed(_premium);
    if (stats == null) {
      emit(
        ExerciseStrengthState(
          status: ExerciseStrengthStatus.ready,
          range: range,
        ),
      );
      return;
    }
    final now = _clock();
    emit(
      ExerciseStrengthState(
        status: ExerciseStrengthStatus.ready,
        records: orderedRecords(stats),
        points: e1rmSeries(stats.history, range: range, now: now, unit: _unit),
        trained: true,
        range: range,
        olderLocked:
            _premium == false &&
            hasE1rmBefore(stats.history, range: StrengthRange.free, now: now),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _follower.cancel();
    await _premiumSubscription.cancel();
    return super.close();
  }
}
