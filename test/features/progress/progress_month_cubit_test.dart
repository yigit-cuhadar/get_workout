import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/progress/domain/progress_usecases.dart';
import 'package:get_workout/features/progress/presentation/progress_month_cubit.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../workout/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

void main() {
  const alice = AuthUser(id: 'u1', email: 'a@b.co');
  const bob = AuthUser(id: 'u2', email: 'c@d.co');
  final november = CalendarDate(2026, 11, 1);
  final december = CalendarDate(2026, 12, 1);

  late DateTime now;
  late MockAuthRepository auth;
  late MockWorkoutRepository workouts;
  late StreamController<AuthUser?> users;

  /// The stream of each range asked for, by user and first date.
  late Map<String, StreamController<List<Workout>>> ranges;

  setUpAll(() => registerFallbackValue(CalendarDate(2026, 1, 1)));

  setUp(() {
    now = DateTime(2026, 11, 13, 12);
    auth = MockAuthRepository();
    workouts = MockWorkoutRepository();
    users = StreamController<AuthUser?>.broadcast();
    ranges = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(
      () => workouts.watchWorkoutsBetween(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((call) {
      final uid = call.positionalArguments.single;
      final from = call.namedArguments[#from];
      return ranges
          .putIfAbsent('$uid $from', StreamController<List<Workout>>.broadcast)
          .stream;
    });
  });

  tearDown(() => users.close());

  ProgressMonthCubit build() => ProgressMonthCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchCount: WatchWorkoutCountInMonth(workouts),
    clock: () => now,
  );

  final two = [workout('w1', const []), workout('w2', const [])];

  test('starts loading at the current month', () {
    expect(build().state, ProgressMonthState(month: november));
  });

  blocTest<ProgressMonthCubit, ProgressMonthState>(
    'counts this month\'s workouts, live',
    build: build,
    act: (_) async {
      users.add(alice);
      await pumpEventQueue();
      ranges['u1 $november']!.add(two);
      await pumpEventQueue();
      ranges['u1 $november']!.add(const []);
    },
    expect: () => [
      ProgressMonthState(
        month: november,
        status: ProgressMonthStatus.ready,
        workouts: 2,
      ),
      ProgressMonthState(month: november, status: ProgressMonthStatus.ready),
    ],
  );

  blocTest<ProgressMonthCubit, ProgressMonthState>(
    'a failed read is a failure, retried on request',
    build: build,
    act: (cubit) async {
      users.add(alice);
      await pumpEventQueue();
      ranges['u1 $november']!.addError(const NetworkFailure('offline'));
      await pumpEventQueue();
      cubit.retry();
      await pumpEventQueue();
      ranges['u1 $november']!.add(two);
    },
    expect: () => [
      ProgressMonthState(
        month: november,
        status: ProgressMonthStatus.failure,
        failure: const NetworkFailure('offline'),
      ),
      ProgressMonthState(month: november),
      ProgressMonthState(
        month: november,
        status: ProgressMonthStatus.ready,
        workouts: 2,
      ),
    ],
  );

  blocTest<ProgressMonthCubit, ProgressMonthState>(
    'moves to the new month only once it has begun',
    build: build,
    act: (cubit) async {
      users.add(alice);
      await pumpEventQueue();
      ranges['u1 $november']!.add(two);
      await pumpEventQueue();
      now = DateTime(2026, 11, 30, 23);
      cubit.refreshNow();
      now = DateTime(2026, 12, 1, 7);
      cubit.refreshNow();
      await pumpEventQueue();
      // The month left may still deliver; it no longer counts.
      ranges['u1 $november']!.add(const []);
      ranges['u1 $december']!.add(two);
    },
    expect: () => [
      ProgressMonthState(
        month: november,
        status: ProgressMonthStatus.ready,
        workouts: 2,
      ),
      ProgressMonthState(month: december),
      ProgressMonthState(
        month: december,
        status: ProgressMonthStatus.ready,
        workouts: 2,
      ),
    ],
  );

  blocTest<ProgressMonthCubit, ProgressMonthState>(
    'a user change drops the previous user\'s count',
    build: build,
    act: (_) async {
      users.add(alice);
      await pumpEventQueue();
      ranges['u1 $november']!.add(two);
      await pumpEventQueue();
      users.add(bob);
      await pumpEventQueue();
      ranges['u1 $november']!.add(const []);
      ranges['u2 $november']!.add(const []);
    },
    expect: () => [
      ProgressMonthState(
        month: november,
        status: ProgressMonthStatus.ready,
        workouts: 2,
      ),
      ProgressMonthState(month: november),
      ProgressMonthState(month: november, status: ProgressMonthStatus.ready),
    ],
  );
}
