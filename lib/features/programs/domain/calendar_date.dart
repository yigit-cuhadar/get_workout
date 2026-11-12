import 'package:forge_core/forge_core.dart';

/// A day on the calendar, without a time or time zone. Arithmetic runs on
/// UTC dates, which have no daylight saving, so adding days never lands on
/// the wrong date.
class CalendarDate extends Equatable implements Comparable<CalendarDate> {
  /// Out-of-range parts roll over, as with [DateTime]: day 32 of January is
  /// 1 February.
  factory CalendarDate(int year, int month, int day) =>
      CalendarDate._(DateTime.utc(year, month, day));

  /// The date [time] shows, in [time]'s own zone (local for [DateTime.now]).
  factory CalendarDate.of(DateTime time) =>
      CalendarDate(time.year, time.month, time.day);

  const CalendarDate._(this._utc);

  final DateTime _utc;

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;

  /// ISO weekday: 1 is Monday, 7 is Sunday.
  int get weekday => _utc.weekday;

  CalendarDate addDays(int days) => CalendarDate(year, month, day + days);

  /// The Monday of this date's week.
  CalendarDate get weekStart => startOfWeek(DateTime.monday);

  /// The first day of this date's week, for weeks starting on ISO weekday
  /// [firstWeekday] (1 Monday to 7 Sunday), as locales differ.
  CalendarDate startOfWeek(int firstWeekday) =>
      addDays(-((weekday - firstWeekday) % 7));

  bool isBefore(CalendarDate other) => compareTo(other) < 0;
  bool isAfter(CalendarDate other) => compareTo(other) > 0;

  /// Local midnight of this date.
  DateTime toLocalDateTime() => DateTime(year, month, day);

  /// `YYYY-MM-DD`, as stored.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Reads [toIso]'s format; null for anything else, including dates that
  /// do not exist such as `2026-02-30`.
  static CalendarDate? tryParse(Object? text) {
    if (text is! String) return null;
    final match = _iso.firstMatch(text);
    if (match == null) return null;
    final [year, month, day] = [
      for (var i = 1; i <= 3; i++) int.parse(match[i]!),
    ];
    final date = CalendarDate(year, month, day);
    return date.year == year && date.month == month && date.day == day
        ? date
        : null;
  }

  static final _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  @override
  int compareTo(CalendarDate other) => _utc.compareTo(other._utc);

  @override
  List<Object?> get props => [_utc];

  @override
  String toString() => toIso();
}
