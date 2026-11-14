import 'package:flutter_test/flutter_test.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/calendar/domain/calendar_month.dart';
import 'package:get_workout/features/calendar/presentation/calendar_marks.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/l10n/app_localizations_en.dart';

import '../programs/fixtures.dart';
import '../workout/fixtures.dart' show workout;

void main() {
  final pushPullLegs = program(id: 'p1');
  PlanEntry plan(PlannedStatus status) => PlanEntry(
    pushPullLegs,
    PlannedDay(date: CalendarDate(2026, 11, 13), dayIndex: 0, status: status),
  );
  final run = CardioEntry(
    CardioSession(
      type: CardioType.treadmillRun,
      date: DateTime(2026, 11, 13, 7),
      duration: const Duration(minutes: 20),
    ),
  );
  final done = WorkoutEntry(
    workout('w1', const [], startedAt: DateTime(2026, 11, 13, 8)),
  );

  DayState state(List<CalendarEntry> entries, {bool today = false}) =>
      calendarDayState(entries, today: today);

  test('maps each mark to its circle', () {
    expect(state([done]), DayState.done);
    expect(state([run]), DayState.light);
    expect(state([plan(PlannedStatus.planned)]), DayState.planned);
    expect(state([plan(PlannedStatus.missed)]), DayState.missed);
    expect(state(const []), DayState.none);
  });

  test('today is the ink ring unless something was done', () {
    expect(state(const [], today: true), DayState.today);
    expect(state([plan(PlannedStatus.planned)], today: true), DayState.today);
    expect(state([plan(PlannedStatus.missed)], today: true), DayState.today);
    expect(state([run], today: true), DayState.light);
  });

  test('a workout today is done inside the ink ring', () {
    expect(state([done], today: true), DayState.todayDone);
    expect(state([run, done], today: true), DayState.todayDone);
  });

  test('a workout outweighs cardio and the plan', () {
    expect(state([run, done, plan(PlannedStatus.planned)]), DayState.done);
    expect(state([run, plan(PlannedStatus.missed)]), DayState.light);
  });

  test('names the five circles in the legend order', () {
    expect(calendarLegend(AppLocalizationsEn()), {
      DayState.done: 'Workout',
      DayState.light: 'Cardio',
      DayState.missed: 'Missed',
      DayState.planned: 'Planned',
      DayState.today: 'Today',
    });
  });
}
