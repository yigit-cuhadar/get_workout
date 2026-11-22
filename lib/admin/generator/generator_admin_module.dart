import 'package:cloud_functions/cloud_functions.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import '../../app/functions_region.dart';
import '../shell/unload_guard.dart';
import 'data/callable_generator_rules_repository.dart';
import 'domain/generator_rules_repository.dart';
import 'domain/generator_rules_usecases.dart';
import 'presentation/generator_rules_cubit.dart';

/// Registers the panel's Generator page. Needs the access module's
/// `CheckAdminAccess`.
class GeneratorAdminModule implements FeatureModule {
  const GeneratorAdminModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerLazySingleton<GeneratorRulesRepository>(
        () => CallableGeneratorRulesRepository(
          FirebaseFunctions.instanceFor(region: functionsRegion),
        ),
      )
      ..registerLazySingleton<UnloadGuard>(platformUnloadGuard)
      ..registerFactory(() => LoadGeneratorRules(sl()))
      ..registerFactory(() => CheckGeneratorRules(sl()))
      ..registerFactory(() => PublishGeneratorRules(sl()))
      ..registerFactory(() => LoadGeneratorRulesHistory(sl()))
      ..registerFactory(
        () => GeneratorRulesCubit(
          loadGeneratorRules: sl(),
          checkGeneratorRules: sl(),
          publishGeneratorRules: sl(),
          loadGeneratorRulesHistory: sl(),
          checkAdminAccess: sl(),
        ),
      );
  }
}
