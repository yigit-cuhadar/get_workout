import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../programs/domain/completed_days.dart';
import 'data/file_local_workout_store.dart';
import 'data/firestore_workout_repository.dart';
import 'data/workout_completed_days.dart';
import 'domain/history_usecases.dart';
import 'domain/workout_repository.dart';
import 'domain/workout_usecases.dart';
import 'presentation/active_workout_cubit.dart';
import 'presentation/history_list_cubit.dart';
import 'presentation/workout_detail_cubit.dart';
import 'presentation/workout_edit_cubit.dart';

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
      ..registerFactory(() => WatchHistory(sl()))
      ..registerFactory(() => WatchStoredWorkout(sl()))
      ..registerFactory(() => WatchRejectedWorkoutEdits(sl()))
      ..registerFactory(() => SaveWorkoutChange(sl()))
      // One history for the whole app: the list and the workout pages share
      // it, and it reports refused edits wherever they happened.
      ..registerLazySingleton(
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
