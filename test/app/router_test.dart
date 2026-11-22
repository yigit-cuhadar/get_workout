import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
import 'package:get_workout/features/account/domain/sync_repository.dart';
import 'package:get_workout/features/account/presentation/sync_status_cubit.dart';
import 'package:get_workout/features/body/presentation/weight_form_cubit.dart';
import 'package:get_workout/features/body/presentation/weight_sheet.dart';
import 'package:get_workout/features/progress/domain/progress_usecases.dart';
import 'package:get_workout/features/progress/presentation/progress_page.dart';
import 'package:get_workout/features/progress/presentation/progress_strength_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:forge_remote_config/forge_remote_config.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/core/widgets/onboarding_question.dart';
import 'package:get_workout/app/router.dart';
import 'package:get_workout/app/theme.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_queries.dart';
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
import 'package:get_workout/features/exercises/presentation/exercise_notes_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_detail_page.dart';
import 'package:get_workout/features/exercises/presentation/exercises_page.dart';
import 'package:get_workout/features/exercises/presentation/widgets/library_list_view.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_page.dart';
import 'package:get_workout/features/exercises/presentation/widgets/body_view.dart';
import 'package:get_workout/features/account/presentation/account_page.dart';
import 'package:get_workout/features/account/domain/consent_repository.dart';
import 'package:get_workout/features/account/presentation/consent_cubit.dart';
import 'package:get_workout/features/account/presentation/delete_account_cubit.dart';
import 'package:get_workout/features/body/domain/body_repository.dart';
import 'package:get_workout/features/body/domain/body_usecases.dart';
import 'package:get_workout/features/body/presentation/body_entry_page.dart';
import 'package:get_workout/features/body/presentation/body_page.dart';
import 'package:get_workout/features/body/presentation/measurement_summary_cubit.dart';
import 'package:get_workout/features/calculators/calculators_module.dart';
import 'package:get_workout/features/calculators/presentation/body_fat_page.dart';
import 'package:get_workout/features/calculators/presentation/body_indices_page.dart';
import 'package:get_workout/features/calculators/presentation/calculators_page.dart';
import 'package:get_workout/features/calculators/presentation/calories_page.dart';
import 'package:get_workout/features/calculators/presentation/macros_page.dart';
import 'package:get_workout/features/calculators/presentation/one_rep_max_page.dart';
import 'package:get_workout/features/calculators/presentation/plates_page.dart';
import 'package:get_workout/features/notifications/presentation/notifications_cubit.dart';
import 'package:get_workout/features/steps/domain/steps.dart';
import 'package:get_workout/features/steps/presentation/health_access_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_repository.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/onboarding_page.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/profile/presentation/profile_details_page.dart';
import 'package:get_workout/features/profile/presentation/profile_page.dart';
import 'package:get_workout/features/profile/presentation/profile_questions.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_repository.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
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
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/domain/paywall_moment.dart';
import 'package:get_workout/features/subscription/presentation/paywall_page.dart';
import 'package:get_workout/features/subscription/presentation/premium_paywall_cubit.dart';
import 'package:get_workout/features/subscription/presentation/premium_trial_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_cubit.dart';
import 'package:get_workout/features/strength/presentation/exercise_strength_page.dart';
import 'package:get_workout/features/strength/presentation/strength_list_cubit.dart';
import 'package:get_workout/features/strength/presentation/strength_list_page.dart';
import 'package:get_workout/features/today/presentation/today_page.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_editing.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:get_workout/features/workout/presentation/workout_detail_cubit.dart';
import 'package:get_workout/features/workout/presentation/workout_detail_page.dart';
import 'package:get_workout/features/workout/presentation/workout_edit_cubit.dart';
import 'package:get_workout/features/workout/presentation/workout_edit_page.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/programs/fixtures.dart' show FixedPremium, card;
import 'answered_consent.dart';
import 'body_stand_in.dart';
import 'no_workout.dart';
import 'progress_stand_ins.dart';
import 'today_stand_ins.dart';
import '../fake_analytics.dart';

import 'package:get_workout/features/analytics/domain/analytics.dart';

import '../fake_body_model.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class _NotificationsStandIn extends MockCubit<NotificationsState>
    implements NotificationsCubit {}

class _FakeActiveProgram extends Fake implements ActiveProgram {}

