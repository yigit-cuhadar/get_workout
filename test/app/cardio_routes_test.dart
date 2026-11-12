import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_session.dart';
import 'package:get_workout/features/cardio/domain/cardio_type.dart';
import 'package:get_workout/features/cardio/domain/cardio_usecases.dart';
import 'package:get_workout/features/cardio/presentation/cardio_form_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_form_page.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_cubit.dart';
import 'package:get_workout/features/cardio/presentation/cardio_list_page.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/progress/presentation/progress_page.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'no_workout.dart';
import 'today_stand_ins.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

class MockCardioRepository extends Mock implements CardioRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockUserLibraryRepository extends Mock implements UserLibraryRepository {}

void main() {
  const guest = AuthUser(id: 'u1', isAnonymous: true);
  final run = CardioSession(
    id: 'r1',
    type: CardioType.outdoorRun,
    date: DateTime(2026, 11, 10, 7),
    duration: const Duration(minutes: 30),
    distanceKm: 5,
  );

  late StreamController<AuthUser?> users;
  late StreamController<List<CardioSession>> sessions;
  late AuthCubit auth;
  late SettingsCubit settings;
  late ProfileCubit profile;
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
    final settingsRepository = MockSettingsRepository();
    settings = SettingsCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchSettings: WatchSettings(settingsRepository),
      updateSettings: UpdateSettings(settingsRepository),
      defaults: UserSettings.defaultsFor(null),
    );
    // Onboarding is covered by the router tests; this user has done it.
    final profiles = MockProfileRepository();
    when(() => profiles.watchProfile('u1')).thenAnswer(
      (_) => Stream.value(UserProfile(onboardingCompletedAt: DateTime(2026))),
    );
    profile = ProfileCubit(
      watchAuthUser: WatchAuthUser(sessionAuth),
      watchProfile: WatchProfile(profiles),
      updateProfile: UpdateProfile(
        profiles,
        SaveOwnedEquipment(MockUserLibraryRepository()),
      ),
    );
    final cardio = MockCardioRepository();
    sessions = StreamController<List<CardioSession>>();
    when(() => cardio.watchSessions('u1')).thenAnswer((_) => sessions.stream);
    when(() => cardio.rejectedWrites).thenAnswer((_) => const Stream.empty());
    sl
      ..registerLazySingleton(
        () => CardioListCubit(
          watchAuthUser: WatchAuthUser(sessionAuth),
          watchSessions: WatchCardioSessions(cardio),
          watchRejectedWrites: WatchRejectedCardioWrites(cardio),
        ),
      )
      ..registerFactoryParam<CardioFormCubit, CardioSession?, DistanceUnit>(
        (session, unit) => CardioFormCubit(
          saveSession: SaveCardioSession(cardio),
          deleteSession: DeleteCardioSession(cardio),
          getCurrentUser: GetCurrentUser(sessionAuth),
          watchAuthUser: WatchAuthUser(sessionAuth),
          unit: unit,
          initial: session,
        ),
      );
    registerTodayStandIns();

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: auth),
          BlocProvider.value(value: settings),
          programList(),
          unknownPremium(),
          noWorkout(),
          noWorkout(),
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
    await settings.close();
    await profile.close();
    await sl.reset();
  });

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder tab(String label) => find.descendant(
    of: find.byType(NavigationBar),
    matching: find.text(label),
  );

  /// The controller buffers [list] until the list subscribes, so nothing is
  /// left loading (a spinner never settles).
  Future<void> openCardio(
    WidgetTester tester, [
    List<CardioSession> list = const [],
  ]) async {
    sessions.add(list);
    await tap(tester, tab('Progress'));
    expect(find.byType(ProgressPage), findsOneWidget);
    await tap(tester, find.text('Cardio'));
  }

  testWidgets('the Progress tab opens cardio inside its branch', (
    tester,
  ) async {
    await start(tester);
    await openCardio(tester);

    expect(find.byType(CardioListPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(router.routerDelegate.currentConfiguration.uri.path, Routes.cardio);
  });

  testWidgets('the empty list offers to log, and the form opens', (
    tester,
  ) async {
    await start(tester);
    await openCardio(tester);

    expect(find.text('No cardio logged yet'), findsOneWidget);
    await tap(tester, find.text('Log cardio'));

    expect(find.byType(CardioNewPage), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.cardioNew,
    );
  });

  testWidgets('a session opens its edit form', (tester) async {
    await start(tester);
    await openCardio(tester, [run]);

    await tap(tester, find.text('Outdoor run'));

    expect(find.byType(CardioSessionPage), findsOneWidget);
    expect(find.text('Edit cardio'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      Routes.cardioSession('r1'),
    );
  });

  testWidgets('back from the form returns to the list', (tester) async {
    await start(tester);
    await openCardio(tester, [run]);
    await tap(tester, find.text('Log cardio'));

    await tap(tester, find.byType(BackButton));

    expect(find.byType(CardioListPage), findsOneWidget);
    expect(find.byType(CardioNewPage), findsNothing);
  });

  testWidgets('a link to an unknown session says it is gone', (tester) async {
    await start(tester);
    sessions.add([run]);
    router.go(Routes.cardioSession('nope'));
    await tester.pumpAndSettle();

    expect(find.text('This session no longer exists'), findsOneWidget);
  });

  testWidgets('tapping the open Progress tab returns to its first page', (
    tester,
  ) async {
    await start(tester);
    await openCardio(tester);

    await tap(tester, tab('Progress'));

    expect(find.byType(ProgressPage), findsOneWidget);
    expect(find.byType(CardioListPage), findsNothing);
  });
}
