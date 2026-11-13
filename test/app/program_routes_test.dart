import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/generator/presentation/generator_page.dart';
import 'package:get_workout/features/generator/presentation/generator_questions_cubit.dart';
import 'package:get_workout/features/programs/data/no_completed_days.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_cubit.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_page.dart';
import 'package:get_workout/features/programs/presentation/program_builder_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_builder_page.dart';
import 'package:get_workout/features/programs/presentation/program_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_detail_page.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/programs/presentation/programs_page.dart';
import 'package:get_workout/features/programs/programs_module.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart';
import 'answered_consent.dart';
import 'no_workout.dart';
import 'today_stand_ins.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

class MockExerciseRepository extends Mock implements ExerciseRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

void main() {
  const guest = AuthUser(id: 'u1', isAnonymous: true);
  final squat = move('squat', name: 'Back Squat');
  final stored = Program(
    id: 'p1',
    name: 'Leg Day',
    days: [
      ProgramDay(name: 'Legs', items: [item('squat')]),
    ],
  );

  late StreamController<AuthUser?> users;
  late StreamController<List<Program>> programs;
  late AuthCubit auth;
  late List<Cubit<Object?>> appCubits;
  late MockProgramRepository repository;
  late GoRouter router;

  // Created inside each test so stream events run in the test's fake zone.
  Future<void> start(WidgetTester tester) async {
    final authRepository = MockAuthRepository();
    users = StreamController<AuthUser?>();
    when(authRepository.watchUser).thenAnswer((_) => users.stream);
    when(() => authRepository.currentUser).thenReturn(guest);
    auth = AuthCubit(
      watchAuthUser: WatchAuthUser(authRepository),
      signOut: SignOut(authRepository),
      deleteAccount: DeleteAccount(authRepository),
      signInAnonymously: SignInAnonymously(authRepository),
    );
    // Like Firebase, the user arrives on subscription.
    final sessionAuth = MockAuthRepository();
    when(sessionAuth.watchUser).thenAnswer((_) => Stream.value(guest));
    when(() => sessionAuth.currentUser).thenReturn(guest);
    final idle = MockAuthRepository();
    when(idle.watchUser).thenAnswer((_) => const Stream.empty());
    // Onboarding is covered by the router tests; this user has done it.
    final profiles = MockProfileRepository();
    when(() => profiles.watchProfile('u1')).thenAnswer(
      (_) => Stream.value(UserProfile(onboardingCompletedAt: DateTime(2026))),
    );
    final profile = ProfileCubit(
      watchAuthUser: WatchAuthUser(sessionAuth),
      watchProfile: WatchProfile(profiles),
      updateProfile: UpdateProfile(
        profiles,
        SaveOwnedEquipment(MockUserLibraryRepository()),
      ),
    );
    final settingsRepository = MockSettingsRepository();
    final settings = SettingsCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchSettings: WatchSettings(settingsRepository),
      updateSettings: UpdateSettings(settingsRepository),
      markTipSeen: MarkTipSeen(settingsRepository),
      defaults: UserSettings.defaultsFor(null),
    );
    final exercises = MockExerciseRepository();
    when(exercises.watchExercises).thenAnswer((_) => Stream.value([squat]));
    final userLibrary = MockUserLibraryRepository();
    final customExercises = MockCustomExerciseRepository();
    when(() => customExercises.rejectedWrites)
        .thenAnswer((_) => const Stream.empty());
    final catalogue = ExerciseCatalogueCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchExercises: WatchExercises(exercises),
      watchCustomExercises: WatchCustomExercises(customExercises),
      syncExercises: SyncExercises(exercises),
    );
    final favorites = FavoritesCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchFavorites: WatchFavorites(userLibrary),
      setFavorite: SetFavorite(userLibrary),
    );
    final equipment = EquipmentCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchEquipment: WatchOwnedEquipment(userLibrary),
      saveEquipment: SaveOwnedEquipment(userLibrary),
    );
    // Never configured, so the premium status stays unknown.
    final store = FakePurchasesRepository(plans: fakePlans);
    final entitlement = EntitlementCubit(
      configure: ConfigurePurchases(store),
      watchEntitlement: WatchEntitlement(store),
      identify: IdentifyPurchaser(store),
      reset: ResetPurchaser(store),
      refresh: RefreshEntitlement(store),
      getManagementUrl: GetManagementUrl(store),
    );
    appCubits = [
      settings,
      catalogue,
      favorites,
      equipment,
      profile,
      entitlement,
    ];

    repository = MockProgramRepository();
    programs = StreamController<List<Program>>();
    when(() => repository.watchPrograms('u1'))
        .thenAnswer((_) => programs.stream);
    when(() => repository.watchActiveProgram('u1'))
        .thenAnswer((_) => Stream.value(null));
    when(() => repository.rejectedWrites)
        .thenAnswer((_) => const Stream.empty());
    when(() => repository.getProgram('u1', 'p1'))
        .thenAnswer((_) async => Ok(stored));
    sl
      ..registerSingleton(PremiumPrompt((_) {}))
      ..registerLazySingleton(
        () => ProgramListCubit(
          firstWeekday: DateTime.monday,
          watchAuthUser: WatchAuthUser(sessionAuth),
          watchPrograms: WatchPrograms(repository),
          watchActiveProgram: WatchActiveProgram(repository),
          watchCompletedDays: const WatchCompletedDays(NoCompletedDays()),
          watchRejectedWrites: WatchRejectedProgramWrites(repository),
          resolveMissedDay: ResolveMissedDay(repository),
          watchPremium: const WatchPremium(FixedPremium(false)),
        ),
        dispose: (cubit) => cubit.close(),
      )
      ..registerFactoryParam<ProgramDetailCubit, String, void>(
        (id, _) => ProgramDetailCubit(
          id,
          list: sl(),
          startProgram: StartProgram(repository),
          changeWeekdays: ChangeWeekdays(repository),
          stopProgram: StopProgram(repository),
          duplicateProgram: DuplicateProgram(repository),
          deleteProgram: DeleteProgram(repository),
          getCurrentUser: GetCurrentUser(sessionAuth),
          watchAuthUser: WatchAuthUser(sessionAuth),
        ),
      )
      ..registerFactoryParam<ProgramBuilderCubit, String?, WeightUnit>(
        (id, unit) => ProgramBuilderCubit(
          programId: id,
          getProgram: GetProgram(repository),
          saveProgram: SaveProgram(repository),
          getCurrentUser: GetCurrentUser(sessionAuth),
          watchAuthUser: WatchAuthUser(sessionAuth),
          catalogue: catalogue,
          weightUnit: unit,
        ),
      )
      ..registerFactoryParam<GeneratorQuestionsCubit, GeneratorPrefill, void>(
        (prefill, _) => GeneratorQuestionsCubit(prefill),
      )
      ..registerFactoryParam<ExercisePickerCubit, int, bool>(
        (max, multiple) => ExercisePickerCubit(max: max, multiple: multiple),
      )
      ..registerFactory(
        () => LibraryCubit(
          watchAuthUser: WatchAuthUser(idle),
          catalogue: catalogue,
          favorites: favorites,
          equipment: equipment,
        ),
        instanceName: ProgramsModule.pickerLibrary,
      );
    registerTodayStandIns();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: auth),
          BlocProvider.value(value: settings),
          answeredConsent(),
          programList(),
          noWorkout(),
          noWorkout(),
          BlocProvider.value(value: catalogue),
          BlocProvider.value(value: favorites),
          BlocProvider.value(value: equipment),
          BlocProvider.value(value: entitlement),
          BlocProvider.value(value: profile),
        ],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router = buildRouter(auth, profile),
        ),
      ),
    );
    users.add(guest);
    await tester.pumpAndSettle();
  }

  tearDown(() async {
    await auth.close();
    for (final cubit in appCubits) {
      await cubit.close();
    }
    await sl.reset();
  });

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  String path() => router.routerDelegate.currentConfiguration.uri.path;

  /// The controller buffers [list] until the list subscribes, so nothing is
  /// left loading (a spinner never settles).
  Future<void> openPrograms(
    WidgetTester tester, [
    List<Program> list = const [],
  ]) async {
    programs.add(list);
    await tap(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Train'),
      ),
    );
    expect(find.byType(ProgramsPage), findsOneWidget);
  }

  testWidgets('the empty tab offers a new program inside its branch', (
    tester,
  ) async {
    await start(tester);
    await openPrograms(tester);

    expect(find.textContaining('No programs yet'), findsOneWidget);
    await tap(tester, find.text('New program'));

    expect(find.byType(ProgramBuilderPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(path(), Routes.programNew);
  });

  testWidgets('a program opens its detail, and its builder from there', (
    tester,
  ) async {
    await start(tester);
    await openPrograms(tester, [stored]);

    await tap(tester, find.text('Leg Day'));
    expect(find.byType(ProgramDetailPage), findsOneWidget);
    // Not active, so no day is open.
    expect(find.text('Back Squat'), findsNothing);
    await tap(tester, find.text('Legs'));
    expect(find.text('Back Squat'), findsOneWidget);
    expect(path(), Routes.program('p1'));

    await tap(tester, find.byTooltip('Edit'));
    expect(find.byType(ProgramBuilderPage), findsOneWidget);
    expect(find.text('Edit program'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Leg Day'), findsOneWidget);
    expect(path(), Routes.programEdit('p1'));

    await tap(tester, find.byType(BackButton));
    expect(find.byType(ProgramDetailPage), findsOneWidget);
  });

  testWidgets('the generator preview without answers opens the questions', (
    tester,
  ) async {
    await start(tester);
    programs.add([stored]);
    router.go(Routes.programGeneratorPreview);
    await tester.pumpAndSettle();

    expect(path(), Routes.programGenerator);
    expect(find.byType(GeneratorPage), findsOneWidget);
  });

  testWidgets('a link to an unknown program says it is gone', (tester) async {
    await start(tester);
    programs.add([stored]);
    router.go(Routes.program('nope'));
    await tester.pumpAndSettle();

    expect(find.text('This program no longer exists.'), findsOneWidget);
  });

  testWidgets('the picker returns the chosen exercises to the builder', (
    tester,
  ) async {
    await start(tester);
    await openPrograms(tester);
    await tap(tester, find.text('New program'));

    await tap(tester, find.text('Add exercises'));
    expect(find.byType(ExercisePickerPage), findsOneWidget);
    await tap(tester, find.text('Back Squat'));
    await tap(tester, find.text('Add 1'));

    expect(find.byType(ExercisePickerPage), findsNothing);
    expect(find.byType(ProgramBuilderPage), findsOneWidget);
    expect(find.text('Back Squat'), findsOneWidget);
  });

  testWidgets('leaving the builder with changes asks first', (tester) async {
    await start(tester);
    await openPrograms(tester);
    await tap(tester, find.text('New program'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Program name'),
      'Push',
    );
    // The page refuses to pop from the next frame on.
    await tester.pump();

    await tap(tester, find.byType(BackButton));
    await tap(tester, find.text('Keep editing'));
    expect(find.byType(ProgramBuilderPage), findsOneWidget);

    await tap(tester, find.byType(BackButton));
    await tap(tester, find.text('Discard'));
    expect(find.byType(ProgramBuilderPage), findsNothing);
    expect(find.byType(ProgramsPage), findsOneWidget);
  });

  Future<void> reselectTrain(WidgetTester tester) => tap(
    tester,
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Train'),
    ),
  );

  testWidgets('reselecting the tab asks before discarding changes', (
    tester,
  ) async {
    await start(tester);
    await openPrograms(tester, [stored]);
    await tap(tester, find.text('Leg Day'));
    await tap(tester, find.byTooltip('Edit'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Leg Day'),
      'Leg Day 2',
    );
    // The page refuses to pop from the next frame on.
    await tester.pump();

    await reselectTrain(tester);
    expect(find.text('Discard changes?'), findsOneWidget);
    await tap(tester, find.text('Keep editing'));
    expect(find.byType(ProgramBuilderPage), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Leg Day 2'), findsOneWidget);

    await reselectTrain(tester);
    await tap(tester, find.text('Discard'));
    expect(find.byType(ProgramBuilderPage), findsNothing);
    expect(find.byType(ProgramDetailPage), findsOneWidget);
  });

  testWidgets('a link to the Exercises view brings the builder with changes '
      'up and asks; keeping them stays', (tester) async {
    await start(tester);
    await openPrograms(tester);
    await tap(tester, find.text('New program'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Program name'),
      'Push',
    );
    await tester.pump();
    await tap(
      tester,
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Today'),
      ),
    );

    // The Exercises view shares the builder's stack, so going there drops it.
    router.go(Routes.exercises);
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    expect(find.byType(ProgramBuilderPage), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );
    await tap(tester, find.text('Keep editing'));

    expect(path(), Routes.programNew);
    expect(find.widgetWithText(TextField, 'Push'), findsOneWidget);
  });

  testWidgets('reselecting the tab without changes returns to its first page', (
    tester,
  ) async {
    await start(tester);
    await openPrograms(tester, [stored]);
    await tap(tester, find.text('Leg Day'));
    await tap(tester, find.byTooltip('Edit'));

    await reselectTrain(tester);

    expect(find.text('Discard changes?'), findsNothing);
    expect(find.byType(ProgramBuilderPage), findsNothing);
    expect(find.byType(ProgramDetailPage), findsNothing);
    expect(find.byType(ProgramsPage), findsOneWidget);
    expect(path(), Routes.programs);
  });

  testWidgets('a just-created program is waited for, then not found', (
    tester,
  ) async {
    await start(tester);
    programs.add(const []);
    router.go(Routes.program('p9', created: true));
    await tester.pump();
    await tester.pump();

    expect(find.byType(LoadingView), findsOneWidget);
    expect(find.text('This program no longer exists.'), findsNothing);

    await tester.pump(ProgramDetailPage.createdWait);
    await tester.pump();
    expect(find.text('This program no longer exists.'), findsOneWidget);
  });

  testWidgets('a just-created program shows once the list has it', (
    tester,
  ) async {
    await start(tester);
    programs.add(const []);
    router.go(Routes.program('p1', created: true));
    await tester.pump();
    await tester.pump();
    expect(find.byType(LoadingView), findsOneWidget);

    programs.add([stored]);
    await tester.pumpAndSettle();
    expect(find.text('Leg Day'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);
  });

  testWidgets('the name field stops at the limit validation uses', (
    tester,
  ) async {
    await start(tester);
    await openPrograms(tester);
    await tap(tester, find.text('New program'));

    // 40 emoji are 80 code units; 30 fit, none is cut in half.
    await tester.enterText(
      find.widgetWithText(TextField, 'Program name'),
      '💪' * 40,
    );
    await tester.pump();

    final field = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Program name'),
    );
    expect(field.controller!.text, '💪' * 30);
  });

  testWidgets('an empty day shows no estimate', (tester) async {
    await start(tester);
    await openPrograms(tester);
    await tap(tester, find.text('New program'));

    expect(find.textContaining('min'), findsNothing);
    await tap(tester, find.text('Add exercises'));
    await tap(tester, find.text('Back Squat'));
    await tap(tester, find.text('Add 1'));
    expect(find.textContaining('min'), findsOneWidget);
  });
}
