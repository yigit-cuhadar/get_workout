import '../../programs/domain/calendar_date.dart';
import '../../programs/domain/program_schedule.dart';
import '../../settings/domain/user_settings.dart';

/// What the reminder settings' controls change, applied to the settings as
/// they are when the user's choice arrives.
extension ReminderSettingsChanges on UserSettings {
  UserSettings withWorkoutReminder({bool? enabled, int? minute}) => copyWith(
    workoutReminder: workoutReminder.copyWith(enabled: enabled, minute: minute),
  );

  /// The series starts [today] when first turned on. A [weekday] other than
  /// the series' own starts it again on the first such day from [today];
  /// its own weekday changes nothing, so the series keeps its dates.
  UserSettings withMeasurementReminder({
    bool? enabled,
    int? everyWeeks,
    int? weekday,
    int? minute,
    required CalendarDate today,
  }) {
    final current = measurementReminder;
    final from = current.from;
    return copyWith(
      measurementReminder: current.copyWith(
        enabled: enabled,
        everyWeeks: everyWeeks,
        minute: minute,
        from: weekday != null && weekday != from?.weekday
            ? ProgramSchedule.nextWeekday([weekday], from: today)
            : from ?? (enabled == true ? today : null),
      ),
    );
  }
}
