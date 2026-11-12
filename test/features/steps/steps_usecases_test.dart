import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/steps/domain/steps_usecases.dart';

import 'steps_fakes.dart';

void main() {
  final now = DateTime(2026, 11, 12, 15);
  late FakeHealthSteps health;
  late MemoryStepsPrompt prompt;

  setUp(() {
    health = FakeHealthSteps(
      clock: () => now,
      stepsFor: (day) => day.day * 100,
    );
    prompt = MemoryStepsPrompt();
  });

  group('GetStepsAccess', () {
    Future<StepsAccess?> access() async =>
        (await GetStepsAccess(health, prompt)()).valueOrNull;

    test('no store, or Health Connect missing', () async {
      health.status = HealthAvailability.unsupported;
      expect(await access(), StepsAccess.unsupported);
      health.status = HealthAvailability.notInstalled;
      expect(await access(), StepsAccess.notInstalled);
    });

    test('granted needs no asking', () async {
      health.permissionStatus = HealthPermission.granted;
      expect(await access(), StepsAccess.granted);
    });

    test('not asked here: explain first, denied or unknown', () async {
      for (final permission in [
        HealthPermission.denied,
        HealthPermission.undetermined,
      ]) {
        health.permissionStatus = permission;
        expect(await access(), StepsAccess.explain, reason: '$permission');
      }
    });

    test('asked here: the platform answer', () async {
      prompt.asked = true;
      health.permissionStatus = HealthPermission.denied;
      expect(await access(), StepsAccess.denied);
      health.permissionStatus = HealthPermission.undetermined;
      expect(await access(), StepsAccess.undetermined);
    });

    test('a marker that cannot be read counts as not asked', () async {
      prompt
        ..asked = true
        ..failure = const UnknownFailure('disk');
      health.permissionStatus = HealthPermission.undetermined;
      expect(await access(), StepsAccess.explain);
    });

    test('store failures pass through', () async {
      health.failure = const UnknownFailure('boom');
      final result = await GetStepsAccess(health, prompt)();
      expect(result.failureOrNull, isA<UnknownFailure>());
    });
  });

  group('AllowStepsAccess', () {
    test('remembers the asking, then asks the platform', () async {
      final result = await AllowStepsAccess(health, prompt)();
      expect(prompt.asked, isTrue);
      expect(result.valueOrNull, StepsAccess.granted);
    });

    test('a refusal is denied; iOS stays undetermined', () async {
      health.grantOnRequest = HealthPermission.denied;
      expect(
        (await AllowStepsAccess(health, prompt)()).valueOrNull,
        StepsAccess.denied,
      );
      health
        ..permissionStatus = HealthPermission.undetermined
        ..grantOnRequest = HealthPermission.undetermined;
      expect(
        (await AllowStepsAccess(health, prompt)()).valueOrNull,
        StepsAccess.undetermined,
      );
    });

    test('asks even when the marker cannot be written', () async {
      prompt.failure = const UnknownFailure('disk');
      expect(
        (await AllowStepsAccess(health, prompt)()).valueOrNull,
        StepsAccess.granted,
      );
    });
  });

  group('GetStepsHistory', () {
    test('the last 30 days, today up to now', () async {
      health.permissionStatus = HealthPermission.granted;
      final history = (await GetStepsHistory(
        health,
        clock: () => now,
      )()).valueOrNull!;
      expect(history.days, hasLength(stepHistoryDays));
      expect(history.days.first.day, DateTime(2026, 10, 14));
      expect(history.days.last.day, DateTime(2026, 11, 12));
      expect(history.days.first.count, 1400);
      // 15:00 is 5/8 of the day.
      expect(history.today, 1200 * 15 ~/ 24);
    });

    test('Android without access fails with PermissionFailure', () async {
      health.permissionStatus = HealthPermission.denied;
      final result = await GetStepsHistory(health, clock: () => now)();
      expect(result.failureOrNull, isA<PermissionFailure>());
    });
  });

  test('GetTodaySteps: today so far against the goal', () async {
    health.permissionStatus = HealthPermission.granted;
    final result = await GetTodaySteps(health, clock: () => now)(1000);
    expect(
      result.valueOrNull,
      const StepGoalProgress(steps: 1200 * 15 ~/ 24, goal: 1000),
    );
  });
}
