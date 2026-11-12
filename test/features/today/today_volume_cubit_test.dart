import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/today/presentation/today_volume_cubit.dart';
import 'package:get_workout/features/volume/domain/volume_usecases.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../workout/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  const alice = AuthUser(id: 'u1', email: 'a@b.co');
  const bob = AuthUser(id: 'u2', email: 'c@d.co');
  CalendarDate d(int y, int m, int day) => CalendarDate(y, m, day);

  // Wednesday 11 November 2026.
  var now = DateTime(2026, 11, 11, 12);
  final sunday = d(2026, 11, 8);

  final squats = workout('w1', [
    exercise('squat', [lift(100, 5), lift(100, 5)]),
  ], startedAt: DateTime(2026, 11, 10, 18));

  late MockAuthRepository auth;
  late MockWorkoutRepository workouts;
  late MockCatalogueCubit catalogue;
  late StreamController<AuthUser?> users;
  late StreamController<ExerciseCatalogueState> catalogueStates;

  /// The stream of each range asked for, by user, first and last date.
  late Map<String, StreamController<List<Workout>>> ranges;

  setUpAll(() => registerFallbackValue(d(2026, 1, 1)));

  setUp(() {
    now = DateTime(2026, 11, 11, 12);
    auth = MockAuthRepository();
    workouts = MockWorkoutRepository();
    catalogue = MockCatalogueCubit();
    users = StreamController<AuthUser?>.broadcast();
    catalogueStates = StreamController<ExerciseCatalogueState>.broadcast();
    ranges = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => catalogue.state).thenReturn(const CatalogueLoading());
    when(() => catalogue.stream).thenAnswer((_) => catalogueStates.stream);
    when(
      () => workouts.watchWorkoutsBetween(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((call) {
      final uid = call.positionalArguments.single;
      final from = call.namedArguments[#from];
      final to = call.namedArguments[#to];
      return ranges
          .putIfAbsent(
            '$uid $from $to',
            StreamController<List<Workout>>.broadcast,
          )
          .stream;
    });
  });

  TodayVolumeCubit build() => TodayVolumeCubit(
    firstWeekday: DateTime.sunday,
    watchAuthUser: WatchAuthUser(auth),
    watchVolume: WatchWeeklyVolume(WatchWorkoutsBetween(workouts)),
    catalogue: catalogue,
    clock: () => now,
  );

  StreamController<List<Workout>> week(String uid, CalendarDate start) =>
      ranges['$uid $start ${start.addDays(6)}']!;

  TodayVolumeState ready(
    List<Workout> done, {
    CalendarDate? start,
    Map<String, ExerciseMuscles> muscles = const {},
  }) => TodayVolumeState(
    weekStart: start ?? sunday,
    status: TodayVolumeStatus.ready,
    week: volumeWeeks(
      done,
      first: start ?? sunday,
      count: 1,
      muscles: muscles,
    ).single,
  );

  test('starts loading at the locale\'s current week', () {
    expect(build().state, TodayVolumeState(weekStart: sunday));
  });

  blocTest<TodayVolumeCubit, TodayVolumeState>(
    'reads this week alone',
    build: build,
    act: (_) async {
      users.add(alice);
      await pumpEventQueue();
      week('u1', sunday).add([squats]);
    },
    expect: () => [
      ready([squats]),
    ],
    verify: (cubit) {
      verify(
        () => workouts.watchWorkoutsBetween(
          'u1',
          from: sunday,
          to: d(2026, 11, 14),
        ),
      ).called(1);
      expect(cubit.state.week!.setsOf(Muscle.quads), 2);
    },
  );

  blocTest<TodayVolumeCubit, TodayVolumeState>(
    'a failed read is a failure of its own, retried on request',
    build: build,
    act: (cubit) async {
      users.add(alice);
      await pumpEventQueue();
      week('u1', sunday).addError(const NetworkFailure('offline'));
      await pumpEventQueue();
      cubit.retry();
      await pumpEventQueue();
      week('u1', sunday).add([squats]);
    },
    expect: () => [
      TodayVolumeState(
        weekStart: sunday,
        status: TodayVolumeStatus.failure,
        failure: const NetworkFailure('offline'),
      ),
      TodayVolumeState(weekStart: sunday),
      ready([squats]),
    ],
  );

  blocTest<TodayVolumeCubit, TodayVolumeState>(
    'counts the library\'s muscles once it loads, keeping the week meanwhile',
    build: build,
    act: (_) async {
      users.add(alice);
      await pumpEventQueue();
      week('u1', sunday).add([squats]);
      await pumpEventQueue();
      final library = CatalogueReady([
        Exercise.custom(
          id: 'squat',
          name: 'Squat',
          loggingType: LoggingType.weightReps,
          mainMuscles: const [Muscle.glute],
        ),
      ]);
      when(() => catalogue.state).thenReturn(library);
      catalogueStates.add(library);
      await pumpEventQueue();
      week('u1', sunday).add([squats]);
    },
    expect: () => [
      ready([squats]),
      ready(
        [squats],
        muscles: {
          'squat': (main: const [Muscle.glute], secondary: const <Muscle>[]),
        },
      ),
    ],
  );

  blocTest<TodayVolumeCubit, TodayVolumeState>(
    'a user change drops the previous user\'s week',
    build: build,
    act: (_) async {
      users.add(alice);
      await pumpEventQueue();
      week('u1', sunday).add([squats]);
      await pumpEventQueue();
      users.add(bob);
      await pumpEventQueue();
      // Alice's week no longer counts.
      week('u1', sunday).add([squats]);
      await pumpEventQueue();
      week('u2', sunday).add(const []);
    },
    expect: () => [
      ready([squats]),
      TodayVolumeState(weekStart: sunday),
      ready(const []),
    ],
  );

  blocTest<TodayVolumeCubit, TodayVolumeState>(
    'follows the next week once the current one ends',
    build: build,
    act: (cubit) async {
      users.add(alice);
      await pumpEventQueue();
      week('u1', sunday).add([squats]);
      await pumpEventQueue();
      now = DateTime(2026, 11, 14, 23);
      cubit.refreshNow();
      now = DateTime(2026, 11, 15, 1);
      cubit.refreshNow();
      await pumpEventQueue();
      week('u1', d(2026, 11, 15)).add(const []);
    },
    expect: () => [
      ready([squats]),
      TodayVolumeState(weekStart: d(2026, 11, 15)),
      ready(const [], start: d(2026, 11, 15)),
    ],
  );
}
