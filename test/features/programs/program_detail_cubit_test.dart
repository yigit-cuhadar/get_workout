import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/programs/data/no_completed_days.dart';
import 'package:get_workout/features/programs/data/no_premium.dart';
import 'package:get_workout/features/programs/domain/active_program.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/programs/domain/program_repository.dart';
import 'package:get_workout/features/programs/domain/program_usecases.dart';
import 'package:get_workout/features/programs/presentation/program_detail_cubit.dart';
import 'package:get_workout/features/programs/presentation/program_list_cubit.dart';
import 'package:mocktail/mocktail.dart';

import 'fixtures.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockProgramRepository extends Mock implements ProgramRepository {}

String copyOf(String name) => '$name (copy)';

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  // Wednesday 11 November 2026.
  final now = DateTime(2026, 11, 11, 9);
  final upperLower = program(id: 'p1');
  final arms = program(id: 'p2', name: 'Arms');
  final armsActive = ActiveProgram(
    programId: 'p2',
    weekdays: const [2, 5],
    nextDayIndex: 0,
    nextDate: CalendarDate(2026, 11, 13),
    startedAt: DateTime(2026, 11, 2),
  );

  late MockAuthRepository auth;
  late MockProgramRepository repository;
  late StreamController<AuthUser?> users;
  late StreamController<ActiveProgram?> active;
  late ProgramListCubit list;

  setUpAll(() {
    registerFallbackValue(upperLower);
    registerFallbackValue(armsActive);
  });

  setUp(() async {
    auth = MockAuthRepository();
    repository = MockProgramRepository();
    users = StreamController<AuthUser?>.broadcast();
    active = StreamController<ActiveProgram?>();
    when(() => auth.currentUser).thenReturn(member);
    // Like Firebase, the current user arrives on subscription.
    Stream<AuthUser?> watchUser() async* {
      yield member;
      yield* users.stream;
    }

    when(() => auth.watchUser()).thenAnswer((_) => watchUser());
    when(() => repository.watchPrograms(any()))
        .thenAnswer((_) => const Stream.empty());
    when(() => repository.watchActiveProgram(any()))
        .thenAnswer((_) => const Stream.empty());
    when(() => repository.watchPrograms('u1'))
        .thenAnswer((_) => Stream.value([arms, upperLower]));
    when(() => repository.watchActiveProgram('u1'))
        .thenAnswer((_) => active.stream);
    when(() => repository.rejectedWrites)
        .thenAnswer((_) => const Stream.empty());
    when(() => repository.startProgram(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.updateActiveProgram(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.stopProgram(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => repository.createProgram(any(), any()))
        .thenAnswer((_) async => const Ok('copy'));
    when(
      () => repository.deleteProgram(
        any(),
        any(),
        clearActive: any(named: 'clearActive'),
      ),
    ).thenAnswer((_) async => const Ok(null));
    list = ProgramListCubit(
      watchAuthUser: WatchAuthUser(auth),
      watchPrograms: WatchPrograms(repository),
      watchActiveProgram: WatchActiveProgram(repository),
      watchCompletedDays: const WatchCompletedDays(NoCompletedDays()),
      watchRejectedWrites: WatchRejectedProgramWrites(repository),
      resolveMissedDay: ResolveMissedDay(repository),
      watchPremium: const WatchPremium(NoPremium()),
      clock: () => now,
    );
  });

  tearDown(() => list.close());

  Future<void> activeIs(ActiveProgram? value) async {
    active.add(value);
    await pumpEventQueue();
  }

  ProgramDetailCubit build([String id = 'p1']) => ProgramDetailCubit(
    id,
    list: list,
    startProgram: StartProgram(repository, clock: () => now),
    changeWeekdays: ChangeWeekdays(repository, clock: () => now),
    stopProgram: StopProgram(repository),
    duplicateProgram: DuplicateProgram(repository),
    deleteProgram: DeleteProgram(repository),
    getCurrentUser: GetCurrentUser(auth),
    watchAuthUser: WatchAuthUser(auth),
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'starts the program on the chosen weekdays, replacing any other',
    setUp: () => activeIs(armsActive),
    build: build,
    act: (cubit) => cubit.start(const [1, 3]),
    expect: () => const [
      ProgramDetailState(status: ProgramDetailStatus.working),
      ProgramDetailState(),
    ],
    verify: (_) => verify(
      () => repository.startProgram(
        'u1',
        ActiveProgram(
          programId: 'p1',
          weekdays: const [1, 3],
          nextDayIndex: 0,
          nextDate: CalendarDate(2026, 11, 11),
          startedAt: now,
        ),
      ),
    ).called(1),
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'refuses weekdays that do not match the days',
    setUp: () => activeIs(null),
    build: build,
    act: (cubit) => cubit.start(const [1, 3, 5]),
    expect: () => [
      const ProgramDetailState(status: ProgramDetailStatus.working),
      isA<ProgramDetailState>()
          .having((s) => s.status, 'status', ProgramDetailStatus.failed)
          .having((s) => s.failure, 'failure', isA<ValidationFailure>()),
    ],
    verify: (_) => verifyNever(() => repository.startProgram(any(), any())),
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'stops and moves only the active program',
    setUp: () => activeIs(armsActive),
    build: () => build('p2'),
    act: (cubit) async {
      await cubit.changeWeekdays(const [1, 4]);
      await cubit.stop();
    },
    verify: (_) {
      verify(
        () => repository.updateActiveProgram(
          'u1',
          armsActive.copyWith(
            weekdays: const [1, 4],
            nextDate: CalendarDate(2026, 11, 12),
          ),
        ),
      ).called(1);
      verify(() => repository.stopProgram('u1')).called(1);
    },
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'stop and change weekdays do nothing for an inactive program',
    setUp: () => activeIs(armsActive),
    build: build,
    act: (cubit) async {
      await cubit.stop();
      await cubit.changeWeekdays(const [1, 4]);
    },
    expect: () => const <ProgramDetailState>[],
    verify: (_) {
      verifyNever(() => repository.stopProgram(any()));
      verifyNever(() => repository.updateActiveProgram(any(), any()));
    },
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'a duplicate is stored as the user\'s own and opened',
    setUp: () => activeIs(null),
    build: build,
    act: (cubit) => cubit.duplicate(copyOf),
    expect: () => const [
      ProgramDetailState(status: ProgramDetailStatus.working),
      ProgramDetailState(
        status: ProgramDetailStatus.duplicated,
        copyId: 'copy',
      ),
    ],
    verify: (_) => verify(
      () => repository.createProgram('u1', upperLower.duplicate(copyOf)),
    ).called(1),
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'deleting the active program also stops it',
    setUp: () => activeIs(armsActive),
    build: () => build('p2'),
    act: (cubit) => cubit.delete(),
    expect: () => const [
      ProgramDetailState(status: ProgramDetailStatus.working),
      ProgramDetailState(status: ProgramDetailStatus.deleted),
    ],
    verify: (_) =>
        verify(() => repository.deleteProgram('u1', 'p2', clearActive: true))
            .called(1),
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'deleting another program leaves the active one',
    setUp: () => activeIs(armsActive),
    build: build,
    act: (cubit) => cubit.delete(),
    verify: (_) =>
        verify(() => repository.deleteProgram('u1', 'p1', clearActive: false))
            .called(1),
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'a failed action is reported',
    setUp: () async {
      await activeIs(null);
      when(
        () => repository.deleteProgram(
          any(),
          any(),
          clearActive: any(named: 'clearActive'),
        ),
      ).thenAnswer((_) async => const Err(NetworkFailure()));
    },
    build: build,
    act: (cubit) => cubit.delete(),
    expect: () => const [
      ProgramDetailState(status: ProgramDetailStatus.working),
      ProgramDetailState(
        status: ProgramDetailStatus.failed,
        failure: NetworkFailure(),
      ),
    ],
  );

  blocTest<ProgramDetailCubit, ProgramDetailState>(
    'closes when the user changes and then does nothing',
    setUp: () => activeIs(null),
    build: build,
    act: (cubit) async {
      await pumpEventQueue();
      when(() => auth.currentUser).thenReturn(null);
      users.add(const AuthUser(id: 'g2', isAnonymous: true));
      await pumpEventQueue();
      await cubit.start(const [1, 4]);
    },
    expect: () => const [
      ProgramDetailState(status: ProgramDetailStatus.closed),
    ],
    verify: (_) => verifyNever(() => repository.startProgram(any(), any())),
  );
}
