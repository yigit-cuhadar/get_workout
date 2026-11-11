import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_exercise_repository.dart';
import 'data/firestore_exercise_source.dart';
import 'data/firestore_user_library_repository.dart';
import 'domain/exercise_repository.dart';
import 'domain/exercise_usecases.dart';
import 'domain/user_library_repository.dart';
import 'presentation/body_model_cubit.dart';
import 'presentation/equipment_cubit.dart';
import 'presentation/exercise_catalogue_cubit.dart';
import 'presentation/exercise_detail_cubit.dart';
import 'presentation/favorites_cubit.dart';
import 'presentation/library_cubit.dart';

/// Registers the exercise catalogue, the library and the user's equipment
/// and favourites. Needs `AuthModule`.
class ExercisesModule implements FeatureModule {
  const ExercisesModule();

  static const _bodyModelAsset = 'assets/models/body_male.glb';

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<ExerciseRepository>(
        () => FirestoreExerciseRepository(
          FirestoreExerciseSource(FirebaseFirestore.instance),
        ),
      )
      ..registerLazySingleton<UserLibraryRepository>(
        () => FirestoreUserLibraryRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchExercises(sl()))
      ..registerFactory(() => SyncExercises(sl()))
      ..registerFactory(() => WatchOwnedEquipment(sl()))
      ..registerFactory(() => SaveOwnedEquipment(sl()))
      ..registerFactory(() => WatchFavorites(sl()))
      ..registerFactory(() => SetFavorite(sl()))
      ..registerLazySingleton(
        () => ExerciseCatalogueCubit(
          watchAuthUser: sl(),
          watchExercises: sl(),
          syncExercises: sl(),
        ),
      )
      ..registerLazySingleton(
        () => FavoritesCubit(
          watchAuthUser: sl(),
          watchFavorites: sl(),
          setFavorite: sl(),
        ),
      )
      ..registerLazySingleton(
        () => EquipmentCubit(
          watchAuthUser: sl(),
          watchEquipment: sl(),
          saveEquipment: sl(),
        ),
      )
      ..registerLazySingleton(
        () => BodyModelCubit(
          () => rootBundle
              .load(_bodyModelAsset)
              .then((data) => Model3D.fromGlb(data.buffer.asUint8List())),
        ),
      )
      ..registerLazySingleton(
        () => LibraryCubit(catalogue: sl(), favorites: sl(), equipment: sl()),
      )
      ..registerFactoryParam<ExerciseDetailCubit, String, void>(
        (exerciseId, _) =>
            ExerciseDetailCubit(exerciseId, catalogue: sl(), equipment: sl()),
      );
  }
}
