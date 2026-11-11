import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_exercise_repository.dart';
import 'data/firestore_exercise_source.dart';
import 'domain/exercise_repository.dart';
import 'domain/exercise_usecases.dart';

/// Registers the exercise catalogue and syncs it once the first session is
/// known, without holding up startup. Needs `AuthModule`.
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
      ..registerFactory(() => SyncExercises(sl()));
    unawaited(_syncOnFirstSession(sl));
  }

  /// The rules let only signed-in users, guests included, read exercises.
  static Future<void> _syncOnFirstSession(GetIt sl) async {
    final watchAuthUser = sl<WatchAuthUser>();
    await watchAuthUser().firstWhere((user) => user != null);
    // A failure is logged by the repository; the next sync retries.
    await sl<SyncExercises>()();
  }
}
