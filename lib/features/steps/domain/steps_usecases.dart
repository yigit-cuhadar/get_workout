import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';

import 'steps.dart';
import 'steps_prompt.dart';

/// Where step access stands. Without access, or with HealthKit's unknown
/// one, the user is first asked in the app ([StepsAccess.explain]) unless
/// they were asked on this device already; a failure to tell counts as not
/// asked, as asking again is harmless. Access granted needs no asking.
class GetStepsAccess implements UseCase<StepsAccess, NoParams> {
  const GetStepsAccess(this._health, this._prompt);
  final HealthSteps _health;
  final StepsPrompt _prompt;

  @override
  Future<Result<StepsAccess>> call([NoParams params = const NoParams()]) async {
    final availability = await _health.availability();
    switch (availability) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: HealthAvailability.unsupported):
        return const Ok(StepsAccess.unsupported);
      case Ok(value: HealthAvailability.notInstalled):
        return const Ok(StepsAccess.notInstalled);
      case Ok(value: HealthAvailability.available):
    }
    final HealthPermission permission;
    switch (await _health.permission()) {
      case Err(:final failure):
        return Err(failure);
      case Ok(value: HealthPermission.granted):
        return const Ok(StepsAccess.granted);
      case Ok(:final value):
        permission = value;
    }
    if ((await _prompt.askedHere()).valueOrNull != true) {
      return const Ok(StepsAccess.explain);
    }
    return Ok(_access(permission));
  }
}

/// The user said yes in the app: remembers that they were asked here, then
/// shows the system's prompt where it still can.
class AllowStepsAccess implements UseCase<StepsAccess, NoParams> {
  const AllowStepsAccess(this._health, this._prompt);
  final HealthSteps _health;
  final StepsPrompt _prompt;

  @override
  Future<Result<StepsAccess>> call([NoParams params = const NoParams()]) async {
    if ((await _prompt.markAskedHere()).failureOrNull case final failure?) {
      Log.e('steps', 'not remembered as asked: ${failure.message}');
    }
    return (await _health.requestPermission()).map(_access);
  }
}

StepsAccess _access(HealthPermission permission) => switch (permission) {
  HealthPermission.granted => StepsAccess.granted,
  HealthPermission.denied => StepsAccess.denied,
  HealthPermission.undetermined => StepsAccess.undetermined,
};

/// The last [stepHistoryDays] days by the clock, today counted up to now.
class GetStepsHistory implements UseCase<StepsHistory, NoParams> {
  GetStepsHistory(this._health, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final HealthSteps _health;
  final DateTime Function() _clock;

  @override
  Future<Result<StepsHistory>> call([NoParams params = const NoParams()]) {
    final now = _clock();
    final first = DateTime(now.year, now.month, now.day - stepHistoryDays + 1);
    return _health
        .dailySteps(first, now)
        .then((result) => result.map(StepsHistory.new));
  }
}

/// Today's steps so far against the daily goal (`settings.stepGoal`), for
/// the Today tab. Fails like [HealthSteps.stepsOn]; on iOS a refusal reads
/// as zero.
class GetTodaySteps implements UseCase<StepGoalProgress, int> {
  GetTodaySteps(this._health, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final HealthSteps _health;
  final DateTime Function() _clock;

  @override
  Future<Result<StepGoalProgress>> call(int goal) async =>
      (await _health.stepsOn(_clock()))
          .map((steps) => StepGoalProgress(steps: steps, goal: goal));
}
