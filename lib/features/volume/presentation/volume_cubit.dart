import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program_usecases.dart';
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

  /// The weeks on screen, oldest first: [week] alone, or with Premium the
  /// [trendWeeks] ending with it. While loading, those of the week shown
  /// before, if any, so the page keeps them until the new ones arrive.
  final List<WeekVolume> weeks;
  final Failure? failure;

  /// The week on screen; see [weeks].
  WeekVolume? get shown => weeks.lastOrNull;

  /// Whether [weeks] hold the trend of the week shown.
  bool get hasTrend =>
      status == VolumeStatus.ready && weeks.length == trendWeeks;

  bool get isThisWeek => week == thisWeek;
  bool get hasNext => week.isBefore(thisWeek);

  @override
  List<Object?> get props => [week, thisWeek, status, weeks, failure];
}

/// The weekly sets per muscle of whoever is signed in, one week at a time,
/// with Premium together with the [trendWeeks] ending with it (read again
/// when Premium comes or goes). Weeks start on ISO weekday [firstWeekday],
/// as the locale does. Starts at the current week and never goes past it.
/// Follows the library, so muscles changed there count at once; drops
/// everything on a user change.
class VolumeCubit extends Cubit<VolumeState> {
  VolumeCubit({
    required this.firstWeekday,
    required WatchAuthUser watchAuthUser,
    required this._watchVolume,
    required ExerciseCatalogueCubit catalogue,
    required WatchPremium watchPremium,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       super(_initial(firstWeekday, clock ?? DateTime.now)) {
    _muscles = _musclesOf(catalogue.state);
    _catalogueSubscription = catalogue.stream.listen((state) {
      _muscles = _musclesOf(state);
      _follow();
    });
    _premiumSubscription = watchPremium()
        .map((premium) => premium ?? false)
        .distinct()
        .listen((premium) {
          if (premium == _premium) return;
          _premium = premium;
          _follow();
        });
    _userSubscription = watchAuthUser()
        .map((user) => user?.id)
        .distinct()
        .listen((uid) {
          _uid = uid;
          _follow(keep: false);
        });
  }

  final int firstWeekday;
  final WatchWeeklyVolume _watchVolume;
  final DateTime Function() _clock;
  late final StreamSubscription<ExerciseCatalogueState> _catalogueSubscription;
  late final StreamSubscription<String?> _userSubscription;
  late final StreamSubscription<bool> _premiumSubscription;
  StreamSubscription<List<WeekVolume>>? _volumeSubscription;
  Map<String, ExerciseMuscles> _muscles = const {};
  String? _uid;

  /// Only Premium reads the trend; everyone else reads the week alone.
  bool _premium = false;
  int _generation = 0;

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
    if (state.status == VolumeStatus.failure) _follow(keep: false);
  }

  void _show(CalendarDate week) {
    final thisWeek = CalendarDate.of(_clock()).startOfWeek(firstWeekday);
    _follow(week: week.isAfter(thisWeek) ? thisWeek : week, thisWeek: thisWeek);
  }

  /// Follows [week] (by default the one shown). With [keep] the weeks on
  /// screen stay while the new ones load, so the model is not rebuilt; a
  /// change of user drops them.
  void _follow({CalendarDate? week, CalendarDate? thisWeek, bool keep = true}) {
    unawaited(_volumeSubscription?.cancel());
    _volumeSubscription = null;
    final generation = ++_generation;
    final shown = week ?? state.week;
    final current = thisWeek ?? state.thisWeek;
    final kept = keep && state.status != VolumeStatus.failure
        ? state.weeks
        : const <WeekVolume>[];
    final loading = VolumeState(week: shown, thisWeek: current, weeks: kept);
    if (state != loading) emit(loading);
    final uid = _uid;
    if (uid == null) return;
    _volumeSubscription =
        _watchVolume((
          uid: uid,
          lastWeek: shown,
          weeks: _premium ? trendWeeks : 1,
          muscles: _muscles,
        )).listen(
          (weeks) {
            // A stream already left may still deliver.
            if (generation != _generation) return;
            emit(
              VolumeState(
                week: shown,
                thisWeek: current,
                status: VolumeStatus.ready,
                weeks: weeks,
              ),
            );
          },
          onError: (Object error) {
            if (generation != _generation) return;
            emit(
              VolumeState(
                week: shown,
                thisWeek: current,
                status: VolumeStatus.failure,
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
    await _premiumSubscription.cancel();
    await _volumeSubscription?.cancel();
    return super.close();
  }
}
