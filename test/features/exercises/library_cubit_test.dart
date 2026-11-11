import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_queries.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';

import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

class MockCatalogueCubit extends MockCubit<ExerciseCatalogueState>
    implements ExerciseCatalogueCubit {}

class MockFavoritesCubit extends MockCubit<FavoritesState>
    implements FavoritesCubit {}

class MockEquipmentCubit extends MockCubit<EquipmentState>
    implements EquipmentCubit {}

final _benchPress = exercise(
  'bench_press',
  name: 'Bench Press',
  popularity: 1,
  main: [Muscle.pec],
  secondary: [Muscle.triceps],
  equipment: [Equipment.barbell, Equipment.bench],
  equipmentAlternatives: [
    [Equipment.dumbbell, Equipment.bench],
  ],
  level: Level.intermediate,
);
final _pushUp = exercise(
  'push_up',
  name: 'Push-Up',
  aliases: ['Press-up'],
  popularity: 2,
  main: [Muscle.pec],
);
final _squat = exercise(
  'squat',
  name: 'Back Squat',
  popularity: 3,
  main: [Muscle.quads],
  equipment: [Equipment.barbell],
  pattern: MovementPattern.squat,
  level: Level.intermediate,
);
final _curl = exercise(
  'curl',
  name: 'Dumbbell Curl',
  popularity: 4,
  main: [Muscle.biceps],
  equipment: [Equipment.dumbbell],
  pattern: MovementPattern.isolation,
);
final _all = [_benchPress, _pushUp, _squat, _curl];

