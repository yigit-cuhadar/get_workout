import 'package:forge_core/forge_core.dart';

import '../../body/domain/body_entry.dart';
import '../../programs/domain/calendar_date.dart';

enum WeightUnit { kg, lb }

enum LengthUnit { cm, inch }

enum ThemePreference { system, light, dark }

/// How a set's effort is shown and picked. Always stored as reps in reserve
/// (RIR) whichever is shown; see `EffortScaleSteps`.
enum EffortScale { byFeel, rir, rpe }

/// The first day of the week everywhere in the app (`settings.weekStart`).
enum WeekStart {
  /// The phone's: the locale's first day of the week.
  automatic,
  monday,
  sunday,
  saturday;

  /// The first day of the week as an ISO weekday (1 Monday to 7 Sunday);
  /// [localeFirstWeekday] when [automatic].
  int firstWeekday(int localeFirstWeekday) => switch (this) {
    automatic => localeFirstWeekday,
    monday => DateTime.monday,
    sunday => DateTime.sunday,
    saturday => DateTime.saturday,
  };
}

/// A first-use tip the app shows once (`settings.seenTips`).
enum Tip {
  /// After the first set is ticked: effort can be logged.
  effort,

  /// In the add-set sheet: what the set types are.
  setTypes,

  /// Once a workout has automatic warm-ups: they can be turned off.
  autoWarmups,
}

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

  /// What lifted weights go up and down by in this unit: 2.5 kg or 5 lb.
  double get weightStep => switch (this) {
    WeightUnit.kg => 2.5,
    WeightUnit.lb => 5,
  };

  /// A lifted weight in this unit as the user sees it. Within two decimals
  /// (the precision weight fields show) it was typed in this unit and shows
  /// as typed; otherwise it was typed in the other unit and shows rounded,
  /// to whole lb or to half kg, or to two decimals when that rounding would
  /// show a weight as 0. Only for display: fields store what is typed,
  /// converted to kg.
  double shown(double value) {
    final hundredths = value * 100;
    final grid = hundredths.round() / 100;
    // A kg round trip drifts at most 3e-11 hundredths up to 1000 kg; the
    // nearest a two-decimal weight in the other unit comes is 4e-6
    // (538.92 lb, 244.45 kg).
    if ((hundredths - hundredths.round()).abs() < 1e-8) return grid;
    return _rounded(value);
  }

  /// An estimated one-rep max stored as [kg], as the user sees it: computed,
  /// never typed, so always rounded as [shown] rounds.
  double estimatedFromKg(double kg) => _rounded(fromKg(kg));

  /// Whole lb or half kg; two decimals when that would show a weight as 0.
  double _rounded(double value) {
    final rounded = switch (this) {
      WeightUnit.kg => (value * 2).round() / 2,
      WeightUnit.lb => value.roundToDouble(),
    };
    if (rounded != 0 || value <= 0) return rounded;
    final hundredths = (value * 100).round() / 100;
    return hundredths > 0 ? hundredths : 0.01;
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

/// One automatic warm-up set: [percent] of the first working set's weight
/// for [reps].
class WarmupStep extends Equatable {
  const WarmupStep(this.percent, this.reps);

  final int percent;
  final int reps;

  @override
  List<Object?> get props => [percent, reps];
}

/// Limits of a custom warm-up scheme.
abstract final class WarmupLimits {
  static const maxSets = 5;
  static const minPercent = 10;
  static const maxPercent = 95;
  static const minReps = 1;
  static const maxReps = 20;
}

/// What keeps a warm-up step from being kept.
enum WarmupStepIssue { percentOutOfRange, repsOutOfRange }

/// Why [step] is not within [WarmupLimits]; empty when it is.
Set<WarmupStepIssue> validateWarmupStep(WarmupStep step) => {
  if (step.percent < WarmupLimits.minPercent ||
      step.percent > WarmupLimits.maxPercent)
    WarmupStepIssue.percentOutOfRange,
  if (step.reps < WarmupLimits.minReps || step.reps > WarmupLimits.maxReps)
    WarmupStepIssue.repsOutOfRange,
};

/// Which warm-up sets exercises start with (`settings.warmups.scheme`).
enum WarmupScheme {
  off([]),
  light([WarmupStep(60, 6)]),
  standard([WarmupStep(50, 8), WarmupStep(75, 4)]),
  full([WarmupStep(40, 8), WarmupStep(60, 5), WarmupStep(80, 2)]),

  /// [WarmupSettings.custom].
  custom([]);

  const WarmupScheme(this.presetSteps);

  /// A preset's sets; none for [off] and [custom].
  final List<WarmupStep> presetSteps;
}

/// Which exercises get warm-ups (`settings.warmups.scope`).
enum WarmupScope {
  every,

  /// Only an exercise whose main muscle no earlier exercise of the workout
  /// has.
  firstPerMuscle,
}

/// The automatic warm-up sets (`settings.warmups`).
class WarmupSettings extends Equatable {
  const WarmupSettings({
    this.scheme = WarmupScheme.standard,
    this.custom = const [],
    this.scope = WarmupScope.every,
  });

  final WarmupScheme scheme;

  /// The custom sets in the order entered, 1 to [WarmupLimits.maxSets],
  /// each within [WarmupLimits]; kept while another scheme is chosen.
  final List<WarmupStep> custom;
  final WarmupScope scope;

  /// The sets added to an exercise; none when off.
  List<WarmupStep> get steps =>
      scheme == WarmupScheme.custom ? custom : scheme.presetSteps;

  /// The sets warm-ups follow by position for their suggestions; off,
  /// warm-ups added by hand follow the standard ones.
  List<WarmupStep> get rampSteps =>
      steps.isEmpty ? WarmupScheme.standard.presetSteps : steps;

  /// Custom, starting from the current sets when there is no custom yet.
  WarmupSettings toCustom() => WarmupSettings(
    scheme: WarmupScheme.custom,
    custom: custom.isEmpty ? rampSteps : custom,
    scope: scope,
  );

  WarmupSettings copyWith({
    WarmupScheme? scheme,
    List<WarmupStep>? custom,
    WarmupScope? scope,
  }) => WarmupSettings(
    scheme: scheme ?? this.scheme,
    custom: custom ?? this.custom,
    scope: scope ?? this.scope,
  );

  @override
  List<Object?> get props => [scheme, custom, scope];
}

/// The set "Add warm-up set" appends after [steps]: midway from the last
/// one to 90 % (on 5 %), half its reps; 50 % × 8 for the first.
WarmupStep nextWarmupStep(List<WarmupStep> steps) {
  final last = steps.lastOrNull;
  if (last == null) return const WarmupStep(50, 8);
  final percent = (((last.percent + 90) / 2) / 5).round() * 5;
  return WarmupStep(
    percent.clamp(WarmupLimits.minPercent, WarmupLimits.maxPercent),
    (last.reps ~/ 2).clamp(WarmupLimits.minReps, WarmupLimits.maxReps),
  );
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

  /// The editor's minus and plus move in these steps.
  static const step = 100;

  /// [goal] moved [steps] steps up (or down when negative), kept within
  /// the limits.
  static int stepped(int goal, int steps) =>
      (goal + steps * step).clamp(min, max);

  /// A typed goal on the nearest step, or null outside the limits.
  static int? typed(int value) => value < min || value > max
      ? null
      : ((value / step).round() * step).clamp(min, max);
}

/// The user's app preferences. Values are always stored metric; these only
/// choose how they are shown.
class UserSettings extends Equatable {
  const UserSettings({
    required this.weightUnit,
    required this.lengthUnit,
    this.themePreference = ThemePreference.system,
    this.effortScale = EffortScale.byFeel,
    this.weekStart = WeekStart.automatic,
    this.restTimer = const RestTimerSettings(),
    this.warmups = const WarmupSettings(),
    this.seenTips = const {},
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
  final WeekStart weekStart;
  final RestTimerSettings restTimer;

  /// Which warm-up sets exercises logged with a weight and reps start with
  /// in a workout in progress, and which exercises; see `warmedUp`.
  final WarmupSettings warmups;

  /// The first-use tips dismissed, or no longer needed as the user did
  /// what they tell.
  final Set<Tip> seenTips;

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
    WeekStart? weekStart,
    RestTimerSettings? restTimer,
    WarmupSettings? warmups,
    Set<Tip>? seenTips,
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
    weekStart: weekStart ?? this.weekStart,
    restTimer: restTimer ?? this.restTimer,
    warmups: warmups ?? this.warmups,
    seenTips: seenTips ?? this.seenTips,
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
    weekStart: weekStart,
    restTimer: restTimer,
    warmups: warmups,
    seenTips: seenTips,
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
    weekStart,
    restTimer,
    warmups,
    seenTips,
    stepGoal,
    workoutReminder,
    measurementReminder,
    customBarWeightKg,
    customPlates,
    customTrackedMeasurements,
  ];
}
