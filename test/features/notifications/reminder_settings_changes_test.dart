import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/notifications/domain/reminder_settings_changes.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  const base = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );
  // A Thursday.
  final today = CalendarDate(2026, 11, 12);
  final sunday = CalendarDate(2026, 11, 1);
  final measuring = base.copyWith(
    measurementReminder: MeasurementReminderSettings(
      enabled: true,
      from: sunday,
    ),
  );

  test('the workout reminder changes only what is given', () {
    final on = base.withWorkoutReminder(enabled: true);
    final later = on.withWorkoutReminder(minute: 1200);

    expect(
      later.workoutReminder,
      const WorkoutReminderSettings(enabled: true, minute: 1200),
    );
  });

  test('turned on for the first time, the series starts today', () {
    final on = base.withMeasurementReminder(enabled: true, today: today);

    expect(on.measurementReminder.from, today);
    expect(on.measurementReminder.enabled, isTrue);
  });

  test('turned off and on again, the series keeps its dates', () {
    final off = measuring.withMeasurementReminder(enabled: false, today: today);
    final on = off.withMeasurementReminder(enabled: true, today: today);

    expect(off.measurementReminder.from, sunday);
    expect(on, measuring);
  });

  test('another weekday starts the series on its next date', () {
    final tuesday = measuring.withMeasurementReminder(
      weekday: DateTime.tuesday,
      today: today,
    );
    final thursday = measuring.withMeasurementReminder(
      weekday: DateTime.thursday,
      today: today,
    );

    expect(tuesday.measurementReminder.from, CalendarDate(2026, 11, 17));
    expect(thursday.measurementReminder.from, today);
  });

  test('the series\' own weekday or cadence changes nothing', () {
    expect(
      measuring.withMeasurementReminder(weekday: DateTime.sunday, today: today),
      measuring,
    );
    expect(
      measuring.withMeasurementReminder(everyWeeks: 4, today: today),
      measuring,
    );
  });

  test('changes apply to the settings they are given', () {
    final current = measuring.copyWith(weightUnit: WeightUnit.lb);

    final changed = current.withMeasurementReminder(minute: 600, today: today);

    expect(changed.weightUnit, WeightUnit.lb);
    expect(changed.measurementReminder.minute, 600);
    expect(changed.measurementReminder.from, sunday);
  });
}