void main() {
  late MockCatalogueCubit catalogue;
  late MockFavoritesCubit favorites;
  late MockEquipmentCubit equipment;
  late MockAuthRepository auth;
  late StreamController<AuthUser?> users;
  late StreamController<ExerciseCatalogueState> catalogueChanges;
  late StreamController<FavoritesState> favoriteChanges;
  late StreamController<EquipmentState> equipmentChanges;
  late StreamController<Failure> rejectedWrites;
  late MockCustomExerciseRepository customRepository;

  setUp(() {
    catalogue = MockCatalogueCubit();
    favorites = MockFavoritesCubit();
    equipment = MockEquipmentCubit();
    users = StreamController();
    auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    catalogueChanges = StreamController.broadcast();
    favoriteChanges = StreamController.broadcast();
    equipmentChanges = StreamController.broadcast();
    rejectedWrites = StreamController.broadcast();
    customRepository = MockCustomExerciseRepository();
    when(() => customRepository.rejectedWrites)
        .thenAnswer((_) => rejectedWrites.stream);
    whenListen(
      catalogue,
      catalogueChanges.stream,
      initialState: CatalogueReady(_all),
    );
    whenListen(
      favorites,
      favoriteChanges.stream,
      initialState: const FavoritesState({}),
    );
    whenListen(
      equipment,
      equipmentChanges.stream,
      initialState: const EquipmentState(null),
    );
  });

  tearDown(() async {
    await catalogueChanges.close();
    await favoriteChanges.close();
    await equipmentChanges.close();
    await users.close();
    await rejectedWrites.close();
  });

  LibraryCubit build() => LibraryCubit(
    watchAuthUser: WatchAuthUser(auth),
    catalogue: catalogue,
    favorites: favorites,
    equipment: equipment,
    watchRejectedCustomWrites: WatchRejectedCustomExerciseWrites(
      customRepository,
    ),
  );

  List<String> results(LibraryCubit cubit) => ids(cubit.state.results);

  test('starts on the body with every exercise by popularity', () {
    final cubit = build();
    expect(cubit.state.view, LibraryView.body);
    expect(results(cubit), ['bench_press', 'push_up', 'squat', 'curl']);
    expect(cubit.state.equipmentChosen, isFalse);
  });

  test('a catalogue still loading gives no results', () {
    whenListen(
      catalogue,
      catalogueChanges.stream,
      initialState: const CatalogueLoading(),
    );
    expect(build().state.results, isEmpty);
  });

  test('the view is kept', () {
    final cubit = build()..setView(LibraryView.list);
    expect(cubit.state.view, LibraryView.list);
  });

  group('search', () {
    test('matches names and aliases', () {
      final cubit = build()..setQuery('press');
      // "Bench Press" by name, "Push-Up" by its alias "Press-up".
      expect(results(cubit), ['bench_press', 'push_up']);
    });

    test('ranks names starting with the query first under popularity', () {
      final cubit = build()..setQuery('b');
      // "Back Squat" starts with b; "Dumbbell Curl" only contains it.
      expect(results(cubit), ['bench_press', 'squat', 'curl']);
    });

    test('A-Z orders the matches by name', () {
      final cubit = build()
        ..setQuery('b')
        ..setSort(ExerciseSort.alphabetical);
      expect(results(cubit), ['squat', 'bench_press', 'curl']);
    });

    test('a blank query shows everything', () {
      final cubit = build()
        ..setQuery('curl')
        ..setQuery('  ');
      expect(results(cubit), hasLength(4));
    });
  });

  test('A-Z sorts the whole list by name', () {
    final cubit = build()..setSort(ExerciseSort.alphabetical);
    expect(results(cubit), ['squat', 'bench_press', 'curl', 'push_up']);
  });

  group('filters', () {
    test('a muscle matches main and secondary muscles', () {
      final cubit = build()..toggleMuscle(Muscle.triceps);
      expect(results(cubit), ['bench_press']);
    });

    test('values of one criterion widen, criteria narrow', () {
      final cubit = build()
        ..toggleEquipment(Equipment.barbell)
        ..toggleEquipment(Equipment.dumbbell);
      expect(results(cubit), ['bench_press', 'squat', 'curl']);

      cubit.toggleLevel(Level.intermediate);
      expect(results(cubit), ['bench_press', 'squat']);

      cubit.toggleMovementPattern(MovementPattern.squat);
      expect(results(cubit), ['squat']);
    });

    test('toggling a value again removes it', () {
      final cubit = build()
        ..toggleMuscle(Muscle.biceps)
        ..toggleMuscle(Muscle.biceps);
      expect(cubit.state.filter.isEmpty, isTrue);
      expect(results(cubit), hasLength(4));
    });

    test('combine with search and sort', () {
      final cubit = build()
        ..toggleMuscle(Muscle.pec)
        ..setQuery('p')
        ..setSort(ExerciseSort.alphabetical);
      expect(results(cubit), ['bench_press', 'push_up']);
    });

    test('clear all removes every filter but keeps search and sort', () {
      final cubit = build()
        ..setQuery('u')
        ..setSort(ExerciseSort.alphabetical)
        ..toggleMuscle(Muscle.quads)
        ..setOnlyFavorites(true)
        ..clearFilters();
      expect(cubit.state.filter, const LibraryFilter());
      expect(cubit.state.query, 'u');
      expect(cubit.state.sort, ExerciseSort.alphabetical);
      expect(results(cubit), ['squat', 'curl', 'push_up']);
    });
  });

  group('favourites', () {
    test('only favourites shows just those, and follows changes', () async {
      final cubit = build()..setOnlyFavorites(true);
      expect(results(cubit), isEmpty);

      favoriteChanges.add(const FavoritesState({'curl', 'push_up'}));
      await pumpEventQueue();
      expect(results(cubit), ['push_up', 'curl']);

      favoriteChanges.add(const FavoritesState({'curl'}));
      await pumpEventQueue();
      expect(results(cubit), ['curl']);
    });
  });

  group('my equipment', () {
    test('only doable uses the owned equipment and its alternatives', () async {
      final cubit = build();
      equipmentChanges.add(
        const EquipmentState({Equipment.dumbbell, Equipment.bench}),
      );
      await pumpEventQueue();
      expect(cubit.state.equipmentChosen, isTrue);

      cubit.setOnlyDoable(true);
      // Bench press through its dumbbell set, push-ups need nothing.
      expect(results(cubit), ['bench_press', 'push_up', 'curl']);
    });

    test('follows equipment changes', () async {
      final cubit = build();
      equipmentChanges.add(const EquipmentState({Equipment.barbell}));
      await pumpEventQueue();
      cubit.setOnlyDoable(true);
      expect(results(cubit), ['push_up', 'squat']);

      equipmentChanges.add(const EquipmentState({Equipment.dumbbell}));
      await pumpEventQueue();
      expect(results(cubit), ['push_up', 'curl']);
    });

    test('unknown equipment counts as bodyweight only', () {
      final cubit = build()..setOnlyDoable(true);
      expect(cubit.state.filter.onlyDoable, isTrue);
      expect(results(cubit), ['push_up']);
    });
  });

  group('a user change', () {
    const guest = AuthUser(id: 'g1', isAnonymous: true);
    const member = AuthUser(id: 'u1', email: 'a@b.co');

    LibraryCubit browsing() => build()
      ..setView(LibraryView.list)
      ..setQuery('b')
      ..setSort(ExerciseSort.alphabetical)
      ..toggleMuscle(Muscle.pec)
      ..toggleEquipment(Equipment.barbell)
      ..toggleLevel(Level.intermediate)
      ..toggleMovementPattern(MovementPattern.horizontalPush)
      ..setOnlyFavorites(true)
      ..setOnlyDoable(true);

    void expectFresh(LibraryCubit cubit) {
      expect(cubit.state.query, '');
      expect(cubit.state.sort, ExerciseSort.popularity);
      expect(cubit.state.filter, const LibraryFilter());
      expect(results(cubit), ['bench_press', 'push_up', 'squat', 'curl']);
      // The view is a preference of the device, not of the user.
      expect(cubit.state.view, LibraryView.list);
    }

    test('resets search, sort and every filter', () async {
      final cubit = browsing();
      users.add(guest);
      await pumpEventQueue();
      expect(cubit.state.query, 'b', reason: 'the first user is no change');

      users.add(member);
      await pumpEventQueue();

      expectFresh(cubit);
    });

    test('resets also when the previous user had chosen equipment', () async {
      final cubit = build();
      users.add(guest);
      equipmentChanges.add(const EquipmentState({Equipment.barbell}));
      await pumpEventQueue();
      cubit
        ..setView(LibraryView.list)
        ..setQuery('b')
        ..setOnlyDoable(true);

      users.add(member);
      equipmentChanges.add(const EquipmentState(null));
      await pumpEventQueue();

      expectFresh(cubit);
      expect(cubit.state.equipmentChosen, isFalse);
    });

    test('resets when signing out', () async {
      final cubit = browsing();
      users.add(member);
      await pumpEventQueue();

      users.add(null);
      await pumpEventQueue();

      expectFresh(cubit);
    });

    test('an update of the same user keeps everything', () async {
      final cubit = browsing();
      users
        ..add(guest)
        ..add(const AuthUser(id: 'g1', isAnonymous: true, displayName: 'G'));
      await pumpEventQueue();
      expect(cubit.state.query, 'b');
      expect(cubit.state.filter.onlyFavorites, isTrue);
    });
  });

  group('catalogue changes', () {
    test('recompute the results and keep the query and filters', () async {
      final cubit = build()
        ..toggleMuscle(Muscle.pec)
        ..setQuery('p');
      final pikePushUp = exercise('pike_push_up', name: 'Pike Push-Up');

      // Bench press was retired, a new one arrived.
      catalogueChanges.add(
        CatalogueReady([_pushUp, _squat, _curl, pikePushUp]),
      );
      await pumpEventQueue();

      expect(results(cubit), ['push_up', 'pike_push_up']);
      expect(cubit.state.query, 'p');
      expect(cubit.state.filter.muscles, {Muscle.pec});
    });

    test('a later failed or loading state keeps the last list', () async {
      final cubit = build();
      catalogueChanges
        ..add(const CatalogueLoading())
        ..add(const CatalogueFailed(NetworkFailure()));
      await pumpEventQueue();
      expect(results(cubit), hasLength(4));
    });
  });

  group('muscle selection', () {
    test('groups the exercises of the muscle, and clears', () {
      final cubit = build()..selectMuscle(Muscle.triceps);
      expect(cubit.state.selectedMuscle, Muscle.triceps);
      expect(cubit.state.muscleExercises!.main, isEmpty);
      expect(ids(cubit.state.muscleExercises!.alsoWorks), ['bench_press']);

      cubit.selectMuscle(null);
      expect(cubit.state.selectedMuscle, isNull);
      expect(cubit.state.muscleExercises, isNull);
    });

    test('ignores the list filters', () {
      final cubit = build()
        ..toggleMuscle(Muscle.quads)
        ..selectMuscle(Muscle.pec);
      expect(ids(cubit.state.muscleExercises!.main), [
        'bench_press',
        'push_up',
      ]);
    });

    test('follows catalogue changes while open', () async {
      final cubit = build()..selectMuscle(Muscle.pec);
      catalogueChanges.add(CatalogueReady([_pushUp]));
      await pumpEventQueue();
      expect(ids(cubit.state.muscleExercises!.main), ['push_up']);
    });
  });

  test('search and sort use the given language, falling back to English', () {
    final cubit = build();
    final translated = exercise(
      'row',
      name: 'Row',
      translations: {'tr': const ExerciseText(name: 'Kürek')},
    );
    catalogueChanges.add(CatalogueReady([translated, _curl]));
    return pumpEventQueue().then((_) {
      cubit
        ..setLanguage('tr')
        ..setQuery('kurek');
      expect(results(cubit), ['row']);
      cubit
        ..setQuery('')
        ..setSort(ExerciseSort.alphabetical);
      // "Dumbbell Curl" has no Turkish text and sorts by its English name.
      expect(results(cubit), ['curl', 'row']);
    });
  });

  group('custom exercises', () {
    final band = Exercise.custom(
      id: 'custom_band',
      name: 'Band Fly',
      loggingType: LoggingType.reps,
      mainMuscles: const [Muscle.pec],
      equipment: const [Equipment.resistanceBand],
    );
    final noEquipment = Exercise.custom(
      id: 'custom_plank',
      name: 'Wall Plank',
      loggingType: LoggingType.duration,
      mainMuscles: const [Muscle.abdominal],
      secondaryMuscles: const [Muscle.pec],
    );

    setUp(
      () => whenListen(
        catalogue,
        catalogueChanges.stream,
        initialState: CatalogueReady(
          withCustomExercises(_all, [noEquipment, band]),
        ),
      ),
    );

    test('come first, by name, and are found by search', () {
      final cubit = build();
      expect(results(cubit), [
        'custom_band',
        'custom_plank',
        'bench_press',
        'push_up',
        'squat',
        'curl',
      ]);
      cubit.setQuery('band');
      expect(results(cubit), ['custom_band']);
    });

    test('match muscle and equipment filters, never level or pattern', () {
      final cubit = build()..toggleMuscle(Muscle.pec);
      expect(results(cubit), [
        'custom_band',
        'custom_plank',
        'bench_press',
        'push_up',
      ]);
      cubit
        ..clearFilters()
        ..toggleEquipment(Equipment.resistanceBand);
      expect(results(cubit), ['custom_band']);
      cubit
        ..clearFilters()
        ..toggleLevel(Level.beginner);
      expect(results(cubit), isNot(contains('custom_band')));
      cubit
        ..clearFilters()
        ..toggleMovementPattern(MovementPattern.horizontalPush);
      expect(results(cubit), ['bench_press', 'push_up']);
    });

    test('without equipment count as doable with any', () {
      final cubit = build()..setOnlyDoable(true);
      expect(results(cubit), ['custom_plank', 'push_up']);
    });

    blocTest<LibraryCubit, LibraryState>(
      'show in favourites and on the muscle sheet',
      build: build,
      act: (cubit) async {
        favoriteChanges.add(const FavoritesState({'custom_band'}));
        await pumpEventQueue();
        cubit
          ..setOnlyFavorites(true)
          ..selectMuscle(Muscle.pec);
      },
      verify: (cubit) {
        expect(results(cubit), ['custom_band']);
        expect(ids(cubit.state.muscleExercises!.main), [
          'custom_band',
          'bench_press',
          'push_up',
        ]);
        expect(ids(cubit.state.muscleExercises!.alsoWorks), ['custom_plank']);
      },
    );
  });

  blocTest<LibraryCubit, LibraryState>(
    'a refused custom exercise write is flagged until shown',
    build: build,
    act: (cubit) async {
      rejectedWrites.add(const PermissionFailure());
      await pumpEventQueue();
      cubit.rejectionShown();
    },
    expect: () => [
      isA<LibraryState>().having(
        (state) => state.customWriteRejected,
        'customWriteRejected',
        isTrue,
      ),
      isA<LibraryState>().having(
        (state) => state.customWriteRejected,
        'customWriteRejected',
        isFalse,
      ),
    ],
  );
}
