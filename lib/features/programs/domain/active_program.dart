import 'package:forge_core/forge_core.dart';

import 'calendar_date.dart';

/// The program the user follows (`users/{uid}.activeProgram`).
class ActiveProgram extends Equatable {
  /// [weekdays] must not be empty.
  ActiveProgram({
    required this.programId,
    required List<int> weekdays,
    required this.nextDayIndex,
    required this.nextDate,
    required this.startedAt,
  }) : assert(weekdays.isNotEmpty),
       weekdays = List.unmodifiable(weekdays.toSet().toList()..sort());

  final String programId;

  /// ISO weekdays (1 Monday to 7 Sunday) the user trains on, ascending.
  final List<int> weekdays;

  /// The program day to do next.
  final int nextDayIndex;

  /// The date that day is planned for; before today it was missed.
  final CalendarDate nextDate;
  final DateTime startedAt;

  ActiveProgram copyWith({
    List<int>? weekdays,
    int? nextDayIndex,
    CalendarDate? nextDate,
  }) => ActiveProgram(
    programId: programId,
    weekdays: weekdays ?? this.weekdays,
    nextDayIndex: nextDayIndex ?? this.nextDayIndex,
    nextDate: nextDate ?? this.nextDate,
    startedAt: startedAt,
  );

  @override
  List<Object?> get props => [
    programId,
    weekdays,
    nextDayIndex,
    nextDate,
    startedAt,
  ];
}
