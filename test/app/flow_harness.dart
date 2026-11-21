import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_remote_config/forge_remote_config.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/account/domain/account_repository.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
import 'package:get_workout/features/account/domain/sync_repository.dart';
import 'package:get_workout/features/account/presentation/delete_account_cubit.dart';
import 'package:get_workout/features/account/presentation/sync_status_cubit.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/calculators/calculators_module.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/notifications/presentation/notifications_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/programs/data/no_completed_days.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_repository.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/catalogue_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/steps/presentation/health_access_cubit.dart';
import 'package:get_workout/features/subscription/domain/paywall_moment.dart';
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/presentation/premium_paywall_cubit.dart';
import 'package:get_workout/features/subscription/presentation/premium_trial_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart' show FixedPremium;
import 'answered_consent.dart';
import 'body_stand_in.dart';
import 'no_workout.dart';
import 'progress_stand_ins.dart';
import 'today_stand_ins.dart';
import '../fake_analytics.dart';

import 'package:get_workout/features/analytics/domain/analytics.dart';

import '../fake_body_model.dart';

class MockAuth extends Mock implements AuthRepository {}

class MockAccount extends Mock implements AccountRepository {}

class _LocalData extends Mock implements LocalAccountData {}

class _Telemetry extends Mock implements Telemetry {}

class _Settings extends Mock implements SettingsRepository {}

class MockProfiles extends Mock implements ProfileRepository {}

class _Body extends Mock implements BodyRepository {}

class _Exercises extends Mock implements ExerciseRepository {}

class _UserLibrary extends Mock implements UserLibraryRepository {}

class _CustomExercises extends Mock implements CustomExerciseRepository {}

class MockPrograms extends Mock implements ProgramRepository {}

class _Catalogue extends Mock implements CatalogueRepository {}

class _NotificationsStandIn extends MockCubit<NotificationsState>
    implements NotificationsCubit {}

class HealthStandIn extends MockCubit<StepsAccess?>
    implements HealthAccessCubit {}

class _Sync implements SyncRepository {
  _Sync(this._backedUp);

  final Stream<bool> _backedUp;

  @override
  Stream<bool> watchBackedUp() => _backedUp;
}

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

const guest = AuthUser(id: 'u1', isAnonymous: true);
const member = AuthUser(
  id: 'u1',
  email: 'a@b.co',
  signInMethods: {SignInMethod.email},
  emailVerified: true,
);

/// [member] before opening the verification link.
const unverifiedMember = AuthUser(
  id: 'u1',
  email: 'a@b.co',
  signInMethods: {SignInMethod.email},
);
final onboarded = UserProfile(onboardingCompletedAt: DateTime(2026));

/// Registers the fallback values the flow tests' mocks match on.
void registerFlowFallbacks() {
  registerFallbackValue(const Program(name: '', days: []));
  registerFallbackValue(const UserProfile());
  registerFallbackValue(<ProfileField>{});
  registerFallbackValue(<Equipment>{});
  registerFallbackValue(SocialProvider.google);
  registerFallbackValue(<String, Object>{});
}

/// The whole app on the real router and pages, its data behind fakes: a
/// mocked auth repository driven through [users], profiles that write
/// through to their stream like Firestore's cache, the fake store, and the
/// tabs the flows pass through as stand-ins. Create it in [setUp], call
/// [start] inside the test (so streams run in the test's fake zone) and
/// [dispose] in [tearDown].
class FlowApp {
  /// What the user's profile stream emits first; null emits nothing.
  UserProfile? storedProfile = onboarded;

  /// The ready-made programs.
  List<CatalogueProgram> readyMade = [];

  /// Step access as the onboarding health step finds it.
  StepsAccess healthAccess = StepsAccess.granted;

  /// Whether the device lets the app notify.
  bool notificationsAllowed = true;

  /// Whether this device's writes are on the server, for Account.
  final backedUp = StreamController<bool>.broadcast();
  final deletionUnderway = DeletionUnderway();

