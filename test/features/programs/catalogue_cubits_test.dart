import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/programs/data/no_completed_days.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_queries.dart';
import 'package:get_workout/features/programs/domain/catalogue_repository.dart';
import 'package:get_workout/features/programs/domain/premium_status.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/catalogue_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockCatalogueRepository extends Mock implements CatalogueRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

class MockExerciseRepository extends Mock implements ExerciseRepository {}

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

class FakePremium implements PremiumStatus {
  final controller = StreamController<bool?>.broadcast();

  @override
  Stream<bool?> watch() => controller.stream;
}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  final days = [
    ProgramDay(name: 'Upper', items: [item('a'), item('b')]),
    ProgramDay(name: 'Lower', items: [item('c')]),
  ];
  final free = card('pr_free', order: 1);
  final paid = card(
    'pr_premium',
    premium: true,
    level: Level.advanced,
    goal: Goal.getStronger,
    daysPerWeek: 5,
    equipment: const [Equipment.barbell, Equipment.cable],
    profile: EquipmentProfile.fullGym,
    order: 2,
  );

  late MockAuthRepository auth;
  late MockCatalogueRepository catalogueRepository;
  late MockProgramRepository programRepository;
  late MockProfileRepository profiles;
  late MockUserLibraryRepository library;
  late StreamController<List<CatalogueProgram>> cards;
  late StreamController<UserProfile> profile;
  late StreamController<Set<Equipment>?> owned;
  late StreamController<List<Program>> userPrograms;
  late StreamController<AuthUser?> users;
  late FakePremium premiumStatus;
  late ProfileCubit profileCubit;
  late EquipmentCubit equipmentCubit;
  late ProgramCatalogueCubit catalogue;
  late ProgramListCubit list;
  late ExerciseCatalogueCubit exercises;

  setUpAll(() {
    registerFallbackValue(program());
  });

  setUp(() {
    auth = MockAuthRepository();
    catalogueRepository = MockCatalogueRepository();
    programRepository = MockProgramRepository();
    profiles = MockProfileRepository();
    library = MockUserLibraryRepository();
    cards = StreamController.broadcast();
    profile = StreamController.broadcast();
    owned = StreamController.broadcast();
    userPrograms = StreamController.broadcast();
    users = StreamController.broadcast();
    premiumStatus = FakePremium();

    when(() => auth.currentUser).thenReturn(member);
    when(auth.watchUser).thenAnswer((_) => Stream.value(member));
    when(catalogueRepository.watchPrograms).thenAnswer((_) => cards.stream);
    when(() => catalogueRepository.getDays(any()))
        .thenAnswer((_) async => Ok(days));
    when(() => profiles.watchProfile('u1')).thenAnswer((_) => profile.stream);
    when(() => library.watchEquipment('u1')).thenAnswer((_) => owned.stream);
    when(() => programRepository.watchPrograms('u1'))
        .thenAnswer((_) => userPrograms.stream);
    when(() => programRepository.watchActiveProgram('u1'))
        .thenAnswer((_) => Stream.value(null));
    when(() => programRepository.rejectedWrites)
        .thenAnswer((_) => const Stream.empty());
    when(() => programRepository.createProgram(any(), any()))
        .thenAnswer((_) async => const Ok('copy1'));

    profileCubit = ProfileCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchProfile: WatchProfile(profiles),
      updateProfile: UpdateProfile(profiles, SaveOwnedEquipment(library)),
    );
    equipmentCubit = EquipmentCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchEquipment: WatchOwnedEquipment(library),
      saveEquipment: SaveOwnedEquipment(library),
    );
    final catalogueAuth = MockAuthRepository();
    // Like Firebase, the current user arrives on subscription.
    Stream<AuthUser?> watchUser() async* {
      yield member;
      yield* users.stream;
    }

    when(catalogueAuth.watchUser).thenAnswer((_) => watchUser());
    catalogue = ProgramCatalogueCubit(
      watchAuthUser: WatchAuthUser(catalogueAuth),
      retryDelay: Duration.zero,
      watchCatalogue: WatchCatalogue(catalogueRepository),
      watchPremium: WatchPremium(premiumStatus),
      profile: profileCubit,
      equipment: equipmentCubit,
    );
    list = ProgramListCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchPrograms: WatchPrograms(programRepository),
      watchActiveProgram: WatchActiveProgram(programRepository),
      watchCompletedDays: const WatchCompletedDays(NoCompletedDays()),
      watchRejectedWrites: WatchRejectedProgramWrites(programRepository),
      resolveMissedDay: ResolveMissedDay(programRepository),
    );
    final exerciseRepository = MockExerciseRepository();
    when(exerciseRepository.watchExercises)
        .thenAnswer((_) => Stream.value([move('a'), move('b'), move('c')]));
    final idle = MockAuthRepository();
    when(idle.watchUser).thenAnswer((_) => const Stream.empty());
    exercises = ExerciseCatalogueCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchExercises: WatchExercises(exerciseRepository),
      watchCustomExercises: WatchCustomExercises(
        MockCustomExerciseRepository(),
      ),
      syncExercises: SyncExercises(exerciseRepository),
    );
  });

  tearDown(() async {
    await catalogue.close();
    await list.close();
    await exercises.close();
    await profileCubit.close();
    await equipmentCubit.close();
  });

  group('ProgramCatalogueCubit', () {
    test('loads the cards', () async {
      expect(catalogue.state.status, ProgramCatalogueStatus.loading);

      cards.add([free, paid]);
      await pumpEventQueue();

      expect(catalogue.state.status, ProgramCatalogueStatus.ready);
      expect(catalogue.state.visible, [free, paid]);
      expect(catalogue.state.dayOptions, [3, 5]);
    });

    test('offline before the first load, then the cards once online', () async {
      cards.addError(const NetworkFailure());
      await pumpEventQueue();
      expect(catalogue.state.status, ProgramCatalogueStatus.offline);

      cards.add([free]);
      await pumpEventQueue();
      expect(catalogue.state.status, ProgramCatalogueStatus.ready);
    });

    test('a failure offers a retry that listens again', () async {
      cards.addError(const PermissionFailure());
      await pumpEventQueue();
      expect(catalogue.state.status, ProgramCatalogueStatus.failure);

      catalogue.retry();
      await pumpEventQueue();
      cards.add([free]);
      await pumpEventQueue();

      expect(catalogue.state.status, ProgramCatalogueStatus.ready);
      verify(catalogueRepository.watchPrograms).called(2);
    });

    test('cards on screen stay after a failure, which listens again', () async {
      cards.add([free]);
      await pumpEventQueue();
      cards.addError(const PermissionFailure());
      await pumpEventQueue();

      expect(catalogue.state.status, ProgramCatalogueStatus.ready);
      expect(catalogue.state.programs, [free]);
      verify(catalogueRepository.watchPrograms).called(2);

      cards.add([free, paid]);
      await pumpEventQueue();
      expect(catalogue.state.programs, [free, paid]);
    });

    test('listens again for every user, and not while signed out', () async {
      cards.add([free]);
      await pumpEventQueue();
      verify(catalogueRepository.watchPrograms).called(1);

      users.add(null);
      await pumpEventQueue();
      verifyNever(catalogueRepository.watchPrograms);
      expect(catalogue.state.programs, [free]);

      users.add(const AuthUser(id: 'u2', isAnonymous: true));
      await pumpEventQueue();
      verify(catalogueRepository.watchPrograms).called(1);
    });

    test('filters, and clears them', () async {
      cards.add([free, paid]);
      await pumpEventQueue();

      catalogue
        ..toggleLevel(Level.advanced)
        ..toggleDays(5);
      expect(catalogue.state.visible, [paid]);
      catalogue.toggleGoal(Goal.buildMuscle);
      expect(catalogue.state.visible, isEmpty);
      catalogue.toggleGoal(Goal.buildMuscle);
      catalogue.toggleProfile(EquipmentProfile.dumbbells);
      expect(catalogue.state.visible, isEmpty);

      catalogue.clearFilters();
      expect(catalogue.state.filter, const CatalogueFilter());
      expect(catalogue.state.visible, [free, paid]);
    });

    test('fits my equipment uses the equipment the user owns', () async {
      cards.add([free, paid]);
      catalogue.setFitsMyEquipment(true);
      await pumpEventQueue();
      expect(catalogue.state.visible, [free, paid]);

      owned.add({Equipment.dumbbell, Equipment.bench});
      await pumpEventQueue();
      expect(catalogue.state.visible, [free]);
    });

    test('recommends from the profile and the equipment', () async {
      premiumStatus.controller.add(true);
      cards.add([free, paid]);
      profile.add(
        const UserProfile(
          goal: Goal.getStronger,
          level: Level.advanced,
          daysPerWeek: 4,
        ),
      );
      await pumpEventQueue();
      expect(catalogue.state.recommended.map((r) => r.program), [paid, free]);

      owned.add({Equipment.dumbbell, Equipment.bench});
      await pumpEventQueue();
      expect(catalogue.state.recommended.map((r) => r.program), [free]);
    });

    test('puts free programs first until premium is known', () async {
      cards.add([free, paid]);
      profile.add(
        const UserProfile(
          goal: Goal.getStronger,
          level: Level.advanced,
          daysPerWeek: 4,
        ),
      );
      await pumpEventQueue();

      expect(catalogue.state.recommended.map((r) => r.program), [free, paid]);
    });

    test(
      'fits my equipment is no filter while the equipment is unknown',
      () async {
        cards.add([free, paid]);
        catalogue.setFitsMyEquipment(true);
        await pumpEventQueue();

        expect(catalogue.state.filtering, isFalse);

        owned.add({Equipment.dumbbell, Equipment.bench});
        await pumpEventQueue();
        expect(catalogue.state.filtering, isTrue);
      },
    );

    test('follows the premium status', () async {
      expect(catalogue.state.premium, isNull);

      premiumStatus.controller.add(true);
      await pumpEventQueue();
      expect(catalogue.state.premium, isTrue);

      premiumStatus.controller.add(null);
      await pumpEventQueue();
      expect(catalogue.state.premium, isNull);
    });
  });

  group('CatalogueDetailCubit', () {
    CatalogueDetailCubit detail(String id) => CatalogueDetailCubit(
      id,
      language: 'en',
      catalogue: catalogue,
      list: list,
      exercises: exercises,
      getDays: GetCatalogueDays(catalogueRepository),
      saveProgram: SaveProgram(programRepository),
      getCurrentUser: GetCurrentUser(auth),
    );

    Future<CatalogueDetailCubit> open(
      String id, {
      bool? premium = false,
      List<Program> mine = const [],
    }) async {
      cards.add([free, paid]);
      premiumStatus.controller.add(premium);
      userPrograms.add(mine);
      await pumpEventQueue();
      final cubit = detail(id);
      addTearDown(cubit.close);
      await pumpEventQueue();
      return cubit;
    }

    test('a free program shows its days', () async {
      final cubit = await open(free.id);

      expect(cubit.state.status, CatalogueDetailStatus.ready);
      expect(cubit.state.program, free);
      expect(cubit.state.days, days);
    });

    test('waits for the card', () async {
      final cubit = detail(free.id);
      addTearDown(cubit.close);
      expect(cubit.state.status, CatalogueDetailStatus.loading);

      cards.add([free]);
      await pumpEventQueue();
      expect(cubit.state.status, CatalogueDetailStatus.ready);
    });

    test('a program missing from the catalogue is not found', () async {
      final cubit = await open('pr_gone');

      expect(cubit.state.status, CatalogueDetailStatus.notFound);
      expect(cubit.state.program, isNull);
    });

    test('a catalogue never loaded offline says so', () async {
      final cubit = detail(free.id);
      addTearDown(cubit.close);
      cards.addError(const NetworkFailure());
      await pumpEventQueue();

      expect(cubit.state.status, CatalogueDetailStatus.offline);
    });

    test('a premium program waits for the premium status, reading '
        'nothing', () async {
      final cubit = await open(paid.id, premium: null);

      expect(cubit.state.status, CatalogueDetailStatus.loading);
      expect(cubit.state.program, paid);
      verifyNever(() => catalogueRepository.getDays(any()));

      premiumStatus.controller.add(true);
      await pumpEventQueue();
      expect(cubit.state.status, CatalogueDetailStatus.ready);
      expect(cubit.state.days, days);
    });

    test('a premium program without premium is locked, its days never '
        'read', () async {
      final cubit = await open(paid.id);

      expect(cubit.state.status, CatalogueDetailStatus.locked);
      expect(cubit.state.program, paid);
      expect(cubit.state.days, isEmpty);
      verifyNever(() => catalogueRepository.getDays(any()));
    });

    test('days the server refuses are locked, and read again when the '
        'status changes', () async {
      when(() => catalogueRepository.getDays(paid.id))
          .thenAnswer((_) async => const Err(PermissionFailure()));
      final cubit = await open(paid.id, premium: true);
      expect(cubit.state.status, CatalogueDetailStatus.locked);

      when(() => catalogueRepository.getDays(paid.id))
          .thenAnswer((_) async => Ok(days));
      premiumStatus.controller
        ..add(null)
        ..add(true);
      await pumpEventQueue();

      expect(cubit.state.status, CatalogueDetailStatus.ready);
    });

    test('losing premium locks the days again', () async {
      final cubit = await open(paid.id, premium: true);
      expect(cubit.state.status, CatalogueDetailStatus.ready);

      premiumStatus.controller.add(false);
      await pumpEventQueue();

      expect(cubit.state.status, CatalogueDetailStatus.locked);
      expect(cubit.state.days, isEmpty);
    });

    test('days not cached offline say so, and a retry reads them', () async {
      when(() => catalogueRepository.getDays(free.id))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      final cubit = await open(free.id);
      expect(cubit.state.status, CatalogueDetailStatus.offline);
      expect(cubit.state.program, free);

      when(() => catalogueRepository.getDays(free.id))
          .thenAnswer((_) async => Ok(days));
      cubit.retry();
      await pumpEventQueue();

      expect(cubit.state.status, CatalogueDetailStatus.ready);
    });

    test('missing days are not found, other failures fail', () async {
      when(() => catalogueRepository.getDays(free.id))
          .thenAnswer((_) async => const Err(NotFoundFailure()));
      final missing = await open(free.id);
      expect(missing.state.status, CatalogueDetailStatus.notFound);

      when(() => catalogueRepository.getDays(free.id))
          .thenAnswer((_) async => const Err(UnknownFailure()));
      final failed = detail(free.id);
      addTearDown(failed.close);
      await pumpEventQueue();
      expect(failed.state.status, CatalogueDetailStatus.failure);
    });

    test('use copies the program into the user\'s programs', () async {
      final cubit = await open(free.id);

      await cubit.use();

      final stored =
          verify(() => programRepository.createProgram('u1', captureAny()))
                  .captured
                  .single
              as Program;
      expect(stored, free.copy(days, 'en'));
      expect(stored.origin, ProgramOrigin.catalog);
      expect(stored.sourceId, free.id);
      expect(cubit.state.copyStatus, CopyStatus.copied);
      expect(cubit.state.copyId, 'copy1');

      cubit.copyHandled();
      expect(cubit.state.copyStatus, CopyStatus.idle);
      expect(cubit.state.copyId, isNull);
    });

    test('a program already copied offers the copy instead', () async {
      final cubit = await open(
        free.id,
        mine: [
          Program(
            id: 'mine1',
            name: 'My version',
            origin: ProgramOrigin.catalog,
            sourceId: free.id,
            days: days,
          ),
        ],
      );

      await cubit.use();

      expect(cubit.state.copyStatus, CopyStatus.alreadyCopied);
      expect(cubit.state.copyId, 'mine1');
      verifyNever(() => programRepository.createProgram(any(), any()));

      cubit.copyHandled();
      await cubit.copy();
      expect(cubit.state.copyStatus, CopyStatus.copied);
      expect(cubit.state.copyId, 'copy1');
    });

    test('an own program of the same name is no copy', () async {
      final cubit = await open(
        free.id,
        mine: [program(id: 'p1', name: free.text('en').name)],
      );

      await cubit.use();

      expect(cubit.state.copyStatus, CopyStatus.copied);
    });

    test('a program the app would not accept is not copied', () async {
      when(() => catalogueRepository.getDays(free.id)).thenAnswer(
        (_) async => Ok([
          ProgramDay(items: [item('retired')]),
        ]),
      );
      final cubit = await open(free.id);

      await cubit.use();

      expect(cubit.state.copyStatus, CopyStatus.failed);
      expect(cubit.state.copyFailure, isA<ValidationFailure>());
      verifyNever(() => programRepository.createProgram(any(), any()));
    });

    test('a locked program cannot be copied', () async {
      final cubit = await open(paid.id);

      await cubit.use();

      expect(cubit.state.copyStatus, CopyStatus.idle);
      verifyNever(() => programRepository.createProgram(any(), any()));
    });
  });
}
