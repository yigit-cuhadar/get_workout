import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_model_viewer/forge_model_viewer.dart';
import 'package:get_it/get_it.dart';

import '../analytics/domain/analytics.dart';
import 'data/firestore_custom_exercise_repository.dart';
import 'data/firestore_exercise_repository.dart';
import 'data/firestore_exercise_source.dart';
import 'data/firestore_user_library_repository.dart';
import 'domain/custom_exercise.dart';
import 'domain/custom_exercise_repository.dart';
import 'domain/exercise_repository.dart';
import 'domain/exercise_usecases.dart';
import '../profile/domain/user_profile.dart';
import 'domain/user_library_repository.dart';
import 'presentation/body_model_cubit.dart';
import 'presentation/custom_exercise_form_cubit.dart';
import 'presentation/custom_write_rejections_cubit.dart';
import 'presentation/equipment_cubit.dart';
import 'presentation/exercise_catalogue_cubit.dart';
import 'presentation/exercise_detail_cubit.dart';
import 'presentation/exercise_notes_cubit.dart';
import 'presentation/favorites_cubit.dart';
import 'presentation/library_cubit.dart';

/// Registers the exercise catalogue, the library, and the user's custom
/// exercises, equipment and favourites. Needs `AuthModule`.
class ExercisesModule implements FeatureModule {
  const ExercisesModule();

  static String _bodyModelAsset(Sex sex) => switch (sex) {
    Sex.male => 'assets/models/body_male.glb',
    Sex.female => 'assets/models/body_female.glb',
  };

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
      ..registerLazySingleton<CustomExerciseRepository>(
        () => FirestoreCustomExerciseRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchExercises(sl()))
      ..registerFactory(() => SyncExercises(sl()))
      ..registerFactory(() => GetExerciseAnimation(sl()))
      ..registerFactory(() => WatchOwnedEquipment(sl()))
      ..registerFactory(() => SaveOwnedEquipment(sl()))
      ..registerFactory(() => WatchFavorites(sl()))
      ..registerFactory(() => SetFavorite(sl()))
      ..registerFactory(() => WatchExerciseNotes(sl()))
      ..registerFactory(() => SetExerciseNote(sl()))
      ..registerFactory(() => WatchCustomExercises(sl()))
      ..registerFactory(() => WatchRejectedCustomExerciseWrites(sl()))
      ..registerFactory(() => SaveCustomExercise(sl()))
      ..registerFactory(() => DeleteCustomExercise(sl()))
      ..registerLazySingleton(
        () => ExerciseCatalogueCubit(
          watchAuthUser: sl(),
          watchExercises: sl(),
          watchCustomExercises: sl(),
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
        () => ExerciseNotesCubit(
          watchAuthUser: sl(),
          watchExerciseNotes: sl(),
          setExerciseNote: sl(),
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
          loadModel: (sex) => rootBundle
              .load(_bodyModelAsset(sex))
              .then((data) => Model3D.fromGlb(data.buffer.asUint8List())),
          watchAuthUser: sl(),
          watchProfile: sl(),
        ),
      )
      ..registerLazySingleton(
        () => LibraryCubit(
          watchAuthUser: sl(),
          catalogue: sl(),
          favorites: sl(),
          equipment: sl(),
          analytics: sl(),
        ),
      )
      ..registerLazySingleton(() => CustomWriteRejectionsCubit(sl()))
      ..registerFactoryParam<ExerciseDetailCubit, String, ExerciseViewSource>(
        (exerciseId, from) => ExerciseDetailCubit(
          exerciseId,
          from: from,
          analytics: sl(),
          catalogue: sl(),
          equipment: sl(),
          getCurrentUser: sl(),
          deleteCustomExercise: sl(),
        ),
      )
      ..registerFactoryParam<CustomExerciseFormCubit, CustomExercise?, void>(
        (exercise, _) => CustomExerciseFormCubit(
          saveExercise: sl(),
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          analytics: sl(),
          initial: exercise,
        ),
      );
  }
}
