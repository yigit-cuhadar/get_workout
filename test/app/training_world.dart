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
import 'package:get_workout/features/calculators/domain/calculators_usecases.dart';
import 'package:get_workout/features/cardio/domain/cardio_repository.dart';
import 'package:get_workout/features/cardio/domain/cardio_usecases.dart';
import 'package:get_workout/features/exercises/domain/custom_exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise.dart';
import 'package:get_workout/features/exercises/domain/exercise_repository.dart';
import 'package:get_workout/features/exercises/domain/exercise_usecases.dart';
import 'package:get_workout/features/exercises/domain/user_library_repository.dart';
import 'package:get_workout/features/exercises/domain/vocabulary.dart';
import 'package:get_workout/features/exercises/presentation/body_model_cubit.dart';
import 'package:get_workout/features/exercises/presentation/equipment_cubit.dart';
import 'package:get_workout/features/exercises/presentation/exercise_catalogue_cubit.dart';
import 'package:get_workout/features/exercises/presentation/favorites_cubit.dart';
import 'package:get_workout/features/exercises/presentation/library_cubit.dart';
import 'package:get_workout/features/generator/domain/generator_answers.dart';
import 'package:get_workout/features/generator/domain/generator_usecases.dart';
import 'package:get_workout/features/generator/presentation/generator_preview_cubit.dart';
import 'package:get_workout/features/generator/presentation/generator_questions_cubit.dart';
import 'package:get_workout/features/profile/domain/profile_usecases.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/profile_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/catalogue_program.dart';
import 'package:get_workout/features/programs/domain/catalogue_repository.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/catalogue_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/exercise_picker_cubit.dart';
import 'package:get_workout/features/programs/presentation/premium_prompt.dart';
import 'package:get_workout/features/programs/presentation/program_builder_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_catalogue_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/programs/programs_module.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:get_workout/features/settings/presentation/settings_cubit.dart';
import 'package:get_workout/features/subscription/domain/subscription_usecases.dart';
import 'package:get_workout/features/subscription/presentation/premium_paywall_cubit.dart';
import 'package:get_workout/features/subscription/subscription_module.dart';
import 'package:get_workout/features/today/presentation/today_steps_cubit.dart';
import 'package:get_workout/features/today/presentation/today_volume_cubit.dart';
import 'package:get_workout/features/today/presentation/today_week_cubit.dart';
import 'package:get_workout/features/workout/data/workout_completed_days.dart';
import 'package:get_workout/features/workout/domain/exercise_stats.dart';
import 'package:get_workout/features/workout/domain/history_usecases.dart';
import 'package:get_workout/features/workout/domain/rest_notifications.dart';
import 'package:get_workout/features/workout/domain/rest_usecases.dart';
import 'package:get_workout/features/workout/domain/workout.dart';
import 'package:get_workout/features/workout/domain/workout_lock_screen.dart';
import 'package:get_workout/features/workout/domain/workout_repository.dart';
import 'package:get_workout/features/workout/domain/workout_end_notice.dart';
import 'package:get_workout/features/workout/domain/workout_usecases.dart';
import 'package:get_workout/features/workout/presentation/active_workout_cubit.dart';
import 'package:get_workout/features/workout/presentation/rest_timer_cubit.dart';
import 'package:get_workout/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../features/body/body_fakes.dart' show FakeProfileRepository;
import '../features/programs/fixtures.dart' show FixedPremium;
import 'answered_consent.dart';

/// Wednesday, 18:00: the day every flow runs on.
final flowStart = DateTime(2026, 11, 11, 18);

/// Every write notifies [changed]; each watch re-reads, like Firestore's
/// local cache showing a write at once.
class LiveData {
  final _changes = StreamController<void>.broadcast(sync: true);

  void changed() => _changes.add(null);

  Stream<T> watch<T>(T Function() read) => Stream.multi((controller) {
    controller.add(read());
    final changes = _changes.stream.listen((_) => controller.add(read()));
    // Not returned: a test zone never resumes after awaiting it.
    controller.onCancel = () => unawaited(changes.cancel());
  });
}

