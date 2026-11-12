import 'dart:math' as math;

import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import '../../programs/domain/calendar_date.dart';

/// The days of steps the Steps page shows, today included.
const stepHistoryDays = 30;

/// What the app may do with the device's step counts.
enum StepsAccess {
  /// No health store on this device.
  unsupported,

  /// Android: Health Connect is missing or needs an update.
  notInstalled,

  /// Not asked on this device yet: explain, and ask only after the user
  /// says yes.
  explain,

  /// Android: refused, or never granted after asking.
  denied,

  granted,

  /// iOS: readable, but HealthKit never says whether access was refused; a
  /// refusal reads as zero steps.
  undetermined;

  bool get readable => this == granted || this == undetermined;
}

/// Steps of a day against the daily goal.
class StepGoalProgress extends Equatable {
  const StepGoalProgress({required this.steps, required this.goal});

  final int steps;
  final int goal;

  /// 0 to 1; 1 from the goal on.
  double get fraction => goal <= 0 ? 1 : math.min(steps / goal, 1);

  bool get reached => steps >= goal;

  /// Steps still to go; 0 once reached.
  int get remaining => math.max(goal - steps, 0);

  @override
  List<Object?> get props => [steps, goal];
}

/// The steps of the last [stepHistoryDays] days, oldest first, today last.
class StepsHistory extends Equatable {
  const StepsHistory(this.days);

  final List<DailySteps> days;

  int get today => days.lastOrNull?.count ?? 0;

  bool get allZero => days.every((day) => day.count == 0);

  /// The seven days of today's week, the week starting on ISO weekday
  /// [firstWeekday] (1 Monday to 7 Sunday); days after today, and any
  /// without a count, are zero.
  List<DailySteps> week(int firstWeekday) {
    final last = days.lastOrNull;
    if (last == null) return const [];
    final counts = {
      for (final day in days) CalendarDate.of(day.day): day.count,
    };
    final today = CalendarDate.of(last.day);
    final start = today.startOfWeek(firstWeekday);
    return [
      for (var i = 0; i < 7; i++)
        DailySteps(
          start.addDays(i).toLocalDateTime(),
          counts[start.addDays(i)] ?? 0,
        ),
    ];
  }

  @override
  List<Object?> get props => [days];
}

/// Whether to say where to allow access next to the counts: HealthKit
/// reads a refusal as zero, so all zero with [access] unknown may be one.
/// Never claims that access was refused.
bool showsAccessHint(StepsAccess access, StepsHistory history) =>
    access == StepsAccess.undetermined && history.allZero;
