import 'package:forge_core/forge_core.dart';

import 'calendar_date.dart';

/// A program day the user did on [date].
class CompletedDay extends Equatable {
  const CompletedDay({required this.date, required this.dayIndex});

  final CalendarDate date;
  final int dayIndex;

  @override
  List<Object?> get props => [date, dayIndex];
}

/// Which program days were done. The workout feature provides it; until
/// then nothing is reported done.
abstract interface class CompletedDays {
  /// The days of program [programId] user [uid] did from [from] to [to],
  /// both included; again on every change.
  Stream<List<CompletedDay>> watch(
    String uid,
    String programId, {
    required CalendarDate from,
    required CalendarDate to,
  });
}