class _HealthAccessStandIn extends MockCubit<StepsAccess?>
    implements HealthAccessCubit {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

class MockProfileRepository extends Mock implements ProfileRepository {}

class MockConsentRepository extends Mock implements ConsentRepository {}

class MockTelemetry extends Mock implements Telemetry {}

class MockBodyRepository extends Mock implements BodyRepository {}

class _SummaryStandIn extends MockCubit<MeasurementSummaryState>
    implements MeasurementSummaryCubit {}

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

/// The question an [OnboardingQuestion] shows, from 1.
int questionOnScreen(WidgetTester tester) =>
    tester.widget<StepProgress>(find.byType(StepProgress)).current;

void main() {
  const guest = AuthUser(id: 'u1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  late MockAuthRepository repository;
  late StreamController<AuthUser?> users;
  late AuthCubit auth;
  late SettingsCubit settings;
  late MockProfileRepository profiles;
  late NotificationsCubit notifications;
  late ProfileCubit profile;
  late ExerciseCatalogueCubit catalogue;
  late FavoritesCubit favorites;
  late EquipmentCubit equipment;
  late BodyModelCubit bodyModel;
  late StreamController<List<Exercise>> exerciseFeed;
  late FakePurchasesRepository store;
  late FakeRemoteConfigRepository remoteConfig;

  /// Receives the paywall's events.
  late MockTelemetry paywallTelemetry;
  late EntitlementCubit entitlement;
  late MockProgramRepository programs;

  /// Keeps the catalogue loading until a test feeds [exerciseFeed].
  var holdCatalogue = false;
  late GoRouter router;
  final onboarded = UserProfile(onboardingCompletedAt: DateTime(2026));

  /// Every choice answered, so onboarding goes through on Next alone; the
  /// number questions answer themselves.
  const choicesAnswered = UserProfile(
    goal: Goal.loseFat,
    level: Level.beginner,
    daysPerWeek: 3,
    equipment: {},
    sex: Sex.female,
  );

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
    registerFallbackValue(<String, Object>{});
  });

  late DeletionUnderway deletionUnderway;

  /// A real consent cubit for the no-consent-page tests; otherwise every
  /// user has answered.
  ConsentCubit? consent;

  /// Step access as the onboarding health step finds it.
  late StepsAccess healthAccess;

  /// The health access cubit the last page created.
  late _HealthAccessStandIn health;

  setUp(() {
    storedProfile = onboarded;
    deletionUnderway = DeletionUnderway();
    consent = null;
    healthAccess = StepsAccess.granted;
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
      () => SyncStatusCubit(watchBackedUp: WatchBackedUp(_BackedUp())),
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
    when(() => userLibrary.watchExerciseNotes(any()))
        .thenAnswer((_) => Stream.value(const {}));
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
    bodyModel = failingBodyModel();
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
    sl.registerSingleton(PremiumPrompt((_) async => false));
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
          analytics: fakeAnalytics(),
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
          analytics: fakeAnalytics(),
          watchAuthUser: WatchAuthUser(settingsAuth),
          catalogue: catalogue,
          favorites: favorites,
          equipment: equipment,
        ),
        instanceName: ProgramsModule.pickerLibrary,
      );
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
      )
      ..registerLazySingleton(
        () => LibraryCubit(
          analytics: fakeAnalytics(),
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
      ..registerLazySingleton(
        () => ExerciseNotesCubit(
          watchAuthUser: WatchAuthUser(settingsAuth),
          watchExerciseNotes: WatchExerciseNotes(userLibrary),
          setExerciseNote: SetExerciseNote(userLibrary),
        ),
        dispose: (cubit) => cubit.close(),
      )
      ..registerFactoryParam<ExerciseDetailCubit, String, void>(
        (id, _) => ExerciseDetailCubit(
          analytics: fakeAnalytics(),
          from: ExerciseViewSource.library,
          id,
          catalogue: catalogue,
          equipment: equipment,
          getCurrentUser: GetCurrentUser(settingsAuth),
          deleteCustomExercise: DeleteCustomExercise(customExercises),
        ),
      )
      ..registerFactoryParam<CustomExerciseFormCubit, CustomExercise?, void>(
        (exercise, _) => CustomExerciseFormCubit(
          analytics: fakeAnalytics(),
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
    paywallTelemetry = MockTelemetry();
    when(() => paywallTelemetry.logEvent(any(), any()))
        .thenAnswer((_) async {});
    notifications = _NotificationsStandIn();
    when(() => notifications.state)
        .thenReturn(const NotificationsState(allowed: true));
    sl.registerFactory<HealthAccessCubit>(() {
      health = _HealthAccessStandIn();
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
    sl.registerSingleton(fakeAnalytics());
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
        RepositoryProvider.value(value: fakeAnalytics()),
        BlocProvider.value(value: auth),
        BlocProvider.value(value: settings),
        if (consent case final consent?)
          BlocProvider.value(value: consent)
        else
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

  Future<void> startAsGuest(WidgetTester tester) async {
    setUpAuth();
    await pumpApp(tester);
    users.add(guest);
    await tester.pumpAndSettle();
  }

  /// From the welcome through every question, each already answered, and
  /// past the reminder step.
  Future<void> finishOnboarding(WidgetTester tester) async {
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    for (var i = 0; i < ProfileField.values.length; i++) {
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    if (find.text('Remind you on training days?').evaluate().isNotEmpty) {
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    }
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

  /// The Exercises tab.
  Future<void> openExercises(WidgetTester tester) =>
      tapTab(tester, 'Exercises');

  /// The exercise list, through the Exercises tab's search box.
  Future<void> openList(WidgetTester tester) async {
    await openExercises(tester);
    await tester.tap(find.byType(ForgeSearchField));
    await tester.pumpAndSettle();
  }

  /// The location of the page in front.
  String front() =>
      openLocations(router.routerDelegate.currentConfiguration).last;

  bool searchFocused(WidgetTester tester) => tester
      .state<EditableTextState>(find.byType(EditableText, skipOffstage: false))
      .widget
      .focusNode
      .hasFocus;

  String path() => router.routerDelegate.currentConfiguration.uri.path;

  int selectedTab(WidgetTester tester) => tester
      .widget<ForgeNavigationBar>(find.byType(ForgeNavigationBar))
      .selectedIndex;

  /// Account; a guest's Profile header opens the guest account sheet.
  Future<void> openAccount(WidgetTester tester) async {
    await tapTab(tester, 'Profile');
    router.go(Routes.account);
    await tester.pumpAndSettle();
  }

  Future<void> openSignUpAsGuest(WidgetTester tester) async {
    await startAsGuest(tester);
    await openAccount(tester);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'a@b.co');
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

  testWidgets("a guest's Profile header opens the guest account sheet", (
    tester,
  ) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Profile');

    await tester.tap(find.text('Create an account to keep your workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Keep your workouts safe'), findsOneWidget);

    // Email links the guest through the create-account form.
    await tester.tap(find.text('Use email instead'));
    await tester.pumpAndSettle();
    expect(find.text('Keep your workouts safe'), findsNothing);
    final page = tester.widget<AuthPage>(find.byType(AuthPage));
    expect(page.initialSignUp, isTrue);
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
    expect(find.byType(ForgeNavigationBar), findsOneWidget);
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
    expect(
      tester
          .widget<ForgeNavigationBar>(find.byType(ForgeNavigationBar))
          .destinations,
      hasLength(5),
    );
    for (final label in [
      'Today',
      'Programs',
      'Exercises',
      'Progress',
      'Profile',
    ]) {
      expect(
        find.descendant(
          of: find.byType(ForgeNavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets('five tabs fit a 375 point wide phone', (tester) async {
    tester.view
      ..physicalSize = const Size(375, 812)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await startAsGuest(tester);

    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<ForgeNavigationBar>(find.byType(ForgeNavigationBar))
          .destinations,
      hasLength(5),
    );
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

    expect(find.text('Guest'), findsNothing);
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
    await openList(tester);

    await tester.tap(find.text('Back Squat'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.text('Back Squat'), findsOneWidget);
    expect(find.byType(ForgeNavigationBar), findsOneWidget);
    expect(selectedTab(tester), 2);
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

    testWidgets('the search box opens it inside the Exercises tab, '
        'searching; back returns to its first page', (tester) async {
      await startAsGuest(tester);
      await openExercises(tester);
      expect(find.byTooltip('New custom exercise'), findsNothing);
      // The pill flies between the two fields.
      ForgeSearchField field() =>
          tester.widget<ForgeSearchField>(find.byType(ForgeSearchField));
      expect(field().heroTag, librarySearchHeroTag);

      await tester.tap(find.byType(ForgeSearchField));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(field().heroTag, librarySearchHeroTag);
      expect(front(), Routes.exerciseList);
      expect(selectedTab(tester), 2);
      // The field is focused once the page is in, after the last frame.
      await tester.pump();
      expect(searchFocused(tester), isTrue);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(path(), Routes.exercises);
    });

    testWidgets('opens on an empty search, keeping the filters', (
      tester,
    ) async {
      await startAsGuest(tester);
      await openList(tester);
      await tester.enterText(find.byType(TextField), 'squat');
      sl<LibraryCubit>().setOnlyFavorites(true);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ForgeSearchField));
      await tester.pumpAndSettle();
      expect(library().query, '');
      expect(find.widgetWithText(TextField, 'squat'), findsNothing);
      expect(library().filter.onlyFavorites, isTrue);
    });

    testWidgets('a muscle opens it filtered, in main and also-works '
        'sections, without the keyboard', (tester) async {
      await startWithSplitSquat(tester);

      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();

      expect(front(), Routes.exerciseList);
      expect(selectedTab(tester), 2);
      expect(searchFocused(tester), isFalse);
      expect(library().filter.muscles, {Muscle.quads});
      expect(ids(library().muscleExercises!.main), ['squat']);
      expect(ids(library().muscleExercises!.alsoWorks), ['split_squat']);
      expect(find.text('Main · 1'), findsOneWidget);
      expect(find.text('Also works · 1'), findsOneWidget);
      expect(find.text('Back Squat'), findsOneWidget);
      expect(find.text('Split Squat'), findsNothing);

      await tester.tap(find.text('Also works · 1'));
      await tester.pumpAndSettle();
      expect(find.text('Back Squat'), findsNothing);
      expect(find.text('Split Squat'), findsOneWidget);

      // The muscle's chip.
      await tester.tap(find.widgetWithText(ForgeChip, 'Quads'));
      await tester.pumpAndSettle();

      expect(library().filter.muscles, isEmpty);
      expect(find.text('Main · 1'), findsNothing);
      expect(find.text('Back Squat'), findsOneWidget);
      expect(find.text('Split Squat'), findsOneWidget);
    });

    testWidgets('a muscle visit clears the search and takes its muscle '
        'along when it ends, so the box opens without it', (tester) async {
      await startAsGuest(tester);
      await openList(tester);
      await tester.enterText(find.byType(TextField), 'bench');
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();
      expect(library().query, '');
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      expect(library().filter.muscles, isEmpty);
      expect(
        find.descendant(
          of: find.byType(ForgeSearchField),
          matching: find.text('bench'),
        ),
        findsNothing,
      );
      await tester.tap(find.byType(ForgeSearchField));
      await tester.pumpAndSettle();
      expect(library().filter.muscles, isEmpty);
      expect(find.textContaining('Main ·'), findsNothing);
    });

    testWidgets('a muscle filter the user changed outlives the visit', (
      tester,
    ) async {
      await startWithSplitSquat(tester);
      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();

      sl<LibraryCubit>().toggleMuscle(Muscle.glute);
      await tester.pumpAndSettle();
      expect(find.textContaining('Main ·'), findsNothing);
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();

      expect(library().filter.muscles, {Muscle.quads, Muscle.glute});
    });

    testWidgets('the count and the sort sit on one line; the sort is a menu', (
      tester,
    ) async {
      await startWithSplitSquat(tester);
      await tester.tap(find.byType(ForgeSearchField));
      await tester.pumpAndSettle();

      expect(find.text('2 exercises'), findsOneWidget);
      await tester.tap(find.text('Most popular'));
      await tester.pumpAndSettle();
      expect(find.byType(ForgeMenu), findsOneWidget);
      await tester.tap(find.text('A–Z'));
      await tester.pumpAndSettle();

      expect(library().sort, ExerciseSort.alphabetical);
      expect(find.text('A–Z'), findsOneWidget);
    });

    testWidgets('the filter button counts the filters on', (tester) async {
      await startAsGuest(tester);
      await openList(tester);
      sl<LibraryCubit>()
        ..setOnlyFavorites(true)
        ..toggleMuscle(Muscle.quads);
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<ForgeSearchField>(find.byType(ForgeSearchField))
            .activeFilters,
        2,
      );
      expect(find.widgetWithText(ForgeChip, 'Quads'), findsOneWidget);
    });

    testWidgets('one muscle picked by hand gives no sections', (tester) async {
      await startWithSplitSquat(tester);
      await tester.tap(find.byType(ForgeSearchField));
      await tester.pumpAndSettle();

      sl<LibraryCubit>().toggleMuscle(Muscle.quads);
      await tester.pumpAndSettle();

      expect(library().muscle, Muscle.quads);
      expect(find.textContaining('Main ·'), findsNothing);
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
      expect(find.text('Main · 1'), findsOneWidget);

      router.go(Routes.exerciseList);
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
      expect(library().filter.muscles, isEmpty);
      expect(find.textContaining('Main ·'), findsNothing);
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
      expect(selectedTab(tester), 2);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ExercisesPage), findsOneWidget);
    });

    testWidgets('selecting Exercises again ends a muscle visit', (
      tester,
    ) async {
      await startAsGuest(tester);
      await openExercises(tester);
      unawaited(router.push(Routes.exerciseListOf(Muscle.quads)));
      await tester.pumpAndSettle();

      await tapTab(tester, 'Exercises');

      expect(find.byType(LibraryPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(library().filter.muscles, isEmpty);
    });

    testWidgets('selecting Exercises again returns to its first page', (
      tester,
    ) async {
      await startAsGuest(tester);
      await openList(tester);
      await tester.tap(find.text('Back Squat'));
      await tester.pumpAndSettle();

      await tapTab(tester, 'Exercises');

      expect(find.byType(ExerciseDetailPage), findsNothing);
      expect(find.byType(LibraryPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(path(), Routes.exercises);
    });

    testWidgets('its + opens a new custom exercise inside the tab, whose '
        'changes are asked about on back', (tester) async {
      await startAsGuest(tester);
      await openList(tester);

      await tester.tap(find.bySemanticsLabel('New custom exercise'));
      await tester.pumpAndSettle();
      expect(find.byType(CustomExerciseNewPage), findsOneWidget);
      expect(front(), Routes.customExerciseNew);
      expect(find.byType(ForgeNavigationBar), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(ForgeTextField, 'Name'),
        'Sled',
      );
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomExerciseNewPage), findsNothing);
      expect(find.byType(LibraryPage), findsOneWidget);
    });
  });

  group('exercise list without a match', () {
    testWidgets('a search matching nothing offers to create it, '
        'named after the search', (tester) async {
      await startAsGuest(tester);
      await openList(tester);
      await tester.enterText(find.byType(TextField), 'benchh');
      await tester.pumpAndSettle();

      expect(find.text('No exercises match "benchh"'), findsOneWidget);
      expect(find.text('No exercises'), findsNothing);
      await tester.tap(find.text('Create custom exercise'));
      await tester.pumpAndSettle();

      expect(find.byType(CustomExerciseNewPage), findsOneWidget);
      expect(front(), Routes.customExerciseNew);
      expect(find.widgetWithText(TextField, 'benchh'), findsOneWidget);

      // The name came from the search, so leaving asks nothing.
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryPage), findsOneWidget);
    });

    testWidgets('with a filter on it offers Clear all, and with a search '
        'also to create it', (tester) async {
      await startAsGuest(tester);
      await openList(tester);
      sl<LibraryCubit>().setOnlyFavorites(true);
      await tester.pumpAndSettle();

      expect(find.text('No exercises match'), findsOneWidget);
      expect(
        find.text('Clear a filter or turn off Only my equipment.'),
        findsOneWidget,
      );
      expect(find.text('Create custom exercise'), findsNothing);

      await tester.enterText(find.byType(TextField), 'benchh');
      await tester.pumpAndSettle();
      expect(find.text('Create custom exercise'), findsOneWidget);

      // The empty card's, under the chips' own.
      await tester.tap(find.widgetWithText(ForgeButton, 'Clear all').last);
      await tester.pumpAndSettle();
      expect(sl<LibraryCubit>().state.filter.isEmpty, isTrue);
      expect(find.text('No exercises match "benchh"'), findsOneWidget);
    });
  });

  group('Programs and Exercises', () {
    testWidgets('each tab opens on its first page at its own location', (
      tester,
    ) async {
      await startAsGuest(tester);

      await tapTab(tester, 'Programs');
      expect(find.byType(ProgramsPage), findsOneWidget);
      expect(find.byType(ExercisesPage), findsNothing);
      expect(selectedTab(tester), 1);
      expect(path(), Routes.programs);

      await tapTab(tester, 'Exercises');
      expect(find.byType(ExercisesPage), findsOneWidget);
      expect(find.byType(ProgramsPage), findsNothing);
      expect(selectedTab(tester), 2);
      expect(path(), Routes.exercises);

      await tapTab(tester, 'Programs');
      expect(find.byType(ProgramsPage), findsOneWidget);
      expect(path(), Routes.programs);
    });

    testWidgets('each location lands on its tab', (tester) async {
      await startAsGuest(tester);

      router.go(Routes.exercises);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 2);
      expect(find.byType(ExercisesPage), findsOneWidget);

      router.go(Routes.today);
      await tester.pumpAndSettle();
      router.go(Routes.programs);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      expect(find.byType(ProgramsPage), findsOneWidget);
    });

    testWidgets('the screen in front is named by its route, a tab switch '
        'and a pushed page included', (tester) async {
      await startAsGuest(tester);
      String? screen() =>
          screenInFront(router.routerDelegate.currentConfiguration)?.name;

      expect(screen(), 'today');
      await tapTab(tester, 'Exercises');
      expect(screen(), 'exercises');
      unawaited(router.push(Routes.exercise('squat')));
      await tester.pumpAndSettle();
      expect(screen(), 'exercise_detail');
      await tapTab(tester, 'Programs');
      expect(screen(), 'programs');
      await tapTab(tester, 'Exercises');
      expect(screen(), 'exercise_detail');
      router.go(Routes.catalogue);
      await tester.pumpAndSettle();
      expect(screen(), 'catalogue');
    });

    testWidgets('deep locations open inside their tab', (tester) async {
      await startAsGuest(tester);
      final pages = {
        Routes.exercise('squat'): (ExerciseDetailPage, 2),
        Routes.exerciseList: (LibraryPage, 2),
        Routes.customExerciseNew: (CustomExerciseNewPage, 2),
        Routes.exerciseProgramNew: (ProgramBuilderPage, 2),
        Routes.catalogue: (CataloguePage, 1),
        Routes.programNew: (ProgramBuilderPage, 1),
      };

      for (final MapEntry(key: location, value: (page, tab)) in pages.entries) {
        router.go(Routes.today);
        await tester.pumpAndSettle();
        router.go(location);
        await tester.pumpAndSettle();
        expect(find.byType(page), findsOneWidget, reason: location);
        expect(selectedTab(tester), tab, reason: location);
      }
    });

    testWidgets('switching tabs keeps both first pages', (tester) async {
      await startAsGuest(tester);
      await openExercises(tester);
      Element element(Type type) =>
          tester.element(find.byType(type, skipOffstage: false));
      final exercises = element(ExercisesPage);

      await tapTab(tester, 'Programs');
      final programs = element(ProgramsPage);
      // Kept, only out of sight.
      expect(element(ExercisesPage), same(exercises));
      expect(find.byType(ExercisesPage), findsNothing);

      router.go(Routes.exercises);
      await tester.pumpAndSettle();
      expect(element(ExercisesPage), same(exercises));
      expect(element(ProgramsPage), same(programs));
      expect(find.byType(ExercisesPage), findsOneWidget);
    });

    testWidgets('each tab restores its own stack', (tester) async {
      await startAsGuest(tester);
      await openList(tester);

      await tapTab(tester, 'Programs');
      expect(find.byType(ProgramsPage), findsOneWidget);
      await tapTab(tester, 'Today');
      await tapTab(tester, 'Exercises');

      expect(find.byType(LibraryPage), findsOneWidget);
      expect(front(), Routes.exerciseList);

      await tapTab(tester, 'Programs');
      expect(find.byType(ProgramsPage), findsOneWidget);
      expect(path(), Routes.programs);
    });

    testWidgets('a tab is built only once it shows', (tester) async {
      await startAsGuest(tester);
      await tapTab(tester, 'Programs');

      expect(find.byType(ExercisesPage, skipOffstage: false), findsNothing);
    });

    testWidgets("a link into one tab leaves the other one's pages", (
      tester,
    ) async {
      await startAsGuest(tester);
      router.go(Routes.exercise('squat'));
      await tester.pumpAndSettle();

      router.go(Routes.programs);
      await tester.pumpAndSettle();
      expect(find.byType(ExerciseDetailPage), findsNothing);
      expect(find.byType(ProgramsPage), findsOneWidget);

      await tapTab(tester, 'Exercises');
      expect(find.byType(ExerciseDetailPage), findsOneWidget);
      expect(path(), Routes.exercise('squat'));
    });

    test('the builder pushed from a page returns in its own tab', () {
      expect(
        returningProgramNew(Routes.catalogueExercise('c1', 'squat')),
        Routes.programNewReturning,
      );
      expect(
        returningProgramNew(Routes.exercise('squat')),
        Routes.exerciseProgramNew,
      );
      expect(returningProgramNew(Routes.workoutExercise('squat')), isNull);
      expect(returningProgramNew(Routes.calendarExercise('squat')), isNull);
    });
  });

  // From an exercise in either tab the builder opens above it, in that tab,
  // with its own picker, and returns to it.
  for (final (:tab, :name, :exercise, :builder, :picker) in [
    (
      tab: 2,
      name: 'Exercises',
      exercise: Routes.exercise('squat'),
      builder: Routes.exerciseProgramNew,
      picker: '${Routes.exerciseProgramNew}/pick',
    ),
    (
      tab: 1,
      name: 'Programs',
      exercise: Routes.catalogueExercise('c1', 'squat'),
      builder: Routes.programNew,
      picker: '${Routes.programs}/pick',
    ),
  ]) {
    group('Add to program without programs, in $name', () {
      Future<void> createProgram(WidgetTester tester) async {
        await startAsGuest(tester);
        router.go(exercise);
        await tester.pumpAndSettle();
        await tester.tap(find.bySemanticsLabel('Exercise options'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add to program'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create program'));
        await tester.pumpAndSettle();
        expect(find.byType(ProgramBuilderPage), findsOneWidget);
        expect(front(), builder);
        expect(selectedTab(tester), tab);
      }

      void expectBackOnTheExercise(WidgetTester tester) {
        expect(find.byType(ProgramBuilderPage), findsNothing);
        expect(find.byType(ExerciseDetailPage), findsOneWidget);
        expect(selectedTab(tester), tab);
        expect(path(), exercise);
      }

      testWidgets('leaving the builder returns to the exercise', (
        tester,
      ) async {
        await createProgram(tester);

        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();

        expectBackOnTheExercise(tester);
      });

      testWidgets('saving the program returns to the exercise', (tester) async {
        await createProgram(tester);
        await tester.enterText(
          find.widgetWithText(ForgeTextField, 'Program name'),
          'Push',
        );
        await tester.tap(find.text('Add exercises'));
        await tester.pumpAndSettle();
        // The picker opens over the whole app, tab bar too.
        expect(front(), picker);
        expect(find.byType(ForgeNavigationBar), findsNothing);
        await tester.tap(find.text('Back Squat'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add 1 exercise'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        verify(() => programs.createProgram('u1', any())).called(1);
        expectBackOnTheExercise(tester);
      });

      testWidgets('leaving with changes asks once, then returns', (
        tester,
      ) async {
        await createProgram(tester);
        await tester.enterText(
          find.widgetWithText(ForgeTextField, 'Program name'),
          'Push',
        );
        // The page refuses to pop from the next frame on.
        await tester.pump();

        await tester.tap(find.bySemanticsLabel('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Discard changes?'), findsOneWidget);
        await tester.tap(find.text('Discard'));
        await tester.pumpAndSettle();

        expect(find.text('Discard changes?'), findsNothing);
        expectBackOnTheExercise(tester);
      });
    });
  }

  group('custom exercise form with changes', () {
    Future<void> fillIn(WidgetTester tester) async {
      await startAsGuest(tester);
      router.go(Routes.customExerciseNew);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(ForgeTextField, 'Name'),
        'Sled push',
      );
      await tester.pump();
    }

    testWidgets('a link into the Exercises tab asks first; keeping them '
        'stays', (tester) async {
      await fillIn(tester);
      await tapTab(tester, 'Today');

      router.go(Routes.exerciseList);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      expect(selectedTab(tester), 2);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(path(), Routes.customExerciseNew);
      expect(find.widgetWithText(TextField, 'Sled push'), findsOneWidget);
    });

    testWidgets('back asks once with the same prompt', (tester) async {
      await fillIn(tester);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsOneWidget);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(CustomExerciseNewPage), findsNothing);
      expect(find.byType(ExercisesPage), findsOneWidget);
    });

    testWidgets('a link into the Programs tab leaves it alone', (tester) async {
      await fillIn(tester);

      router.go(Routes.catalogue);
      await tester.pumpAndSettle();
      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(CataloguePage), findsOneWidget);

      await tapTab(tester, 'Exercises');
      expect(find.widgetWithText(TextField, 'Sled push'), findsOneWidget);
    });

    testWidgets('without changes a link leaves it silently', (tester) async {
      await startAsGuest(tester);
      router.go(Routes.customExerciseNew);
      await tester.pumpAndSettle();

      router.go(Routes.exerciseList);
      await tester.pumpAndSettle();

      expect(find.text('Discard changes?'), findsNothing);
      expect(find.byType(LibraryPage), findsOneWidget);
    });
  });

  testWidgets('an unknown exercise id shows not found', (tester) async {
    await startAsGuest(tester);

    router.go(Routes.exercise('retired_since'));
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.text('This exercise is no longer available.'), findsOneWidget);
    expect(find.byType(ForgeNavigationBar), findsOneWidget);
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

  testWidgets('Today opens the calculators inside the tab', (tester) async {
    await startAsGuest(tester);
    await tapTab(tester, 'Today');

    await tester.scrollUntilVisible(
      find.text('Calculators'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Calculators'));
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsPage), findsOneWidget);

    await tester.tap(find.text('Calories'));
    await tester.pumpAndSettle();
    expect(find.byType(CaloriesPage), findsOneWidget);
    expect(find.byType(ForgeNavigationBar), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(CalculatorsPage), findsOneWidget);
  });

  testWidgets('every calculator has a route under Today', (tester) async {
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
      expect(find.byType(ForgeNavigationBar), findsOneWidget, reason: route);
      expect(route, startsWith('${Routes.calculators}/'));
    }
  });

  testWidgets('a calculator keeps its place when switching tabs', (
    tester,
  ) async {
    await startAsGuest(tester);
    router.go(Routes.plates);
    await tester.pumpAndSettle();

    await tapTab(tester, 'Profile');
    await tapTab(tester, 'Today');

    expect(find.byType(PlatesPage), findsOneWidget);
  });

  testWidgets('Compare opens the one Body page, not another above the day', (
    tester,
  ) async {
    final summary = _SummaryStandIn();
    when(() => summary.state).thenReturn(const MeasurementSummaryState());
    sl.registerFactoryParam<MeasurementSummaryCubit, String?, void>(
      (_, _) => summary,
    );
    await startAsGuest(tester);
    router.go(Routes.bodyEntry('d1'));
    await tester.pumpAndSettle();
    expect(find.byType(BodyEntryPage), findsOneWidget);

    router.go(Routes.bodyEntryCompare('d1'));
    await tester.pumpAndSettle();

    expect(find.byType(BodyPage, skipOffstage: false), findsOneWidget);
    expect(find.byType(BodyEntryPage, skipOffstage: false), findsNothing);
    verify(() => summary.showDay('d1')).called(1);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(BodyPage, skipOffstage: false), findsNothing);
  });

  group('onboarding', () {
    testWidgets('a new user sees onboarding once the session resolves', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.byType(ForgeNavigationBar), findsNothing);
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
      expect(find.byType(SplashScreen), findsOneWidget);
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
      storedProfile = choicesAnswered;
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

      await finishOnboarding(tester);

      expect(find.byType(ProgramSuggestionPage), findsOneWidget);
      expect(find.text('Program pr_free'), findsOneWidget);
      expect(find.text('Program pr_paid'), findsNothing);
      expect(find.text('Not now'), findsNothing);

      await tester.tap(find.text('See other programs'));
      await tester.pumpAndSettle();
      expect(find.byType(CataloguePage), findsOneWidget);
    });

    testWidgets('the suggestion is saved, not started', (tester) async {
      registerFallbackValue(_FakeActiveProgram());
      readyMade = [
        card(
          'pr_free',
          goal: Goal.loseFat,
          equipment: const [Equipment.bodyweight],
          profile: EquipmentProfile.bodyweight,
        ),
      ];
      storedProfile = choicesAnswered;
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
      await finishOnboarding(tester);

      await tester.tap(find.text('Start this program'));
      await tester.pumpAndSettle();

      verify(() => programs.createProgram(any(), any())).called(1);
      verifyNever(() => programs.startProgram(any(), any()));
      expect(path(), Routes.program('p1'));
    });

    testWidgets('the target weight asks as its own step, naming the weight', (
      tester,
    ) async {
      storedProfile = choicesAnswered;
      await startAsGuest(tester);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      for (var i = 0; i < ProfileField.values.length - 1; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Your goal'), findsOneWidget);
      expect(
        find.text('Now, where do you want your weight to be?'),
        findsOneWidget,
      );
      expect(find.textContaining('You weigh '), findsOneWidget);
      // The ruler marks the weight now.
      final picker = tester.widget<NumberPicker>(find.byType(NumberPicker));
      expect(picker.marker?.label, startsWith('Now '));
    });

    testWidgets('a next question slides in from the right, Back from the left', (
      tester,
    ) async {
      storedProfile = choicesAnswered;
      await startAsGuest(tester);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      final first = find.text('What is your main goal?');
      final startX = tester.getTopLeft(first).dx;

      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Midway: the first leaves to the left, the second comes from the right.
      expect(tester.getTopLeft(first).dx, lessThan(startX));
      final second = find.byType(ProfileQuestion).last;
      expect(tester.getTopLeft(second).dx, greaterThan(startX));
      await tester.pumpAndSettle();
      expect(first, findsNothing);

      tester
          .widget<OnboardingQuestion>(find.byType(OnboardingQuestion))
          .onBack!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.getTopLeft(first).dx, lessThan(startX));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(first).dx, startX);
    });

    testWidgets('the reminder step turns reminders on, then moves on', (
      tester,
    ) async {
      storedProfile = choicesAnswered;
      await startAsGuest(tester);
      when(() => notifications.state)
          .thenReturn(const NotificationsState(allowed: false));
      when(() => notifications.allow()).thenAnswer((_) async => false);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      for (var i = 0; i < ProfileField.values.length; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }

      expect(find.text('Remind you on training days?'), findsOneWidget);
      await tester.tap(find.text('Turn on reminders'));
      await tester.pumpAndSettle();

      // Refused: it moves on without a word; health access is granted already.
      verify(() => notifications.allow()).called(1);
      expect(find.text('Remind you on training days?'), findsNothing);
      expect(find.byType(TodayPage), findsOneWidget);
    });

    for (final (access, settings) in [
      (StepsAccess.explain, false),
      (StepsAccess.denied, true),
    ]) {
      testWidgets('the health step shows while access is ${access.name}', (
        tester,
      ) async {
        healthAccess = access;
        storedProfile = choicesAnswered;
        await startAsGuest(tester);
        await finishOnboarding(tester);

        expect(find.text('Bring in steps and cardio?'), findsOneWidget);
        await tester.tap(find.textContaining('Connect '));
        await tester.pumpAndSettle();

        // A refusal still asks on Android, where the stand-in stays refused
        // and so leads to the settings.
        verify(health.allow).called(1);
        if (settings) {
          verify(health.openSettings).called(1);
        } else {
          verifyNever(health.openSettings);
        }
        expect(find.text('Bring in steps and cardio?'), findsNothing);
        expect(find.byType(TodayPage), findsOneWidget);
      });
    }

    testWidgets('once asked on this iPhone (access undetermined), the health '
        'step is skipped', (tester) async {
      healthAccess = StepsAccess.undetermined;
      storedProfile = choicesAnswered;
      await startAsGuest(tester);
      await finishOnboarding(tester);

      expect(find.text('Bring in steps and cardio?'), findsNothing);
      verifyNever(health.allow);
      expect(find.byType(TodayPage), findsOneWidget);
    });

    testWidgets('onboarding goes forward and back one question at a time', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(questionOnScreen(tester), 1);

      // Nothing to skip: Continue waits for an answer.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(questionOnScreen(tester), 1);

      await tester.tap(find.text('Build muscle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(questionOnScreen(tester), 2);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(questionOnScreen(tester), 1);

      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Get started'), findsOneWidget);
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
      expect(find.byType(SplashScreen), findsNothing);
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
      expect(find.byType(ForgeNavigationBar), findsNothing);
    });

    testWidgets('a profile stream that dies on onboarding does not trap', (
      tester,
    ) async {
      storedProfile = choicesAnswered;
      await startAsGuest(tester);

      profileStream.addError(const NetworkFailure());
      await tester.pump();
      expect(find.byType(OnboardingPage), findsOneWidget);

      // Completing follows the profile again at once and moves on.
      await finishOnboarding(tester);

      expect(find.byType(TodayPage), findsOneWidget);
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('a deep link waits behind onboarding, which lands on Today', (
      tester,
    ) async {
      storedProfile = choicesAnswered;
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

      await finishOnboarding(tester);

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
      expect(find.byType(ForgeNavigationBar), findsNothing);

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
      expect(find.text('Get started'), findsOneWidget);
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
    // Over the tab bar.
    expect(find.byType(ForgeNavigationBar), findsNothing);
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
    expect(find.byType(ForgeNavigationBar), findsOneWidget);
  });

  group('no consent page', () {
    const unanswered = (consent: null, fromServer: true);
    final page = find.text('Help improve GetWorkout?');
    late MockConsentRepository consents;
    late MockTelemetry telemetry;

    /// Starts as onboarded guest u1, who answered; every other user never
    /// answered.
    Future<void> start(WidgetTester tester) async {
      setUpAuth();
      consents = MockConsentRepository();
      when(() => consents.watchConsent(any())).thenAnswer((call) {
        final uid = call.positionalArguments.first as String;
        final controller = StreamController<StoredConsent>()
          ..add(uid == 'u1' ? (consent: true, fromServer: true) : unanswered);
        addTearDown(controller.close);
        return controller.stream;
      });
      telemetry = MockTelemetry();
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
    }

    testWidgets('a new guest after sign-out goes from the last onboarding '
        'question to the reminder, collected without being asked', (
      tester,
    ) async {
      await start(tester);
      when(() => repository.signInAnonymously()).thenAnswer((_) async {
        users.add(const AuthUser(id: 'u2', isAnonymous: true));
        return const Ok(guest);
      });
      storedProfile = null;

      users.add(null);
      await tester.pumpAndSettle();
      profileStream.add(choicesAnswered);
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      for (var i = 0; i < ProfileField.values.length; i++) {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      expect(page, findsNothing);
      if (find.text('Remind you on training days?').evaluate().isNotEmpty) {
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      }

      expect(find.byType(TodayPage), findsOneWidget);
      expect(page, findsNothing);
      verify(() => telemetry.apply('u2', null)).called(1);
      verifyNever(() => consents.saveConsent(any(), any()));
    });

    testWidgets('an account that never answered signs in from the tabs and '
        'stays on them', (tester) async {
      await start(tester);
      storedProfile = null;

      users.add(const AuthUser(id: 'u2', email: 'b@c.de'));
      await tester.pumpAndSettle();
      profileStream.add(onboarded);
      await tester.pumpAndSettle();

      expect(find.byType(TodayPage), findsOneWidget);
      expect(page, findsNothing);
      verify(() => telemetry.apply('u2', null)).called(1);
    });
  });

  group('pages follow the signed-in user', () {
    const other = AuthUser(id: 'u2', isAnonymous: true);

    testWidgets('onboarding starts over for a new user, writing only theirs', (
      tester,
    ) async {
      storedProfile = const UserProfile();
      await startAsGuest(tester);
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lose fat'));
      await tester.pumpAndSettle();

      storedProfile = choicesAnswered;
      users.add(other);
      await tester.pump();
      // Never an endless loader: the new user's profile arrives.
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);

      await finishOnboarding(tester);

      verify(
        () => profiles.completeOnboarding(
          'u2',
          choicesAnswered.copyWith(
            birthYear: DateTime.now().year - 30,
            heightCm: 170,
            weightKg: 70,
            targetWeightKg: 70,
          ),
        ),
      ).called(1);
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
            .widget<OnboardingChoices<Goal>>(
              find.byType(OnboardingChoices<Goal>),
            )
            .selected,
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
      expect(find.byType(ProfileQuestionPage), findsOneWidget);
      expect(find.text('Get stronger'), findsNothing);

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
      expect(find.byType(ListRow), findsNWidgets(9));
      expect(find.text('Goal'), findsNothing);

      profileStream.addError(const NetworkFailure());
      await tester.pump();
      await tester.pump();
      expect(find.text("Couldn't load your profile"), findsOneWidget);

      storedProfile = onboarded;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('—'), findsWidgets);
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
    // A loader never settles, so pump frames by hand.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ExerciseDetailPage), findsOneWidget);
    expect(find.byType(SkeletonBar), findsWidgets);
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

    testWidgets('the card offers nothing while the status is unknown', (
      tester,
    ) async {
      await startAsGuest(tester);
      await tapTab(tester, 'Profile');
      expect(find.text('Checking…'), findsOneWidget);
      expect(find.text('Get Premium'), findsNothing);
      expect(find.text('Manage subscription'), findsNothing);

      await tester.tap(find.text('GetWorkout Premium'));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsNothing);
    });

    testWidgets('a free user starts the yearly trial', (tester) async {
      await openProfileAsFreeGuest(tester);
      expect(find.text('7 days free'), findsOneWidget);
      expect(find.text('23 more ready-made programs'), findsOneWidget);

      await tapVisible(tester, 'Get Premium');
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.text(r'$7.99 / month'), findsOneWidget);
      expect(find.text(r'$39.99 / year'), findsOneWidget);
      expect(find.text('Best value'), findsOneWidget);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Terms of Use'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);

      await tapVisible(tester, 'Start 7-day free trial');

      expect(find.byType(PaywallPage), findsNothing);
      expect(find.text('Welcome to Premium!'), findsOneWidget);
      expect(find.textContaining('Free trial until'), findsOneWidget);
      verify(
        () => paywallTelemetry.logEvent('paywall_view', {
          'layout': 'a',
          'moment': 'user',
        }),
      ).called(1);
      verify(
        () => paywallTelemetry.logEvent('paywall_purchase', {
          'plan': 'yearly',
          'layout': 'a',
          'moment': 'user',
        }),
      ).called(1);
    });

    testWidgets('layout B shows the plans as cards', (tester) async {
      await openProfileAsFreeGuest(tester);
      remoteConfig.values['paywall_layout'] = 'b';

      await tapVisible(tester, 'Get Premium');
      expect(find.text(r'$7.99'), findsOneWidget);
      expect(find.text(r'$39.99'), findsOneWidget);
      expect(find.text('7 days free'), findsOneWidget);
      expect(find.text(r'$39.99 / year'), findsNothing);

      await tester.ensureVisible(find.text('Monthly'));
      await tester.pump();
      await tester.tap(find.text('Monthly'));
      await tester.pump();
      expect(find.text('Subscribe'), findsOneWidget);
      verify(
        () => paywallTelemetry.logEvent('paywall_view', {
          'layout': 'b',
          'moment': 'user',
        }),
      ).called(1);
    });

    testWidgets('layout C shows one plan and links to the other', (
      tester,
    ) async {
      await openProfileAsFreeGuest(tester);
      remoteConfig.values['paywall_layout'] = 'c';

      await tapVisible(tester, 'Get Premium');
      expect(find.text('Yearly · 7 days free'), findsOneWidget);
      expect(find.text(r'$39.99 / year'), findsOneWidget);
      expect(find.text(r'That is $3.33 a month.'), findsOneWidget);
      expect(find.text(r'$7.99 / month'), findsNothing);

      await tapVisible(tester, 'See monthly plan');
      expect(find.text(r'$7.99 / month'), findsOneWidget);
      expect(find.text('See yearly plan'), findsOneWidget);
      expect(find.text('Subscribe'), findsOneWidget);
      verify(
        () => paywallTelemetry.logEvent('paywall_view', {
          'layout': 'c',
          'moment': 'user',
        }),
      ).called(1);
    });

    testWidgets('with large text the whole paywall scrolls', (tester) async {
      tester.view
        ..physicalSize = const Size(375, 667)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await openProfileAsFreeGuest(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tapVisible(tester, 'Get Premium');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Monthly'));
      await tester.pumpAndSettle();
      final page = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(
        find.text('Subscribe'),
        200,
        scrollable: page,
      );
      await tester.scrollUntilVisible(
        find.text('Restore purchases'),
        200,
        scrollable: page,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore purchases'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing to restore.'), findsOneWidget);
    });

    testWidgets('a restore after a failed load keeps the load message', (
      tester,
    ) async {
      await openProfileAsFreeGuest(tester);
      store.failure = const NetworkFailure();
      await tapVisible(tester, 'Get Premium');
      expect(find.text("Couldn't load plans"), findsOneWidget);
      expect(find.text('Subscribe'), findsOneWidget);

      store.failure = null;
      await tapVisible(tester, 'Restore purchases');

      expect(find.text('Nothing to restore.'), findsOneWidget);
      expect(find.text("Couldn't load plans"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a pending purchase closes the paywall once approved', (
      tester,
    ) async {
      await openProfileAsFreeGuest(tester);
      await tapVisible(tester, 'Get Premium');
      store.failure = const PurchaseFailure(PurchaseFailureReason.pending);

      await tapVisible(tester, 'Start 7-day free trial');
      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.textContaining('waiting for approval'), findsOneWidget);

      store
        ..failure = null
        ..approvePending();
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsNothing);
      expect(find.text('You have Premium.'), findsOneWidget);
    });

    testWidgets('the onboarding paywall is hard when the offering says so', (
      tester,
    ) async {
      await openProfileAsFreeGuest(tester);
      store.metadata = const {dismissibleKey: false};
      unawaited(router.push(Routes.paywallAt(PaywallMoment.onboarding)));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsOneWidget);
      expect(find.bySemanticsLabel('Close'), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(PaywallPage), findsOneWidget);

      await tapVisible(tester, 'Start 7-day free trial');
      expect(find.byType(PaywallPage), findsNothing);
    });

    for (final moment in [PaywallMoment.onboarding, PaywallMoment.appOpen]) {
      testWidgets('on iOS the ${moment.name} paywall is full screen: a drag '
          'down does not close it', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        await openProfileAsFreeGuest(tester);
        store.metadata = const {dismissibleKey: false};
        unawaited(router.push(Routes.paywallAt(moment)));
        await tester.pumpAndSettle();

        await tester.fling(
          find.byType(PaywallPage),
          const Offset(0, 600),
          2000,
        );
        await tester.pumpAndSettle();
        expect(find.byType(PaywallPage), findsOneWidget);
        expect(find.bySemanticsLabel('Close'), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });
    }

    testWidgets('a hard paywall waits for a pending purchase', (tester) async {
      await openProfileAsFreeGuest(tester);
      store.metadata = const {dismissibleKey: false};
      unawaited(router.push(Routes.paywallAt(PaywallMoment.onboarding)));
      await tester.pumpAndSettle();
      store.failure = const PurchaseFailure(PurchaseFailureReason.pending);

      await tapVisible(tester, 'Start 7-day free trial');
      expect(find.textContaining('waiting for approval'), findsOneWidget);
      expect(find.text('Got it'), findsNothing);
      expect(find.bySemanticsLabel('Close'), findsNothing);

      store
        ..failure = null
        ..approvePending();
      await tester.pumpAndSettle();
      expect(find.byType(PaywallPage), findsNothing);
    });

    testWidgets('any other paywall stays closable', (tester) async {
      await openProfileAsFreeGuest(tester);
      store.metadata = const {dismissibleKey: false};
      unawaited(router.push(Routes.paywallAt(PaywallMoment.workoutDone)));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(PaywallPage), findsNothing);
    });

    testWidgets('the paywall closes at once for a subscriber', (tester) async {
      await openProfileAsFreeGuest(tester);
      unawaited(store.purchase(fakePlans.first));
      await tester.pumpAndSettle();
      expect(find.textContaining('Premium, renews'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);

      unawaited(router.push(Routes.paywall));
      await tester.pumpAndSettle();

      expect(find.byType(PaywallPage), findsNothing);
      expect(find.text('You have Premium.'), findsOneWidget);
      verifyNever(() => paywallTelemetry.logEvent('paywall_view', any()));
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
            set: (weightKg: 100, reps: 4, durationS: null),
          ),
          RecordKind.bestE1rm: StatRecord(
            value: 112,
            date: yesterday,
            workoutId: 'w1',
            set: (weightKg: 100, reps: 4, durationS: null),
          ),
        },
        history: [
          HistoryPoint(
            date: yesterday,
            workoutId: 'w1',
            bestE1rmKg: 112,
            bestSet: (weightKg: 100, reps: 4, durationS: null),
            workoutName: 'Legs',
          ),
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
        ..unregister<ProgressStrengthCubit>()
        ..registerFactory(
          () => ProgressStrengthCubit(
            watchAuthUser: WatchAuthUser(strengthAuth),
            watchHighlights: WatchStrengthHighlights(workouts),
            catalogue: catalogue,
          ),
        )
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
            rebuildStats: RebuildExerciseStats(workouts),
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
            getRecords: GetHeldRecords(workouts),
          ),
        );
    }

    Future<void> back(WidgetTester tester) async {
      await tester.tap(find.bySemanticsLabel('Back'));
      await tester.pumpAndSettle();
    }

    testWidgets('the Strength card opens the list; an exercise its page', (
      tester,
    ) async {
      await startAsGuest(tester);
      registerStrength();
      await tapTab(tester, 'Progress');
      await tester.scrollUntilVisible(
        find.text('Strength'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ProgressPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
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

    testWidgets('a session opens its workout, and back returns', (
      tester,
    ) async {
      await startAsGuest(tester);
      registerStrength();
      router.go(Routes.strengthExercise('squat'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('100 × 4 · e1RM 112'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ExerciseStrengthPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(find.text('100 × 4 · e1RM 112'));
      await tester.pumpAndSettle();
      expect(find.byType(WorkoutDetailPage), findsOneWidget);
      await back(tester);
      expect(find.byType(ExerciseStrengthPage), findsOneWidget);
      expect(path(), Routes.strengthExercise('squat'));
    });
  });

  testWidgets('a workout opened above Today is edited in Today\'s tab, and '
      'Back returns through it to Today', (tester) async {
    await startAsGuest(tester);
    final workout = Workout(
      id: 'w1',
      startedAt: DateTime(2026, 11, 13, 7),
      finishedAt: DateTime(2026, 11, 13, 8),
      name: 'Push',
    );
    sl
      ..registerFactoryParam<WorkoutDetailCubit, String, void>((_, _) {
        final cubit = _WorkoutDetailStandIn();
        when(() => cubit.state).thenReturn(
          WorkoutDetailState(
            status: WorkoutDetailStatus.ready,
            workout: workout,
          ),
        );
        return cubit;
      })
      ..registerFactoryParam<WorkoutEditCubit, String?, PastWorkoutPlan>((
        _,
        _,
      ) {
        final cubit = _WorkoutEditStandIn();
        // Not loading: its skeleton would never settle.
        when(
          () => cubit.state,
        ).thenReturn(const WorkoutEditState(status: WorkoutEditStatus.missing));
        when(() => cubit.hasChanges).thenReturn(false);
        when(() => cubit.isNew).thenReturn(false);
        return cubit;
      });
    unawaited(router.push(Routes.todayWorkout('w1')));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutDetailPage), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Workout options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutEditPage), findsOneWidget);
    expect(selectedTab(tester), 0);

    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutDetailPage), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(TodayPage), findsOneWidget);
    expect(path(), Routes.today);
  });

  testWidgets('Log weight opens its sheet over Progress, which stays', (
    tester,
  ) async {
    await startAsGuest(tester);
    sl.registerFactoryParam<WeightFormCubit, WeightFormSetup, WeightUnit>((
      _,
      _,
    ) {
      final cubit = _WeightFormCubit();
      when(() => cubit.state)
          .thenReturn(WeightFormState(date: DateTime(2026), weight: 70));
      when(() => cubit.isEditing).thenReturn(false);
      return cubit;
    });
    await tapTab(tester, 'Progress');

    await tester.tap(find.text('Log weight'));
    await tester.pumpAndSettle();
    expect(find.byType(WeightSheet), findsOneWidget);
    expect(find.byType(ProgressPage), findsOneWidget);
    expect(path(), Routes.progress);
  });
}

class _WorkoutDetailStandIn extends MockCubit<WorkoutDetailState>
    implements WorkoutDetailCubit {}

class _WorkoutEditStandIn extends MockCubit<WorkoutEditState>
    implements WorkoutEditCubit {}

class _WeightFormCubit extends MockCubit<WeightFormState>
    implements WeightFormCubit {}

class _BackedUp implements SyncRepository {
  @override
  Stream<bool> watchBackedUp() => Stream.value(true);
}
