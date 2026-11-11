import 'package:forge_core/forge_core.dart';

enum WeightUnit { kg, lb }

enum LengthUnit { cm, inch }

enum ThemePreference { system, light, dark }

/// The user's app preferences. Values are always stored metric; these only
/// choose how they are shown.
class UserSettings extends Equatable {
  const UserSettings({
    required this.weightUnit,
    required this.lengthUnit,
    this.themePreference = ThemePreference.system,
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

  UserSettings copyWith({
    WeightUnit? weightUnit,
    LengthUnit? lengthUnit,
    ThemePreference? themePreference,
  }) => UserSettings(
    weightUnit: weightUnit ?? this.weightUnit,
    lengthUnit: lengthUnit ?? this.lengthUnit,
    themePreference: themePreference ?? this.themePreference,
  );

  @override
  List<Object?> get props => [weightUnit, lengthUnit, themePreference];
}
