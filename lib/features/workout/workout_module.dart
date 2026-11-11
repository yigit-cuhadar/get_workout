import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../programs/domain/completed_days.dart';
import 'data/file_active_workout_store.dart';
import 'data/firestore_workout_repository.dart';
import 'data/workout_completed_days.dart';
import 'domain/workout_repository.dart';
import 'domain/workout_usecases.dart';
import 'presentation/active_workout_cubit.dart';

/// Registers the workout feature. Needs `AuthModule`, `ExercisesModule` and
/// `ProgramsModule`, which takes [completedDays] for its plan.
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
      ..registerLazySingleton<ActiveWorkoutStore>(
        () => FileActiveWorkoutStore(getApplicationSupportDirectory),
      )
      ..registerFactory(() => LoadActiveWorkout(sl()))
      ..registerFactory(() => KeepActiveWorkout(sl()))
      ..registerFactory(() => ClearActiveWorkout(sl()))
      ..registerFactory(() => NewWorkoutId(sl()))
      ..registerFactory(() => WatchExerciseStats(sl()))
      ..registerFactory(() => WatchRejectedWorkoutWrites(sl()))
      ..registerFactory(() => FinishWorkout(sl()))
      ..registerFactory(() => SaveWorkoutAsProgram(sl()))
      // One workout in progress for the whole app.
      ..registerLazySingleton(
        () => ActiveWorkoutCubit(
          watchAuthUser: sl(),
          loadActiveWorkout: sl(),
          keepActiveWorkout: sl(),
          clearActiveWorkout: sl(),
          newWorkoutId: sl(),
          watchStats: sl(),
          finishWorkout: sl(),
          saveAsProgram: sl(),
          completeProgramDay: sl(),
          watchRejectedWrites: sl(),
          programs: sl(),
          catalogue: sl(),
        ),
      );
  }
}
