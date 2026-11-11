import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/completed_days.dart';
import 'package:get_workout/features/programs/domain/program.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_schedule.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

class MockCompletedDays extends Mock implements CompletedDays {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  // Wednesday 11 November 2026.
  var now = DateTime(2026, 11, 11, 12);
  final upperLower = program(id: 'p1');
  final other = program(id: 'p2', name: 'Arms');
  final active = ActiveProgram(
    programId: 'p1',
    weekdays: const [1, 4],
    nextDayIndex: 1,
    nextDate: CalendarDate(2026, 11, 12),
    startedAt: DateTime(2026, 11, 2),
  );

  late MockAuthRepository auth;
  late MockProgramRepository repository;
  late MockCompletedDays completedDays;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<List<Program>>> programs;
  late Map<String, StreamController<ActiveProgram?>> actives;
  late StreamController<List<CompletedDay>> completed;
  late StreamController<Failure> rejected;
  late FakePremium premium;

  setUpAll(() {
    registerFallbackValue(CalendarDate(2026, 1, 1));
    registerFallbackValue(active);
  });

  setUp(() {
    auth = MockAuthRepository();
    repository = MockProgramRepository();
    completedDays = MockCompletedDays();
    users = StreamController<AuthUser?>();
    programs = {};
    actives = {};
    completed = StreamController<List<CompletedDay>>.broadcast();
    rejected = StreamController<Failure>.broadcast();
    premium = FakePremium();
    now = DateTime(2026, 11, 11, 12);
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.rejectedWrites).thenAnswer((_) => rejected.stream);
    when(() => repository.updateActiveProgram(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.watchPrograms(any())).thenAnswer(
      (call) => programs
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<List<Program>>.new,
          )
          .stream,
    );
    when(() => repository.watchActiveProgram(any())).thenAnswer(
      (call) => actives
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<ActiveProgram?>.new,
          )
          .stream,
    );
    when(
      () => completedDays.watch(
        any(),
        any(),
        from: any(named: 'from'),
        to: any(named: 'to'),
      ),
    ).thenAnswer((_) => completed.stream);
  });

  ProgramListCubit build() => ProgramListCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchPrograms: WatchPrograms(repository),
    watchActiveProgram: WatchActiveProgram(repository),
    watchCompletedDays: WatchCompletedDays(completedDays),
    watchRejectedWrites: WatchRejectedProgramWrites(repository),
    resolveMissedDay: ResolveMissedDay(repository, clock: () => now),
    watchPremium: WatchPremium(premium),
    clock: () => now,
  );

  Future<void> signIn(AuthUser user) async {
    users.add(user);
    await pumpEventQueue();
  }

  test('starts loading', () {
    expect(build().state, const ProgramListState());
  });

  blocTest<ProgramListCubit, ProgramListState>(
    'is ready once programs and the active program are known',
    build: build,
    act: (_) async {
      await signIn(member);
      programs['u1']!.add([other, upperLower]);
      await pumpEventQueue();
      actives['u1']!.add(null);
    },
    expect: () => [
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [other, upperLower],
      ),
    ],
    verify: (cubit) {
      expect(cubit.state.activeProgram, isNull);
      expect(cubit.state.otherPrograms, [other, upperLower]);
      verifyNever(
        () => completedDays.watch(
          any(),
          any(),
          from: any(named: 'from'),
          to: any(named: 'to'),
        ),
      );
    },
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'plans the active program\'s week with its done days',
    build: build,
    act: (_) async {
      await signIn(member);
      programs['u1']!.add([other, upperLower]);
      actives['u1']!.add(active);
      await pumpEventQueue();
      completed.add([
        CompletedDay(date: CalendarDate(2026, 11, 9), dayIndex: 0),
      ]);
    },
    skip: 1,
    expect: () => [
      ProgramListState(
        status: ProgramListStatus.ready,
        programs: [other, upperLower],
        active: active,
        weekPlan: [
          PlannedDay(
            date: CalendarDate(2026, 11, 9),
            dayIndex: 0,
            status: PlannedStatus.done,
          ),
          PlannedDay(
            date: CalendarDate(2026, 11, 12),
            dayIndex: 1,
            status: PlannedStatus.planned,
          ),
        ],
      ),
    ],
    verify: (cubit) {
      expect(cubit.state.activeProgram, upperLower);
      expect(cubit.state.otherPrograms, [other]);
      verify(
        () => completedDays.watch(
          'u1',
          'p1',
          from: CalendarDate(2026, 11, 9),
          to: CalendarDate(2026, 11, 15),
        ),
      ).called(1);
    },
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'a finished program is marked and plans nothing',
    build: build,
    act: (_) async {
      await signIn(member);
      programs['u1']!.add([program(id: 'p1', lengthWeeks: 1)]);
      actives['u1']!.add(active);
    },
    verify: (cubit) {
      expect(cubit.state.finished, isTrue);
      expect(cubit.state.weekPlan, isEmpty);
    },
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'an active program that no longer exists shows as none',
    build: build,
    act: (_) async {
      await signIn(member);
      programs['u1']!.add([other]);
      actives['u1']!.add(active);
    },
    verify: (cubit) {
      expect(cubit.state.status, ProgramListStatus.ready);
      expect(cubit.state.activeProgram, isNull);
      expect(cubit.state.weekPlan, isEmpty);
      expect(cubit.state.otherPrograms, [other]);
    },
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'a user change resets to loading and follows the new user',
    build: build,
    act: (_) async {
      await signIn(guest);
      programs['g1']!.add([other]);
      actives['g1']!.add(null);
      await pumpEventQueue();
      await signIn(member);
      programs['g1']!.add([upperLower]);
      await pumpEventQueue();
      programs['u1']!.add([upperLower]);
      actives['u1']!.add(null);
    },
    expect: () => [
      ProgramListState(status: ProgramListStatus.ready, programs: [other]),
      const ProgramListState(),
      ProgramListState(status: ProgramListStatus.ready, programs: [upperLower]),
    ],
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'signing out leaves it loading with nothing shown',
    build: build,
    act: (_) async {
      await signIn(member);
      programs['u1']!.add([other]);
      actives['u1']!.add(null);
      await pumpEventQueue();
      await signIn(const AuthUser(id: 'g2', isAnonymous: true));
    },
    skip: 1,
    expect: () => [const ProgramListState()],
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'a failing stream shows a failure until retried',
    build: build,
    act: (cubit) async {
      await signIn(member);
      programs['u1']!.addError(const PermissionFailure());
      await pumpEventQueue();
      programs.clear();
      actives.clear();
      cubit.retry();
      await pumpEventQueue();
      programs['u1']!.add([other]);
      actives['u1']!.add(null);
    },
    expect: () => [
      const ProgramListState(
        status: ProgramListStatus.failure,
        failure: PermissionFailure(),
      ),
      const ProgramListState(),
      ProgramListState(status: ProgramListStatus.ready, programs: [other]),
    ],
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'reports a rejected write once',
    build: build,
    act: (cubit) async {
      rejected.add(const PermissionFailure());
      await pumpEventQueue();
      cubit.rejectionShown();
    },
    expect: () => [
      const ProgramListState(writeRejected: true),
      const ProgramListState(),
    ],
  );

  blocTest<ProgramListCubit, ProgramListState>(
    'refreshing on a new day replans, a new week follows its done days',
    build: build,
    act: (cubit) async {
      await signIn(member);
      programs['u1']!.add([upperLower]);
      actives['u1']!.add(active);
      await pumpEventQueue();
      // Friday: Thursday's day was missed.
      now = DateTime(2026, 11, 13, 8);
      cubit.refreshNow();
      // Monday of the next week.
      now = DateTime(2026, 11, 16, 8);
      cubit.refreshNow();
    },
    skip: 1,
    expect: () => [
      isA<ProgramListState>().having((s) => s.weekPlan, 'weekPlan', [
        PlannedDay(
          date: CalendarDate(2026, 11, 12),
          dayIndex: 1,
          status: PlannedStatus.missed,
        ),
      ]),
      // Still missed: the missed day comes first again, from Monday on.
      isA<ProgramListState>().having((s) => s.weekPlan, 'weekPlan', [
        PlannedDay(
          date: CalendarDate(2026, 11, 16),
          dayIndex: 1,
          status: PlannedStatus.planned,
        ),
        PlannedDay(
          date: CalendarDate(2026, 11, 19),
          dayIndex: 0,
          status: PlannedStatus.planned,
        ),
      ]),
    ],
    verify: (_) => verify(
      () => completedDays.watch(
        'u1',
        'p1',
        from: CalendarDate(2026, 11, 16),
        to: CalendarDate(2026, 11, 22),
      ),
    ).called(1),
  );

  group('a missed day', () {
    // Thursday's day 1 was missed; today is Friday 13 November.
    setUp(() => now = DateTime(2026, 11, 13, 8));

    Future<void> ready() async {
      await signIn(member);
      programs['u1']!.add([upperLower]);
      actives['u1']!.add(active);
      await pumpEventQueue();
    }

    blocTest<ProgramListCubit, ProgramListState>(
      'is offered with the date it would move to',
      build: build,
      act: (_) => ready(),
      verify: (cubit) {
        expect(
          cubit.state.missed,
          PlannedDay(
            date: CalendarDate(2026, 11, 12),
            dayIndex: 1,
            status: PlannedStatus.missed,
          ),
        );
        expect(cubit.state.moveDate, CalendarDate(2026, 11, 16));
      },
    );

    blocTest<ProgramListCubit, ProgramListState>(
      'is not offered while nothing was missed',
      build: () {
        now = DateTime(2026, 11, 12, 8);
        return build();
      },
      act: (_) => ready(),
      verify: (cubit) {
        expect(cubit.state.missed, isNull);
        expect(cubit.state.moveDate, isNull);
      },
    );

    for (final (choice, expected) in [
      (
        MissedDayChoice.doToday,
        active.copyWith(nextDate: CalendarDate(2026, 11, 13)),
      ),
      (
        MissedDayChoice.moveToNextWeekday,
        active.copyWith(nextDate: CalendarDate(2026, 11, 16)),
      ),
      (
        MissedDayChoice.skip,
        active.copyWith(nextDayIndex: 0, nextDate: CalendarDate(2026, 11, 16)),
      ),
    ]) {
      blocTest<ProgramListCubit, ProgramListState>(
        'resolves it: ${choice.name}',
        build: build,
        act: (cubit) async {
          await ready();
          await cubit.resolveMissed(choice);
        },
        verify: (cubit) {
          verify(() => repository.updateActiveProgram('u1', expected))
              .called(1);
          expect(cubit.state.resolving, isFalse);
          expect(cubit.state.resolveFailure, isNull);
        },
      );
    }

    blocTest<ProgramListCubit, ProgramListState>(
      'a failed resolution is reported once',
      setUp: () =>
          when(() => repository.updateActiveProgram(any(), any()))
              .thenAnswer((_) async => const Err(NetworkFailure())),
      build: build,
      act: (cubit) async {
        await ready();
        final resolving = cubit.resolveMissed(MissedDayChoice.skip);
        expect(cubit.state.resolving, isTrue);
        await resolving;
        expect(cubit.state.resolveFailure, const NetworkFailure());
        cubit.resolveFailureShown();
      },
      verify: (cubit) {
        expect(cubit.state.resolving, isFalse);
        expect(cubit.state.resolveFailure, isNull);
      },
    );

    group('of a premium copy', () {
      setUp(
        () => when(
          () => repository.watchPrograms('u1'),
        ).thenAnswer((_) => Stream.value([program(id: 'p1', premium: true)])),
      );

      Future<void> readyWith(bool? hasPremium) async {
        await signIn(member);
        premium.controller.add(hasPremium);
        actives['u1']!.add(active);
        await pumpEventQueue();
      }

      blocTest<ProgramListCubit, ProgramListState>(
        'is locked without premium, still active and not resolved',
        build: build,
        act: (cubit) async {
          await readyWith(false);
          await cubit.resolveMissed(MissedDayChoice.skip);
        },
        verify: (cubit) {
          expect(cubit.state.active, active);
          expect(
            cubit.state.access(cubit.state.activeProgram!),
            ProgramAccess.locked,
          );
          verifyNever(() => repository.updateActiveProgram(any(), any()));
        },
      );

      blocTest<ProgramListCubit, ProgramListState>(
        'waits while premium is unknown',
        build: build,
        act: (cubit) async {
          await readyWith(null);
          await cubit.resolveMissed(MissedDayChoice.skip);
        },
        verify: (cubit) {
          expect(
            cubit.state.access(cubit.state.activeProgram!),
            ProgramAccess.waiting,
          );
          verifyNever(() => repository.updateActiveProgram(any(), any()));
        },
      );

      blocTest<ProgramListCubit, ProgramListState>(
        'opens again with premium',
        build: build,
        act: (cubit) async {
          await readyWith(false);
          premium.controller.add(true);
          await pumpEventQueue();
          await cubit.resolveMissed(MissedDayChoice.skip);
        },
        verify: (cubit) {
          expect(
            cubit.state.access(cubit.state.activeProgram!),
            ProgramAccess.open,
          );
          verify(() => repository.updateActiveProgram('u1', any())).called(1);
        },
      );
    });
  });

  blocTest<ProgramListCubit, ProgramListState>(
    'a user change clears the previous user\'s notices',
    build: build,
    act: (_) async {
      await signIn(member);
      rejected.add(const PermissionFailure());
      await pumpEventQueue();
      await signIn(guest);
    },
    verify: (cubit) => expect(cubit.state, const ProgramListState()),
  );
}