/// The user's programs and active program in memory.
class FakeProgramRepository extends LiveData implements ProgramRepository {
  final programs = <String, Program>{};
  ActiveProgram? active;
  var _ids = 0;

  void add(Program program) {
    programs[program.id!] = program;
    changed();
  }

  @override
  Stream<List<Program>> watchPrograms(String uid) => watch(
    () => programs.values.toList()..sort((a, b) => a.name.compareTo(b.name)),
  );

  @override
  Future<Result<Program>> getProgram(String uid, String id) async =>
      programs[id] == null ? const Err(NotFoundFailure()) : Ok(programs[id]!);

  @override
  Future<Result<String>> createProgram(String uid, Program program) async {
    final id = 'new${++_ids}';
    add(
      Program(
        id: id,
        name: program.name,
        origin: program.origin,
        sourceId: program.sourceId,
        lengthWeeks: program.lengthWeeks,
        days: program.days,
        premium: program.premium,
      ),
    );
    return Ok(id);
  }

  @override
  Future<Result<void>> updateProgram(String uid, Program program) async {
    add(program);
    return const Ok(null);
  }

  @override
  Future<Result<void>> deleteProgram(
    String uid,
    String id, {
    required bool clearActive,
  }) async {
    programs.remove(id);
    if (clearActive) active = null;
    changed();
    return const Ok(null);
  }

  @override
  Stream<ActiveProgram?> watchActiveProgram(String uid) => watch(() => active);

  @override
  Future<Result<void>> startProgram(String uid, ActiveProgram active) =>
      updateActiveProgram(uid, active);

  @override
  Future<Result<void>> updateActiveProgram(
    String uid,
    ActiveProgram active,
  ) async {
    this.active = active;
    changed();
    return const Ok(null);
  }

  @override
  Future<Result<void>> stopProgram(String uid) async {
    active = null;
    changed();
    return const Ok(null);
  }

  @override
  Stream<Failure> get rejectedWrites => const Stream.empty();
}

/// Finished workouts and their stats in memory, every write taken by the
/// "server" at once; a workout that moves the program on moves it in
/// [programs].
class FakeWorkoutRepository extends LiveData implements WorkoutRepository {
  FakeWorkoutRepository(this.programs);

  final FakeProgramRepository programs;
  final workouts = <String, Workout>{};
  final stats = <String, ExerciseStats>{};
  var _ids = 0;

  @override
  String newWorkoutId(String uid) => 'w${++_ids}';

  @override
  Stream<ExerciseStats?> watchStats(String uid, String exerciseId) =>
      watch(() => stats[exerciseId]);

  @override
  Stream<Map<String, ExerciseStats>> watchAllStats(String uid) =>
      watch(() => {...stats});

  @override
  Future<Result<Map<String, StatsRead>>> getStats(
    String uid,
    List<String> exerciseIds,
  ) async =>
      Ok({for (final id in exerciseIds) id: (stats: stats[id], current: true)});

