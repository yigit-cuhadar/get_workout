import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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

class MockFirestore extends Mock implements FirebaseFirestore {}

class MockUser extends Mock implements User {}

class MockUserCredential extends Mock implements UserCredential {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, {String? reason})
    : super(
        code: code,
        message: 'error',
        details: reason == null ? null : {'reason': reason},
      );
}

void main() {
  late MockFunctions functions;
  late MockCallable callable;
  late MockAuth auth;
  late MockUser user;
  late MockFirestore firestore;
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
    firestore = MockFirestore();
    repository = CallableAccountRepository(
      functions,
      auth,
      firestore,
      pendingWritesWait: const Duration(milliseconds: 50),
    );
    when(() => firestore.waitForPendingWrites()).thenAnswer((_) async {});
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
    test('sends pending writes, then calls the function', () async {
      expect((await repository.deleteAccount()).isOk, isTrue);
      verifyInOrder([
        () => firestore.waitForPendingWrites(),
        () => callable.call<void>(),
      ]);
      verifyNever(() => auth.signOut());
    });

    test('offline, nothing is asked of the server', () async {
      when(() => firestore.waitForPendingWrites())
          .thenAnswer((_) => Completer<void>().future);
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<NetworkFailure>(),
      );
      verifyNever(() => callable.call<void>());
    });

    test('a function not deployed or not callable is unavailable', () async {
      for (final code in ['not-found', 'permission-denied']) {
        when(() => callable.call<void>()).thenThrow(FunctionsError(code));
        expect(
          (await repository.deleteAccount()).failureOrNull,
          isA<DeletionUnavailableFailure>(),
        );
      }
    });

    test('the reason in the details decides, not the message', () async {
      when(() => callable.call<void>()).thenThrow(
        FunctionsError('failed-precondition', reason: 'recent-sign-in'),
      );
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<AuthFailure>().having(
          (f) => f.code,
          'code',
          recentLoginRequiredCode,
        ),
      );
      when(() => callable.call<void>())
          .thenThrow(FunctionsError('internal', reason: 'sign-in-not-deleted'));
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<PartlyDeletedFailure>(),
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
          .thenThrow(FunctionsError('failed-precondition'));
      expect(
        (await repository.deleteAccount()).failureOrNull,
        isA<UnknownFailure>(),
      );
    });
  });

  test('signs out', () async {
    expect((await repository.signOut()).isOk, isTrue);
    verify(() => auth.signOut()).called(1);
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
