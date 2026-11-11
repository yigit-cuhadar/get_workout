import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_admin_exercise_repository.dart';
import 'domain/admin_exercise_repository.dart';
import 'domain/exercise_admin_usecases.dart';
import 'presentation/exercise_editor_cubit.dart';
import 'presentation/exercise_list_cubit.dart';

/// Registers the panel's exercise list and editor.
class ExerciseAdminModule implements FeatureModule {
  const ExerciseAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AdminExerciseRepository>(
        () => FirestoreAdminExerciseRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchExerciseRecords(sl()))
      ..registerFactory(() => LoadExerciseRecord(sl()))
      ..registerFactory(() => CreateExercise(sl()))
      ..registerFactory(() => UpdateExercise(sl()))
      ..registerFactory(() => ExerciseListCubit(watchExerciseRecords: sl()))
      // The id to edit, or null for a new exercise.
      ..registerFactoryParam<ExerciseEditorCubit, String?, void>(
        (id, _) => ExerciseEditorCubit(
          id: id,
          loadExerciseRecord: sl(),
          watchExerciseRecords: sl(),
          createExercise: sl(),
          updateExercise: sl(),
          checkAdminAccess: sl(),
        ),
      );
  }
}
