import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/account/data/callable_account_repository.dart';
import 'package:get_workout/features/account/domain/account_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockFunctions extends Mock implements FirebaseFunctions {}

class MockCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock implements HttpsCallableResult<void> {}

class MockAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockUserCredential extends Mock implements UserCredential {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, [String message = 'error'])
    : super(code: code, message: message);
}

void main() {
  late MockFunctions functions;
  late MockCallable callable;
  late MockAuth auth;
  late MockUser user;
  late CallableAccountRepository repository;

  setUpAll(
    () => registerFallbackValue(
      EmailAuthProvider.credential(email: 'x', password: 'y'),
    ),
  );

  setUp(() {
    functions = MockFunctions();
    callable = MockCallable();
    auth = MockAuth();
    user = MockUser();
    repository = CallableAccountRepository(functions, auth);
    when(() => functions.httpsCallable('deleteAccount')).thenReturn(callable);
    when(() => callable.call<void>())
        .thenAnswer((_) async => MockCallableResult());
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.email).thenReturn('a@b.co');
    when(() => user.reauthenticateWithCredential(any()))
        .thenAnswer((_) async => MockUserCredential());
  });

  group('deleteAccount', () {
    test('calls the function, then signs out here', () async {
      expect((await repository.deleteAccount()).isOk, isTrue);
      verifyInOrder([() => callable.call<void>(), () => auth.signOut()]);
    });

    test('a function that is not deployed is unavailable, not done', () async {
      when(() => callable.call<void>()).thenThrow(FunctionsError('not-found'));
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<DeletionUnavailableFailure>(),
      );
      verifyNever(() => auth.signOut());
    });

    test('a sign-in too old asks for a recent one', () async {
      when(() => callable.call<void>()).thenThrow(
        FunctionsError('failed-precondition', recentLoginRequiredCode),
      );
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          recentLoginRequiredCode,
        ),
      );
    });

    test('other errors map as Firebase errors', () async {
      when(() => callable.call<void>())
          .thenThrow(FunctionsError('unavailable'));
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<NetworkFailure>(),
      );
      when(() => callable.call<void>())
          .thenThrow(FunctionsError('failed-precondition', 'something else'));
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<UnknownFailure>(),
      );
    });
  });

  group('reauthenticate', () {
    test('signs in again with the email and password', () async {
      expect((await repository.reauthenticate('secret')).isOk, isTrue);
      final credential =
          verify(() => user.reauthenticateWithCredential(captureAny()))
                  .captured
                  .single
              as AuthCredential;
      expect(credential.providerId, 'password');
    });

    test('fails without an email user', () async {
      when(() => user.email).thenReturn(null);
      expect(
        (await repository.reauthenticate('secret')).failureOrNull,
        isA<AuthFailure>(),
      );
      verifyNever(() => user.reauthenticateWithCredential(any()));
    });

    test('a wrong password is an auth failure', () async {
      when(() => user.reauthenticateWithCredential(any()))
          .thenThrow(FirebaseAuthException(code: 'invalid-credential'));
      expect(
        (await repository.reauthenticate('nope')).failureOrNull,
        isA<AuthFailure>().having((f) => f.code, 'code', 'invalid-credential'),
      );
    });
  });
}
