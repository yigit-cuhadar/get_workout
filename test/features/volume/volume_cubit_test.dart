import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/volume/domain/volume_usecases.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:get_workout/features/volume/presentation/volume_cubit.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart' show FakePremium;
import '../workout/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const other = AuthUser(id: 'u2', email: 'c@d.co');
  CalendarDate d(int y, int m, int day) => CalendarDate(y, m, day);

  // Wednesday 11 November 2026.
  var now = DateTime(2026, 11, 11, 12);
  final thisMonday = d(2026, 11, 9);
  final lastMonday = d(2026, 11, 2);
  final thisSunday = d(2026, 11, 8);

  final squats = workout('w1', [
    exercise('squat', [lift(100, 5), lift(100, 5)]),
  ], startedAt: DateTime(2026, 11, 10, 18));

  late MockAuthRepository auth;
  late MockWorkoutRepository workouts;
  late MockCatalogueCubit catalogue;
  late FakePremium premium;
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
    premium = FakePremium();
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

  VolumeCubit build({int firstWeekday = DateTime.monday}) => VolumeCubit(
    firstWeekday: firstWeekday,
    watchAuthUser: WatchAuthUser(auth),
    watchVolume: WatchWeeklyVolume(WatchWorkoutsBetween(workouts)),
    catalogue: catalogue,
    watchPremium: WatchPremium(premium),
    clock: () => now,
  );

  /// The first date of the [count] weeks ending with [week].
  CalendarDate start(CalendarDate week, int count) =>
      week.addDays(-7 * (count - 1));

  /// The stream of [uid]'s [count] weeks ending with [week].
  StreamController<List<Workout>> range(
    String uid,
    CalendarDate week, {
    int count = 1,
  }) => ranges['$uid ${start(week, count)} ${week.addDays(6)}']!;

  List<WeekVolume> weeksOf(
    CalendarDate week,
    List<Workout> done, {
    int count = 1,
    Map<String, ExerciseMuscles> muscles = const {},
  }) => volumeWeeks(
    done,
    first: start(week, count),
    count: count,
    muscles: muscles,
  );

  VolumeState ready(
    CalendarDate week,
    List<Workout> done, {
    int count = 1,
    Map<String, ExerciseMuscles> muscles = const {},
  }) => VolumeState(
    week: week,
    thisWeek: thisMonday,
    status: VolumeStatus.ready,
    weeks: weeksOf(week, done, count: count, muscles: muscles),
  );

  test('starts loading at the current week', () {
    expect(build().state, VolumeState(week: thisMonday, thisWeek: thisMonday));
    expect(
      build(firstWeekday: DateTime.sunday).state,
      VolumeState(week: thisSunday, thisWeek: thisSunday),
    );
  });

  blocTest<VolumeCubit, VolumeState>(
    'without Premium reads the week shown alone',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
    },
    expect: () => [
      ready(thisMonday, [squats]),
    ],
    verify: (cubit) {
      verify(
        () => workouts.watchWorkoutsBetween(
          'u1',
          from: thisMonday,
          to: d(2026, 11, 15),
        ),
      ).called(1);
      expect(cubit.state.shown!.setsOf(Muscle.quads), 2);
      expect(cubit.state.hasTrend, isFalse);
    },
  );

  blocTest<VolumeCubit, VolumeState>(
    'with Premium reads the 12 weeks ending with it, and the week alone '
    'again once Premium ends',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
      await pumpEventQueue();
      premium.controller.add(true);
      await pumpEventQueue();
      range('u1', thisMonday, count: trendWeeks).add([squats]);
      await pumpEventQueue();
      premium.controller.add(false);
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
    },
    expect: () => [
      ready(thisMonday, [squats]),
      // The week stays on screen while the trend loads.
      VolumeState(
        week: thisMonday,
        thisWeek: thisMonday,
        weeks: weeksOf(thisMonday, [squats]),
      ),
      ready(thisMonday, [squats], count: trendWeeks),
      VolumeState(
        week: thisMonday,
        thisWeek: thisMonday,
        weeks: weeksOf(thisMonday, [squats], count: trendWeeks),
      ),
      ready(thisMonday, [squats]),
    ],
    verify: (_) => verify(
      () => workouts.watchWorkoutsBetween(
        'u1',
        from: d(2026, 8, 24),
        to: d(2026, 11, 15),
      ),
    ).called(1),
  );

  blocTest<VolumeCubit, VolumeState>(
    'an unknown Premium status reads the week alone',
    build: build,
    act: (cubit) async {
      premium.controller.add(null);
      users.add(member);
      await pumpEventQueue();
      range('u1', thisMonday).add(const []);
    },
    expect: () => [ready(thisMonday, const [])],
  );

  blocTest<VolumeCubit, VolumeState>(
    'weeks start on the locale\'s first weekday',
    build: () => build(firstWeekday: DateTime.sunday),
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
    },
    verify: (cubit) => verify(
      () => workouts.watchWorkoutsBetween(
        'u1',
        from: thisSunday,
        to: d(2026, 11, 14),
      ),
    ).called(1),
  );

  blocTest<VolumeCubit, VolumeState>(
    'goes back and forth a week, never past the current one, keeping the '
    'week on screen while the next loads',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
      await pumpEventQueue();
      cubit.nextWeek();
      cubit.previousWeek();
      await pumpEventQueue();
      range('u1', lastMonday).add(const []);
      await pumpEventQueue();
      cubit.nextWeek();
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
    },
    expect: () => [
      ready(thisMonday, [squats]),
      VolumeState(
        week: lastMonday,
        thisWeek: thisMonday,
        weeks: weeksOf(thisMonday, [squats]),
      ),
      ready(lastMonday, const []),
      VolumeState(
        week: thisMonday,
        thisWeek: thisMonday,
        weeks: weeksOf(lastMonday, const []),
      ),
      ready(thisMonday, [squats]),
    ],
    verify: (cubit) {
      expect(cubit.state.isThisWeek, isTrue);
      expect(cubit.state.hasNext, isFalse);
    },
  );

  blocTest<VolumeCubit, VolumeState>(
    'drops what the week left behind still delivers',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      final left = range('u1', thisMonday);
      cubit.previousWeek();
      left.add([squats]);
      await pumpEventQueue();
      left.addError(const NetworkFailure());
      await pumpEventQueue();
      range('u1', lastMonday).add(const []);
    },
    expect: () => [
      VolumeState(week: lastMonday, thisWeek: thisMonday),
      ready(lastMonday, const []),
    ],
  );

  blocTest<VolumeCubit, VolumeState>(
    'a new week that began while the page was open becomes the current one',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      cubit.previousWeek();
      now = DateTime(2026, 11, 16, 8);
      cubit.nextWeek();
      cubit.nextWeek();
    },
    skip: 1,
    expect: () => [
      VolumeState(week: thisMonday, thisWeek: d(2026, 11, 16)),
      VolumeState(week: d(2026, 11, 16), thisWeek: d(2026, 11, 16)),
    ],
  );

  blocTest<VolumeCubit, VolumeState>(
    'counts the library\'s muscles once it is loaded, keeping the week '
    'on screen meanwhile',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
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
      range('u1', thisMonday).add([squats]);
    },
    expect: () => [
      ready(thisMonday, [squats]),
      VolumeState(
        week: thisMonday,
        thisWeek: thisMonday,
        weeks: weeksOf(thisMonday, [squats]),
      ),
      ready(
        thisMonday,
        [squats],
        muscles: {
          'squat': (main: [Muscle.glute], secondary: <Muscle>[]),
        },
      ),
    ],
    verify: (cubit) {
      expect(cubit.state.shown!.setsOf(Muscle.glute), 2);
      expect(cubit.state.shown!.setsOf(Muscle.quads), 0);
    },
  );

  blocTest<VolumeCubit, VolumeState>(
    'a failure offers a retry',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      range('u1', thisMonday).addError(const NetworkFailure());
      await pumpEventQueue();
      ranges.clear();
      cubit.retry();
      await pumpEventQueue();
      range('u1', thisMonday).add(const []);
    },
    expect: () => [
      VolumeState(
        week: thisMonday,
        thisWeek: thisMonday,
        status: VolumeStatus.failure,
        failure: const NetworkFailure(),
      ),
      VolumeState(week: thisMonday, thisWeek: thisMonday),
      ready(thisMonday, const []),
    ],
  );

  blocTest<VolumeCubit, VolumeState>(
    'a user change drops the previous user\'s weeks',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
      await pumpEventQueue();
      users.add(other);
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
      range('u2', thisMonday).add(const []);
    },
    expect: () => [
      ready(thisMonday, [squats]),
      VolumeState(week: thisMonday, thisWeek: thisMonday),
      ready(thisMonday, const []),
    ],
  );

  group('a new first weekday', () {
    blocTest<VolumeCubit, VolumeState>(
      'moves the current week to the new current week',
      build: build,
      act: (cubit) async {
        users.add(member);
        await pumpEventQueue();
        range('u1', thisMonday).add([squats]);
        await pumpEventQueue();
        cubit.changeFirstWeekday(DateTime.monday);
        cubit.changeFirstWeekday(DateTime.sunday);
        await pumpEventQueue();
        range('u1', thisSunday).add([squats]);
      },
      expect: () => [
        ready(thisMonday, [squats]),
        VolumeState(week: thisSunday, thisWeek: thisSunday),
        VolumeState(
          week: thisSunday,
          thisWeek: thisSunday,
          status: VolumeStatus.ready,
          weeks: weeksOf(thisSunday, [squats]),
        ),
      ],
    );

    blocTest<VolumeCubit, VolumeState>(
      'moves an earlier week to the one sharing most of its days',
      build: build,
      act: (cubit) async {
        users.add(member);
        await pumpEventQueue();
        cubit.previousWeek();
        await pumpEventQueue();
        cubit.changeFirstWeekday(DateTime.saturday);
        await pumpEventQueue();
      },
      verify: (cubit) {
        // Monday 2 to Sunday 8 becomes Saturday 31 October to Friday 6.
        expect(cubit.state.week, d(2026, 10, 31));
        expect(cubit.state.thisWeek, d(2026, 11, 7));
        expect(cubit.state.status, VolumeStatus.loading);
        verify(
          () => workouts.watchWorkoutsBetween(
            'u1',
            from: d(2026, 10, 31),
            to: d(2026, 11, 6),
          ),
        ).called(1);
      },
    );
  });
}
