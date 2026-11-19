import 'package:forge_core/forge_core.dart';

import 'calendar_date.dart';

/// The program the user follows (`users/{uid}.activeProgram`).
class ActiveProgram extends Equatable {
  /// [schedule] must not be empty.
  ActiveProgram({
    required this.programId,
    required Map<int, int> schedule,
    required this.nextDayIndex,
    required this.nextDate,
    this.movedFrom,
    required this.startedAt,
  }) : assert(schedule.isNotEmpty),
       schedule = Map.unmodifiable({
         for (final weekday in schedule.keys.toList()..sort())
           weekday: schedule[weekday]!,
       });

  final String programId;

  /// The program day done on each ISO weekday (1 Monday to 7 Sunday) the
  /// user trains on, by ascending weekday. A day may be on several.
  final Map<int, int> schedule;

  /// The program day to do next.
  final int nextDayIndex;

  /// The date that day is planned for; before today it was missed.
  final CalendarDate nextDate;

  /// The date the next day was planned for before it moved to an earlier
  /// one: it took that date's place along, so training weekdays up to it
  /// rest.
  final CalendarDate? movedFrom;
  final DateTime startedAt;

  /// The weekdays the user trains on, ascending.
  List<int> get weekdays => schedule.keys.toList();

  ActiveProgram copyWith({
    Map<int, int>? schedule,
    int? nextDayIndex,
    CalendarDate? nextDate,
    CalendarDate? Function()? movedFrom,
  }) => ActiveProgram(
    programId: programId,
    schedule: schedule ?? this.schedule,
    nextDayIndex: nextDayIndex ?? this.nextDayIndex,
    nextDate: nextDate ?? this.nextDate,
    movedFrom: movedFrom != null ? movedFrom() : this.movedFrom,
    startedAt: startedAt,
  );

  @override
  List<Object?> get props => [
    programId,
    schedule,
    nextDayIndex,
    nextDate,
    movedFrom,
    startedAt,
  ];
}
