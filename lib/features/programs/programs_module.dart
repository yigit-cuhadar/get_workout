import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../exercises/presentation/library_cubit.dart';
import '../settings/domain/user_settings.dart';
import '../settings/presentation/first_weekday.dart';
import 'data/firestore_catalogue_repository.dart';
import 'data/firestore_program_repository.dart';
import 'data/no_completed_days.dart';
import 'domain/catalogue_repository.dart';
import 'domain/completed_days.dart';
import 'domain/premium_status.dart';
import 'domain/program_repository.dart';
import 'domain/program_usecases.dart';
import 'presentation/add_to_program_cubit.dart';
import 'presentation/catalogue_detail_cubit.dart';
import 'presentation/exercise_picker_cubit.dart';
import 'presentation/program_builder_cubit.dart';
import 'presentation/program_detail_cubit.dart';
import 'presentation/premium_prompt.dart';
import 'presentation/program_catalogue_cubit.dart';
import 'presentation/program_list_cubit.dart';

/// Registers the programs feature and the ready-made programs. Needs
/// `AuthModule`, `ProfileModule` and `ExercisesModule`.
class ProgramsModule implements FeatureModule {
  const ProgramsModule({
    this.completedDays = nothingDone,
    required this.premium,
    required this.showPremium,
  });

  /// Builds what reports the program days done; the workout feature passes
  /// its own in bootstrap.
  final CompletedDays Function(GetIt sl) completedDays;

  /// Builds what reports whether the user has premium: the subscription
  /// feature's, passed in bootstrap.
  final PremiumStatus Function(GetIt sl) premium;

  /// What a premium call to action does: the subscription feature's
  /// paywall, passed in bootstrap.
  final void Function(BuildContext context) showPremium;

  /// Reports nothing done.
  static CompletedDays nothingDone(GetIt _) => const NoCompletedDays();

  /// The exercise picker's own [LibraryCubit], so picking never changes the
  /// Exercises tab's search and filters.
  static const pickerLibrary = 'exercisePicker';

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<CompletedDays>(() => completedDays(sl))
      ..registerLazySingleton<PremiumStatus>(() => premium(sl))
      ..registerSingleton(PremiumPrompt(showPremium))
      ..registerLazySingleton<CatalogueRepository>(
        () => FirestoreCatalogueRepository(FirebaseFirestore.instance),
      )
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
      ..registerFactory(() => ResolveMissedDay(sl()))
      ..registerFactory(() => WatchCatalogue(sl()))
      ..registerFactory(() => GetCatalogueDays(sl()))
      ..registerFactory(() => WatchPremium(sl()))
      // One list for the whole app: the tab and the program pages share it.
      ..registerLazySingleton(
        () => ProgramListCubit(
          firstWeekday: currentFirstWeekday(sl()),
          watchAuthUser: sl(),
          watchPrograms: sl(),
          watchActiveProgram: sl(),
          watchCompletedDays: sl(),
          watchRejectedWrites: sl(),
          resolveMissedDay: sl(),
          watchPremium: sl(),
        ),
      )
      // One catalogue for the whole app, keeping its filters.
      ..registerLazySingleton(
        () => ProgramCatalogueCubit(
          watchAuthUser: sl(),
          watchCatalogue: sl(),
          watchPremium: sl(),
          profile: sl(),
          equipment: sl(),
        ),
      )
      ..registerFactoryParam<CatalogueDetailCubit, String, String>(
        (programId, language) => CatalogueDetailCubit(
          programId,
          language: language,
          catalogue: sl(),
          list: sl(),
          exercises: sl(),
          getDays: sl(),
          saveProgram: sl(),
          getCurrentUser: sl(),
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
      ..registerFactory(() => AddExerciseToProgram(sl()))
      ..registerFactory(
        () => AddToProgramCubit(
          list: sl(),
          addExercise: sl(),
          catalogue: sl(),
          getCurrentUser: sl(),
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