  late final MockAuth repository;
  late final MockAccount account;
  late final StreamController<AuthUser?> users;
  late final AuthCubit auth;
  late final SettingsCubit settings;
  late final MockProfiles profiles;
  late StreamController<UserProfile> profileStream;
  late final ProfileCubit profile;
  late final NotificationsCubit notifications;
  late final ExerciseCatalogueCubit catalogue;
  late final FavoritesCubit favorites;
  late final EquipmentCubit equipment;
  late final BodyModelCubit bodyModel;
  late final StreamController<List<Exercise>> exerciseFeed;
  late final FakePurchasesRepository store;
  late final FakeRemoteConfigRepository remoteConfig;
  late final EntitlementCubit entitlement;
  late final MockPrograms programs;

  /// The health access cubit the last page created.
  late HealthStandIn health;
  late GoRouter router;

  void start() {
    repository = MockAuth();
    users = StreamController<AuthUser?>.broadcast();
    when(() => repository.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.currentUser).thenReturn(guest);
    when(() => repository.sendEmailVerification())
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.verificationSentAt).thenReturn(null);
    // The verification page reloads quietly; tests that verify say so.
    when(() => repository.reloadUser())
        .thenAnswer((_) async => const Err(NetworkFailure()));
    auth = AuthCubit(
      watchAuthUser: WatchAuthUser(repository),
      signOut: SignOut(repository),
      deleteAccount: DeleteAccount(repository),
      signInAnonymously: SignInAnonymously(repository),
    );
    sl.registerFactory(
      () =>
          SyncStatusCubit(watchBackedUp: WatchBackedUp(_Sync(backedUp.stream))),
    );
    sl.registerFactory(
      () => AuthFormCubit(
        signInWithEmail: SignInWithEmail(repository),
        signUpWithEmail: SignUpWithEmail(repository),
        signInWithProvider: SignInWithProvider(repository),
        sendPasswordReset: SendPasswordReset(repository),
        getCurrentUser: GetCurrentUser(repository),
        signInAnonymously: SignInAnonymously(repository),
      ),
    );
    sl.registerFactory(
      () => EmailVerificationCubit(
        reloadUser: ReloadUser(repository),
        sendEmailVerification: SendEmailVerification(repository),
        changeEmail: ChangeEmail(repository),
        getVerificationSentAt: GetVerificationSentAt(repository),
        signOut: SignOut(repository),
      ),
    );
    account = MockAccount();
    final local = _LocalData();
    when(() => local.holdWrites(any())).thenAnswer((_) async {});
    when(() => local.releaseWrites(any())).thenAnswer((_) async {});
    when(() => local.clear(any())).thenAnswer((_) async => const Ok(null));
    final accountTelemetry = _Telemetry();
    when(() => accountTelemetry.forget(any()))
        .thenAnswer((_) async => const Ok(null));
    sl.registerFactory(
      () => DeleteAccountCubit(
        getCurrentUser: GetCurrentUser(repository),
        deleteAccount: DeleteUserAccount(
          account,
          local,
          accountTelemetry,
          fakeAnalytics(),
        ),
        reauthenticate: Reauthenticate(repository),
        reauthenticateWithProvider: ReauthenticateWithProvider(repository),
        reauthenticateWithAppleCode: ReauthenticateWithAppleCode(repository),
        underway: deletionUnderway,
        releaseWorkouts: (_) async {},
        resumeWorkouts: () async {},
      ),
    );
    sl.registerSingleton(fakeAnalytics());
    const CalculatorsModule().register(sl);
    // Settings stay at their defaults, and calculators start signed out, so
    // they ask for no known values.
    final signedOut = MockAuth();
    when(signedOut.watchUser).thenAnswer((_) => const Stream.empty());
    when(() => signedOut.currentUser).thenReturn(null);
    sl
      ..registerFactory(() => GetCurrentUser(signedOut))
      ..registerFactory(() => WatchProfile(MockProfiles()))
      ..registerFactory(() => WatchBodyEntries(_Body()));
    settings = SettingsCubit(
      watchAuthUser: WatchAuthUser(signedOut),
      watchSettings: WatchSettings(_Settings()),
      updateSettings: UpdateSettings(_Settings()),
      markTipSeen: MarkTipSeen(_Settings()),
      defaults: UserSettings.defaultsFor(null),
    );
    final exercises = _Exercises();
    exerciseFeed = StreamController<List<Exercise>>()..add([_squat]);
    when(exercises.watchExercises).thenAnswer((_) => exerciseFeed.stream);
    final userLibrary = _UserLibrary();
    when(() => userLibrary.saveEquipment(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    final customExercises = _CustomExercises();
    when(() => customExercises.rejectedWrites)
        .thenAnswer((_) => const Stream.empty());
    catalogue = ExerciseCatalogueCubit(
      watchAuthUser: WatchAuthUser(signedOut),
      watchExercises: WatchExercises(exercises),
      watchCustomExercises: WatchCustomExercises(customExercises),
      syncExercises: SyncExercises(exercises),
    );
    favorites = FavoritesCubit(
      watchAuthUser: WatchAuthUser(signedOut),
      watchFavorites: WatchFavorites(userLibrary),
      setFavorite: SetFavorite(userLibrary),
    );
    equipment = EquipmentCubit(
      watchAuthUser: WatchAuthUser(signedOut),
      watchEquipment: WatchOwnedEquipment(userLibrary),
      saveEquipment: SaveOwnedEquipment(userLibrary),
    );
    bodyModel = failingBodyModel();
    _registerPrograms(userLibrary);
    profiles = MockProfiles();
    when(() => profiles.watchProfile(any())).thenAnswer((_) {
      profileStream = StreamController<UserProfile>();
      if (storedProfile case final stored?) profileStream.add(stored);
      return profileStream.stream;
    });
    // Like Firestore's local cache: the write shows up in the stream at once.
    when(() => profiles.completeOnboarding(any(), any())).thenAnswer((call) {
      final answers = call.positionalArguments[1] as UserProfile;
      profileStream.add(
        storedProfile = UserProfile(
          goal: answers.goal,
          level: answers.level,
          daysPerWeek: answers.daysPerWeek,
          equipment: answers.equipment,
          onboardingCompletedAt: DateTime(2026),
        ),
      );
      return Future.value(const Ok(null));
    });
    sl.registerFactory(
      () => CompleteOnboarding(profiles, SaveOwnedEquipment(userLibrary)),
    );
    profile = ProfileCubit(
      watchAuthUser: WatchAuthUser(repository),
      watchProfile: WatchProfile(profiles),
      updateProfile: UpdateProfile(profiles, SaveOwnedEquipment(userLibrary)),
    );
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
      presentCustomerCenter: PresentCustomerCenter(store),
      // Past every expiry, so no expiry timer outlives a test.
      clock: () => DateTime(9999),
    );
    registerTodayStandIns();
    registerBodyListStandIn();
    registerProgressStandIns();
    remoteConfig = FakeRemoteConfigRepository(
      SubscriptionModule.remoteConfigDefaults,
    );
    final paywallTelemetry = _Telemetry();
    when(() => paywallTelemetry.logEvent(any(), any()))
        .thenAnswer((_) async {});
    notifications = _NotificationsStandIn();
    when(() => notifications.state)
        .thenReturn(NotificationsState(allowed: notificationsAllowed));
    sl.registerFactory<HealthAccessCubit>(() {
      health = HealthStandIn();
      when(() => health.state).thenReturn(healthAccess);
      when(health.load).thenAnswer((_) async {});
      when(health.allow).thenAnswer((_) async {});
      when(health.openSettings).thenAnswer((_) async {});
      return health;
    });
    sl.registerFactoryParam<PremiumPaywallCubit, PaywallMoment?, void>(
      (moment, _) => PremiumPaywallCubit(
        analytics: Analytics(paywallTelemetry),
        getOffering: GetPaywallOffering(store),
        purchasePlan: PurchasePlan(store),
        restorePurchases: RestorePurchases(store),
        getLayout: GetPaywallLayout(remoteConfig),
        isPremium: () => entitlement.isActive,
        moment: moment,
      ),
    );
    sl.registerFactory(
      () => PremiumTrialCubit(GetPremiumTrial(GetPaywallOffering(store))),
    );
  }

