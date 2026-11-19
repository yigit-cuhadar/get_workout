import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';

import 'fixtures.dart';

void main() {
  final active = ActiveProgram(
    programId: 'p1',
    schedule: const {1: 0, 5: 1},
    nextDayIndex: 0,
    nextDate: CalendarDate(2026, 11, 13),
    startedAt: DateTime(2026, 11, 2),
  );

  test('the active program\'s working sets of a week, while it runs', () {
    // Two days of two exercises with three sets each.
    final running = ProgramListState(
      programs: [program(id: 'p1')],
      active: active,
    );
    expect(running.plannedWeeklySets, 12);

    final finished = ProgramListState(
      programs: [program(id: 'p1')],
      active: active,
      finished: true,
    );
    expect(finished.plannedWeeklySets, isNull);
    expect(const ProgramListState().plannedWeeklySets, isNull);
  });
}
