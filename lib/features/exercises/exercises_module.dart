import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_exercise_repository.dart';
import 'data/firestore_exercise_source.dart';
import 'domain/exercise_repository.dart';
import 'domain/exercise_usecases.dart';
import 'presentation/exercise_catalogue_cubit.dart';

/// Registers the exercise catalogue. Needs `AuthModule`.
class ExercisesModule implements FeatureModule {
  const ExercisesModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<ExerciseRepository>(
        () => FirestoreExerciseRepository(
          FirestoreExerciseSource(FirebaseFirestore.instance),
        ),
      )
      ..registerFactory(() => WatchExercises(sl()))
      ..registerFactory(() => SyncExercises(sl()))
      ..registerLazySingleton(
        () => ExerciseCatalogueCubit(
          watchAuthUser: sl(),
          watchExercises: sl(),
          syncExercises: sl(),
        ),
      );
  }
}
