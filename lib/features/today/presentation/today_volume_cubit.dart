import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/calendar_date.dart';
import '../../volume/domain/volume_usecases.dart';
import '../../volume/domain/weekly_volume.dart';

enum TodayVolumeStatus { loading, ready, failure }

class TodayVolumeState extends Equatable {
  const TodayVolumeState({
    required this.weekStart,
    this.status = TodayVolumeStatus.loading,
    this.week,
    this.failure,
  });

  /// The first day of the current week.
  final CalendarDate weekStart;
  final TodayVolumeStatus status;

  /// Set once ready.
  final WeekVolume? week;
  final Failure? failure;

  @override
  List<Object?> get props => [weekStart, status, week, failure];
}

/// This week's sets per muscle of whoever is signed in, for the Today
/// card: `WatchWeeklyVolume` with one week, never the trend. Weeks start
/// on ISO weekday [firstWeekday], the app's. Follows the library
/// like the volume page; drops everything on a user change.
class TodayVolumeCubit extends Cubit<TodayVolumeState> {
  TodayVolumeCubit({
    required int firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchVolume,
    required ExerciseCatalogueCubit catalogue,
    DateTime Function()? clock,
  }) : _firstWeekday = firstWeekday,
       _clock = clock ?? DateTime.now,
       super(TodayVolumeState(weekStart: _weekStart(firstWeekday, clock))) {
    _muscles = _musclesOf(catalogue.state);
    _catalogueSubscription = catalogue.stream.listen((state) {
      _muscles = _musclesOf(state);
      _follow(keep: true);
    });
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          _uid = uid;
          _follow();
        });
  }

  int _firstWeekday;
  int get firstWeekday => _firstWeekday;
  final WatchWeeklyVolume _watchVolume;
  final DateTime Function() _clock;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<List<WeekVolume>>? _volumeSubscription;
  Map<String, ExerciseMuscles> _muscles = const {};
  String? _uid;
  int _generation = 0;

  static CalendarDate _weekStart(
    int firstWeekday,
    DateTime Function()? clock,
  ) => CalendarDate.of((clock ?? DateTime.now)()).startOfWeek(firstWeekday);

  /// Until the library is loaded, the muscles stored with each workout
  /// count.
  static Map<String, ExerciseMuscles> _musclesOf(
    ExerciseCatalogueState state,
  ) => switch (state) {
    CatalogueReady(:final exercises) => {
      for (final exercise in exercises)
        exercise.id: (
          main: exercise.mainMuscles,
          secondary: exercise.secondaryMuscles,
        ),
    },
    _ => const {},
  };

  /// Follows the new week once the current one has ended.
  void refreshNow() {
    if (_weekStart(_firstWeekday, _clock) != state.weekStart) _follow();
  }

  /// Starts the week on [firstWeekday] from now on.
  void changeFirstWeekday(int firstWeekday) {
    if (firstWeekday == _firstWeekday) return;
    _firstWeekday = firstWeekday;
    _follow();
  }

  /// Follows the week again after a failure.
  void retry() {
    if (state.status == TodayVolumeStatus.failure) _follow();
  }

  /// With [keep] the week on screen stays until it is read again, so a
  /// library update does not flash the card.
  void _follow({bool keep = false}) {
    unawaited(_volumeSubscription?.cancel());
    _volumeSubscription = null;
    final generation = ++_generation;
    final weekStart = _weekStart(_firstWeekday, _clock);
    final loading = TodayVolumeState(weekStart: weekStart);
    final kept =
        keep &&
        state.status == TodayVolumeStatus.ready &&
        state.weekStart == weekStart;
    if (!kept && state != loading) emit(loading);
    final uid = _uid;
    if (uid == null) return;
    _volumeSubscription =
        _watchVolume((
          uid: uid,
          lastWeek: weekStart,
          weeks: 1,
          muscles: _muscles,
        )).listen(
          (weeks) {
            // A stream already left may still deliver.
            if (generation != _generation) return;
            emit(
              TodayVolumeState(
                weekStart: weekStart,
                status: TodayVolumeStatus.ready,
                week: weeks.single,
              ),
            );
          },
          onError: (Object error) {
            if (generation != _generation) return;
            emit(
              TodayVolumeState(
                weekStart: weekStart,
                status: TodayVolumeStatus.failure,
                failure: error is Failure
                    ? error
                    : UnknownFailure('$error', error),
              ),
            );
          },
        );
  }

  @override
  Future<void> close() async {
    await _userSubscription.cancel();
    await _catalogueSubscription.cancel();
    await _volumeSubscription?.cancel();
    return super.close();
  }
}
