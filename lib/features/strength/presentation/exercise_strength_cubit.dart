import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../../core/user_stream_follower.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../programs/domain/program_usecases.dart';
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
    this.sessions = const [],
    this.trained = false,
    this.charted = false,
    this.range = StrengthRange.free,
    this.rangeStart,
    this.olderLocked = false,
    this.loggingType,
  });

  final ExerciseStrengthStatus status;
  final List<RecordEntry> records;

  /// The chart's e1RM points in [range], oldest first.
  final List<E1rmPoint> points;

  /// The workouts in [range] (all of them without a chart), newest first.
  final List<HistoryPoint> sessions;

  /// The exercise has stats; without them there is nothing to show.
  final bool trained;

  /// The exercise has an e1RM in some workout. Without a weight and reps
  /// (bodyweight, timed) it never has, and there is no chart.
  final bool charted;

  /// The range shown: the one chosen, as far as Premium allows.
  final StrengthRange range;

  /// The first day of [range]; for all of it, the first workout's date.
  final DateTime? rangeStart;

  /// A free user has results from before [StrengthRange.free]; tell them
  /// Premium shows those.
  final bool olderLocked;

  /// How the stats were kept, guessed from them (see [loggingTypeOf]) for
  /// an exercise no longer in the library; null without stats.
  final LoggingType? loggingType;

  @override
  List<Object?> get props => [
    status,
    records,
    points,
    sessions,
    trained,
    charted,
    range,
    rangeStart,
    olderLocked,
    loggingType,
  ];
}

/// The records, e1RM chart and sessions of exercise [exerciseId] for
/// whoever is signed in, followed live. Ranges beyond [StrengthRange.free]
/// show only while the user is known to have Premium; the page asks for
/// Premium before choosing one. Stats stored before records kept their set
/// and sessions their best set ([ExerciseStats.outdated]) show at once and
/// are rebuilt from the workouts, once per page.
class ExerciseStrengthCubit extends Cubit<ExerciseStrengthState> {
  ExerciseStrengthCubit({
    required this.exerciseId,
    required WatchAuthUser watchAuthUser,
    required WatchExerciseStats watchStats,
    required WatchPremium watchPremium,
    required this._rebuildStats,
    required this._unit,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(const ExerciseStrengthState()) {
    _follower = UserStreamFollower(
      userIds: watchAuthUser().map((user) => user?.id),
      watch: (uid) => watchStats((uid: uid, exerciseId: exerciseId)),
      onUser: (uid) {
        _uid = uid;
        _loaded = false;
        _stats = null;
        _rebuilt = false;
        _chosen = StrengthRange.free;
        emit(const ExerciseStrengthState());
      },
      onData: (stats) {
        _loaded = true;
        _stats = stats;
        _publish();
        _rebuildIfOutdated();
      },
      onError: (_) {
        _loaded = false;
        emit(
          const ExerciseStrengthState(status: ExerciseStrengthStatus.failure),
        );
      },
      logTag: 'strength',
    );
    _premiumSubscription = watchPremium().listen((premium) {
      _premium = premium;
      _publish();
    });
  }

  final String exerciseId;
  final RebuildExerciseStats _rebuildStats;
  final DateTime Function() _clock;
  late final UserStreamFollower<ExerciseStats?> _follower;
  late final StreamSubscription<bool?> _premiumSubscription;
  WeightUnit _unit;
  String? _uid;
  bool _loaded = false;
  bool _rebuilt = false;
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

  void _rebuildIfOutdated() {
    final uid = _uid;
    if (_rebuilt || uid == null || !(_stats?.outdated ?? false)) return;
    _rebuilt = true;
    unawaited(
      _rebuildStats((uid: uid, exerciseId: exerciseId)).then((result) {
        if (result.failureOrNull case final failure?) {
          Log.e('strength', 'stats not rebuilt: ${failure.message}');
        }
      }),
    );
  }

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
    final charted = stats.history.any((point) => point.bestE1rmKg != null);
    final start = charted ? range.start(now) : null;
    emit(
      ExerciseStrengthState(
        status: ExerciseStrengthStatus.ready,
        records: orderedRecords(stats),
        points: e1rmSeries(stats.history, range: range, now: now, unit: _unit),
        sessions: sessionsFrom(stats.history, start),
        trained: true,
        charted: charted,
        range: range,
        rangeStart: start ?? stats.history.firstOrNull?.date,
        olderLocked:
            charted &&
            _premium == false &&
            hasResultsBefore(
              stats.history,
              range: StrengthRange.free,
              now: now,
            ),
        loggingType: loggingTypeOf(stats),
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
