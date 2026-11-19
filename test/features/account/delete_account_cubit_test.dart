import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/account/domain/account_repository.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
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
  const closedSheet = AuthFailure('closed', code: cancelledCode);
  const otherAccount = AuthFailure('mismatch', code: 'user-mismatch');

  late MockAuthRepository auth;
  late MockAccountRepository account;
  late MockLocalAccountData local;
  late MockTelemetry telemetry;
  late DeletionUnderway underway;

  /// What the workout in progress was told, in order.
  late List<String> workouts;

  /// Whether the router was held at each server call.
  late List<bool> heldAtCall;

  setUpAll(() => registerFallbackValue(SocialProvider.google));

  setUp(() {
    auth = MockAuthRepository();
    account = MockAccountRepository();
    local = MockLocalAccountData();
    telemetry = MockTelemetry();
    underway = DeletionUnderway();
    workouts = [];
    heldAtCall = [];
    when(() => auth.currentUser).thenReturn(member);
    when(() => account.deleteAccount(appleCode: any(named: 'appleCode')))
        .thenAnswer((_) async {
          heldAtCall.add(underway.value);
          return const Ok(null);
        });
    when(() => auth.reauthenticate(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => auth.reauthenticateWithProvider(any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => account.signOut()).thenAnswer((_) async => const Ok(null));
    when(() => local.clear(any())).thenAnswer((_) async => const Ok(null));
    when(() => local.holdWrites(any())).thenAnswer((_) async {});
    when(() => local.releaseWrites(any())).thenAnswer((_) async {});
    when(() => telemetry.forget(any())).thenAnswer((_) async => const Ok(null));
  });

  DeleteAccountCubit build() => DeleteAccountCubit(
    getCurrentUser: GetCurrentUser(auth),
    deleteAccount: DeleteUserAccount(account, local, telemetry),
    reauthenticate: Reauthenticate(auth),
    reauthenticateWithProvider: ReauthenticateWithProvider(auth),
    reauthenticateWithAppleCode: ReauthenticateWithAppleCode(auth),
    underway: underway,
    releaseWorkouts: (uid) async => workouts.add('release $uid'),
    resumeWorkouts: () async => workouts.add('resume'),
  );

  void failWith(Failure failure) =>
      when(() => account.deleteAccount(appleCode: any(named: 'appleCode')))
          .thenAnswer((_) async => Err(failure));

  const deleting = DeleteAccountState(DeleteStatus.deleting);
  const needsSignIn = DeleteAccountState(DeleteStatus.needsSignIn);
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
    expect: () => [deleting, needsSignIn, deleting, done],
    verify: (_) {
      verify(() => auth.reauthenticate('secret')).called(1);
      verify(() => account.deleteAccount()).called(2);
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'a wrong password asks again and deletes nothing',
    setUp: () {
      failWith(recentLogin);
      when(() => auth.reauthenticate(any()))
          .thenAnswer((_) async => const Err(wrongPassword));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      await cubit.confirmPassword('nope');
    },
    expect: () => [
      deleting,
      needsSignIn,
      deleting,
      const DeleteAccountState(
        DeleteStatus.needsSignIn,
        failure: wrongPassword,
      ),
    ],
    verify: (_) => verify(() => account.deleteAccount()).called(1),
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'signs in again with a provider when the sign-in is too old, then '
    'deletes',
    setUp: () {
      final answers = [const Err<void>(recentLogin), const Ok<void>(null)];
      when(() => account.deleteAccount())
          .thenAnswer((_) async => answers.removeAt(0));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      await cubit.confirmWithProvider(SocialProvider.google);
    },
    expect: () => [deleting, needsSignIn, deleting, done],
    verify: (_) {
      verify(() => auth.reauthenticateWithProvider(SocialProvider.google))
          .called(1);
      verify(() => account.deleteAccount()).called(2);
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'signing in again with Apple deletes with its fresh code',
    setUp: () {
      final answers = [const Err<void>(recentLogin), const Ok<void>(null)];
      when(() => account.deleteAccount(appleCode: any(named: 'appleCode')))
          .thenAnswer((_) async => answers.removeAt(0));
      when(() => auth.reauthenticateWithAppleCode())
          .thenAnswer((_) async => const Ok('code-1'));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      await cubit.confirmWithProvider(SocialProvider.apple);
    },
    expect: () => [deleting, needsSignIn, deleting, done],
    verify: (_) {
      verify(() => account.deleteAccount(appleCode: 'code-1')).called(1);
      verifyNever(() => auth.reauthenticateWithProvider(any()));
    },
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'a closed provider sheet asks again, says nothing and deletes nothing',
    setUp: () {
      failWith(recentLogin);
      when(() => auth.reauthenticateWithProvider(any()))
          .thenAnswer((_) async => const Err(closedSheet));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      await cubit.confirmWithProvider(SocialProvider.google);
    },
    expect: () => [deleting, needsSignIn, deleting, needsSignIn],
    verify: (_) => verify(() => account.deleteAccount()).called(1),
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'another account at the provider asks again with the failure',
    setUp: () {
      failWith(recentLogin);
      when(() => auth.reauthenticateWithProvider(any()))
          .thenAnswer((_) async => const Err(otherAccount));
    },
    build: build,
    act: (cubit) async {
      await cubit.delete();
      await cubit.confirmWithProvider(SocialProvider.google);
    },
    expect: () => [
      deleting,
      needsSignIn,
      deleting,
      const DeleteAccountState(DeleteStatus.needsSignIn, failure: otherAccount),
    ],
    verify: (_) => verify(() => account.deleteAccount()).called(1),
  );

  blocTest<DeleteAccountCubit, DeleteAccountState>(
    'cancelling the sign-in prompt goes back without deleting',
    setUp: () => failWith(recentLogin),
    build: build,
    act: (cubit) async {
      await cubit.delete();
      cubit.cancel();
    },
    expect: () => [
      deleting,
      needsSignIn,
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

  group('deleteWithApple', () {
    setUp(
      () =>
          when(() => auth.reauthenticateWithAppleCode())
              .thenAnswer((_) async => const Ok('code-1')),
    );

    blocTest<DeleteAccountCubit, DeleteAccountState>(
      'signs in again with Apple, then deletes with its code for the server '
      'to revoke',
      build: build,
      act: (cubit) => cubit.deleteWithApple(),
      expect: () => [deleting, done],
      verify: (_) {
        verifyInOrder([
          () => auth.reauthenticateWithAppleCode(),
          () => account.deleteAccount(appleCode: 'code-1'),
        ]);
      },
    );

    blocTest<DeleteAccountCubit, DeleteAccountState>(
      'a closed Apple sheet deletes nothing and says nothing',
      setUp: () => when(() => auth.reauthenticateWithAppleCode()).thenAnswer(
        (_) async => const Err(AuthFailure('closed', code: cancelledCode)),
      ),
      build: build,
      act: (cubit) => cubit.deleteWithApple(),
      expect: () => [deleting, const DeleteAccountState(DeleteStatus.idle)],
      verify: (_) => verifyNever(
        () => account.deleteAccount(appleCode: any(named: 'appleCode')),
      ),
    );

    blocTest<DeleteAccountCubit, DeleteAccountState>(
      'a failed Apple sign-in deletes nothing and fails',
      setUp: () => when(() => auth.reauthenticateWithAppleCode()).thenAnswer(
        (_) async => const Err(AuthFailure('other', code: 'user-mismatch')),
      ),
      build: build,
      act: (cubit) => cubit.deleteWithApple(),
      expect: () => [
        deleting,
        isA<DeleteAccountState>()
            .having((s) => s.status, 'status', DeleteStatus.failed)
            .having((s) => s.failure, 'failure', isA<AppleRevokeFailure>()),
      ],
      verify: (_) => verifyNever(
        () => account.deleteAccount(appleCode: any(named: 'appleCode')),
      ),
    );

    blocTest<DeleteAccountCubit, DeleteAccountState>(
      'Apple refusing the revocation fails with nothing deleted',
      setUp: () => failWith(const AppleNotRevokedFailure()),
      build: build,
      act: (cubit) => cubit.deleteWithApple(),
      expect: () => [
        deleting,
        const DeleteAccountState(
          DeleteStatus.failed,
          failure: AppleNotRevokedFailure(),
        ),
      ],
      verify: (_) {
        expect(workouts, ['release u1', 'resume']);
        verifyNever(() => local.clear(any()));
      },
    );
  });
}
