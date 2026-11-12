import 'package:forge_core/forge_core.dart';
import 'package:get_it/get_it.dart';

import 'domain/calculators_usecases.dart';

/// Registers the calculators. Pages create their cubits with the user's
/// units, so only the use cases live here. Needs `ProfileModule` and
/// `BodyModule`, whose use cases give the values calculators start from.
class CalculatorsModule implements FeatureModule {
  const CalculatorsModule();

  @override
  void register(GetIt sl) {
    sl
      ..registerFactory(EstimateCalories.new)
      ..registerFactory(EstimateBodyFat.new)
      ..registerFactory(EstimateOneRepMax.new)
      ..registerFactory(LoadPlates.new)
      ..registerFactory(CheckBarWeight.new)
      ..registerFactory(CheckPlate.new)
      ..registerFactory(SplitMacros.new)
      ..registerFactory(CalculateBodyIndices.new)
      ..registerFactory(() => GetKnownBodyValues(sl(), sl()));
  }
}
