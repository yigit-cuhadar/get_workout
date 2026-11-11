import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../exercises/presentation/library_cubit.dart';
import '../settings/domain/user_settings.dart';
import 'data/firestore_program_repository.dart';
import 'data/no_completed_days.dart';
import 'domain/completed_days.dart';
import 'domain/program_repository.dart';
import 'domain/program_usecases.dart';
import 'presentation/exercise_picker_cubit.dart';
import 'presentation/program_builder_cubit.dart';
import 'presentation/program_detail_cubit.dart';
import 'presentation/program_list_cubit.dart';

/// Registers the programs feature. Needs `AuthModule` and `ExercisesModule`.
class ProgramsModule implements FeatureModule {
  const ProgramsModule();

  /// The exercise picker's own [LibraryCubit], so picking never changes the
  /// Exercises tab's search and filters.
  static const pickerLibrary = 'exercisePicker';

  @override
  void register(GetIt sl) {
    // A module registered earlier (the workout feature) may provide the real
    // one.
    if (!sl.isRegistered<CompletedDays>()) {
      sl.registerLazySingleton<CompletedDays>(() => const NoCompletedDays());
    }
    sl
      ..registerLazySingleton<ProgramRepository>(
        () => FirestoreProgramRepository(FirebaseFirestore.instance),
      )
      ..registerFactory(() => WatchPrograms(sl()))
      ..registerFactory(() => WatchActiveProgram(sl()))
      ..registerFactory(() => WatchRejectedProgramWrites(sl()))
      ..registerFactory(() => WatchCompletedDays(sl()))
      ..registerFactory(() => GetProgram(sl()))
      ..registerFactory(() => SaveProgram(sl()))
      ..registerFactory(() => DuplicateProgram(sl()))
      ..registerFactory(() => DeleteProgram(sl()))
      ..registerFactory(() => StartProgram(sl()))
      ..registerFactory(() => ChangeWeekdays(sl()))
      ..registerFactory(() => StopProgram(sl()))
      // One list for the whole app: the tab and the program pages share it.
      ..registerLazySingleton(
        () => ProgramListCubit(
          watchAuthUser: sl(),
          watchPrograms: sl(),
          watchActiveProgram: sl(),
          watchCompletedDays: sl(),
          watchRejectedWrites: sl(),
        ),
      )
      ..registerFactoryParam<ProgramDetailCubit, String, void>(
        (programId, _) => ProgramDetailCubit(
          programId,
          list: sl(),
          startProgram: sl(),
          changeWeekdays: sl(),
          stopProgram: sl(),
          duplicateProgram: sl(),
          deleteProgram: sl(),
          getCurrentUser: sl(),
          watchAuthUser: sl(),
        ),
      )
      ..registerFactoryParam<ProgramBuilderCubit, String?, WeightUnit>(
        (programId, unit) => ProgramBuilderCubit(
          programId: programId,
          getProgram: sl(),
          saveProgram: sl(),
          getCurrentUser: sl(),
          watchAuthUser: sl(),
          catalogue: sl(),
          weightUnit: unit,
        ),
      )
      ..registerFactoryParam<ExercisePickerCubit, int, bool>(
        (max, multiple) => ExercisePickerCubit(max: max, multiple: multiple),
      )
      ..registerFactory(
        () => LibraryCubit(
          watchAuthUser: sl(),
          catalogue: sl(),
          favorites: sl(),
          equipment: sl(),
        ),
        instanceName: pickerLibrary,
      );
  }
}
