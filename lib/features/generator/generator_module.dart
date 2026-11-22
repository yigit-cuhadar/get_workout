import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'data/server_generator_repository.dart';
import 'domain/generator_answers.dart';
import 'domain/generator_repository.dart';
import 'domain/generator_usecases.dart';
import 'presentation/generator_preview_cubit.dart';
import 'presentation/generator_questions_cubit.dart';

/// Registers the program generator. Needs `AuthModule`, `ExercisesModule`
/// and `ProgramsModule`, whose `SaveProgram` stores what it makes.
class GeneratorModule implements FeatureModule {
  const GeneratorModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<GeneratorRepository>(
        () => ServerGeneratorRepository(
          FirebaseFunctions.instanceFor(
            region: ServerGeneratorRepository.region,
          ),
          FirebaseFirestore.instance,
        ),
      )
      ..registerFactory(() => GenerateProgram(sl()))
      ..registerFactory(() => WatchGeneratorOptions(sl()))
      ..registerFactoryParam<GeneratorQuestionsCubit, GeneratorPrefill, void>(
        (prefill, _) => GeneratorQuestionsCubit(prefill, watchOptions: sl()),
      )
      // The second parameter is the language the program is named in.
      ..registerFactoryParam<GeneratorPreviewCubit, GeneratorAnswers, String>(
        (answers, language) => GeneratorPreviewCubit(
          answers,
          language: language,
          catalogue: sl(),
          generateProgram: sl(),
          saveProgram: sl(),
          getCurrentUser: sl(),
          analytics: sl(),
        ),
      );
  }
}
