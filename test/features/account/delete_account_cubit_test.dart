import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/account/domain/account_repository.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
import 'package:get_workout/features/account/domain/consent_repository.dart';
import 'package:get_workout/features/account/presentation/delete_account_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockAccountRepository extends Mock implements AccountRepository {}

class MockLocalAccountData extends Mock implements LocalAccountData {}

class MockTelemetry extends Mock implements Telemetry {}

void main() {
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  const recentLogin = AuthFailure(
    recentLoginRequiredCode,
    code: recentLoginRequiredCode,
  );
  const wrongPassword = AuthFailure('wrong', code: 'invalid-credential');

  late MockAuthRepository auth;
  late MockAccountRepository account;
  late MockLocalAccountData local;
  late MockTelemetry telemetry;
  late DeletionUnderway underway;

  /// What the workout in progress was told, in order.
  late List<String> workouts;

  /// Whether the router was held at each server call.
  late List<bool> heldAtCall;

  setUp(() {
    auth = MockAuthRepository();
    account = MockAccountRepository();
    local = MockLocalAccountData();
    telemetry = MockTelemetry();
    underway = DeletionUnderway();
    workouts = [];
    heldAtCall = [];
    when(() => auth.currentUser).thenReturn(member);
    when(() => account.deleteAccount()).thenAnswer((_) async {
      heldAtCall.add(underway.value);
      return const Ok(null);
    });
    when(() => account.reauthenticate(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => account.signOut()).thenAnswer((_) async => const Ok(null));
    when(() => local.clear(any())).thenAnswer((_) async => const Ok(null));
    when(() => telemetry.forget(any())).thenAnswer((_) async => const Ok(null));
  });

  DeleteAccountCubit build() => DeleteAccountCubit(
    getCurrentUser: GetCurrentUser(auth),
    deleteAccount: DeleteUserAccount(account, local, telemetry),
    reauthenticate: Reauthenticate(account),
    underway: underway,
    releaseWorkouts: (uid) async => workouts.add('release $uid'),
    resumeWorkouts: () async => workouts.add('resume'),
  );

  void failWith(Failure failure) =>
      when(() => account.deleteAccount()).thenAnswer((_) async => Err(failure));

  const deleting = DeleteAccountState(DeleteStatus.deleting);
  const needsPassword = DeleteAccountState(DeleteStatus.needsPassword);
  const done = DeleteAccountState(DeleteStatus.done);

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'stops the workout from writing, deletes, clears the device, signs out',
    build: build,
    act: (cubit) => cubit.delete(),
    expect: () => [deleting, done],
    verify: (_) {
      expect(workouts, ['release u1']);
      expect(heldAtCall, [true]);
      expect(underway.value, isFalse);
      verifyInOrder([() => local.clear('u1'), () => account.signOut()]);
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'says so when the server cannot delete, and gives everything back',
    setUp: () => failWith(const DeletionUnavailableFailure()),
    build: build,
    act: (cubit) => cubit.delete(),
    expect: () => [
      deleting,
      const DeleteAccountState(
        DeleteStatus.failed,
        failure: DeletionUnavailableFailure(),
      ),
    ],
    verify: (_) {
      expect(workouts, ['release u1', 'resume']);
      expect(underway.value, isFalse);
      verifyNever(() => local.clear(any()));
      verifyNever(() => account.signOut());
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'offline fails before anything is deleted',
    setUp: () => failWith(const NetworkFailure()),
    build: build,
    act: (cubit) => cubit.delete(),
    expect: () => [
      deleting,
      const DeleteAccountState(DeleteStatus.failed, failure: NetworkFailure()),
    ],
    verify: (_) => verifyNever(() => local.clear(any())),
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'with only the sign-in left, the user stays held on the page and '
    'finishes on retry',
    setUp: () {
      final answers = [
        const Err<void>(PartlyDeletedFailure()),
        const Ok<void>(null),
      ];
      when(() => account.deleteAccount())
          .thenAnswer((_) async => answers.removeAt(0));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      expect(underway.value, isTrue);
      verifyNever(() => account.signOut());
      await cubit.delete();
    },
    expect: () => [
      deleting,
      const DeleteAccountState(
        DeleteStatus.partlyDeleted,
        failure: PartlyDeletedFailure(),
      ),
      deleting,
      done,
    ],
    verify: (_) {
      expect(underway.value, isFalse);
      verify(() => account.signOut()).called(1);
      // The workout never comes back for a user whose data is gone.
      expect(workouts, isNot(contains('resume')));
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'asks for the password when the sign-in is too old, then deletes',
    setUp: () {
      final answers = [const Err<void>(recentLogin), const Ok<void>(null)];
      when(() => account.deleteAccount())
          .thenAnswer((_) async => answers.removeAt(0));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      await cubit.confirmPassword('secret');
    },
    expect: () => [deleting, needsPassword, deleting, done],
    verify: (_) {
      verify(() => account.reauthenticate('secret')).called(1);
      verify(() => account.deleteAccount()).called(2);
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'a wrong password asks again and deletes nothing',
    setUp: () {
      failWith(recentLogin);
      when(() => account.reauthenticate(any()))
          .thenAnswer((_) async => const Err(wrongPassword));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      await cubit.confirmPassword('nope');
    },
    expect: () => [
      deleting,
      needsPassword,
      deleting,
      const DeleteAccountState(
        DeleteStatus.needsPassword,
        failure: wrongPassword,
      ),
    ],
    verify: (_) => verify(() => account.deleteAccount()).called(1),
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'cancelling the password prompt goes back without deleting',
    setUp: () => failWith(recentLogin),
    build: build,
    act: (cubit) async {
      await cubit.delete();
      cubit.cancel();
    },
    expect: () => [
      deleting,
      needsPassword,
      const DeleteAccountState(DeleteStatus.idle),
    ],
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'a second tap while deleting, or after it is done, is ignored',
    build: build,
    act: (cubit) async {
      await Future.wait([cubit.delete(), cubit.delete()]);
      await cubit.delete();
    },
    expect: () => [deleting, done],
    verify: (_) => verify(() => account.deleteAccount()).called(1),
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'fails without a signed-in user',
    setUp: () => when(() => auth.currentUser).thenReturn(null),
    build: build,
    act: (cubit) => cubit.delete(),
    expect: () => [
      deleting,
      isA<DeleteAccountState>()
          .having((s) => s.status, 'status', DeleteStatus.failed)
          .having((s) => s.failure, 'failure', isA<AuthFailure>()),
    ],
    verify: (_) {
      verifyNever(() => account.deleteAccount());
      expect(underway.value, isFalse);
    },
  );
}