  @override
  Future<Result<void>> saveWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats> stats, {
    ActiveProgram? advance,
  }) async {
    workouts[workout.id] = workout;
    this.stats.addAll(stats);
    changed();
    if (advance != null) await programs.updateActiveProgram(uid, advance);
    return const Ok(null);
  }

  @override
  Future<Result<bool>> isStored(String uid, String id) async =>
      Ok(workouts.containsKey(id));

  @override
  Future<Result<ExerciseWorkouts>> workoutsWith(
    String uid,
    String exerciseId,
  ) async => Ok((
    workouts: [
      for (final workout in workouts.values)
        if (workout.exerciseIds.contains(exerciseId)) workout,
    ],
    complete: true,
  ));

  @override
  Future<Result<void>> saveStats(
    String uid,
    String exerciseId,
    ExerciseStats? stats,
  ) async {
    if (stats == null) {
      this.stats.remove(exerciseId);
    } else {
      this.stats[exerciseId] = stats;
    }
    changed();
    return const Ok(null);
  }

  @override
  Future<Result<WorkoutsByExercise>> workoutsDoing(
    String uid,
    List<String> exerciseIds,
  ) => throw UnimplementedError();

  @override
  Future<Result<List<Workout>>> programWorkouts(
    String uid,
    String programId,
  ) async => Ok([
    for (final workout in workouts.values)
      if (workout.programId == programId) workout,
  ]);

  @override
  Stream<List<Workout>> watchWorkoutsBetween(
    String uid, {
    required CalendarDate from,
    required CalendarDate to,
  }) => watch(
    () => [
      for (final workout in workouts.values)
        if (!workout.startDate.isBefore(from) && !workout.startDate.isAfter(to))
          workout,
    ]..sort((a, b) => a.startedAt.compareTo(b.startedAt)),
  );

  @override
  Stream<StoredWorkout?> watchWorkout(String uid, String id) => watch(
    () => switch (workouts[id]) {
      final workout? => (workout: workout, pending: false),
      null => null,
    },
  );

  @override
  Future<Result<void>> updateWorkout(
    String uid,
    Workout workout,
    Map<String, ExerciseStats?> stats,
  ) => throw UnimplementedError();

  @override
  Future<Result<void>> deleteWorkout(
    String uid,
    String id,
    Map<String, ExerciseStats?> stats,
  ) => throw UnimplementedError();

  @override
  Stream<Failure> get rejectedEdits => const Stream.empty();
}

/// What the device keeps, in memory.
class FakeLocalWorkoutStore implements LocalWorkoutStore {
  LocalWorkouts kept = const LocalWorkouts();

  @override
  Future<Result<LocalWorkouts>> load(String uid) async => Ok(kept);

  @override
  Future<Result<void>> save(String uid, LocalWorkouts workouts) async {
    kept = workouts;
    return const Ok(null);
  }

  @override
  Future<Result<void>> remove(String uid) async {
    kept = const LocalWorkouts();
    return const Ok(null);
  }
}

/// The ready-made programs: cards and their days.
class FakeCatalogueRepository implements CatalogueRepository {
  final cards = <CatalogueProgram>[];
  final days = <String, List<ProgramDay>>{};

  @override
  Stream<List<CatalogueProgram>> watchPrograms() => Stream.value(cards);

  @override
  Future<Result<List<ProgramDay>>> getDays(String id) async =>
      days[id] == null ? const Err(NotFoundFailure()) : Ok(days[id]!);
}

class _MockAuthRepository extends Mock implements AuthRepository {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockExerciseRepository extends Mock implements ExerciseRepository {}

class _MockUserLibrary extends Mock implements UserLibraryRepository {}

class _MockCustomExercises extends Mock implements CustomExerciseRepository {}

class _MockCardioRepository extends Mock implements CardioRepository {}

class _MockRestNotifications extends Mock implements RestNotifications {}

/// Records the workout end notice instead of showing it.
class FakeWorkoutEndNotice implements WorkoutEndNotice {
  EndNotice? scheduled;

  @override
  Future<Result<void>> schedule(
    DateTime at, {
    required String title,
    required String body,
  }) async {
    scheduled = (at: at, title: title, body: body);
    return const Ok(null);
  }

