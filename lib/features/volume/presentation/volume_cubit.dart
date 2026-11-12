import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/calendar_date.dart';
import '../domain/volume_usecases.dart';
import '../domain/weekly_volume.dart';

enum VolumeStatus { loading, ready, failure }

class VolumeState extends Equatable {
  const VolumeState({
    required this.week,
    required this.thisWeek,
    this.status = VolumeStatus.loading,
    this.weeks = const [],
    this.failure,
  });

  /// The first day of the week shown.
  final CalendarDate week;

  /// The first day of the current week; no week after it is shown.
  final CalendarDate thisWeek;
  final VolumeStatus status;

  /// When ready, the [trendWeeks] weeks ending with [week], oldest first.
  final List<WeekVolume> weeks;
  final Failure? failure;

  /// The week shown, once ready.
  WeekVolume? get shown => weeks.lastOrNull;

  bool get isThisWeek => week == thisWeek;
  bool get hasNext => week.isBefore(thisWeek);

  @override
  List<Object?> get props => [week, thisWeek, status, weeks, failure];
}

/// The weekly sets per muscle of whoever is signed in, one week at a time
/// with the [trendWeeks] before it. Weeks start on ISO weekday
/// [firstWeekday], as the locale does. Starts at the current week and
/// never goes past it. Follows the library, so muscles changed there count
/// at once; resets to loading on every user change.
class VolumeCubit extends Cubit<VolumeState> {
  VolumeCubit({
    required this.firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchVolume,
    required ExerciseCatalogueCubit catalogue,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(_initial(firstWeekday, clock ?? DateTime.now)) {
    _muscles = _musclesOf(catalogue.state);
    _catalogueSubscription = catalogue.stream.listen((state) {
      _muscles = _musclesOf(state);
      _follow(keepShown: true);
    });
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          _uid = uid;
          _follow();
        });
  }

  final int firstWeekday;
  final WatchWeeklyVolume _watchVolume;
  final DateTime Function() _clock;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  late final StreamSubscription<String?> _userSubscription;
  StreamSubscription<List<WeekVolume>>? _volumeSubscription;
  Map<String, ExerciseMuscles> _muscles = const {};
  String? _uid;

  static VolumeState _initial(int firstWeekday, DateTime Function() clock) {
    final thisWeek = CalendarDate.of(clock()).startOfWeek(firstWeekday);
    return VolumeState(week: thisWeek, thisWeek: thisWeek);
  }

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

  void previousWeek() => _show(state.week.addDays(-DateTime.daysPerWeek));

  void nextWeek() {
    if (state.hasNext) _show(state.week.addDays(DateTime.daysPerWeek));
  }

  /// Follows the workouts again after a failure.
  void retry() {
    if (state.status == VolumeStatus.failure) _follow();
  }

  void _show(CalendarDate week) {
    final thisWeek = CalendarDate.of(_clock()).startOfWeek(firstWeekday);
    emit(
      VolumeState(
        week: week.isAfter(thisWeek) ? thisWeek : week,
        thisWeek: thisWeek,
      ),
    );
    _follow();
  }

  /// With [keepShown] the weeks on screen stay until the new ones arrive.
  void _follow({bool keepShown = false}) {
    unawaited(_volumeSubscription?.cancel());
    _volumeSubscription = null;
    final loading = VolumeState(week: state.week, thisWeek: state.thisWeek);
    if (state != loading &&
        !(keepShown && state.status == VolumeStatus.ready)) {
      emit(loading);
    }
    final uid = _uid;
    if (uid == null) return;
    _volumeSubscription =
        _watchVolume((
          uid: uid,
          lastWeek: state.week,
          weeks: trendWeeks,
          muscles: _muscles,
        )).listen(
          (weeks) => emit(
            VolumeState(
              week: state.week,
              thisWeek: state.thisWeek,
              status: VolumeStatus.ready,
              weeks: weeks,
            ),
          ),
          onError: (Object error) => emit(
            VolumeState(
              week: state.week,
              thisWeek: state.thisWeek,
              status: VolumeStatus.failure,
              failure: error is Failure
                  ? error
                  : UnknownFailure('$error', error),
            ),
          ),
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
