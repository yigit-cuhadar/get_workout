import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/steps/domain/steps_usecases.dart';
import 'package:get_workout/features/today/presentation/today_steps_cubit.dart';

import '../steps/steps_fakes.dart';

/// Counts system prompts, which Today must never show; can report access
/// granted while reads are refused, and hold reads while [gate] is set.
class _Health extends FakeHealthSteps {
  _Health({super.clock, super.stepsFor});

  var requests = 0;
  bool grantedCheck = false;
  Completer<void>? gate;

  @override
  Future<Result<HealthPermission>> requestPermission() {
    requests++;
    return super.requestPermission();
  }

  @override
  Future<Result<HealthPermission>> permission() async =>
      grantedCheck ? const Ok(HealthPermission.granted) : super.permission();

  @override
  Future<Result<int>> stepsOn(DateTime day) async {
    final result = super.stepsOn(day);
    await gate?.future;
    return result;
  }
}

void main() {
  // Noon: half of the day's 8,000 steps so far.
  final now = DateTime(2026, 11, 12, 12);
  late _Health health;
  late MemoryStepsPrompt prompt;
  late TodayStepsCubit cubit;

  setUp(() {
    health = _Health(clock: () => now, stepsFor: (_) => 8000);
    prompt = MemoryStepsPrompt();
    cubit = TodayStepsCubit(
      getAccess: GetStepsAccess(health, prompt),
      getTodaySteps: GetTodaySteps(health, clock: () => now),
    );
  });

  tearDown(() => cubit.close());

  test('starts loading', () {
    expect(cubit.state, const TodayStepsState());
  });

  test('today\'s steps against the goal once access is granted', () async {
    health.permissionStatus = HealthPermission.granted;
    await cubit.load(10000);
    expect(cubit.state.status, TodayStepsStatus.ready);
    expect(cubit.state.progress!.goal, 10000);
    expect(cubit.state.progress!.steps, greaterThan(0));
  });

  test('a new goal is read against at once', () async {
    health.permissionStatus = HealthPermission.granted;
    await cubit.load(10000);
    final steps = cubit.state.progress!.steps;
    await cubit.load(1000);
    expect(cubit.state.progress, StepGoalProgress(steps: steps, goal: 1000));
  });

  test('not asked here yet: set up on the Steps page, never asked', () async {
    await cubit.load(10000);
    expect(cubit.state, const TodayStepsState(status: TodayStepsStatus.setUp));
    expect(health.requests, 0);
    expect(prompt.asked, isFalse);
  });

  test(
    'refused, or Health Connect missing: set up on the Steps page',
    () async {
      prompt.asked = true;
      await cubit.load(10000);
      expect(cubit.state.status, TodayStepsStatus.setUp);

      health.status = HealthAvailability.notInstalled;
      await cubit.load(10000);
      expect(cubit.state.status, TodayStepsStatus.setUp);
      expect(health.requests, 0);
    },
  );

  test('access taken back between check and read: set up again', () async {
    health.grantedCheck = true;
    await cubit.load(10000);
    expect(cubit.state.status, TodayStepsStatus.setUp);
  });

  test('no health store: no card', () async {
    health.status = HealthAvailability.unsupported;
    await cubit.load(10000);
    expect(
      cubit.state,
      const TodayStepsState(status: TodayStepsStatus.unavailable),
    );
  });

  test('a failed read is a failure of its own, and a load retries', () async {
    health
      ..permissionStatus = HealthPermission.granted
      ..failure = const HealthFailure();
    await cubit.load(10000);
    expect(
      cubit.state,
      const TodayStepsState(
        status: TodayStepsStatus.failure,
        failure: HealthFailure(),
      ),
    );

    health.failure = null;
    await cubit.load(10000);
    expect(cubit.state.status, TodayStepsStatus.ready);
  });

  test('a newer load wins over one still running', () async {
    final gate = Completer<void>();
    health
      ..permissionStatus = HealthPermission.granted
      ..gate = gate;
    final first = cubit.load(10000);
    await pumpEventQueue();
    health.gate = null;
    await cubit.load(5000);
    expect(cubit.state.progress!.goal, 5000);
    // The older read ends last and is dropped.
    gate.complete();
    await first;
    expect(cubit.state.progress!.goal, 5000);
  });
}
