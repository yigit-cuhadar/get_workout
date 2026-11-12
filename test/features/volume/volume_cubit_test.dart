import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/volume/domain/volume_usecases.dart';
import 'package:get_workout/features/volume/domain/weekly_volume.dart';
import 'package:get_workout/features/volume/presentation/volume_cubit.dart';
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
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const other = AuthUser(id: 'u2', email: 'c@d.co');
  CalendarDate d(int y, int m, int day) => CalendarDate(y, m, day);

  // Wednesday 11 November 2026.
  var now = DateTime(2026, 11, 11, 12);
  final thisMonday = d(2026, 11, 9);
  final thisSunday = d(2026, 11, 8);

  final squats = workout('w1', [
    exercise('squat', [lift(100, 5), lift(100, 5)]),
  ], startedAt: DateTime(2026, 11, 10, 18));

  late MockAuthRepository auth;
  late MockWorkoutRepository workouts;
  late MockCatalogueCubit catalogue;
  late StreamController<AuthUser?> users;
  late StreamController<ExerciseCatalogueState> catalogueStates;

  /// The stream of each range asked for, by user and first date.
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
    when(() => workouts.watchWorkoutsBetween(any(), any(), any())).thenAnswer((
      call,
    ) {
      final [uid, from, _] = call.positionalArguments;
      return ranges
          .putIfAbsent('$uid $from', StreamController<List<Workout>>.broadcast)
          .stream;
    });
  });

  VolumeCubit build({int firstWeekday = DateTime.monday}) => VolumeCubit(
    firstWeekday: firstWeekday,
    watchAuthUser: WatchAuthUser(auth),
    watchVolume: WatchWeeklyVolume(WatchWorkoutsBetween(workouts)),
    catalogue: catalogue,
    clock: () => now,
  );

  /// The first date of the [trendWeeks] weeks ending with [week].
  CalendarDate trendStart(CalendarDate week) =>
      week.addDays(-7 * (trendWeeks - 1));

  StreamController<List<Workout>> range(String uid, CalendarDate week) =>
      ranges['$uid ${trendStart(week)}']!;

  VolumeState ready(
    CalendarDate week,
    List<Workout> done, {
    CalendarDate? thisWeek,
    Map<String, ExerciseMuscles> muscles = const {},
  }) => VolumeState(
    week: week,
    thisWeek: thisWeek ?? thisMonday,
    status: VolumeStatus.ready,
    weeks: volumeWeeks(
      done,
      first: trendStart(week),
      count: trendWeeks,
      muscles: muscles,
    ),
  );

  test('starts loading at the current week', () {
    expect(build().state, VolumeState(week: thisMonday, thisWeek: thisMonday));
    expect(
      build(firstWeekday: DateTime.sunday).state,
      VolumeState(week: thisSunday, thisWeek: thisSunday),
    );
  });

  blocTest<VolumeCubit, VolumeState>(
    'shows the week with the 11 before it, from the user\'s workouts',
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
          d(2026, 8, 24),
          d(2026, 11, 15),
        ),
      ).called(1);
      final shown = cubit.state.shown!;
      expect(shown.start, thisMonday);
      expect(shown.setsOf(Muscle.quads), 2);
    },
  );

  blocTest<VolumeCubit, VolumeState>(
    'weeks start on the locale\'s first weekday',
    build: () => build(firstWeekday: DateTime.sunday),
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      range('u1', thisSunday).add([squats]);
    },
    verify: (cubit) {
      verify(
        () => workouts.watchWorkoutsBetween(
          'u1',
          d(2026, 8, 23),
          d(2026, 11, 14),
        ),
      ).called(1);
      expect(cubit.state.shown!.start, thisSunday);
    },
  );

  blocTest<VolumeCubit, VolumeState>(
    'goes back and forth a week, never past the current one',
    build: build,
    act: (cubit) async {
      users.add(member);
      await pumpEventQueue();
      cubit.nextWeek();
      cubit.previousWeek();
      await pumpEventQueue();
      range('u1', d(2026, 11, 2)).add([squats]);
      await pumpEventQueue();
      cubit.nextWeek();
      await pumpEventQueue();
      range('u1', thisMonday).add([squats]);
    },
    expect: () => [
      VolumeState(week: d(2026, 11, 2), thisWeek: thisMonday),
      ready(d(2026, 11, 2), [squats]),
      VolumeState(week: thisMonday, thisWeek: thisMonday),
      ready(thisMonday, [squats]),
    ],
    verify: (cubit) {
      expect(cubit.state.isThisWeek, isTrue);
      expect(cubit.state.hasNext, isFalse);
    },
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
}
