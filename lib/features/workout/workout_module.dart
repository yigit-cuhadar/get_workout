import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/device_localizations.dart';
import '../programs/domain/completed_days.dart';
import 'data/file_local_workout_store.dart';
import 'data/firestore_workout_repository.dart';
import 'data/workout_completed_days.dart';
import 'domain/workout_repository.dart';
import 'domain/workout_usecases.dart';
import 'presentation/active_workout_cubit.dart';
import 'presentation/rest_timer_cubit.dart';

/// Registers the workout feature. Needs `AuthModule`, `SettingsModule`,
/// `NotificationsModule`, `ExercisesModule` and `ProgramsModule`, which
/// takes [completedDays] for its plan.
class WorkoutModule implements FeatureModule {
  const WorkoutModule();

  /// The program days done, from the stored workouts.
  static CompletedDays completedDays(GetIt _) =>
      WorkoutCompletedDays(FirebaseFirestore.instance);

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
      ..registerFactory(() => LoadLocalWorkouts(sl()))
      ..registerFactory(() => KeepLocalWorkouts(sl()))
      ..registerFactory(() => ConfirmStoredWorkout(sl()))
      ..registerFactory(() => RebuildExerciseStats(sl()))
      ..registerFactory(() => NewWorkoutId(sl()))
      ..registerFactory(() => WatchExerciseStats(sl()))
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
        ),
      )
      ..registerLazySingleton(
        () => RestTimerCubit(
          workout: sl(),
          settings: sl(),
          notifications: sl.getAsync<Notifications>(),
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
        ),
      );
  }
}