  @override
  Future<Result<void>> cancel() async {
    scheduled = null;
    return const Ok(null);
  }
}

class _MockLockScreen extends Mock implements WorkoutLockScreen {}

class _MockTelemetry extends Mock implements Telemetry {}

class _VolumeStandIn extends MockCubit<TodayVolumeState>
    implements TodayVolumeCubit {}

class _StepsStandIn extends MockCubit<TodayStepsState>
    implements TodayStepsCubit {}

class _EntitlementStandIn extends MockCubit<EntitlementState>
    implements EntitlementCubit {}

/// The app over in-memory repositories for one guest, from the real router
/// down: Today, Programs with the ready-made programs and the builder, the
/// generator, the workout in progress and, with [registerMore], the pages
/// a test adds. Every clock reads [now]. Weekly volume and steps are
/// stand-ins.
class TrainingWorld {
  TrainingWorld({
    required this.exercises,
    this.premium = false,
    UserSettings? settings,
    UserProfile? profile,
  }) : settings =
           settings ??
           UserSettings(
             weightUnit: WeightUnit.kg,
             lengthUnit: LengthUnit.cm,
             // Asked already, no warm-ups and no tips, so sets and panels
             // stay as the tests put them.
             restTimer: const RestTimerSettings(notify: false),
             warmups: const WarmupSettings(scheme: WarmupScheme.off),
             seenTips: Tip.values.toSet(),
           ) {
    profiles.profile =
        profile ?? UserProfile(onboardingCompletedAt: DateTime(2026));
  }

  static const guest = AuthUser(id: 'u1', isAnonymous: true);

  final List<Exercise> exercises;
  final bool premium;
  final UserSettings settings;
  DateTime now = flowStart;

  final endNotice = FakeWorkoutEndNotice();

  /// Whether this device was asked to notify when a rest is over.
  bool notificationsAskedHere = true;

  final programs = FakeProgramRepository();
  late final workouts = FakeWorkoutRepository(programs);
  final local = FakeLocalWorkoutStore();
  final catalogue = FakeCatalogueRepository();
  final profiles = FakeProfileRepository();
  late GoRouter router;

  /// The guest, signed in for good.
  late WatchAuthUser watchUser;
  late GetCurrentUser currentUser;

  /// Closed at the end, in this order.
  final _cubits = <BlocBase<Object?>>[];

  DateTime _clock() => now;

  /// Closes [cubit] with the rest at the end.
  void own(BlocBase<Object?> cubit) => _cubits.add(cubit);

