import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/domain/body_entry.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/progress/domain/measurement_prompt.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';

void main() {
  // Every 2 weeks on Sundays from Sunday 1 November: next Sunday 15.
  final settings = MeasurementReminderSettings(
    enabled: true,
    everyWeeks: 2,
    from: CalendarDate(2026, 11, 1),
  );
  final sunday = CalendarDate(2026, 11, 15);
  final photos = BodyEntry(
    id: 'e1',
    date: DateTime(2026, 11, 1, 9),
    weightKg: 80,
    photos: const {PhotoPose.back: 'b', PhotoPose.front: 'f'},
  );

  MeasurementPrompt? on(
    CalendarDate today, {
    List<BodyEntry> entries = const [],
    MeasurementReminderSettings? reminder,
    CalendarDate? dismissed,
  }) => measurementPrompt(
    reminder ?? settings,
    entries,
    today: today,
    dismissed: dismissed,
  );

  test('from two days before the next date through that day', () {
    expect(on(CalendarDate(2026, 11, 12)), isNull);
    expect(
      on(CalendarDate(2026, 11, 13)),
      MeasurementPrompt(date: sunday, today: false),
    );
    expect(on(sunday), MeasurementPrompt(date: sunday, today: true));
    // Monday: the next date is two weeks on.
    expect(on(CalendarDate(2026, 11, 16)), isNull);
  });

  test('only while the reminder is on', () {
    expect(on(sunday, reminder: settings.copyWith(enabled: false)), isNull);
    expect(on(sunday, reminder: const MeasurementReminderSettings()), isNull);
  });

  test('leaves once a measurement day is saved, or when dismissed', () {
    final measured = BodyEntry(
      id: 'e2',
      date: DateTime(2026, 11, 14, 8),
      measurements: const {BodyMeasurement.waist: 80},
    );
    final weighed = BodyEntry(
      id: 'e3',
      date: DateTime(2026, 11, 14, 8),
      weightKg: 80,
    );
    expect(on(sunday, entries: [measured]), isNull);
    // A quick weight log is not a measurement day.
    expect(on(sunday, entries: [weighed]), isNotNull);
    expect(on(sunday, dismissed: sunday), isNull);
    expect(on(sunday, dismissed: CalendarDate(2026, 11, 1)), isNotNull);
  });

  test('the newest photos and their poses, else the newest entry', () {
    final lastPhotos = on(sunday, entries: [photos])?.lastPhotos;
    expect(lastPhotos?.date, DateTime(2026, 11, 1, 9));
    expect(lastPhotos?.poses, [PhotoPose.front, PhotoPose.back]);
    final weighed = BodyEntry(
      id: 'e3',
      date: DateTime(2026, 11, 8),
      weightKg: 80,
    );
    final prompt = on(sunday, entries: [weighed]);
    expect(prompt?.lastPhotos, isNull);
    expect(prompt?.lastMeasured, DateTime(2026, 11, 8));
    expect(on(sunday)?.lastMeasured, isNull);
  });
}
