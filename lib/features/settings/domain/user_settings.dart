import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../programs/domain/calendar_date.dart';

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

  /// A lifted weight stored as [kg], as the user sees it in this unit: see
  /// [shown].
  double shownFromKg(double kg) => shown(fromKg(kg));

  /// A lifted weight in this unit as the user sees it. On the entry grid
  /// (two decimals, what weight fields write back) it was typed in this unit
  /// and shows as typed; otherwise it was typed in the other unit and shows
  /// rounded, to whole lb or to half kg. Only for display: stored weights
  /// never change.
  double shown(double value) {
    final hundredths = value * 100;
    // Float noise of a kg round trip is far below this; a weight typed in
    // the other unit lands this close to the grid about once in a million.
    if ((hundredths - hundredths.round()).abs() < 1e-6) {
      return hundredths.round() / 100;
    }
    return switch (this) {
      WeightUnit.kg => (value * 2).round() / 2,
      WeightUnit.lb => value.roundToDouble(),
    };
  }
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

/// A local time of day, in minutes after midnight, for reminders.
abstract final class ReminderTime {
  static const max = 24 * 60 - 1;
}

/// The reminder on the active program's training days
/// (`settings.reminders.workout`).
class WorkoutReminderSettings extends Equatable {
  const WorkoutReminderSettings({this.enabled = false, this.minute = 8 * 60});

  final bool enabled;

  /// Minutes after local midnight, 0 to [ReminderTime.max].
  final int minute;

  WorkoutReminderSettings copyWith({bool? enabled, int? minute}) =>
      WorkoutReminderSettings(
        enabled: enabled ?? this.enabled,
        minute: minute ?? this.minute,
      );

  @override
  List<Object?> get props => [enabled, minute];
}

/// The reminder to log weight and measurements
/// (`settings.reminders.measurement`): every [everyWeeks] weeks from
/// [from], which also gives its weekday.
class MeasurementReminderSettings extends Equatable {
  const MeasurementReminderSettings({
    this.enabled = false,
    this.everyWeeks = 4,
    this.from,
    this.minute = 9 * 60,
  });

  final bool enabled;
  final int everyWeeks;

  /// The first date of the series; null until the reminder is turned on.
  final CalendarDate? from;

  /// Minutes after local midnight, 0 to [ReminderTime.max].
  final int minute;

  /// What the settings offer for [everyWeeks].
  static const choicesWeeks = [1, 2, 4];

  MeasurementReminderSettings copyWith({
    bool? enabled,
    int? everyWeeks,
    CalendarDate? from,
    int? minute,
  }) => MeasurementReminderSettings(
    enabled: enabled ?? this.enabled,
    everyWeeks: everyWeeks ?? this.everyWeeks,
    from: from ?? this.from,
    minute: minute ?? this.minute,
  );

  @override
  List<Object?> get props => [enabled, everyWeeks, from, minute];
}

/// The daily step goal (`settings.stepGoal`) the user can choose.
abstract final class StepGoal {
  static const standard = 10000;
  static const min = 1000;
  static const max = 50000;

  /// The editor moves in these steps.
  static const step = 500;
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
    this.stepGoal = StepGoal.standard,
    this.workoutReminder = const WorkoutReminderSettings(),
    this.measurementReminder = const MeasurementReminderSettings(),
    this.customBarWeightKg,
    this.customPlates,
    this.customTrackedMeasurements,
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

  /// Steps a day, within [StepGoal.min] and [StepGoal.max].
  final int stepGoal;

  final WorkoutReminderSettings workoutReminder;
  final MeasurementReminderSettings measurementReminder;

  /// Set once the user edits their bar; until then [barWeightKg] follows
  /// [weightUnit], so switching units also switches the standard bar.
  final double? customBarWeightKg;

  /// Set once the user edits their plates; see [customBarWeightKg].
  final List<Plate>? customPlates;

  /// What a measurement day asks for, once the user has chosen; until
  /// then a default that depends on the profile's sex.
  final Set<BodyMeasurement>? customTrackedMeasurements;

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
    int? stepGoal,
    WorkoutReminderSettings? workoutReminder,
    MeasurementReminderSettings? measurementReminder,
    double? customBarWeightKg,
    List<Plate>? customPlates,
    Set<BodyMeasurement>? customTrackedMeasurements,
  }) => UserSettings(
    weightUnit: weightUnit ?? this.weightUnit,
    lengthUnit: lengthUnit ?? this.lengthUnit,
    themePreference: themePreference ?? this.themePreference,
    effortScale: effortScale ?? this.effortScale,
    restTimer: restTimer ?? this.restTimer,
    stepGoal: stepGoal ?? this.stepGoal,
    workoutReminder: workoutReminder ?? this.workoutReminder,
    measurementReminder: measurementReminder ?? this.measurementReminder,
    customBarWeightKg: customBarWeightKg ?? this.customBarWeightKg,
    customPlates: customPlates ?? this.customPlates,
    customTrackedMeasurements:
        customTrackedMeasurements ?? this.customTrackedMeasurements,
  );

  /// Drops the custom bar and plates, back to the standard set of the unit.
  UserSettings withStandardEquipment() => UserSettings(
    weightUnit: weightUnit,
    lengthUnit: lengthUnit,
    themePreference: themePreference,
    effortScale: effortScale,
    restTimer: restTimer,
    stepGoal: stepGoal,
    customTrackedMeasurements: customTrackedMeasurements,
    workoutReminder: workoutReminder,
    measurementReminder: measurementReminder,
  );

  @override
  List<Object?> get props => [
    weightUnit,
    lengthUnit,
    themePreference,
    effortScale,
    restTimer,
    stepGoal,
    workoutReminder,
    measurementReminder,
    customBarWeightKg,
    customPlates,
    customTrackedMeasurements,
  ];
}