  /// Registers everything and shows Today.
  Future<void> start(
    WidgetTester tester, {
    void Function(TrainingWorld world)? registerMore,
  }) async {
    tester.view
      ..physicalSize = const Size(1290, 2796)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(sl.reset);
    _registerFallbacks();

    // Like Firebase, the user arrives on subscription.
    final session = _MockAuthRepository();
    when(session.watchUser).thenAnswer((_) => Stream.value(guest));
    when(() => session.currentUser).thenReturn(guest);
    watchUser = WatchAuthUser(session);
    currentUser = GetCurrentUser(session);
    final auth = AuthCubit(
      watchAuthUser: watchUser,
      signOut: SignOut(session),
      deleteAccount: DeleteAccount(session),
      signInAnonymously: SignInAnonymously(session),
    );

    final settingsRepository = _MockSettingsRepository();
    when(() => settingsRepository.watchSettings(any()))
        .thenAnswer((_) => Stream.value(settings));
    when(() => settingsRepository.saveSettings(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => settingsRepository.markTipSeen(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    final settingsCubit = SettingsCubit(
      watchAuthUser: watchUser,
      watchSettings: WatchSettings(settingsRepository),
      updateSettings: UpdateSettings(settingsRepository),
      markTipSeen: MarkTipSeen(settingsRepository),
      defaults: settings,
    );

    final library = _MockUserLibrary();
    when(() => library.watchEquipment(any()))
        .thenAnswer((_) => Stream.value(EquipmentProfile.fullGym.equipment));
    when(() => library.watchFavorites(any()))
        .thenAnswer((_) => Stream.value(const {}));
    when(() => library.watchExerciseNotes(any()))
        .thenAnswer((_) => Stream.value(const {}));
    final profile = ProfileCubit(
      watchAuthUser: watchUser,
      watchProfile: WatchProfile(profiles),
      updateProfile: UpdateProfile(profiles, SaveOwnedEquipment(library)),
    );
    // Signed out to the library: it never syncs or looks for custom ones.
    final idle = _MockAuthRepository();
    when(idle.watchUser).thenAnswer((_) => const Stream.empty());
    final exerciseRepository = _MockExerciseRepository();
    when(exerciseRepository.watchExercises)
        .thenAnswer((_) => Stream.value(exercises));
    final customExercises = _MockCustomExercises();
    final exerciseCatalogue = ExerciseCatalogueCubit(
      watchAuthUser: WatchAuthUser(idle),
      watchExercises: WatchExercises(exerciseRepository),
      watchCustomExercises: WatchCustomExercises(customExercises),
      syncExercises: SyncExercises(exerciseRepository),
    );
    final favorites = FavoritesCubit(
      watchAuthUser: watchUser,
      watchFavorites: WatchFavorites(library),
      setFavorite: SetFavorite(library),
    );
    final equipment = EquipmentCubit(
      watchAuthUser: watchUser,
      watchEquipment: WatchOwnedEquipment(library),
      saveEquipment: SaveOwnedEquipment(library),
    );
    final bodyModel = BodyModelCubit(() async => throw const FormatException());
    final entitlement = _EntitlementStandIn();
    when(() => entitlement.state).thenReturn(
      premium
          ? const EntitlementActive(Entitlement(isActive: true))
          : const EntitlementInactive(),
    );
    when(() => entitlement.isActive).thenReturn(premium);

    final list = ProgramListCubit(
      firstWeekday: DateTime.monday,
      watchAuthUser: watchUser,
      watchPrograms: WatchPrograms(programs),
      watchActiveProgram: WatchActiveProgram(programs),
      watchCompletedDays: WatchCompletedDays(WorkoutCompletedDays(workouts)),
      watchRejectedWrites: WatchRejectedProgramWrites(programs),
      resolveMissedDay: ResolveMissedDay(programs, clock: _clock),
      moveNextDay: MoveNextDay(programs, clock: _clock),
      watchPremium: WatchPremium(FixedPremium(premium)),
      clock: _clock,
    );
    final workout = ActiveWorkoutCubit(
      watchAuthUser: watchUser,
      loadLocal: LoadLocalWorkouts(local),
      keepLocal: KeepLocalWorkouts(local),
      newWorkoutId: NewWorkoutId(workouts),
      watchStats: WatchExerciseStats(workouts),
      finishWorkout: FinishWorkout(workouts, clock: _clock),
      scheduleEndNotice: ScheduleWorkoutEndNotice(endNotice),
      cancelEndNotice: CancelWorkoutEndNotice(endNotice),
      endText: (workout, lastSetAt) => (
        title: lastSetAt == null ? 'Removed' : 'Ended ${workout.name}',
        body: '',
      ),
      confirmStored: ConfirmStoredWorkout(workouts),
      rebuildStats: RebuildExerciseStats(workouts),
      saveAsProgram: SaveWorkoutAsProgram(SaveProgram(programs)),
      updateProgramDay: UpdateProgramDay(SaveProgram(programs)),
      programs: list,
      catalogue: exerciseCatalogue,
      watchSettings: WatchSettings(settingsRepository),
      loadPlates: const LoadPlates(),
      clock: _clock,
    );
    final notifications = _MockRestNotifications();
    when(notifications.askedHere)
        .thenAnswer((_) async => Ok(notificationsAskedHere));
    when(notifications.markAskedHere).thenAnswer((_) async {
      notificationsAskedHere = true;
      return const Ok(null);
    });
    when(notifications.cancel).thenAnswer((_) async => const Ok(null));
    when(
      () => notifications.schedule(
        any(),
        title: any(named: 'title'),
        body: any(named: 'body'),
        alert: any(named: 'alert'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    final lockScreen = _MockLockScreen();
    when(() => lockScreen.show(any())).thenAnswer((_) async => const Ok(null));
    when(lockScreen.clear).thenAnswer((_) async => const Ok(null));
    final rest = RestTimerCubit(
      workout: workout,
      settings: settingsCubit,
      shouldAsk: ShouldAskRestNotifications(notifications),
      allow: AllowRestNotifications(notifications),
      decline: DeclineRestNotifications(notifications),
      schedule: ScheduleRestNotification(notifications),
      cancel: CancelRestNotification(notifications),
      text: (_, _) => (title: 'Rest over', body: 'Back to it'),
      showOnLockScreen: ShowWorkoutOnLockScreen(lockScreen),
      clearLockScreen: ClearWorkoutFromLockScreen(lockScreen),
      lockScreenText: (_, _) => (current: null, rest: 'Rest', afterRest: null),
      clock: _clock,
    );
    final cardio = _MockCardioRepository();
    when(
      () => cardio.watchSessionsBetween(
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) => Stream.value(const []));
    final store = FakePurchasesRepository(plans: fakePlans);
    final telemetry = _MockTelemetry();
    when(() => telemetry.logEvent(any(), any())).thenAnswer((_) async {});
    final saveProgram = SaveProgram(programs);
    final startProgram = StartProgram(
      programs,
      WorkoutCompletedDays(workouts),
      clock: _clock,
    );

    sl
      ..registerSingleton<ProgramListCubit>(list)
      ..registerSingleton(PremiumPrompt((_) {}))
      ..registerLazySingleton(
        () => ProgramCatalogueCubit(
          watchAuthUser: watchUser,
          watchCatalogue: WatchCatalogue(catalogue),
          watchPremium: WatchPremium(FixedPremium(premium)),
          profile: profile,
          equipment: equipment,
        ),
        dispose: (cubit) => cubit.close(),
      )
      ..registerFactoryParam<CatalogueDetailCubit, String, String>(
        (id, language) => CatalogueDetailCubit(
          id,
          language: language,
          catalogue: sl(),
          list: list,
          exercises: exerciseCatalogue,
          getDays: GetCatalogueDays(catalogue),
          saveProgram: saveProgram,
          startProgram: startProgram,
          getCurrentUser: currentUser,
        ),
      )
      ..registerFactoryParam<ProgramDetailCubit, String, void>(
        (id, _) => ProgramDetailCubit(
          id,
          list: list,
          startProgram: startProgram,
          changeWeekdays: ChangeWeekdays(programs, clock: _clock),
          stopProgram: StopProgram(programs),
          duplicateProgram: DuplicateProgram(programs),
          deleteProgram: DeleteProgram(programs),
          getCurrentUser: currentUser,
          watchAuthUser: watchUser,
        ),
      )
      ..registerFactoryParam<ProgramBuilderCubit, String?, WeightUnit>(
        (id, unit) => ProgramBuilderCubit(
          programId: id,
          getProgram: GetProgram(programs),
          saveProgram: saveProgram,
          getCurrentUser: currentUser,
          watchAuthUser: watchUser,
          catalogue: exerciseCatalogue,
          weightUnit: unit,
        ),
      )
      ..registerFactoryParam<ExercisePickerCubit, int, bool>(
        (max, multiple) => ExercisePickerCubit(max: max, multiple: multiple),
      )
      ..registerFactory(
        () => LibraryCubit(
          watchAuthUser: watchUser,
          catalogue: exerciseCatalogue,
          favorites: favorites,
          equipment: equipment,
        ),
        instanceName: ProgramsModule.pickerLibrary,
      )
      ..registerFactoryParam<GeneratorQuestionsCubit, GeneratorPrefill, void>(
        (prefill, _) => GeneratorQuestionsCubit(prefill),
      )
      ..registerFactoryParam<GeneratorPreviewCubit, GeneratorAnswers, void>(
        (answers, _) => GeneratorPreviewCubit(
          answers,
          catalogue: exerciseCatalogue,
          generateProgram: const GenerateProgram(),
          saveProgram: saveProgram,
          getCurrentUser: currentUser,
        ),
      )
      ..registerFactory(
        () => PremiumPaywallCubit(
          getOffering: GetPaywallOffering(store),
          purchasePlan: PurchasePlan(store),
          restorePurchases: RestorePurchases(store),
          getLayout: GetPaywallLayout(
            FakeRemoteConfigRepository(SubscriptionModule.remoteConfigDefaults),
          ),
          logView: LogPaywallView(telemetry),
          logPurchase: LogPaywallPurchase(telemetry),
          isPremium: () => premium,
        ),
      )
      ..registerFactoryParam<TodayWeekCubit, int, void>(
        (firstWeekday, _) => TodayWeekCubit(
          firstWeekday: firstWeekday,
          watchAuthUser: watchUser,
          watchWorkouts: WatchWorkoutsBetween(workouts),
          watchCardio: WatchCardioBetween(cardio),
          watchPrograms: WatchPrograms(programs),
          watchActiveProgram: WatchActiveProgram(programs),
          clock: _clock,
        ),
      )
      ..registerFactoryParam<TodayVolumeCubit, int, void>((_, _) {
        final cubit = _VolumeStandIn();
        when(() => cubit.state)
            .thenReturn(TodayVolumeState(weekStart: CalendarDate.of(now)));
        return cubit;
      })
      ..registerFactory<TodayStepsCubit>(() {
        final cubit = _StepsStandIn();
        when(() => cubit.state).thenReturn(
          const TodayStepsState(status: TodayStepsStatus.unavailable),
        );
        when(() => cubit.load(any())).thenAnswer((_) async {});
        return cubit;
      });
    _cubits.addAll([
      rest,
      workout,
      list,
      auth,
      settingsCubit,
      profile,
      exerciseCatalogue,
      favorites,
      equipment,
      bodyModel,
    ]);
    registerMore?.call(this);

    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: auth),
          BlocProvider.value(value: settingsCubit),
          answeredConsent(),
          BlocProvider.value(value: profile),
          BlocProvider.value(value: exerciseCatalogue),
          BlocProvider.value(value: favorites),
          BlocProvider.value(value: equipment),
          BlocProvider.value(value: bodyModel),
          BlocProvider.value(value: workout),
          BlocProvider.value(value: rest),
          BlocProvider<EntitlementCubit>.value(value: entitlement),
          BlocProvider.value(value: list),
        ],
        child: MaterialApp.router(
          theme: AppPreset.shipped.lightTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router = buildRouter(auth, profile),
        ),
      ),
    );
    await settle(tester);
  }

  /// Closes what [start] made, so no timer outlives the test; call last.
  Future<void> stop(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Not awaited: a close awaits subscription cancels, after which a test
    // zone never resumes.
    for (final cubit in _cubits) {
      unawaited(cubit.close());
    }
    await tester.pump(const Duration(seconds: 1));
  }

  /// The location of the page in front.
  String get front =>
      openLocations(router.routerDelegate.currentConfiguration).last;

  static void _registerFallbacks() {
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(<String, Object>{});
    registerFallbackValue(CalendarDate(2026, 1, 1));
    registerFallbackValue(RestAlert.chimeVibrate);
    registerFallbackValue(Tip.values.first);
    registerFallbackValue(UserSettings.defaultsFor(null));
    registerFallbackValue(
      LockScreenWorkout(name: '', startedAt: DateTime(2026)),
    );
  }
}

/// Two seconds of frames: enough for a route transition, a sheet or a
/// snack bar to come in, and bounded, as the workout's clocks tick for
/// ever.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapText(WidgetTester tester, String text) =>
    tapOn(tester, find.text(text));

/// Scrolls [finder] into view when it is in a list, taps it and settles.
Future<void> tapOn(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// [text] in the dialog in front.
Finder inDialog(String text) =>
    find.descendant(of: find.byType(Dialog), matching: find.text(text));

/// Opens a tab from the navigation bar.
Future<void> openTab(WidgetTester tester, String label) => tapOn(
  tester,
  find.descendant(
    of: find.byType(ForgeNavigationBar),
    matching: find.text(label),
  ),
);

/// A day's date as [CalendarDate].
CalendarDate dateOf(DateTime time) => CalendarDate.of(time);
