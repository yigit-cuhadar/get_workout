import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/notifications/domain/notification_repository.dart';
import 'package:get_workout/features/notifications/domain/notifications_usecases.dart';
import 'package:get_workout/features/notifications/domain/reminder_plan.dart';
import 'package:get_workout/features/notifications/presentation/notifications_cubit.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:get_workout/features/settings/domain/settings_repository.dart';
import 'package:get_workout/features/settings/domain/settings_usecases.dart';
import 'package:get_workout/features/settings/domain/user_settings.dart';
import 'package:mocktail/mocktail.dart';

import '../programs/fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockSettingsRepository extends Mock implements SettingsRepository {}

class MockProgramListCubit extends MockCubit<ProgramListState>
    implements ProgramListCubit {}

class MockNotificationRepository extends Mock
    implements NotificationRepository {}

class MockAnnouncementRepository extends Mock
    implements AnnouncementRepository {}

void main() {
  // Wednesday 11 November 2026, 07:00.
  final now = DateTime(2026, 11, 11, 7);
  final today = CalendarDate(2026, 11, 11);
  const base = UserSettings(
    weightUnit: WeightUnit.kg,
    lengthUnit: LengthUnit.cm,
  );
  final reminding = base.copyWith(
    workoutReminder: const WorkoutReminderSettings(enabled: true),
    measurementReminder: MeasurementReminderSettings(
      enabled: true,
      from: today,
    ),
  );
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [1, 3, 5],
    nextDayIndex: 0,
    nextDate: today,
    startedAt: DateTime(2026, 11, 2),
  );

  ProgramListState ready({bool premiumCopy = false, bool? premium = false}) =>
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1', premium: premiumCopy)],
        active: active,
        premium: premium,
      );

  late MockAuthRepository auth;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<UserSettings>> settings;
  late MockProgramListCubit programs;
  late StreamController<ProgramListState> programStates;
  late MockNotificationRepository device;
  late MockAnnouncementRepository announcements;
  late bool allowed;
  late bool requestGrants;

  /// What each sync asked for, in order.
  late List<({ReminderKind kind, List<ReminderNotice> wanted})> syncs;

  /// While set, every sync waits for it.
  Completer<void>? gate;

  setUpAll(() => registerFallbackValue(ReminderKind.workout));

  setUp(() {
    users = StreamController.broadcast(sync: true);
    settings = {};
    auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    programs = MockProgramListCubit();
    programStates = StreamController.broadcast(sync: true);
    when(() => programs.state).thenReturn(const ProgramListState());
    when(() => programs.stream).thenAnswer((_) => programStates.stream);
    device = MockNotificationRepository();
    announcements = MockAnnouncementRepository();
    allowed = true;
    requestGrants = true;
    syncs = [];
    gate = null;
    when(device.allowed).thenAnswer((_) async => Ok(allowed));
    when(device.request).thenAnswer((_) async {
      allowed = requestGrants;
      return Ok(allowed);
    });
    when(device.openSettings).thenAnswer((_) async => const Ok(null));
    when(device.refreshTimeZone).thenAnswer((_) async => const Ok(null));
    when(() => device.syncReminders(any(), any())).thenAnswer((call) async {
      syncs.add((
        kind: call.positionalArguments[0] as ReminderKind,
        wanted: call.positionalArguments[1] as List<ReminderNotice>,
      ));
      await gate?.future;
      return const Ok(null);
    });
    when(() => announcements.follow(any()))
        .thenAnswer((_) async => const Ok(null));
  });

  tearDown(() async {
    await users.close();
    await programStates.close();
    for (final controller in settings.values) {
      await controller.close();
    }
  });

  NotificationsCubit build({DateTime? at}) {
    final repository = MockSettingsRepository();
    when(() => repository.watchSettings(any())).thenAnswer(
      (call) => settings
          .putIfAbsent(
            call.positionalArguments.single as String,
            () => StreamController.broadcast(sync: true),
          )
          .stream,
    );
    return NotificationsCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchSettings: WatchSettings(repository),
      programs: programs,
      planWorkout: const PlanWorkoutReminders(),
      planMeasurement: const PlanMeasurementReminders(),
      sync: SyncReminders(device),
      getAccess: GetNotificationAccess(device),
      requestAccess: RequestNotificationAccess(device),
      openSettings: OpenNotificationSettings(device),
      refreshTimeZone: RefreshTimeZone(device),
      followAnnouncements: FollowAnnouncements(announcements),
      workoutText: (reminder) => (
        title: 'Workout',
        body: reminder.day == null
            ? reminder.programName
            : '${reminder.day!.day.name} · ${reminder.programName}',
      ),
      measurementText: () => (title: 'Measure', body: 'Log it'),
      language: () => 'en',
      clock: () => at ?? now,
    );
  }

  void signIn(String uid) => users.add(AuthUser(id: uid));

  void emitSettings(String uid, UserSettings value) =>
      settings[uid]!.add(value);

  void emitPrograms(ProgramListState state) {
    when(() => programs.state).thenReturn(state);
    programStates.add(state);
  }

  List<ReminderNotice> lastOf(ReminderKind kind) =>
      syncs.lastWhere((sync) => sync.kind == kind).wanted;

  test(
    'plans both kinds once the user\'s settings and programs are known',
    () async {
      final cubit = build();
      signIn('u1');
      emitPrograms(ready());
      await pumpEventQueue();
      expect(syncs, isEmpty, reason: 'settings still loading');

      emitSettings('u1', reminding);
      await pumpEventQueue();

      final workout = lastOf(ReminderKind.workout);
      expect(workout.first.at, DateTime(2026, 11, 11, 8));
      expect(workout.first.body, 'Upper · Upper Lower');
      expect(workout[1].body, 'Upper Lower');
      expect(lastOf(ReminderKind.measurement), hasLength(4));
      expect(lastOf(ReminderKind.measurement).first.title, 'Measure');
      await cubit.close();
    },
  );

  test('leaves workout reminders alone while programs load', () async {
    final cubit = build();
    signIn('u1');
    await pumpEventQueue();
    emitSettings('u1', reminding);
    await pumpEventQueue();

    expect(syncs.map((sync) => sync.kind), [ReminderKind.measurement]);
    await cubit.close();
  });

  test('a premium copy waits for the premium status, then is locked', () async {
    final cubit = build();
    signIn('u1');
    emitPrograms(ready(premiumCopy: true, premium: null));
    emitSettings('u1', reminding);
    await pumpEventQueue();
    expect(syncs.where((sync) => sync.kind == ReminderKind.workout), isEmpty);

    emitPrograms(ready(premiumCopy: true));
    await pumpEventQueue();

    expect(lastOf(ReminderKind.workout), isEmpty);
    await cubit.close();
  });

  test('a schedule or settings change plans again', () async {
    final cubit = build();
    signIn('u1');
    emitPrograms(ready());
    emitSettings('u1', reminding);
    await pumpEventQueue();

    // Today's day done: the program moved on to Friday.
    emitPrograms(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [program(id: 'p1')],
        active: active.copyWith(
          nextDayIndex: 1,
          nextDate: CalendarDate(2026, 11, 13),
        ),
        weekPlan: [
          PlannedDay(date: today, dayIndex: 0, status: PlannedStatus.done),
        ],
        premium: false,
      ),
    );
    await pumpEventQueue();
    expect(lastOf(ReminderKind.workout).first.at, DateTime(2026, 11, 13, 8));
    expect(lastOf(ReminderKind.workout).first.body, 'Lower · Upper Lower');

    emitSettings(
      'u1',
      reminding.copyWith(workoutReminder: const WorkoutReminderSettings()),
    );
    await pumpEventQueue();
    expect(lastOf(ReminderKind.workout), isEmpty);
    await cubit.close();
  });

  test(
    'a change of user drops the previous user\'s reminders at once',
    () async {
      final cubit = build();
      signIn('u1');
      emitPrograms(ready());
      emitSettings('u1', reminding);
      await pumpEventQueue();
      syncs.clear();

      signIn('u2');
      await pumpEventQueue();

      expect(syncs, [
        (kind: ReminderKind.workout, wanted: const <ReminderNotice>[]),
        (kind: ReminderKind.measurement, wanted: const <ReminderNotice>[]),
      ]);
      await cubit.close();
    },
  );

  test('signing out drops the reminders', () async {
    final cubit = build();
    users.add(null);
    await pumpEventQueue();

    expect(syncs.map((sync) => sync.wanted), everyElement(isEmpty));
    expect(syncs, hasLength(2));
    await cubit.close();
  });

  test('the first user at start keeps the reminders until planned', () async {
    final cubit = build();
    signIn('u1');
    await pumpEventQueue();

    expect(syncs, isEmpty);
    await cubit.close();
  });

  test('resuming refreshes the time zone and plans again', () async {
    final cubit = build();
    signIn('u1');
    emitPrograms(ready());
    emitSettings('u1', reminding);
    await pumpEventQueue();
    syncs.clear();

    await cubit.resumed();
    await pumpEventQueue();

    verify(device.refreshTimeZone).called(1);
    expect(syncs.map((sync) => sync.kind), [
      ReminderKind.workout,
      ReminderKind.measurement,
    ]);
    await cubit.close();
  });

  group('a reminder turned off is cleared whatever the programs say', () {
    final off = reminding.copyWith(
      workoutReminder: const WorkoutReminderSettings(minute: 1200),
    );
    for (final (name, programState) in [
      ('loading', const ProgramListState()),
      (
        'failed',
        const ProgramListState(
          status: ProgramListStatus.failure,
          failure: UnknownFailure('offline'),
        ),
      ),
      ('premium unknown', ready(premiumCopy: true, premium: null)),
    ]) {
      test(name, () async {
        final cubit = build();
        signIn('u1');
        emitPrograms(programState);
        emitSettings('u1', off);
        await pumpEventQueue();

        expect(lastOf(ReminderKind.workout), isEmpty);
        await cubit.close();
      });
    }
  });

  test(
    'a time changed while programs load applies once they are known',
    () async {
      final cubit = build();
      signIn('u1');
      emitSettings(
        'u1',
        reminding.copyWith(
          workoutReminder: const WorkoutReminderSettings(
            enabled: true,
            minute: 1200,
          ),
        ),
      );
      await pumpEventQueue();
      expect(syncs.where((sync) => sync.kind == ReminderKind.workout), isEmpty);

      emitPrograms(ready());
      await pumpEventQueue();

      expect(lastOf(ReminderKind.workout).first.at, DateTime(2026, 11, 11, 20));
      await cubit.close();
    },
  );

  test(
    'changes during a running sync are planned once, on the latest',
    () async {
      final cubit = build();
      signIn('u1');
      emitPrograms(ready());
      gate = Completer();
      emitSettings('u1', reminding);
      await pumpEventQueue();
      expect(syncs, hasLength(1), reason: 'the first sync is running');

      for (final minute in [600, 660]) {
        emitSettings(
          'u1',
          reminding.copyWith(
            workoutReminder: WorkoutReminderSettings(
              enabled: true,
              minute: minute,
            ),
          ),
        );
      }
      gate!.complete();
      gate = null;
      await pumpEventQueue();

      final workout = syncs.where((sync) => sync.kind == ReminderKind.workout);
      expect(workout, hasLength(2));
      expect(workout.last.wanted.first.at, DateTime(2026, 11, 11, 11));
      await cubit.close();
    },
  );

  test(
    'a user change during a running sync ends with nothing pending',
    () async {
      final cubit = build();
      signIn('u1');
      emitPrograms(ready());
      gate = Completer();
      emitSettings('u1', reminding);
      await pumpEventQueue();

      signIn('u2');
      emitPrograms(const ProgramListState());
      gate!.complete();
      gate = null;
      await pumpEventQueue();

      expect(lastOf(ReminderKind.workout), isEmpty);
      expect(lastOf(ReminderKind.measurement), isEmpty);
      await cubit.close();
    },
  );

  test('switching to another program reminds of that one', () async {
    final cubit = build();
    signIn('u1');
    emitPrograms(ready());
    emitSettings('u1', reminding);
    await pumpEventQueue();

    emitPrograms(
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [
          program(id: 'p1'),
          program(id: 'p2', name: 'Push Pull'),
        ],
        active: ActiveProgram(
          programId: 'p2',
          weekdays: const [4],
          nextDayIndex: 0,
          nextDate: CalendarDate(2026, 11, 12),
          startedAt: now,
        ),
        premium: false,
      ),
    );
    await pumpEventQueue();

    final workout = lastOf(ReminderKind.workout);
    expect(workout.first.at, DateTime(2026, 11, 12, 8));
    expect(workout.first.body, 'Upper · Push Pull');
    expect(workout[1].body, 'Push Pull');
    await cubit.close();
  });

  test('deleting the active program drops its reminders', () async {
    final cubit = build();
    signIn('u1');
    emitPrograms(ready());
    emitSettings('u1', reminding);
    await pumpEventQueue();

    emitPrograms(
      ProgramListState(
        status: ProgramListStatus.ready,
        active: active,
        premium: false,
      ),
    );
    await pumpEventQueue();

    expect(lastOf(ReminderKind.workout), isEmpty);
    await cubit.close();
  });

  group('access', () {
    test('known at start; announcements followed once allowed', () async {
      final cubit = build();
      await pumpEventQueue();

      expect(cubit.state, const NotificationsState(allowed: true));
      verify(() => announcements.follow('en')).called(1);

      await cubit.resumed();
      verifyNever(() => announcements.follow(any()));
      await cubit.close();
    });

    test('not allowed: no announcements until the user allows', () async {
      allowed = false;
      final cubit = build();
      await pumpEventQueue();
      expect(cubit.state, const NotificationsState(allowed: false));
      verifyNever(() => announcements.follow(any()));

      expect(await cubit.allow(), isTrue);

      expect(cubit.state, const NotificationsState(allowed: true));
      verify(() => announcements.follow('en')).called(1);
      await cubit.close();
    });

    test('allowing does not wait for announcements to be followed', () async {
      allowed = false;
      final following = Completer<Result<void>>();
      when(() => announcements.follow(any()))
          .thenAnswer((_) => following.future);
      final cubit = build();
      await pumpEventQueue();

      expect(await cubit.allow(), isTrue);

      verify(() => announcements.follow('en')).called(1);
      following.complete(const Ok(null));
      await cubit.close();
    });

    test('a refusal is reported', () async {
      allowed = false;
      requestGrants = false;
      final cubit = build();
      await pumpEventQueue();

      expect(await cubit.allow(), isFalse);
      expect(cubit.state, const NotificationsState(allowed: false));
      await cubit.close();
    });

    test('allowed already: nothing is asked', () async {
      final cubit = build();
      await pumpEventQueue();

      expect(await cubit.allow(), isTrue);
      verifyNever(device.request);
      await cubit.close();
    });

    test('a failed follow is tried again on resume', () async {
      when(() => announcements.follow(any()))
          .thenAnswer((_) async => const Err(UnknownFailure('offline')));
      final cubit = build();
      await pumpEventQueue();

      await cubit.resumed();

      verify(() => announcements.follow('en')).called(2);
      await cubit.close();
    });
  });
}
