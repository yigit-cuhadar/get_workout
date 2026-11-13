import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/app/train_page.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/custom_exercise_form_cubit.dart';
import 'package:get_workout/features/exercises/presentation/custom_exercise_form_page.dart';
import 'package:get_workout/features/exercises/presentation/custom_write_rejections_cubit.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_page.dart';
import 'package:get_workout/features/exercises/presentation/exercises_page.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_page.dart';
import 'package:get_workout/features/exercises/presentation/widgets/body_view.dart';
import 'package:get_workout/features/exercises/presentation/widgets/library_list_view.dart';
import 'package:get_workout/features/account/presentation/account_page.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
import 'package:get_workout/features/account/domain/consent_repository.dart';
import 'package:get_workout/features/account/presentation/consent_cubit.dart';
import 'package:get_workout/features/account/presentation/delete_account_cubit.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/calculators/calculators_module.dart';
import 'package:get_workout/features/calculators/presentation/body_fat_page.dart';
import 'package:get_workout/features/calculators/presentation/body_indices_page.dart';
import 'package:get_workout/features/calculators/presentation/calculators_page.dart';
import 'package:get_workout/features/calculators/presentation/calories_page.dart';
import 'package:get_workout/features/calculators/presentation/macros_page.dart';
import 'package:get_workout/features/calculators/presentation/one_rep_max_page.dart';
import 'package:get_workout/features/calculators/presentation/plates_page.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/onboarding_page.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/profile/presentation/profile_details_page.dart';
import 'package:get_workout/features/profile/presentation/profile_form_cubit.dart';
import 'package:get_workout/features/profile/presentation/profile_page.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_repository.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/data/no_completed_days.dart';
import 'package:get_workout/features/programs/presentation/catalogue_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/catalogue_page.dart';
import 'package:get_workout/features/programs/programs_module.dart';
import 'package:get_workout/features/programs/presentation/program_builder_page.dart';
import 'package:get_workout/features/programs/presentation/program_builder_cubit.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_cubit.dart';
import 'package:get_workout/features/programs/presentation/add_to_program_cubit.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_suggestion_page.dart';
import 'package:get_workout/features/programs/presentation/programs_page.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';
import 'package:get_workout/features/subscription/presentation/premium_paywall_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_cubit.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_page.dart';
import 'package:get_workout/features/strength/presentation/strength_list_cubit.dart';
import 'package:get_workout/features/strength/presentation/strength_list_page.dart';
import 'package:get_workout/features/today/presentation/today_page.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:get_workout/features/workout/presentation/workout_detail_cubit.dart';
import 'package:get_workout/features/workout/presentation/workout_detail_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart' show FixedPremium, card;
import 'answered_consent.dart';
import 'body_stand_in.dart';
import 'no_workout.dart';
import 'today_stand_ins.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockConsentRepository extends Mock implements ConsentRepository {}

class MockTelemetry extends Mock implements Telemetry {}

class MockBodyRepository extends Mock implements BodyRepository {}

class MockExerciseRepository extends Mock implements ExerciseRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

class MockCustomExerciseRepository extends Mock
    implements CustomExerciseRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockCatalogueRepository extends Mock implements CatalogueRepository {}

class MockWorkoutRepository extends Mock implements WorkoutRepository {}

const _squat = Exercise(
  id: 'squat',
  loggingType: LoggingType.weightReps,
  mechanic: Mechanic.compound,
  laterality: Laterality.bilateral,
  level: Level.beginner,
  force: Force.push,
  movementPattern: MovementPattern.squat,
  position: Position.standing,
  equipment: [Equipment.barbell],
  mainMuscles: [Muscle.quads],
  family: 'squat',
  familyRank: 1,
  defaultRestS: 120,
  popularity: 1,
  l10n: {'en': ExerciseText(name: 'Back Squat')},
);

/// Works the quads as a secondary muscle.
const _splitSquat = Exercise(
  id: 'split_squat',
  loggingType: LoggingType.weightReps,
  mechanic: Mechanic.compound,
  laterality: Laterality.unilateral,
  level: Level.beginner,
  force: Force.push,
  movementPattern: MovementPattern.lunge,
  position: Position.standing,
  equipment: [],
  mainMuscles: [Muscle.glute],
  secondaryMuscles: [Muscle.quads],
  family: 'split_squat',
  familyRank: 1,
  defaultRestS: 90,
  popularity: 2,
  l10n: {'en': ExerciseText(name: 'Split Squat')},
);

