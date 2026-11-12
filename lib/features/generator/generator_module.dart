import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'domain/generator_answers.dart';
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
      ..registerFactory(GenerateProgram.new)
      ..registerFactoryParam<GeneratorQuestionsCubit, GeneratorPrefill, void>(
        (prefill, _) => GeneratorQuestionsCubit(prefill),
      )
      ..registerFactoryParam<GeneratorPreviewCubit, GeneratorAnswers, void>(
        (answers, _) => GeneratorPreviewCubit(
          answers,
          catalogue: sl(),
          generateProgram: sl(),
          saveProgram: sl(),
          getCurrentUser: sl(),
        ),
      );
  }
}
