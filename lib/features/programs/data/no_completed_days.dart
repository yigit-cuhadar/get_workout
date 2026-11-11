import '../domain/calendar_date.dart';
import '../domain/completed_days.dart';

/// Reports nothing done, until the workout feature registers its own
/// [CompletedDays].
class NoCompletedDays implements CompletedDays {
  const NoCompletedDays();

  @override
  Stream<List<CompletedDay>> watch(
    String uid,
    String programId, {
    required CalendarDate from,
    required CalendarDate to,
  }) => Stream.value(const []);
}