void main() {
  const guest = AuthUser(id: 'u1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  late MockAuthRepository repository;
  late StreamController<AuthUser?> users;
  late AuthCubit auth;
  late SettingsCubit settings;
  late MockProfileRepository profiles;
  late ProfileCubit profile;
  late ExerciseCatalogueCubit catalogue;
  late FavoritesCubit favorites;
  late EquipmentCubit equipment;
  late BodyModelCubit bodyModel;
  late StreamController<List<Exercise>> exerciseFeed;
  late FakePurchasesRepository store;
  late EntitlementCubit entitlement;
  late MockProgramRepository programs;

  /// Keeps the catalogue loading until a test feeds [exerciseFeed].
  var holdCatalogue = false;
  late GoRouter router;
  final onboarded = UserProfile(onboardingCompletedAt: DateTime(2026));

  /// The ready-made programs; none unless a test sets them.
  var readyMade = <CatalogueProgram>[];

  /// What the user's profile stream emits first; null emits nothing until
  /// the test adds to [profileStream].
  UserProfile? storedProfile;
  late StreamController<UserProfile> profileStream;

  setUpAll(() {
    registerFallbackValue(const Program(name: '', days: []));
    registerFallbackValue(const UserProfile());
    registerFallbackValue(<ProfileField>{});
    registerFallbackValue(<Equipment>{});
  });

  late DeletionUnderway deletionUnderway;

  /// A real consent cubit for the consent prompt's tests; otherwise every
  /// user has answered.
  ConsentCubit? consent;

  setUp(() {
    storedProfile = onboarded;
    deletionUnderway = DeletionUnderway();
    consent = null;
  });

  // Created inside each test so stream events run in the test's fake zone.
  void setUpAuth() {
    repository = MockAuthRepository();
    // The auth and profile cubits both follow the user.
    users = StreamController<AuthUser?>.broadcast();
    when(() => repository.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.currentUser).thenReturn(guest);
    auth = AuthCubit(
      watchAuthUser: WatchAuthUser(repository),
      signOut: SignOut(repository),
      deleteAccount: DeleteAccount(repository),
      signInAnonymously: SignInAnonymously(repository),
    );
    sl.registerFactory(
      () => AuthFormCubit(
        signInWithEmail: SignInWithEmail(repository),
        signUpWithEmail: SignUpWithEmail(repository),
        signInWithProvider: SignInWithProvider(repository),
        sendPasswordReset: SendPasswordReset(repository),
        getCurrentUser: GetCurrentUser(repository),
      ),
    );
    const CalculatorsModule().register(sl);
    // Settings are covered by their own tests; here they stay at defaults.
    final settingsAuth = MockAuthRepository();
    when(settingsAuth.watchUser).thenAnswer((_) => const Stream.empty());
    when(() => settingsAuth.currentUser).thenReturn(null);
    // Calculators start signed out here, so they ask for no known values.
    sl
      ..registerFactory(() => GetCurrentUser(settingsAuth))
      ..registerFactory(() => WatchProfile(MockProfileRepository()))
      ..registerFactory(() => WatchBodyEntries(MockBodyRepository()));
    final settingsRepository = MockSettingsRepository();
    settings = SettingsCubit(
      watchAuthUser: WatchAuthUser(settingsAuth),
      watchSettings: WatchSettings(settingsRepository),
      updateSettings: UpdateSettings(settingsRepository),
      markTipSeen: MarkTipSeen(settingsRepository),
      defaults: UserSettings.defaultsFor(null),
    );
    // The library runs on a fixed catalogue with no user data and a model
    // that fails to load (rendering it is the viewer package's business).
    final exercises = MockExerciseRepository();
    exerciseFeed = StreamController<List<Exercise>>();
    if (!holdCatalogue) exerciseFeed.add([_squat]);
    when(exercises.watchExercises).thenAnswer((_) => exerciseFeed.stream);
    final userLibrary = MockUserLibraryRepository();
    // Onboarding saves an equipment answer through the library.
    when(() => userLibrary.saveEquipment(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    final customExercises = MockCustomExerciseRepository();
    when(() => customExercises.rejectedWrites)
        .thenAnswer((_) => const Stream.empty());
    catalogue = ExerciseCatalogueCubit(
      watchAuthUser: WatchAuthUser(settingsAuth),
      watchExercises: WatchExercises(exercises),
      watchCustomExercises: WatchCustomExercises(customExercises),
      syncExercises: SyncExercises(exercises),
    );
    favorites = FavoritesCubit(
      watchAuthUser: WatchAuthUser(settingsAuth),
      watchFavorites: WatchFavorites(userLibrary),
      setFavorite: SetFavorite(userLibrary),
    );
    equipment = EquipmentCubit(
      watchAuthUser: WatchAuthUser(settingsAuth),
      watchEquipment: WatchOwnedEquipment(userLibrary),
      saveEquipment: SaveOwnedEquipment(userLibrary),
    );
    bodyModel = BodyModelCubit(() async => throw const FormatException());
    // Programs are covered by their own tests; here the user has none.
    final programAuth = MockAuthRepository();
    when(programAuth.watchUser).thenAnswer((_) => Stream.value(guest));
    when(() => programAuth.currentUser).thenReturn(guest);
    programs = MockProgramRepository();
    when(() => programs.watchPrograms(any()))
        .thenAnswer((_) => Stream.value(const []));
    when(() => programs.watchActiveProgram(any()))
        .thenAnswer((_) => Stream.value(null));
    when(() => programs.rejectedWrites).thenAnswer((_) => const Stream.empty());
    when(() => programs.createProgram(any(), any()))
        .thenAnswer((_) async => const Ok('p1'));
    sl.registerSingleton(PremiumPrompt((_) {}));
    // "Add to program" without programs, and the builder it opens.
    sl
      ..registerFactory(
        () => AddToProgramCubit(
          list: sl(),
          addExercise: AddExerciseToProgram(SaveProgram(programs)),
          catalogue: catalogue,
          getCurrentUser: GetCurrentUser(programAuth),
        ),
      )
      ..registerFactoryParam<ProgramBuilderCubit, String?, WeightUnit>(
        (id, unit) => ProgramBuilderCubit(
          programId: id,
          getProgram: GetProgram(programs),
          saveProgram: SaveProgram(programs),
          getCurrentUser: GetCurrentUser(programAuth),
          watchAuthUser: WatchAuthUser(programAuth),
          catalogue: catalogue,
          weightUnit: unit,
        ),
      )
      ..registerFactoryParam<ExercisePickerCubit, int, bool>(
        (max, multiple) => ExercisePickerCubit(max: max, multiple: multiple),
      )
      ..registerFactory(
        () => LibraryCubit(
          watchAuthUser: WatchAuthUser(settingsAuth),
          catalogue: catalogue,
          favorites: favorites,
          equipment: equipment,
        ),
        instanceName: ProgramsModule.pickerLibrary,
      );
    sl.registerLazySingleton(
      () => ProgramListCubit(
        watchAuthUser: WatchAuthUser(programAuth),
        watchPrograms: WatchPrograms(programs),
        watchActiveProgram: WatchActiveProgram(programs),
        watchCompletedDays: const WatchCompletedDays(NoCompletedDays()),
        watchRejectedWrites: WatchRejectedProgramWrites(programs),
        resolveMissedDay: ResolveMissedDay(programs),
        watchPremium: const WatchPremium(FixedPremium(false)),
      ),
      dispose: (cubit) => cubit.close(),
    );
    // The catalogue knows the user owns no equipment.
    final catalogueLibrary = MockUserLibraryRepository();
    when(() => catalogueLibrary.watchEquipment(any()))
        .thenAnswer((_) => Stream.value(const {}));
    final catalogueEquipment = EquipmentCubit(
      watchAuthUser: WatchAuthUser(programAuth),
      watchEquipment: WatchOwnedEquipment(catalogueLibrary),
      saveEquipment: SaveOwnedEquipment(catalogueLibrary),
    );
    final readyMadePrograms = MockCatalogueRepository();
    when(readyMadePrograms.watchPrograms)
        .thenAnswer((_) => Stream.value(readyMade));
    when(() => readyMadePrograms.getDays(any())).thenAnswer(
      (_) async => const Ok([
        ProgramDay(
          items: [
            ProgramItem(exerciseId: 'squat', sets: 3, repMin: 8, restS: 60),
          ],
        ),
      ]),
    );
    sl
      ..registerLazySingleton(
        () => ProgramCatalogueCubit(
          watchAuthUser: WatchAuthUser(programAuth),
          watchCatalogue: WatchCatalogue(readyMadePrograms),
          watchPremium: const WatchPremium(FixedPremium(false)),
          profile: profile,
          equipment: catalogueEquipment,
        ),
        dispose: (cubit) async {
          await cubit.close();
          await catalogueEquipment.close();
        },
      )
      ..registerFactoryParam<CatalogueDetailCubit, String, String>(
        (id, language) => CatalogueDetailCubit(
          id,
          language: language,
          catalogue: sl(),
          list: sl(),
          exercises: catalogue,
          getDays: GetCatalogueDays(readyMadePrograms),
          saveProgram: SaveProgram(programs),
          getCurrentUser: GetCurrentUser(programAuth),
        ),
      )
      ..registerLazySingleton(
        () => LibraryCubit(
          watchAuthUser: WatchAuthUser(settingsAuth),
          catalogue: catalogue,
          favorites: favorites,
          equipment: equipment,
        ),
        dispose: (cubit) => cubit.close(),
      )
      ..registerLazySingleton(
        () => CustomWriteRejectionsCubit(
          WatchRejectedCustomExerciseWrites(customExercises),
        ),
        dispose: (cubit) => cubit.close(),
      )
      ..registerFactoryParam<ExerciseDetailCubit, String, void>(
        (id, _) => ExerciseDetailCubit(
          id,
          catalogue: catalogue,
          equipment: equipment,
          getCurrentUser: GetCurrentUser(settingsAuth),
          deleteCustomExercise: DeleteCustomExercise(customExercises),
        ),
      )
      ..registerFactoryParam<CustomExerciseFormCubit, CustomExercise?, void>(
        (exercise, _) => CustomExerciseFormCubit(
          saveExercise: SaveCustomExercise(customExercises),
          getCurrentUser: GetCurrentUser(settingsAuth),
          watchAuthUser: WatchAuthUser(settingsAuth),
          initial: exercise,
        ),
      );
    profiles = MockProfileRepository();
    when(() => profiles.watchProfile(any())).thenAnswer((_) {
      profileStream = StreamController<UserProfile>();
      if (storedProfile case final stored?) profileStream.add(stored);
      return profileStream.stream;
    });
    // Like Firestore's local cache: the write shows up in the stream at once.
    when(() => profiles.completeOnboarding(any(), any())).thenAnswer((call) {
      profileStream.add(storedProfile = onboarded);
      return Future.value(const Ok(null));
    });
    when(() => profiles.saveFields(any(), any(), any())).thenAnswer((call) {
      profileStream.add(
        storedProfile = call.positionalArguments[1] as UserProfile,
      );
      return Future.value(const Ok(null));
    });
    sl
      ..registerFactory(
        () => CompleteOnboarding(profiles, SaveOwnedEquipment(userLibrary)),
      )
      ..registerLazySingleton(SkippedOnboarding.new)
      ..registerFactory(
        () => UpdateProfile(profiles, SaveOwnedEquipment(userLibrary)),
      );
    profile = ProfileCubit(
      watchAuthUser: WatchAuthUser(repository),
      watchProfile: WatchProfile(profiles),
      updateProfile: UpdateProfile(profiles, SaveOwnedEquipment(userLibrary)),
    );
    // Purchases run on the fake store; tests identify the user themselves.
    store = FakePurchasesRepository(
      plans: fakePlans,
      purchaseDelay: Duration.zero,
    );
    entitlement = EntitlementCubit(
      configure: ConfigurePurchases(store),
      watchEntitlement: WatchEntitlement(store),
      identify: IdentifyPurchaser(store),
      reset: ResetPurchaser(store),
      refresh: RefreshEntitlement(store),
      getManagementUrl: GetManagementUrl(store),
      // Past every expiry, so no expiry timer outlives a test.
      clock: () => DateTime(9999),
    );
    registerTodayStandIns();
    registerBodyListStandIn();
    sl.registerFactory(
      () => PremiumPaywallCubit(
        getOffering: GetOffering(store),
        purchasePlan: PurchasePlan(store),
        restorePurchases: RestorePurchases(store),
      ),
    );
  }

  tearDown(() async {
    await auth.close();
    await settings.close();
    await profile.close();
    await entitlement.close();
    await sl.reset();
    await catalogue.close();
    await favorites.close();
    await equipment.close();
    await bodyModel.close();
    await exerciseFeed.close();
    holdCatalogue = false;
    readyMade = [];
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: auth),
        BlocProvider.value(value: settings),
        if (consent case final consent?)
          BlocProvider.value(value: consent)
        else
          answeredConsent(),
        programList(),
        noWorkout(),
        BlocProvider.value(value: profile),
        BlocProvider.value(value: catalogue),
        BlocProvider.value(value: favorites),
        BlocProvider.value(value: equipment),
        BlocProvider.value(value: bodyModel),
        BlocProvider.value(value: entitlement),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router = buildRouter(
          auth,
          profile,
          deletionUnderway: deletionUnderway,
          skippedOnboarding: sl(),
        ),
      ),
    ),
  );

  Future<void> startAsGuest(WidgetTester tester) async {
    setUpAuth();
    await pumpApp(tester);
    users.add(guest);
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Train's Exercises view.
  Future<void> openExercises(WidgetTester tester) async {
    await tapTab(tester, 'Train');
    await tester.tap(find.text('Exercises'));
    await tester.pumpAndSettle();
  }

  /// The exercise list, through the Exercises view's search box.
  Future<void> openList(WidgetTester tester) async {
    await openExercises(tester);
    await tester.tap(find.byType(LibrarySearchEntry));
    await tester.pumpAndSettle();
  }

  /// The location of the page in front of Train's stack.
  String front() =>
      openLocations(router.routerDelegate.currentConfiguration).last;

  bool searchFocused(WidgetTester tester) => tester
      .state<EditableTextState>(find.byType(EditableText, skipOffstage: false))
      .widget
      .focusNode
      .hasFocus;

  String path() => router.routerDelegate.currentConfiguration.uri.path;

  int selectedTab(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

  Future<void> openAccount(WidgetTester tester) async {
    await tapTab(tester, 'Profile');
    await tester.tap(find.text('Create account or sign in'));
    await tester.pumpAndSettle();
  }

  Future<void> openSignUpAsGuest(WidgetTester tester) async {
    await startAsGuest(tester);
    await openAccount(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'a@b.co');
  }

  testWidgets('the auth page closes once the guest is upgraded', (
    tester,
  ) async {
    await openSignUpAsGuest(tester);

    users.add(member);
    await tester.pumpAndSettle();

    expect(find.byType(AuthPage), findsNothing);
    expect(find.text('a@b.co'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('a failed guest start offers a retry', (tester) async {
    setUpAuth();
    var attempts = 0;
    when(() => repository.signInAnonymously()).thenAnswer((_) async {
      if (++attempts == 1) return const Err(NetworkFailure());
      users.add(guest);
      return const Ok(guest);
    });
    await pumpApp(tester);

    users.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('a session update keeps the auth form', (tester) async {
    await openSignUpAsGuest(tester);

    users.add(const AuthUser(id: 'u1', displayName: 'G', isAnonymous: true));
    await tester.pumpAndSettle();

    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('a@b.co'), findsOneWidget);
  });

  testWidgets('a started session lands on Today with four tabs', (
    tester,
  ) async {
    await startAsGuest(tester);

    expect(find.byType(TodayPage), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
  });

  testWidgets('tabs switch and keep their own stack', (tester) async {
    await startAsGuest(tester);
    await openAccount(tester);
    expect(find.byType(AccountPage), findsOneWidget);

    await tapTab(tester, 'Train');
    expect(find.byType(ProgramsPage), findsOneWidget);
    expect(find.byType(AccountPage), findsNothing);

    await tapTab(tester, 'Profile');
    expect(find.byType(AccountPage), findsOneWidget);
  });

  testWidgets('tapping the open tab returns to its first page', (tester) async {
    await startAsGuest(tester);
    await openAccount(tester);

    await tapTab(tester, 'Profile');

    expect(find.byType(AccountPage), findsNothing);
    expect(find.byType(ProfilePage), findsOneWidget);
  });

  testWidgets('the profile row shows the email once signed in', (tester) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Profile');

    users.add(member);
    await tester.pumpAndSettle();

    expect(find.text('Create account or sign in'), findsNothing);
    expect(find.text('a@b.co'), findsOneWidget);
  });

  testWidgets('the root location opens Today', (tester) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Train');

    router.go('/');
    await tester.pumpAndSettle();

    expect(find.byType(TodayPage), findsOneWidget);
  });

  testWidgets('an exercise opens its detail inside the Train tab', (
    tester,
  ) async {
    await startAsGuest(tester);
    await openList(tester);

    await tester.tap(find.text('Back Squat'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.text('Back Squat'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  group('exercise list', () {
    LibraryState library() => sl<LibraryCubit>().state;
    List<String> ids(List<Exercise> exercises) => [
      for (final exercise in exercises) exercise.id,
    ];

    Future<void> startWithSplitSquat(WidgetTester tester) async {
      holdCatalogue = true;
      await startAsGuest(tester);
      exerciseFeed.add([_squat, _splitSquat]);
      await openExercises(tester);
    }

    testWidgets('the search box opens it inside Train, searching; back '
        'returns to the Exercises view', (tester) async {
      await startAsGuest(tester);
      await openExercises(tester);
      expect(find.byTooltip('New custom exercise'), findsNothing);

      await tester.tap(find.byType(LibrarySearchEntry));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(front(), Routes.exerciseList);
      expect(selectedTab(tester), 1);
      expect(searchFocused(tester), isTrue);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(path(), Routes.exercises);
    });

    testWidgets('keeps the search for the next time it opens', (tester) async {
      await startAsGuest(tester);
      await openList(tester);
      await tester.enterText(find.byType(TextField), 'squat');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(LibrarySearchEntry),
          matching: find.text('squat'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byType(LibrarySearchEntry));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'squat'), findsOneWidget);
    });

    testWidgets('a muscle opens it filtered, in main and also-works '
        'sections, without the keyboard', (tester) async {
      await startWithSplitSquat(tester);

      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();

      expect(front(), Routes.exerciseList);
      expect(selectedTab(tester), 1);
      expect(searchFocused(tester), isFalse);
      expect(library().filter.muscles, {Muscle.quads});
      expect(ids(library().muscleExercises!.main), ['squat']);
      expect(ids(library().muscleExercises!.alsoWorks), ['split_squat']);
      expect(find.text('Main'), findsOneWidget);
      expect(find.text('Also works'), findsOneWidget);

      // The muscle's chip.
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(library().filter.muscles, isEmpty);
      expect(find.text('Main'), findsNothing);
      expect(find.text('Also works'), findsNothing);
      expect(find.text('Back Squat'), findsOneWidget);
      expect(find.text('Split Squat'), findsOneWidget);
    });

    testWidgets('a muscle visit clears the search and takes its muscle '
        'along when it ends, so the box opens without it', (tester) async {
      await startAsGuest(tester);
      await openList(tester);
      await tester.enterText(find.byType(TextField), 'bench');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();
      expect(library().query, '');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(library().filter.muscles, isEmpty);
      expect(
        find.descendant(
          of: find.byType(LibrarySearchEntry),
          matching: find.text('bench'),
        ),
        findsNothing,
      );
      await tester.tap(find.byType(LibrarySearchEntry));
      await tester.pumpAndSettle();
      expect(library().filter.muscles, isEmpty);
      expect(find.text('Main'), findsNothing);
    });

    testWidgets('a muscle filter the user changed outlives the visit', (
      tester,
    ) async {
      await startWithSplitSquat(tester);
      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();

      sl<LibraryCubit>().toggleMuscle(Muscle.glute);
      await tester.pumpAndSettle();
      expect(find.text('Main'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(library().filter.muscles, {Muscle.quads, Muscle.glute});
    });

    testWidgets('one muscle picked by hand gives no sections', (tester) async {
      await startWithSplitSquat(tester);
      await tester.tap(find.byType(LibrarySearchEntry));
      await tester.pumpAndSettle();

      sl<LibraryCubit>().toggleMuscle(Muscle.quads);
      await tester.pumpAndSettle();

      expect(library().muscle, Muscle.quads);
      expect(find.text('Main'), findsNothing);
      expect(find.text('Split Squat'), findsOneWidget);
    });

    testWidgets('a link to another muscle updates the open page', (
      tester,
    ) async {
      await startWithSplitSquat(tester);
      router.go(Routes.exerciseListOf(Muscle.quads));
      await tester.pumpAndSettle();

      router.go(Routes.exerciseListOf(Muscle.glute));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(library().filter.muscles, {Muscle.glute});
      expect(ids(library().muscleExercises!.main), ['split_squat']);
      expect(find.text('Main'), findsOneWidget);

      router.go(Routes.exerciseList);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(library().filter.muscles, isEmpty);
      expect(find.text('Main'), findsNothing);
    });

    testWidgets('one gesture on the model opens one page', (tester) async {
      await startAsGuest(tester);
      await openExercises(tester);
      final model = tester.element(find.byType(BodyView));

      openMuscleList(model, Muscle.quads);
      await tester.pump();
      // A second tap, or a slide ending, while the list comes in.
      openMuscleList(model, Muscle.glute);
      await tester.pumpAndSettle();

      expect(find.byType(LibraryPage), findsOneWidget);
      expect(library().filter.muscles, {Muscle.quads});
    });

    testWidgets('is not taken for an exercise id', (tester) async {
      await startAsGuest(tester);

      router.go(Routes.exerciseList);
      await tester.pumpAndSettle();

      expect(find.byType(LibraryPage), findsOneWidget);
      expect(find.byType(ExerciseDetailPage), findsNothing);
      expect(selectedTab(tester), 1);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ExercisesPage), findsOneWidget);
    });

    testWidgets('selecting Train again ends a muscle visit', (tester) async {
      await startAsGuest(tester);
      await openExercises(tester);
      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();

      await tapTab(tester, 'Train');

      expect(find.byType(LibraryPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(library().filter.muscles, isEmpty);
    });

    testWidgets('selecting Train again returns to the Exercises view', (
      tester,
    ) async {
      await startAsGuest(tester);
      await openList(tester);
      await tester.tap(find.text('Back Squat'));
      await tester.pumpAndSettle();

      await tapTab(tester, 'Train');

      expect(find.byType(ExerciseDetailPage), findsNothing);
      expect(find.byType(LibraryPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(path(), Routes.exercises);
    });

    testWidgets('its + opens a new custom exercise inside the tab, whose '
        'changes are asked about on back', (tester) async {
      await startAsGuest(tester);
      await openList(tester);

      await tester.tap(find.byTooltip('New custom exercise'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomExerciseNewPage), findsOneWidget);
      expect(front(), Routes.customExerciseNew);
      expect(find.byType(NavigationBar), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Sled');
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomExerciseNewPage), findsNothing);
      expect(find.byType(LibraryPage), findsOneWidget);
    });
  });

  group('Train', () {
    testWidgets('opens on My program, its views at their own locations', (
      tester,
    ) async {
      await startAsGuest(tester);

      await tapTab(tester, 'Train');
      expect(find.byType(ProgramsPage), findsOneWidget);
      expect(find.byType(ExercisesPage), findsNothing);
      expect(path(), Routes.programs);

      await tester.tap(find.text('Exercises'));
      await tester.pumpAndSettle();
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(find.byType(ProgramsPage), findsNothing);
      expect(path(), Routes.exercises);

      await tester.tap(find.text('My program'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramsPage), findsOneWidget);
      expect(path(), Routes.programs);
    });

    testWidgets('each location lands on Train in its view', (tester) async {
      await startAsGuest(tester);

      router.go(Routes.exercises);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      expect(find.byType(ExercisesPage), findsOneWidget);

      router.go(Routes.today);
      await tester.pumpAndSettle();
      router.go(Routes.programs);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      expect(find.byType(ProgramsPage), findsOneWidget);
    });

    testWidgets('deep locations of both views open inside Train', (
      tester,
    ) async {
      await startAsGuest(tester);
      final pages = {
        Routes.exercise('squat'): ExerciseDetailPage,
        Routes.exerciseList: LibraryPage,
        Routes.customExerciseNew: CustomExerciseNewPage,
        Routes.catalogue: CataloguePage,
      };

      for (final MapEntry(key: location, value: page) in pages.entries) {
        router.go(Routes.today);
        await tester.pumpAndSettle();
        router.go(location);
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget, reason: location);
        expect(selectedTab(tester), 1, reason: location);
      }
    });

    testWidgets('switching views keeps both views and the page', (
      tester,
    ) async {
      await startAsGuest(tester);
      await openExercises(tester);
      Element element(Type type) =>
          tester.element(find.byType(type, skipOffstage: false));
      final train = element(TrainPage);
      final exercises = element(ExercisesPage);

      await tester.tap(find.text('My program'));
      await tester.pumpAndSettle();
      final programs = element(ProgramsPage);
      // Kept, only out of sight.
      expect(element(ExercisesPage), same(exercises));
      expect(find.byType(ExercisesPage), findsNothing);

      router.go(Routes.exercises);
      await tester.pumpAndSettle();
      expect(element(TrainPage), same(train));
      expect(element(ExercisesPage), same(exercises));
      expect(element(ProgramsPage), same(programs));
      expect(find.byType(ExercisesPage), findsOneWidget);
    });

    testWidgets('selecting Train again restores the view it showed', (
      tester,
    ) async {
      await startAsGuest(tester);
      await openExercises(tester);

      await tapTab(tester, 'Today');
      await tapTab(tester, 'Train');

      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(path(), Routes.exercises);
    });

    testWidgets('a view is built only once it shows', (tester) async {
      await startAsGuest(tester);
      await tapTab(tester, 'Train');

      expect(find.byType(ExercisesPage, skipOffstage: false), findsNothing);
    });

    testWidgets('a page above a view leaves with the view switched', (
      tester,
    ) async {
      await startAsGuest(tester);
      router.go(Routes.exercise('squat'));
      await tester.pumpAndSettle();

      router.go(Routes.programs);
      await tester.pumpAndSettle();

      expect(find.byType(ExerciseDetailPage), findsNothing);
      expect(find.byType(ProgramsPage), findsOneWidget);
    });
  });

  group('Add to program without programs', () {
    Future<void> createProgram(WidgetTester tester) async {
      await startAsGuest(tester);
      router.go(Routes.exercise('squat'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add to…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to program'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create program'));
      await tester.pumpAndSettle();
      expect(find.byType(ProgramBuilderPage), findsOneWidget);
    }

    void expectBackOnTheExercise(WidgetTester tester) {
      expect(find.byType(ProgramBuilderPage), findsNothing);
      expect(find.byType(ExerciseDetailPage), findsOneWidget);
      expect(selectedTab(tester), 1);
      expect(path(), Routes.exercise('squat'));
    }

    testWidgets('leaving the builder returns to the exercise', (tester) async {
      await createProgram(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expectBackOnTheExercise(tester);
    });

    testWidgets('saving the program returns to the exercise', (tester) async {
      await createProgram(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Program name'),
        'Push',
      );
      await tester.tap(find.text('Add exercises'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back Squat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(() => programs.createProgram('u1', any())).called(1);
      expectBackOnTheExercise(tester);
    });

    testWidgets('leaving with changes asks once, then returns', (tester) async {
      await createProgram(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Program name'),
        'Push',
      );
      // The page refuses to pop from the next frame on.
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expectBackOnTheExercise(tester);
    });
  });

  group('custom exercise form with changes', () {
    Future<void> fillIn(WidgetTester tester) async {
      await startAsGuest(tester);
      router.go(Routes.customExerciseNew);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Sled push',
      );
      await tester.pump();
    }

    testWidgets('a link into Train asks first; keeping them stays', (
      tester,
    ) async {
      await fillIn(tester);
      await tapTab(tester, 'Today');

      router.go(Routes.catalogue);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(selectedTab(tester), 1);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(path(), Routes.customExerciseNew);
      expect(find.widgetWithText(TextField, 'Sled push'), findsOneWidget);
    });

    testWidgets('back asks once with the same prompt', (tester) async {
      await fillIn(tester);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(CustomExerciseNewPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
    });

    testWidgets('without changes a link leaves it silently', (tester) async {
      await startAsGuest(tester);
      router.go(Routes.customExerciseNew);
      await tester.pumpAndSettle();

      router.go(Routes.catalogue);
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(CataloguePage), findsOneWidget);
    });
  });

  testWidgets('an unknown exercise id shows not found', (tester) async {
    await startAsGuest(tester);

    router.go(Routes.exercise('retired_since'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.text('This exercise is no longer available.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('editing an exercise that is not custom shows not found', (
    tester,
  ) async {
    await startAsGuest(tester);

    router.go(Routes.customExerciseEdit('squat'));
    await tester.pumpAndSettle();

    expect(find.byType(CustomExerciseEditPage), findsOneWidget);
    expect(find.text('This exercise is no longer available.'), findsOneWidget);
  });

  testWidgets('Profile opens the calculators inside the tab', (tester) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Profile');

    await tester.tap(find.text('Calculators'));
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsPage), findsOneWidget);

    await tester.tap(find.text('Calories'));
    await tester.pumpAndSettle();
    expect(find.byType(CaloriesPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsPage), findsOneWidget);
  });

  testWidgets('every calculator has a route under Profile', (tester) async {
    await startAsGuest(tester);
    final pages = {
      Routes.calories: CaloriesPage,
      Routes.bodyFat: BodyFatPage,
      Routes.oneRepMax: OneRepMaxPage,
      Routes.plates: PlatesPage,
      Routes.macros: MacrosPage,
      Routes.bodyIndices: BodyIndicesPage,
    };

    for (final MapEntry(key: route, value: page) in pages.entries) {
      router.go(route);
      await tester.pumpAndSettle();
      expect(find.byType(page), findsOneWidget, reason: route);
      expect(find.byType(NavigationBar), findsOneWidget, reason: route);
      expect(route, startsWith('${Routes.calculators}/'));
    }
  });

  testWidgets('a calculator keeps its place when switching tabs', (
    tester,
  ) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Profile');
    router.go(Routes.plates);
    await tester.pumpAndSettle();

    await tapTab(tester, 'Today');
    await tapTab(tester, 'Profile');

    expect(find.byType(PlatesPage), findsOneWidget);
  });

  group('onboarding', () {
    testWidgets('a new user sees onboarding once the session resolves', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('a returning user waits for the profile, then skips it', (
      tester,
    ) async {
      storedProfile = null;
      setUpAuth();
      await pumpApp(tester);
      users.add(guest);
      await tester.pump();
      await tester.pump();

      // The splash stays while the profile is loading.
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(TodayPage), findsNothing);

      profileStream.add(onboarded);
      await tester.pumpAndSettle();

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('a profile that cannot be read does not trap the user', (
      tester,
    ) async {
      storedProfile = null;
      setUpAuth();
      await pumpApp(tester);
      users.add(guest);
      await tester.pump();
      profileStream.addError(const NetworkFailure());
      await tester.pumpAndSettle();

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);

      // The read is retried; a new user is not let off onboarding by it.
      storedProfile = const UserProfile();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
    });

    testWidgets('skipping completes onboarding and lands on Today, with '
        'no program suggested', (tester) async {
      readyMade = [
        card(
          'pr_free',
          goal: Goal.loseFat,
          equipment: const [Equipment.bodyweight],
          profile: EquipmentProfile.bodyweight,
        ),
      ];
      storedProfile = const UserProfile();
      await startAsGuest(tester);
      // Answers the free program fits, which finishing would suggest.
      when(() => profiles.completeOnboarding(any(), any())).thenAnswer((_) {
        profileStream.add(
          storedProfile = UserProfile(
            goal: Goal.loseFat,
            onboardingCompletedAt: DateTime(2026),
          ),
        );
        return Future.value(const Ok(null));
      });

      await tester.tap(find.text('Lose fat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      verify(
        () => profiles.completeOnboarding(
          'u1',
          const UserProfile(goal: Goal.loseFat),
        ),
      ).called(1);
      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(ProgramSuggestionPage), findsNothing);
    });

    testWidgets('a fitting free program is suggested after onboarding', (
      tester,
    ) async {
      readyMade = [
        card(
          'pr_free',
          goal: Goal.loseFat,
          equipment: const [Equipment.bodyweight],
          profile: EquipmentProfile.bodyweight,
        ),
        card('pr_paid', premium: true, goal: Goal.loseFat, order: 2),
      ];
      storedProfile = const UserProfile(
        goal: Goal.loseFat,
        level: Level.beginner,
        daysPerWeek: 3,
        equipment: {},
      );
      await startAsGuest(tester);
      when(() => profiles.completeOnboarding(any(), any())).thenAnswer((_) {
        profileStream.add(
          storedProfile = UserProfile(
            goal: Goal.loseFat,
            onboardingCompletedAt: DateTime(2026),
          ),
        );
        return Future.value(const Ok(null));
      });

      // Through every question to the summary, and finished there.
      for (var i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('Skip this question'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Start training'));
      await tester.pumpAndSettle();

      expect(find.byType(ProgramSuggestionPage), findsOneWidget);
      expect(find.text('Program pr_free'), findsOneWidget);
      expect(find.text('Program pr_paid'), findsNothing);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayPage), findsOneWidget);
    });

    testWidgets('onboarding goes forward and back one question at a time', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);
      expect(find.text('Question 1 of 9'), findsOneWidget);

      await tester.tap(find.text('Build muscle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Question 2 of 9'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Question 1 of 9'), findsOneWidget);
    });

    testWidgets('a retried guest start ends the splash for the new guest', (
      tester,
    ) async {
      await startAsGuest(tester);
      var attempts = 0;
      when(() => repository.signInAnonymously()).thenAnswer((_) async {
        if (++attempts == 1) return const Err(NetworkFailure());
        users.add(const AuthUser(id: 'u2', isAnonymous: true));
        return const Ok(guest);
      });

      // Signed out, and the new guest could not start.
      users.add(null);
      await tester.pumpAndSettle();
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      // Same gate as the previous user, but a different user: it refreshes.
      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(LoadingView), findsNothing);
      verify(() => profiles.watchProfile('u2')).called(1);
    });

    testWidgets('a deletion underway keeps the user in place until it ends', (
      tester,
    ) async {
      await startAsGuest(tester);
      await tapTab(tester, 'Profile');
      deletionUnderway.value = true;

      // The server deleted the profile; the user is not signed out yet.
      profileStream.add(const UserProfile());
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);

      deletionUnderway.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
    });

    testWidgets('signing out onboards the new guest', (tester) async {
      await startAsGuest(tester);
      await tapTab(tester, 'Profile');
      when(() => repository.signInAnonymously()).thenAnswer((_) async {
        users.add(const AuthUser(id: 'u2', isAnonymous: true));
        return const Ok(guest);
      });
      storedProfile = const UserProfile();

      // Like Firebase: no user for a moment, while the auth cubit stays
      // signed in as the old user and starts a new guest.
      users.add(null);
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('a profile stream that dies on onboarding does not trap', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);

      profileStream.addError(const NetworkFailure());
      await tester.pump();
      expect(find.byType(OnboardingPage), findsOneWidget);

      // Completing follows the profile again at once and moves on.
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('a deep link waits behind onboarding, which lands on Today', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      setUpAuth();
      await pumpApp(tester);
      router.go(Routes.exercise('squat'));
      users.add(guest);
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(ExerciseDetailPage), findsNothing);

      // Also once onboarding shows.
      router.go(Routes.exercise('squat'));
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(ExerciseDetailPage), findsNothing);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('a returning user signs in from onboarding; their profile '
        'decides', (tester) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);

      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      final auth = tester.widget<AuthPage>(find.byType(AuthPage));
      expect(auth.initialSignUp, isFalse);
      expect(find.byType(NavigationBar), findsNothing);

      // The account (another uid) has completed onboarding.
      storedProfile = onboarded;
      users.add(const AuthUser(id: 'u2', email: 'b@c.de'));
      await tester.pumpAndSettle();

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(AuthPage), findsNothing);
      // The guest wrote no profile to get there.
      verifyNever(() => profiles.completeOnboarding(any(), any()));
      verifyNever(() => profiles.saveFields(any(), any(), any()));
    });

    testWidgets('an account without a completed profile is onboarded', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);
      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();

      users.add(const AuthUser(id: 'u2', email: 'b@c.de'));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(AuthPage), findsNothing);
      expect(find.text('Question 1 of 9'), findsOneWidget);
      // Signed in already.
      expect(find.text('I already have an account'), findsNothing);
    });

    testWidgets('a guest linked to a new account is not offered to sign in', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);
      expect(find.text('I already have an account'), findsOneWidget);

      // Linking keeps the uid and the guest's unfinished onboarding.
      users.add(member);
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('I already have an account'), findsNothing);
    });

    testWidgets('a personal question can be skipped on its own', (
      tester,
    ) async {
      storedProfile = const UserProfile(
        goal: Goal.loseFat,
        level: Level.beginner,
        daysPerWeek: 3,
        equipment: {},
      );
      await startAsGuest(tester);
      for (var i = 0; i < 4; i++) {
        expect(find.text('Skip this question'), findsNothing);
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Question 5 of 9'), findsOneWidget);

      await tester.tap(find.text('Skip this question'));
      await tester.pumpAndSettle();

      expect(find.text('Question 6 of 9'), findsOneWidget);
    });

    testWidgets('linking the guest does not bring onboarding back', (
      tester,
    ) async {
      await startAsGuest(tester);

      users.add(member);
      await tester.pumpAndSettle();

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
      verify(() => profiles.watchProfile('u1')).called(1);
    });

    testWidgets('another user without a completed profile is onboarded', (
      tester,
    ) async {
      await startAsGuest(tester);

      storedProfile = const UserProfile();
      users.add(const AuthUser(id: 'u2', isAnonymous: true));
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
    });
  });

  testWidgets('Profile edits one answer at a time', (tester) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Profile');

    await tester.tap(find.text('Your profile'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileDetailsPage), findsOneWidget);

    await tester.tap(find.text('Goal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get stronger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    verify(
      () => profiles.saveFields(
        'u1',
        onboarded.copyWith(goal: Goal.getStronger),
        {ProfileField.goal},
      ),
    ).called(1);
    expect(find.byType(ProfileDetailsPage), findsOneWidget);
    expect(find.text('Get stronger'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  group('consent prompt', () {
    const unanswered = (consent: null, fromServer: true);
    final dialog = find.text('Help improve GetWorkout?');
    late MockConsentRepository consents;

    /// Starts as onboarded guest u1, who answered; [answers] are the
    /// server's answers of the other users (none: not answered).
    Future<void> start(
      WidgetTester tester, [
      Map<String, bool> answers = const {},
    ]) async {
      setUpAuth();
      consents = MockConsentRepository();
      when(() => consents.watchConsent(any())).thenAnswer((call) {
        final uid = call.positionalArguments.first as String;
        return Stream.value(
          uid == 'u1'
              ? (consent: true, fromServer: true)
              : answers.containsKey(uid)
              ? (consent: answers[uid], fromServer: true)
              : unanswered,
        );
      });
      when(() => consents.saveConsent(any(), any()))
          .thenAnswer((_) async => const Ok(null));
      final telemetry = MockTelemetry();
      when(() => telemetry.follow(any()))
          .thenAnswer((_) async => const Ok(null));
      when(() => telemetry.apply(any(), any()))
          .thenAnswer((_) async => const Ok(null));
      consent = ConsentCubit(
        watchAuthUser: WatchAuthUser(repository),
        getCurrentUser: GetCurrentUser(repository),
        deletionUnderway: deletionUnderway,
        watchConsent: WatchAnalyticsConsent(consents),
        saveConsent: SaveAnalyticsConsent(consents),
        followUser: FollowAnalyticsUser(telemetry),
        applyConsent: ApplyAnalyticsConsent(telemetry),
      );
      addTearDown(consent!.close);
      await pumpApp(tester);
      users.add(guest);
      await tester.pumpAndSettle();
      expect(find.byType(TodayPage), findsOneWidget);
      expect(dialog, findsNothing);
    }

    testWidgets('a new guest after sign-out is asked only on Today, once', (
      tester,
    ) async {
      await start(tester);
      when(() => repository.signInAnonymously()).thenAnswer((_) async {
        users.add(const AuthUser(id: 'u2', isAnonymous: true));
        return const Ok(guest);
      });
      // The new guest's profile arrives after their consent.
      storedProfile = null;

      users.add(null);
      await tester.pumpAndSettle();
      // Still on the tabs, the new guest's profile loading.
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(dialog, findsNothing);

      profileStream.add(const UserProfile());
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(dialog, findsNothing);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayPage), findsOneWidget);
      expect(dialog, findsOneWidget);

      await tester.tap(find.text("Don't allow"));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      verify(() => consents.saveConsent('u2', false)).called(1);
    });

    testWidgets('an account signed in from the tabs is asked once its '
        'profile shows it onboarded', (tester) async {
      await start(tester);
      storedProfile = null;

      users.add(const AuthUser(id: 'u2', email: 'b@c.de'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);

      profileStream.add(onboarded);
      await tester.pumpAndSettle();
      expect(find.byType(TodayPage), findsOneWidget);
      expect(dialog, findsOneWidget);
    });
  });

  group('pages follow the signed-in user', () {
    const other = AuthUser(id: 'u2', isAnonymous: true);

    testWidgets('onboarding starts over for a new user, writing only theirs', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);
      await tester.tap(find.text('Lose fat'));
      await tester.pumpAndSettle();

      users.add(other);
      await tester.pump();
      // Never an endless loader: the new user's profile arrives.
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Question 1 of 9'), findsOneWidget);

      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      verify(() => profiles.completeOnboarding('u2', const UserProfile()))
          .called(1);
      verifyNever(() => profiles.completeOnboarding('u1', any()));
      expect(find.byType(TodayPage), findsOneWidget);
    });

    testWidgets('an open question shows and saves the new user\'s answer', (
      tester,
    ) async {
      await startAsGuest(tester);
      router.go(Routes.profileQuestion(ProfileField.goal));
      await tester.pumpAndSettle();

      storedProfile = onboarded.copyWith(goal: Goal.generalFitness);
      users.add(other);
      await tester.pumpAndSettle();
      expect(find.byType(ProfileQuestionPage), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<Goal>>(find.byType(RadioGroup<Goal>))
            .groupValue,
        Goal.generalFitness,
      );

      await tester.tap(find.text('Get stronger'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      verify(
        () => profiles.saveFields(
          'u2',
          onboarded.copyWith(goal: Goal.getStronger),
          {ProfileField.goal},
        ),
      ).called(1);
      verifyNever(() => profiles.saveFields('u1', any(), any()));
    });

    testWidgets('a question opened while the profile loads waits for it', (
      tester,
    ) async {
      await startAsGuest(tester);
      router.go(Routes.profileQuestion(ProfileField.goal));
      await tester.pumpAndSettle();

      storedProfile = null;
      users.add(const AuthUser(id: 'u2', email: 'b@c.de'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LoadingView), findsOneWidget);

      profileStream.add(onboarded);
      await tester.pumpAndSettle();
      expect(find.text('Get stronger'), findsOneWidget);
    });
  });

  group('Your profile', () {
    testWidgets('shows a loader, then a retry when the profile is unreadable', (
      tester,
    ) async {
      await startAsGuest(tester);
      await tapTab(tester, 'Profile');
      await tester.tap(find.text('Your profile'));
      await tester.pumpAndSettle();

      storedProfile = null;
      users.add(const AuthUser(id: 'u2', email: 'b@c.de'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(LoadingView), findsOneWidget);
      expect(find.text('Not answered'), findsNothing);

      profileStream.addError(const NetworkFailure());
      await tester.pump();
      await tester.pump();
      expect(
        find.text("Couldn't load your profile. Check your connection."),
        findsOneWidget,
      );

      storedProfile = onboarded;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Not answered'), findsWidgets);
    });

    testWidgets('a rejected save is reported once after the page closed', (
      tester,
    ) async {
      final rejection = Completer<Result<void>>();
      await startAsGuest(tester);
      when(() => profiles.saveFields(any(), any(), any()))
          .thenAnswer((_) => rejection.future);
      await tapTab(tester, 'Profile');
      await tester.tap(find.text('Your profile'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Goal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get stronger'));
      await tester.pumpAndSettle();

      // The page closes at once, before the server answers.
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileDetailsPage), findsOneWidget);

      rejection.complete(const Err(PermissionFailure()));
      await tester.pumpAndSettle();
      expect(
        find.text("A change to your profile couldn't be saved."),
        findsOneWidget,
      );

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(
        find.text("A change to your profile couldn't be saved."),
        findsNothing,
      );
    });
  });

  testWidgets('a detail link opened while the catalogue loads waits for it', (
    tester,
  ) async {
    holdCatalogue = true;
    await startAsGuest(tester);

    router.go(Routes.exercise('squat'));
    // A spinner never settles, so pump frames by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('This exercise is no longer available.'), findsNothing);

    exerciseFeed.add([_squat]);
    await tester.pumpAndSettle();

    expect(find.text('Back Squat'), findsOneWidget);
    expect(find.text('This exercise is no longer available.'), findsNothing);
  });

  group('Premium', () {
    Future<void> openProfileAsFreeGuest(WidgetTester tester) async {
      await startAsGuest(tester);
      await entitlement.identify(guest.id);
      await tapTab(tester, 'Profile');
    }

    Future<void> tapVisible(WidgetTester tester, String text) async {
      await tester.ensureVisible(find.text(text));
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    testWidgets('the row does nothing while the status is unknown', (
      tester,
    ) async {
      await startAsGuest(tester);
      await tapTab(tester, 'Profile');
      expect(find.text('Checking…'), findsOneWidget);

      await tester.tap(find.text('GetWorkout Premium'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsNothing);
    });

    testWidgets('a free user starts the yearly trial', (tester) async {
      await openProfileAsFreeGuest(tester);
      expect(find.text('Free'), findsOneWidget);

      await tapVisible(tester, 'GetWorkout Premium');
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.text(r'$4.99 per month'), findsOneWidget);
      expect(find.text(r'7 days free, then $39.99 per year'), findsOneWidget);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      await tapVisible(tester, 'Start free trial');

      expect(find.byType(PaywallPage), findsNothing);
      expect(find.text('Welcome to Premium!'), findsOneWidget);
      expect(find.textContaining('Free trial until'), findsOneWidget);
    });

    testWidgets('a restore after a failed load keeps the load message', (
      tester,
    ) async {
      await openProfileAsFreeGuest(tester);
      store.failure = const NetworkFailure();
      await tapVisible(tester, 'GetWorkout Premium');
      expect(find.text('No internet connection'), findsOneWidget);

      store.failure = null;
      await tapVisible(tester, 'Restore purchases');

      expect(find.textContaining('No purchases to restore'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Start free trial'), findsNothing);
    });

    testWidgets('a pending purchase closes the paywall once approved', (
      tester,
    ) async {
      await openProfileAsFreeGuest(tester);
      await tapVisible(tester, 'GetWorkout Premium');
      store.failure = const PurchaseFailure(PurchaseFailureReason.pending);

      await tapVisible(tester, 'Start free trial');
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.textContaining('waiting for approval'), findsOneWidget);

      store
        ..failure = null
        ..approvePending();
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsNothing);
      expect(find.text('You have Premium.'), findsOneWidget);
    });

    testWidgets('the paywall closes at once for a subscriber', (tester) async {
      await openProfileAsFreeGuest(tester);
      unawaited(store.purchase(fakePlans.first));
      await tester.pumpAndSettle();
      expect(find.textContaining('Premium, renews'), findsOneWidget);

      unawaited(router.push(Routes.paywall));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsNothing);
      expect(find.text('You have Premium.'), findsOneWidget);
    });
  });

  group('strength', () {
    /// The strength pages and a workout's page, for a user whose squat set
    /// a record in workout `w1`.
    void registerStrength() {
      final strengthAuth = MockAuthRepository();
      when(strengthAuth.watchUser).thenAnswer((_) => Stream.value(guest));
      when(() => strengthAuth.currentUser).thenReturn(guest);
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final squat = ExerciseStats(
        records: {
          RecordKind.heaviestWeight: StatRecord(
            value: 100,
            date: yesterday,
            workoutId: 'w1',
          ),
        },
        history: [
          HistoryPoint(date: yesterday, workoutId: 'w1', bestE1rmKg: 112),
        ],
      );
      final workouts = MockWorkoutRepository();
      when(() => workouts.watchAllStats(any()))
          .thenAnswer((_) => Stream.value({'squat': squat}));
      when(() => workouts.watchStats(any(), any()))
          .thenAnswer((_) => Stream.value(squat));
      when(() => workouts.watchWorkout(any(), any()))
          .thenAnswer((_) => Stream.value(null));
      sl
        ..registerFactory(
          () => StrengthListCubit(
            watchAuthUser: WatchAuthUser(strengthAuth),
            watchAllStats: WatchAllExerciseStats(workouts),
            catalogue: catalogue,
          ),
        )
        ..registerFactoryParam<ExerciseStrengthCubit, String, WeightUnit>(
          (id, unit) => ExerciseStrengthCubit(
            exerciseId: id,
            watchAuthUser: WatchAuthUser(strengthAuth),
            watchStats: WatchExerciseStats(workouts),
            watchPremium: const WatchPremium(FixedPremium(false)),
            unit: unit,
          ),
        )
        ..registerFactoryParam<WorkoutDetailCubit, String, void>(
          (id, _) => WorkoutDetailCubit(
            id: id,
            getCurrentUser: GetCurrentUser(strengthAuth),
            watchAuthUser: WatchAuthUser(strengthAuth),
            watchWorkout: WatchStoredWorkout(workouts),
            saveChange: SaveWorkoutChange(workouts),
            changed: (_, _, {required deleted, required staleStats}) {},
          ),
        );
    }

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }

    testWidgets('Progress lists the exercise and opens its page', (
      tester,
    ) async {
      await startAsGuest(tester);
      registerStrength();
      await tapTab(tester, 'Progress');
      await tester.tap(find.text('Strength'));
      await tester.pumpAndSettle();
      expect(find.byType(StrengthListPage), findsOneWidget);

      await tester.tap(find.text('Back Squat'));
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseStrengthPage), findsOneWidget);
      expect(path(), Routes.strengthExercise('squat'));

      await back(tester);
      expect(find.byType(StrengthListPage), findsOneWidget);
    });

    testWidgets('records and progress opens above the exercise and leaves '
        'the Progress tab alone', (tester) async {
      await startAsGuest(tester);
      registerStrength();
      router.go(Routes.strength);
      await tester.pumpAndSettle();
      expect(find.byType(StrengthListPage), findsOneWidget);

      await tapTab(tester, 'Train');
      router.go(Routes.exercise('squat'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Records and progress'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ExerciseDetailPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Records and progress'));
      await tester.pumpAndSettle();

      // Pushed above the exercise, in the Train tab.
      expect(find.byType(ExerciseStrengthPage), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(path(), Routes.exercise('squat'));

      // A record opens the workout that set it, and back returns here.
      await tester.scrollUntilVisible(
        find.text('Heaviest weight'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ExerciseStrengthPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('Heaviest weight'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutDetailPage), findsOneWidget);
      await back(tester);
      expect(find.byType(ExerciseStrengthPage), findsOneWidget);

      await back(tester);
      expect(find.byType(ExerciseDetailPage), findsOneWidget);
      expect(path(), Routes.exercise('squat'));

      await tapTab(tester, 'Progress');
      expect(find.byType(StrengthListPage), findsOneWidget);
      expect(path(), Routes.strength);
    });
  });
}
