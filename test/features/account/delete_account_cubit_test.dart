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

  setUp(() {
    auth = MockAuthRepository();
    account = MockAccountRepository();
    local = MockLocalAccountData();
    telemetry = MockTelemetry();
    when(() => auth.currentUser).thenReturn(member);
    when(() => account.deleteAccount()).thenAnswer((_) async => const Ok(null));
    when(() => account.reauthenticate(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => local.clear(any())).thenAnswer((_) async => const Ok(null));
    when(() => telemetry.forget()).thenAnswer((_) async => const Ok(null));
  });

  DeleteAccountCubit build() => DeleteAccountCubit(
    getCurrentUser: GetCurrentUser(auth),
    deleteAccount: DeleteUserAccount(account, local, telemetry),
    reauthenticate: Reauthenticate(account),
  );

  const deleting = DeleteAccountState(DeleteStatus.deleting);
  const needsPassword = DeleteAccountState(DeleteStatus.needsPassword);

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'deletes the signed-in user and what the device keeps of them',
    build: build,
    act: (cubit) => cubit.delete(),
    expect: () => [deleting, const DeleteAccountState(DeleteStatus.done)],
    verify: (_) => verify(() => local.clear('u1')).called(1),
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'says so when the server cannot delete yet, and keeps everything',
    setUp: () =>
        when(() => account.deleteAccount())
            .thenAnswer((_) async => const Err(DeletionUnavailableFailure())),
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
      verifyNever(() => local.clear(any()));
      verifyNever(() => telemetry.forget());
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
    expect: () => [
      deleting,
      needsPassword,
      deleting,
      const DeleteAccountState(DeleteStatus.done),
    ],
    verify: (_) {
      verify(() => account.reauthenticate('secret')).called(1);
      verify(() => account.deleteAccount()).called(2);
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'a wrong password asks again and deletes nothing',
    setUp: () {
      when(() => account.deleteAccount())
          .thenAnswer((_) async => const Err(recentLogin));
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
    setUp: () =>
        when(() => account.deleteAccount())
            .thenAnswer((_) async => const Err(recentLogin)),
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
    'a second tap while deleting is ignored',
    build: build,
    act: (cubit) async {
      await Future.wait([cubit.delete(), cubit.delete()]);
    },
    expect: () => [deleting, const DeleteAccountState(DeleteStatus.done)],
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
    verify: (_) => verifyNever(() => account.deleteAccount()),
  );
}
