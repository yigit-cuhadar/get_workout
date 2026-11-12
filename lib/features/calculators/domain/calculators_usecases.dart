import '../../body/domain/body_entry.dart';
import '../../body/domain/body_usecases.dart';
import '../../profile/domain/profile_usecases.dart';
import '../../profile/domain/user_profile.dart';
import '../../settings/domain/user_settings.dart';
import 'body_fat.dart';
import 'body_indices.dart';
import 'calculation.dart';
import 'calories.dart';
import 'known_body_values.dart';
import 'macros.dart';
import 'one_rep_max.dart';
import 'plates.dart';

// Calculators are pure and synchronous, so these are plain callables rather
// than the async `UseCase`, like `WatchSettings`.

class EstimateCalories {
  const EstimateCalories();

  Calculation<CalorieEstimate> call({
    required Sex sex,
    required double weightKg,
    required double heightCm,
    required double ageYears,
    required ActivityLevel activity,
  }) => estimateCalories(
    sex: sex,
    weightKg: weightKg,
    heightCm: heightCm,
    ageYears: ageYears,
    activity: activity,
  );
}

class EstimateBodyFat {
  const EstimateBodyFat();

  Calculation<double> call({
    required Sex sex,
    required double heightCm,
    required double neckCm,
    required double waistCm,
    double? hipCm,
  }) => estimateBodyFat(
    sex: sex,
    heightCm: heightCm,
    neckCm: neckCm,
    waistCm: waistCm,
    hipCm: hipCm,
  );
}

class EstimateOneRepMax {
  const EstimateOneRepMax();

  Calculation<OneRepMax> call({
    required double weightKg,
    required int reps,
    required double incrementKg,
  }) => estimateOneRepMax(
    weightKg: weightKg,
    reps: reps,
    incrementKg: incrementKg,
  );
}

class LoadPlates {
  const LoadPlates();

  Calculation<PlateLoad> call({
    required double targetKg,
    required double barKg,
    required List<Plate> plates,
  }) => loadPlates(targetKg: targetKg, barKg: barKg, plates: plates);
}

class CheckBarWeight {
  const CheckBarWeight();

  Calculation<double> call(double kg) => checkBarWeight(kg);
}

class CheckPlate {
  const CheckPlate();

  Calculation<Plate> call({required double weightKg, required int pairs}) =>
      checkPlate(weightKg: weightKg, pairs: pairs);
}

class SplitMacros {
  const SplitMacros();

  Calculation<Macros> call({
    required double calories,
    required double weightKg,
    required double proteinGPerKg,
    required double fatPercent,
  }) => splitMacros(
    calories: calories,
    weightKg: weightKg,
    proteinGPerKg: proteinGPerKg,
    fatPercent: fatPercent,
  );
}

class CalculateBodyIndices {
  const CalculateBodyIndices();

  Calculation<BodyIndices> call({
    required double weightKg,
    required double heightCm,
    double? bodyFatPercent,
  }) => calculateBodyIndices(
    weightKg: weightKg,
    heightCm: heightCm,
    bodyFatPercent: bodyFatPercent,
  );
}

/// What a user's profile and body entries already say, for
/// the calculators to start from. Both are read once, at the same time; a
/// source that cannot be read adds nothing, so this never fails.
class GetKnownBodyValues {
  GetKnownBodyValues(
    this._watchProfile,
    this._watchEntries, {
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;
  final WatchProfile _watchProfile;
  final WatchBodyEntries _watchEntries;
  final DateTime Function() _clock;

  Future<KnownBodyValues> call(String uid) async {
    final (profile, entries) = await (
      _firstOr(_watchProfile(uid), const UserProfile()),
      _firstOr(_watchEntries(uid), const <BodyEntry>[]),
    ).wait;
    return knownBodyValues(
      profile: profile,
      entries: entries,
      currentYear: _clock().year,
    );
  }

  static Future<T> _firstOr<T>(Stream<T> stream, T fallback) async {
    try {
      return await stream.first;
    } on Object {
      return fallback;
    }
  }
}