  /// The user has no programs of their own; the catalogue holds
  /// [readyMade], each a single day of squats.
  void _registerPrograms(_UserLibrary userLibrary) {
    final programAuth = MockAuth();
    when(programAuth.watchUser).thenAnswer((_) => Stream.value(guest));
    when(() => programAuth.currentUser).thenReturn(guest);
    programs = MockPrograms();
    when(() => programs.watchPrograms(any()))
        .thenAnswer((_) => Stream.value(const []));
    when(() => programs.watchActiveProgram(any()))
        .thenAnswer((_) => Stream.value(null));
    when(() => programs.rejectedWrites).thenAnswer((_) => const Stream.empty());
    when(() => programs.createProgram(any(), any()))
        .thenAnswer((_) async => const Ok('p1'));
    sl.registerSingleton(PremiumPrompt((_) async => false));
    sl.registerLazySingleton(
      () => ProgramListCubit(
        firstWeekday: DateTime.monday,
        watchAuthUser: WatchAuthUser(programAuth),
        watchPrograms: WatchPrograms(programs),
        watchActiveProgram: WatchActiveProgram(programs),
        watchCompletedDays: const WatchCompletedDays(NoCompletedDays()),
        watchRejectedWrites: WatchRejectedProgramWrites(programs),
        resolveMissedDay: ResolveMissedDay(programs),
        moveNextDay: MoveNextDay(programs),
        watchPremium: const WatchPremium(FixedPremium(false)),
      ),
      dispose: (cubit) => cubit.close(),
    );
    final catalogueLibrary = _UserLibrary();
    when(() => catalogueLibrary.watchEquipment(any()))
        .thenAnswer((_) => Stream.value(const {}));
    final catalogueEquipment = EquipmentCubit(
      watchAuthUser: WatchAuthUser(programAuth),
      watchEquipment: WatchOwnedEquipment(catalogueLibrary),
      saveEquipment: SaveOwnedEquipment(catalogueLibrary),
    );
    final readyMadePrograms = _Catalogue();
    when(readyMadePrograms.watchPrograms)
        .thenAnswer((_) => Stream.value(readyMade));
    when(() => readyMadePrograms.getDays(any())).thenAnswer(
      (_) async => const Ok([
        ProgramDay(
          items: [
            ProgramItem(
              exerciseId: 'squat',
              sets: 3,
              repMin: 8,
              repMax: 8,
              restS: 60,
            ),
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
          analytics: fakeAnalytics(),
          id,
          language: language,
          catalogue: sl(),
          list: sl(),
          exercises: catalogue,
          getDays: GetCatalogueDays(readyMadePrograms),
          saveProgram: SaveProgram(programs),
          startProgram: StartProgram(programs, const NoCompletedDays()),
          getCurrentUser: GetCurrentUser(programAuth),
        ),
      );
  }

  Future<void> dispose() async {
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
    await backedUp.close();
    deletionUnderway.dispose();
  }

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        RepositoryProvider.value(value: fakeAnalytics()),
        BlocProvider.value(value: auth),
        BlocProvider.value(value: settings),
        answeredConsent(),
        programList(),
        noWorkout(),
        BlocProvider<NotificationsCubit>.value(value: notifications),
        BlocProvider.value(value: profile),
        BlocProvider.value(value: catalogue),
        BlocProvider.value(value: favorites),
        BlocProvider.value(value: equipment),
        BlocProvider.value(value: bodyModel),
        BlocProvider.value(value: entitlement),
      ],
      child: MaterialApp.router(
        theme: ThemeData(
          extensions: AppPreset.shipped.lightTheme().extensions.values,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router = buildRouter(
          auth,
          profile,
          deletionUnderway: deletionUnderway,
        ),
      ),
    ),
  );

  /// Started and signed in as [user], settled on the first page.
  Future<void> startAs(WidgetTester tester, AuthUser user) async {
    start();
    when(() => repository.currentUser).thenReturn(user);
    await pump(tester);
    users.add(user);
    await tester.pumpAndSettle();
  }

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ForgeNavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps [text], scrolling it into view first.
  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  Future<void> tapBack(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
  }

  /// The path of the location in front.
  String path() => router.routerDelegate.currentConfiguration.uri.path;
}
