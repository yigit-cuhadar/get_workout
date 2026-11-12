import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../settings/domain/user_settings.dart';
import '../domain/calendar_date.dart';
import '../domain/program.dart';
import '../domain/program_validation.dart';

extension ProgramText on AppLocalizations {
  /// The day's name, or "Day n" when it has none.
  String dayName(ProgramDay day, int index) {
    final name = day.name.trim();
    return name.isEmpty ? programDayDefault(index + 1) : name;
  }

  /// `3 × 8–12`, `3 × 10` or `3 × 45 s`, with the target weight if any.
  String itemSummary(ProgramItem item, WeightUnit unit) {
    final min = item.repMin;
    final max = item.repMax;
    final duration = item.durationS;
    final work = duration != null
        ? programSeconds(duration)
        : min == null || max == null || min == max
        ? '${min ?? max ?? ''}'
        : programRepRange(min, max);
    final target = item.targetKg;
    final sets = programSetsTimes(item.sets, work);
    return target == null ? sets : '$sets · ${liftedWeightText(target, unit)}';
  }

  /// A total (volume), to one decimal.
  String weightText(double kg, WeightUnit unit) =>
      _weightText(unit.fromKg(kg), unit, 1);

  /// One lifted weight, as [WeightUnitConversion.shown] shows it.
  String liftedWeightText(double kg, WeightUnit unit) =>
      _weightText(unit.shownFromKg(kg), unit, 2);

  /// An estimated one-rep max, as [WeightUnitConversion.estimatedFromKg]
  /// shows it.
  String estimatedWeightText(double kg, WeightUnit unit) =>
      _weightText(unit.estimatedFromKg(kg), unit, 2);

  String _weightText(double value, WeightUnit unit, int maxDecimals) {
    final number = (NumberFormat.decimalPattern(
      localeName,
    )..maximumFractionDigits = maxDecimals).format(value);
    return switch (unit) {
      WeightUnit.kg => programWeightKg(number),
      WeightUnit.lb => programWeightLb(number),
    };
  }

  String weightUnitLabel(WeightUnit unit) => switch (unit) {
    WeightUnit.kg => unitKg,
    WeightUnit.lb => unitLb,
  };

  /// Rounded to whole minutes, at least one.
  String estimateText(Duration duration) {
    final minutes = (duration.inSeconds / 60).round();
    return programEstimate(minutes < 1 ? 1 : minutes);
  }

  /// "Superset A" for two items, "Circuit A" for more.
  String groupLabel(String group, int size) =>
      size == 2 ? programSuperset(group) : programCircuit(group);

  /// Short weekday name of ISO weekday [weekday].
  String weekdayShort(int weekday) =>
      // 1 January 2024 was a Monday.
      DateFormat.E(localeName).format(DateTime(2024, 1, weekday));

  /// Full weekday name of ISO weekday [weekday].
  String weekdayLong(int weekday) =>
      DateFormat.EEEE(localeName).format(DateTime(2024, 1, weekday));

  String weekdayList(List<int> weekdays) =>
      weekdays.map(weekdayShort).join(listSeparator);

  String planDate(CalendarDate date) =>
      DateFormat.MMMEd(localeName).format(date.toLocalDateTime());

  String programIssueText(ProgramIssue issue) => switch (issue) {
    ProgramIssue.nameMissing => programErrorNameMissing,
    ProgramIssue.nameTooLong => programErrorNameTooLong(
      ProgramLimits.maxNameLength,
    ),
    ProgramIssue.lengthWeeksOutOfRange => programErrorLength(
      ProgramLimits.minLengthWeeks,
      ProgramLimits.maxLengthWeeks,
    ),
    ProgramIssue.noDays => programErrorNoDays,
    ProgramIssue.tooManyDays => programErrorTooManyDays(ProgramLimits.maxDays),
  };

  String dayIssueText(DayIssue issue) => switch (issue) {
    DayIssue.nameTooLong => programErrorDayName(ProgramLimits.maxDayNameLength),
    DayIssue.noItems => programErrorNoItems,
    DayIssue.tooManyItems => programErrorTooManyItems(
      ProgramLimits.maxItemsPerDay,
    ),
  };

  String itemIssueText(ItemIssue issue) => switch (issue) {
    ItemIssue.exerciseUnavailable => programErrorUnavailable,
    ItemIssue.setsOutOfRange => programErrorSets(
      ProgramLimits.minSets,
      ProgramLimits.maxSets,
    ),
    ItemIssue.repsMissing => programErrorRepsMissing,
    ItemIssue.repsOutOfRange => programErrorReps(
      ProgramLimits.minReps,
      ProgramLimits.maxReps,
    ),
    ItemIssue.repRangeInverted => programErrorRepRange,
    ItemIssue.durationMissing => programErrorDurationMissing,
    ItemIssue.durationOutOfRange => programErrorDuration(
      ProgramLimits.minDurationS,
      ProgramLimits.maxDurationS ~/ 60,
    ),
    ItemIssue.restOutOfRange => programErrorRest(ProgramLimits.maxRestS),
    ItemIssue.targetOutOfRange => programErrorTarget,
    ItemIssue.wrongTarget => programErrorWrongTarget,
    ItemIssue.groupInvalid => programErrorGroup,
  };
}
