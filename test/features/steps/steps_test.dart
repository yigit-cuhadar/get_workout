import 'package:flutter_test/flutter_test.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/steps/domain/steps.dart';

void main() {
  group('StepGoalProgress', () {
    test('part of the goal', () {
      const progress = StepGoalProgress(steps: 2500, goal: 10000);
      expect(progress.fraction, 0.25);
      expect(progress.reached, isFalse);
      expect(progress.remaining, 7500);
    });

    test('reached at the goal and beyond, never past full', () {
      for (final steps in [10000, 14000]) {
        final progress = StepGoalProgress(steps: steps, goal: 10000);
        expect(progress.fraction, 1);
        expect(progress.reached, isTrue);
        expect(progress.remaining, 0);
      }
    });

    test('none yet', () {
      const progress = StepGoalProgress(steps: 0, goal: 8000);
      expect(progress.fraction, 0);
      expect(progress.remaining, 8000);
    });
  });

  group('StepsHistory', () {
    // Thursday 12 November 2026 is today.
    final history = StepsHistory([
      for (var i = 29; i >= 0; i--)
        DailySteps(DateTime(2026, 11, 12 - i), 1000 + i),
    ]);

    test('today is the last day', () {
      expect(history.today, 1000);
    });

    test('the week from Monday: days after today are zero', () {
      final week = history.week(DateTime.monday);
      expect(week.map((day) => day.day), [
        for (var day = 9; day <= 15; day++) DateTime(2026, 11, day),
      ]);
      expect(week.map((day) => day.count), [1003, 1002, 1001, 1000, 0, 0, 0]);
    });

    test('the week from Sunday or Saturday, as locales start it', () {
      expect(history.week(DateTime.sunday).first.day, DateTime(2026, 11, 8));
      expect(history.week(DateTime.saturday).first.day, DateTime(2026, 11, 7));
      // A week starting today.
      expect(history.week(DateTime.thursday).first.day, DateTime(2026, 11, 12));
    });

    test('a week reaching before the history counts zero there', () {
      final short = StepsHistory([DailySteps(DateTime(2026, 11, 12), 500)]);
      expect(short.week(DateTime.monday).map((day) => day.count), [
        0,
        0,
        0,
        500,
        0,
        0,
        0,
      ]);
    });

    test('a week across a month end', () {
      final week = StepsHistory([DailySteps(DateTime(2026, 12, 1), 10)])
          .week(DateTime.monday);
      expect(week.first.day, DateTime(2026, 11, 30));
      expect(week.last.day, DateTime(2026, 12, 6));
    });

    test('no week without days', () {
      expect(const StepsHistory([]).week(DateTime.monday), isEmpty);
      expect(const StepsHistory([]).today, 0);
    });
  });

  group('showsAccessHint', () {
    final zeros = StepsHistory([
      for (var day = 1; day <= 30; day++)
        DailySteps(DateTime(2026, 11, day), 0),
    ]);
    final some = StepsHistory([
      for (var day = 1; day <= 30; day++)
        DailySteps(DateTime(2026, 11, day), day == 3 ? 40 : 0),
    ]);

    test('all zero with access unknown (iOS)', () {
      expect(showsAccessHint(StepsAccess.undetermined, zeros), isTrue);
    });

    test('not once any day has steps', () {
      expect(showsAccessHint(StepsAccess.undetermined, some), isFalse);
    });

    test('not when access is known to be granted', () {
      expect(showsAccessHint(StepsAccess.granted, zeros), isFalse);
    });
  });

  test('only granted and undetermined access are readable', () {
    expect(StepsAccess.values.where((access) => access.readable), [
      StepsAccess.granted,
      StepsAccess.undetermined,
    ]);
  });

  group('StepsSummary', () {
    // Thursday 12 November 2026 is today; the week starts on Monday 9.
    final today = DateTime(2026, 11, 12, 15);
    final week = [
      DailySteps(DateTime(2026, 11, 9), 9000),
      DailySteps(DateTime(2026, 11, 10), 7000),
      DailySteps(DateTime(2026, 11, 11), 8001),
      DailySteps(DateTime(2026, 11, 12), 20000),
      DailySteps(DateTime(2026, 11, 13), 0),
    ];

    test('the days before today: average and goal reached', () {
      expect(
        StepsSummary.before(today, week, goal: 8000),
        const StepsSummary(days: 3, average: 8000, reached: 2),
      );
    });

    test('reached counts a day exactly at the goal', () {
      expect(StepsSummary.before(today, week, goal: 9000).reached, 1);
    });

    test('none over on the first day of the period', () {
      expect(
        StepsSummary.before(today, week.sublist(3), goal: 8000),
        const StepsSummary(days: 0, average: 0, reached: 0),
      );
    });
  });
}
