import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/firestore_admin_program_repository.dart';
import 'domain/admin_program_repository.dart';
import 'domain/program_admin_usecases.dart';
import 'presentation/program_editor_cubit.dart';
import 'presentation/program_list_cubit.dart';

/// Registers the panel's program list and editor. Needs the exercise
/// module's `WatchExerciseRecords` and the access module's
/// `CheckAdminAccess`.
class ProgramAdminModule implements FeatureModule {
  const ProgramAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<AdminProgramRepository>(
        () => FirestoreAdminProgramRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchProgramCards(sl()))
      ..registerFactory(() => LoadProgramRecord(sl()))
      ..registerFactory(() => CreateProgram(sl()))
      ..registerFactory(() => UpdateProgram(sl()))
      ..registerFactory(() => ProgramListCubit(watchProgramCards: sl()))
      // The id to edit, or null for a new program.
      ..registerFactoryParam<ProgramEditorCubit, String?, void>(
        (id, _) => ProgramEditorCubit(
          id: id,
          loadProgramRecord: sl(),
          watchProgramCards: sl(),
          watchExerciseRecords: sl(),
          createProgram: sl(),
          updateProgram: sl(),
          checkAdminAccess: sl(),
        ),
      );
  }
}
