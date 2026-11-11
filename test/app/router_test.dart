import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_page.dart';
import 'package:get_workout/features/exercises/presentation/exercises_page.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/account/presentation/account_page.dart';
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
import 'package:get_workout/features/profile/presentation/profile_page.dart';
import 'package:get_workout/features/programs/presentation/programs_page.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/today/presentation/today_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockExerciseRepository extends Mock implements ExerciseRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

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

  /// Keeps the catalogue loading until a test feeds [exerciseFeed].
  var holdCatalogue = false;
  late GoRouter router;
  final onboarded = UserProfile(onboardingCompletedAt: DateTime(2026));

  /// What the user's profile stream emits first; null emits nothing until
  /// the test adds to [profileStream].
  UserProfile? storedProfile;
  late StreamController<UserProfile> profileStream;

  setUpAll(() {
    registerFallbackValue(const UserProfile());
    registerFallbackValue(<ProfileField>{});
  });

  setUp(() => storedProfile = onboarded);

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
    final settingsRepository = MockSettingsRepository();
    settings = SettingsCubit(
      watchAuthUser: WatchAuthUser(settingsAuth),
      watchSettings: WatchSettings(settingsRepository),
      updateSettings: UpdateSettings(settingsRepository),
      defaults: UserSettings.defaultsFor(null),
    );
    // The library runs on a fixed catalogue with no user data and a model
    // that fails to load (rendering it is the viewer package's business).
    final exercises = MockExerciseRepository();
    exerciseFeed = StreamController<List<Exercise>>();
    if (!holdCatalogue) exerciseFeed.add([_squat]);
    when(exercises.watchExercises).thenAnswer((_) => exerciseFeed.stream);
    final userLibrary = MockUserLibraryRepository();
    catalogue = ExerciseCatalogueCubit(
      watchAuthUser: WatchAuthUser(settingsAuth),
      watchExercises: WatchExercises(exercises),
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
    sl
      ..registerLazySingleton(
        () => LibraryCubit(
          watchAuthUser: WatchAuthUser(settingsAuth),
          catalogue: catalogue,
          favorites: favorites,
          equipment: equipment,
        ),
        dispose: (cubit) => cubit.close(),
      )
      ..registerFactoryParam<ExerciseDetailCubit, String, void>(
        (id, _) =>
            ExerciseDetailCubit(id, catalogue: catalogue, equipment: equipment),
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
      ..registerFactory(
        () => UpdateProfile(profiles, SaveOwnedEquipment(userLibrary)),
      );
    profile = ProfileCubit(
      watchAuthUser: WatchAuthUser(repository),
      watchProfile: WatchProfile(profiles),
    );
  }

  tearDown(() async {
    await auth.close();
    await settings.close();
    await profile.close();
    await sl.reset();
    await catalogue.close();
    await favorites.close();
    await equipment.close();
    await bodyModel.close();
    await exerciseFeed.close();
    holdCatalogue = false;
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: auth),
        BlocProvider.value(value: settings),
        BlocProvider.value(value: profile),
        BlocProvider.value(value: catalogue),
        BlocProvider.value(value: favorites),
        BlocProvider.value(value: equipment),
        BlocProvider.value(value: bodyModel),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router = buildRouter(auth, profile),
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

  testWidgets('a started session lands on Today with five tabs', (
    tester,
  ) async {
    await startAsGuest(tester);

    expect(find.byType(TodayPage), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });

  testWidgets('tabs switch and keep their own stack', (tester) async {
    await startAsGuest(tester);
    await openAccount(tester);
    expect(find.byType(AccountPage), findsOneWidget);

    await tapTab(tester, 'Programs');
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
    await tapTab(tester, 'Programs');

    router.go('/');
    await tester.pumpAndSettle();

    expect(find.byType(TodayPage), findsOneWidget);
  });

  testWidgets('an exercise opens its detail inside the Exercises tab', (
    tester,
  ) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Exercises');
    expect(find.byType(ExercisesPage), findsOneWidget);

    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back Squat'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.text('Back Squat'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('the Exercises tab remembers the list view and returns to it', (
    tester,
  ) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Exercises');
    await tester.tap(find.text('List'));
    await tester.pumpAndSettle();
    router.go(Routes.exercise('squat'));
    await tester.pumpAndSettle();

    await tapTab(tester, 'Exercises');

    expect(find.byType(ExerciseDetailPage), findsNothing);
    expect(find.text('1 exercise'), findsOneWidget);
  });

  testWidgets('an unknown exercise id shows not found', (tester) async {
    await startAsGuest(tester);

    router.go(Routes.exercise('retired_since'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.text('This exercise is no longer available.'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
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

    testWidgets('skipping completes onboarding and lands on Today', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);

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
}
