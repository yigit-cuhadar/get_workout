import 'package:forge_core/forge_core.dart';

enum WeightUnit { kg, lb }

enum LengthUnit { cm, inch }

enum ThemePreference { system, light, dark }

/// How effort is asked for per set, if at all. Always stored as reps in
/// reserve (RIR); RPE is shown as `10 - RIR`.
enum EffortScale { off, rir, rpe }

const kgPerLb = 0.45359237;
const cmPerInch = 2.54;

extension WeightUnitConversion on WeightUnit {
  double toKg(double value) => switch (this) {
    WeightUnit.kg => value,
    WeightUnit.lb => value * kgPerLb,
  };

  double fromKg(double kg) => switch (this) {
    WeightUnit.kg => kg,
    WeightUnit.lb => kg / kgPerLb,
  };
}

extension LengthUnitConversion on LengthUnit {
  double toCm(double value) => switch (this) {
    LengthUnit.cm => value,
    LengthUnit.inch => value * cmPerInch,
  };

  double fromCm(double cm) => switch (this) {
    LengthUnit.cm => cm,
    LengthUnit.inch => cm / cmPerInch,
  };
}

/// Limits of the bar and plate inventory. They keep the plate calculator's
/// search bounded and let 0.25 lb (0.113 kg) change plates in.
const maxBarWeightKg = 100.0;
const minPlateWeightKg = 0.1;
const maxPlateWeightKg = 100.0;
const maxPlateSizes = 12;
const maxPlatePairs = 20;

/// One plate size the user can load, and how many pairs of it they have.
class Plate extends Equatable {
  const Plate({required this.weightKg, required this.pairs});

  final double weightKg;
  final int pairs;

  @override
  List<Object?> get props => [weightKg, pairs];
}

/// The rest timer (`settings.restTimer`).
class RestTimerSettings extends Equatable {
  const RestTimerSettings({
    this.enabled = true,
    this.defaultS = 90,
    this.notify,
  });

  /// Whether ticking a set starts a rest.
  final bool enabled;

  /// The rest when neither the program nor the exercise gives one.
  final int defaultS;

  /// Whether a notification says when a rest is over while the app is in
  /// the background; null until the user has been asked.
  final bool? notify;

  static const minS = 15;
  static const maxS = 600;

  /// What the settings page offers for [defaultS].
  static const choicesS = [30, 45, 60, 90, 120, 150, 180, 240, 300];

  RestTimerSettings copyWith({bool? enabled, int? defaultS, bool? notify}) =>
      RestTimerSettings(
        enabled: enabled ?? this.enabled,
        defaultS: defaultS ?? this.defaultS,
        notify: notify ?? this.notify,
      );

  @override
  List<Object?> get props => [enabled, defaultS, notify];
}

/// The user's app preferences. Values are always stored metric; these only
/// choose how they are shown.
class UserSettings extends Equatable {
  const UserSettings({
    required this.weightUnit,
    required this.lengthUnit,
    this.themePreference = ThemePreference.system,
    this.effortScale = EffortScale.off,
    this.restTimer = const RestTimerSettings(),
    this.customBarWeightKg,
    this.customPlates,
  });

  /// Imperial for the countries that use it day to day, metric elsewhere.
  factory UserSettings.defaultsFor(String? countryCode) {
    final imperial = _imperialCountries.contains(countryCode?.toUpperCase());
    return UserSettings(
      weightUnit: imperial ? WeightUnit.lb : WeightUnit.kg,
      lengthUnit: imperial ? LengthUnit.inch : LengthUnit.cm,
    );
  }

  static const _imperialCountries = {'US', 'LR', 'MM'};

  final WeightUnit weightUnit;
  final LengthUnit lengthUnit;
  final ThemePreference themePreference;
  final EffortScale effortScale;
  final RestTimerSettings restTimer;

  /// Set once the user edits their bar; until then [barWeightKg] follows
  /// [weightUnit], so switching units also switches the standard bar.
  final double? customBarWeightKg;

  /// Set once the user edits their plates; see [customBarWeightKg].
  final List<Plate>? customPlates;

  double get barWeightKg => customBarWeightKg ?? defaultBarWeightKg(weightUnit);

  /// Largest first.
  List<Plate> get plates => customPlates ?? defaultPlates(weightUnit);

  static double defaultBarWeightKg(WeightUnit unit) => switch (unit) {
    WeightUnit.kg => 20,
    WeightUnit.lb => 45 * kgPerLb,
  };

  static List<Plate> defaultPlates(WeightUnit unit) => switch (unit) {
    WeightUnit.kg => const [
      Plate(weightKg: 25, pairs: 4),
      Plate(weightKg: 20, pairs: 1),
      Plate(weightKg: 15, pairs: 1),
      Plate(weightKg: 10, pairs: 1),
      Plate(weightKg: 5, pairs: 1),
      Plate(weightKg: 2.5, pairs: 1),
      Plate(weightKg: 1.25, pairs: 1),
    ],
    WeightUnit.lb => [
      for (final (lb, pairs) in const [
        (45.0, 4),
        (35.0, 1),
        (25.0, 1),
        (10.0, 2),
        (5.0, 1),
        (2.5, 1),
      ])
        Plate(weightKg: lb * kgPerLb, pairs: pairs),
    ],
  };

  UserSettings copyWith({
    WeightUnit? weightUnit,
    LengthUnit? lengthUnit,
    ThemePreference? themePreference,
    EffortScale? effortScale,
    RestTimerSettings? restTimer,
    double? customBarWeightKg,
    List<Plate>? customPlates,
  }) => UserSettings(
    weightUnit: weightUnit ?? this.weightUnit,
    lengthUnit: lengthUnit ?? this.lengthUnit,
    themePreference: themePreference ?? this.themePreference,
    effortScale: effortScale ?? this.effortScale,
    restTimer: restTimer ?? this.restTimer,
    customBarWeightKg: customBarWeightKg ?? this.customBarWeightKg,
    customPlates: customPlates ?? this.customPlates,
  );

  /// Drops the custom bar and plates, back to the standard set of the unit.
  UserSettings withStandardEquipment() => UserSettings(
    weightUnit: weightUnit,
    lengthUnit: lengthUnit,
    themePreference: themePreference,
    effortScale: effortScale,
    restTimer: restTimer,
  );

  @override
  List<Object?> get props => [
    weightUnit,
    lengthUnit,
    themePreference,
    effortScale,
    restTimer,
    customBarWeightKg,
    customPlates,
  ];
}
