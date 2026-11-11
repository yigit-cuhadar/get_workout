import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
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
  late ExerciseCatalogueCubit catalogue;
  late FavoritesCubit favorites;
  late EquipmentCubit equipment;
  late BodyModelCubit bodyModel;
  late GoRouter router;

  // Created inside each test so stream events run in the test's fake zone.
  void setUpAuth() {
    repository = MockAuthRepository();
    users = StreamController<AuthUser?>();
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
    when(exercises.watchExercises).thenAnswer((_) => Stream.value([_squat]));
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
  }

  tearDown(() async {
    await auth.close();
    await settings.close();
    await sl.reset();
    await catalogue.close();
    await favorites.close();
    await equipment.close();
    await bodyModel.close();
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: auth),
        BlocProvider.value(value: settings),
        BlocProvider.value(value: catalogue),
        BlocProvider.value(value: favorites),
        BlocProvider.value(value: equipment),
        BlocProvider.value(value: bodyModel),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router = buildRouter(auth),
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
}
