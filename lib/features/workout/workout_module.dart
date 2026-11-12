import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/device_localizations.dart';
import '../programs/domain/completed_days.dart';
import 'data/android_workout_lock_screen.dart';
import 'data/device_rest_notifications.dart';
import 'data/file_local_workout_store.dart';
import 'data/firestore_workout_repository.dart';
import 'data/ios_workout_lock_screen.dart';
import 'data/workout_completed_days.dart';
import 'domain/history_usecases.dart';
import 'domain/rest_notifications.dart';
import 'domain/rest_usecases.dart';
import 'domain/workout_lock_screen.dart';
import 'domain/workout_repository.dart';
import 'domain/workout_usecases.dart';
import 'presentation/active_workout_cubit.dart';
import 'presentation/history_list_cubit.dart';
import 'presentation/rest_timer_cubit.dart';
import 'presentation/workout_detail_cubit.dart';
import 'presentation/workout_edit_cubit.dart';

/// Registers the workout feature. Needs `AuthModule`, `SettingsModule`,
/// `NotificationsModule`, `ExercisesModule` and `ProgramsModule`, which
/// takes [completedDays] for its plan.
class WorkoutModule implements FeatureModule {
  const WorkoutModule();

  /// The program days done, from the stored workouts.
  static CompletedDays completedDays(GetIt sl) => WorkoutCompletedDays(sl());

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<WorkoutRepository>(
        () => FirestoreWorkoutRepository(FirebaseFirestore.instance),
      )
      // App support files are private and not shown to the user.
      ..registerLazySingleton<LocalWorkoutStore>(
        () => FileLocalWorkoutStore(getApplicationSupportDirectory),
      )
      ..registerLazySingleton<RestNotifications>(
        () => DeviceRestNotifications(
          sl.getAsync<Notifications>(),
          getApplicationSupportDirectory,
        ),
      )
      ..registerLazySingleton<WorkoutLockScreen>(
        () => defaultTargetPlatform == TargetPlatform.iOS
            ? const IosWorkoutLockScreen()
            : AndroidWorkoutLockScreen(sl.getAsync<Notifications>()),
      )
      ..registerFactory(() => ShowWorkoutOnLockScreen(sl()))
      ..registerFactory(() => ClearWorkoutFromLockScreen(sl()))
      ..registerFactory(() => WatchLockScreenTaps(sl()))
      ..registerFactory(() => ShouldAskRestNotifications(sl()))
      ..registerFactory(() => AllowRestNotifications(sl()))
      ..registerFactory(() => DeclineRestNotifications(sl()))
      ..registerFactory(() => ScheduleRestNotification(sl()))
      ..registerFactory(() => CancelRestNotification(sl()))
      ..registerFactory(() => LoadLocalWorkouts(sl()))
      ..registerFactory(() => KeepLocalWorkouts(sl()))
      ..registerFactory(() => ConfirmStoredWorkout(sl()))
      ..registerFactory(() => RebuildExerciseStats(sl()))
      ..registerFactory(() => NewWorkoutId(sl()))
      ..registerFactory(() => WatchExerciseStats(sl()))
      ..registerFactory(() => WatchAllExerciseStats(sl()))
      ..registerFactory(() => FinishWorkout(sl()))
      ..registerFactory(() => SaveWorkoutAsProgram(sl()))
      // One workout in progress for the whole app.
      ..registerLazySingleton(
        () => ActiveWorkoutCubit(
          watchAuthUser: sl(),
          loadLocal: sl(),
          keepLocal: sl(),
          confirmStored: sl(),
          rebuildStats: sl(),
          newWorkoutId: sl(),
          watchStats: sl(),
          finishWorkout: sl(),
          saveAsProgram: sl(),
          programs: sl(),
          catalogue: sl(),
          watchSettings: sl(),
        ),
      )
      ..registerLazySingleton(
        () => RestTimerCubit(
          workout: sl(),
          settings: sl(),
          shouldAsk: sl(),
          allow: sl(),
          decline: sl(),
          schedule: sl(),
          cancel: sl(),
          text: (workout, next) {
            final l10n = deviceLocalizations();
            return (
              title: l10n.restOver,
              body: next == null
                  ? l10n.restNotificationBack
                  : l10n.restNotificationNext(
                      workout.exercises[next.exercise].name,
                      next.set + 1,
                    ),
            );
          },
          showOnLockScreen: sl(),
          clearLockScreen: sl(),
          lockScreenText: (workout, next) {
            final l10n = deviceLocalizations();
            final rest = l10n.restLockScreenTitle;
            if (next == null) {
              return (current: null, rest: rest, afterRest: null);
            }
            final exercise = workout.exercises[next.exercise];
            return (
              current: l10n.workoutLockScreenCurrent(
                exercise.name,
                next.set + 1,
                exercise.sets.length,
              ),
              rest: rest,
              afterRest: l10n.restNotificationNext(exercise.name, next.set + 1),
            );
          },
        ),
      )
      ..registerFactory(() => WatchHistory(sl()))
      ..registerFactory(() => WatchWorkoutsBetween(sl()))
      ..registerFactory(() => WatchStoredWorkout(sl()))
      ..registerFactory(() => WatchRejectedWorkoutEdits(sl()))
      ..registerFactory(() => SaveWorkoutChange(sl()))
      // One per history page. The workout pages open above it, so it is
      // there to report their refused edits.
      ..registerFactory(
        () => HistoryListCubit(
          watchAuthUser: sl(),
          watchHistory: sl(),
          watchRejectedEdits: sl(),
        ),
      )
      ..registerFactoryParam<WorkoutDetailCubit, String, void>(
        (id, _) => WorkoutDetailCubit(
          id: id,
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          watchWorkout: sl(),
          saveChange: sl(),
          changed: sl<ActiveWorkoutCubit>().storedWorkoutChanged,
        ),
      )
      // A stored workout's id, or none and the name of a new past workout.
      ..registerFactoryParam<WorkoutEditCubit, String?, String>(
        (id, name) => WorkoutEditCubit(
          id: id,
          name: name,
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          watchWorkout: sl(),
          newWorkoutId: sl(),
          saveChange: sl(),
          changed: sl<ActiveWorkoutCubit>().storedWorkoutChanged,
          catalogue: sl(),
        ),
      );
  }
}
