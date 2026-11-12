import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/steps/domain/steps_usecases.dart';
import 'package:get_workout/features/steps/presentation/steps_cubit.dart';

import 'steps_fakes.dart';

/// Reports access as granted while reads see [permissionStatus], as when
/// Android access is taken back between the check and the read; and holds
/// reads while [gate] is set.
class _Health extends FakeHealthSteps {
  _Health({super.clock, super.stepsFor});

  bool grantedCheck = false;
  Completer<void>? gate;

  @override
  Future<Result<HealthPermission>> permission() async =>
      grantedCheck ? const Ok(HealthPermission.granted) : super.permission();

  @override
  Future<Result<List<DailySteps>>> dailySteps(
    DateTime first,
    DateTime last,
  ) async {
    final result = super.dailySteps(first, last);
    await gate?.future;
    return result;
  }
}

void main() {
  final now = DateTime(2026, 11, 12, 12);
  late _Health health;
  late MemoryStepsPrompt prompt;
  late StepsCubit cubit;

  setUp(() {
    health = _Health(clock: () => now, stepsFor: (_) => 1000);
    prompt = MemoryStepsPrompt();
    cubit = StepsCubit(
      getAccess: GetStepsAccess(health, prompt),
      allowAccess: AllowStepsAccess(health, prompt),
      getHistory: GetStepsHistory(health, clock: () => now),
      openSettings: OpenHealthSettings(health),
    );
  });

  tearDown(() => cubit.close());

  test('starts unknown', () {
    expect(cubit.state, const StepsState());
  });

  group('availability', () {
    test('no health store', () async {
      health.status = HealthAvailability.unsupported;
      await cubit.load();
      expect(cubit.state, const StepsState(access: StepsAccess.unsupported));
    });

    test('Health Connect missing: its store page opens', () async {
      health.status = HealthAvailability.notInstalled;
      await cubit.load();
      expect(cubit.state.access, StepsAccess.notInstalled);

      expect(await cubit.openSettings(), isTrue);
      expect(health.settingsOpened, 1);
      expect(cubit.state.busy, isFalse);
    });

    test('installed while away: explained on resume', () async {
      health.status = HealthAvailability.notInstalled;
      await cubit.load();
      health.status = HealthAvailability.available;
      await cubit.load();
      expect(cubit.state.access, StepsAccess.explain);
    });
  });

  group('access', () {
    test('explained first; the system is asked only on continue', () async {
      await cubit.load();
      expect(cubit.state, const StepsState(access: StepsAccess.explain));
      expect(health.permissionStatus, HealthPermission.denied);

      await cubit.allow();

      expect(prompt.asked, isTrue);
      expect(cubit.state.access, StepsAccess.granted);
      expect(cubit.state.history!.days, hasLength(stepHistoryDays));
      expect(cubit.state.history!.today, 500);
      expect(cubit.state.accessHint, isFalse);
    });

    test('granted already: straight to the steps', () async {
      health.permissionStatus = HealthPermission.granted;
      await cubit.load();
      expect(cubit.state.access, StepsAccess.granted);
      expect(cubit.state.history, isNotNull);
      expect(prompt.asked, isFalse);
    });

    test('Android refusal: denied, then asked again from there', () async {
      health.grantOnRequest = HealthPermission.denied;
      await cubit.load();
      await cubit.allow();
      expect(cubit.state, const StepsState(access: StepsAccess.denied));

      // Allowed in Health Connect's settings, then back in the app.
      expect(await cubit.openSettings(), isTrue);
      health.permissionStatus = HealthPermission.granted;
      await cubit.load();
      expect(cubit.state.access, StepsAccess.granted);
      expect(cubit.state.history, isNotNull);
    });

    test(
      'asked here before and still denied: denied, no explanation',
      () async {
        prompt.asked = true;
        await cubit.load();
        expect(cubit.state.access, StepsAccess.denied);
      },
    );

    test('taken back while away: denied, steps dropped', () async {
      health.permissionStatus = HealthPermission.granted;
      await cubit.load();
      prompt.asked = true;
      health.permissionStatus = HealthPermission.denied;
      await cubit.load();
      expect(cubit.state, const StepsState(access: StepsAccess.denied));
    });

    test('taken back between the check and the read: denied', () async {
      health.grantedCheck = true;
      await cubit.load();
      expect(cubit.state, const StepsState(access: StepsAccess.denied));
    });
  });

  group('iOS, access never revealed', () {
    setUp(() {
      health
        ..permissionStatus = HealthPermission.undetermined
        ..grantOnRequest = HealthPermission.undetermined;
    });

    test('explained once, then read whatever the answer', () async {
      await cubit.load();
      expect(cubit.state.access, StepsAccess.explain);
      await cubit.allow();
      expect(cubit.state.access, StepsAccess.undetermined);
      expect(cubit.state.history!.today, 500);
      expect(cubit.state.accessHint, isFalse);

      await cubit.load();
      expect(cubit.state.access, StepsAccess.undetermined);
    });

    test('all zero: a hint where to allow access, not a denial', () async {
      prompt.asked = true;
      health.stepsFor = (_) => 0;
      await cubit.load();
      expect(cubit.state.access, StepsAccess.undetermined);
      expect(cubit.state.accessHint, isTrue);

      expect(await cubit.openSettings(), isTrue);
      expect(health.settingsOpened, 1);
    });
  });

  group('refresh', () {
    setUp(() => health.permissionStatus = HealthPermission.granted);

    test('a load on resume reads again, keeping the steps meanwhile', () async {
      await cubit.load();
      health.stepsFor = (_) => 3000;
      final emitted = <StepsState>[];
      final subscription = cubit.stream.listen(emitted.add);

      await cubit.load();
      await subscription.cancel();

      expect(emitted.every((state) => state.history != null), isTrue);
      expect(cubit.state.history!.today, 1500);
    });

    test('a newer load wins over one still reading', () async {
      final gate = health.gate = Completer();
      final first = cubit.load();
      await pumpEventQueue();
      health
        ..gate = null
        ..stepsFor = (_) => 3000;
      await cubit.load();
      expect(cubit.state.history!.today, 1500);

      // The older read, of the old counts, ends last and is dropped.
      gate.complete();
      await first;
      expect(cubit.state.history!.today, 1500);
    });

    test('a failed refresh keeps the steps and reports it', () async {
      await cubit.load();
      const failure = UnknownFailure('boom');
      health.failure = failure;
      await cubit.load();
      expect(cubit.state.history, isNotNull);
      expect(cubit.state.failure, failure);

      health.failure = null;
      await cubit.load();
      expect(cubit.state.failure, isNull);
    });
  });

  test('a failed first load fails until retried', () async {
    health.failure = const UnknownFailure('boom');
    await cubit.load();
    expect(cubit.state.access, isNull);
    expect(cubit.state.failure, isA<UnknownFailure>());

    health
      ..failure = null
      ..permissionStatus = HealthPermission.granted;
    await cubit.load();
    expect(cubit.state.access, StepsAccess.granted);
    expect(cubit.state.failure, isNull);
  });

  test('a failed request is reported, access unchanged', () async {
    await cubit.load();
    health.failure = const UnknownFailure('boom');
    await cubit.allow();
    expect(cubit.state.access, StepsAccess.explain);
    expect(cubit.state.failure, isA<UnknownFailure>());
    expect(cubit.state.busy, isFalse);
  });

  test('settings that do not open say so', () async {
    health.status = HealthAvailability.unsupported;
    expect(await cubit.openSettings(), isFalse);
    expect(cubit.state.busy, isFalse);
  });
}
