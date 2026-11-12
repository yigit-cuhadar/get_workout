import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/account/domain/account_repository.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
import 'package:get_workout/features/account/domain/consent_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockAccountRepository extends Mock implements AccountRepository {}

class MockLocalAccountData extends Mock implements LocalAccountData {}

class MockTelemetry extends Mock implements Telemetry {}

void main() {
  late MockAccountRepository account;
  late MockLocalAccountData local;
  late MockTelemetry telemetry;

  setUp(() {
    account = MockAccountRepository();
    local = MockLocalAccountData();
    telemetry = MockTelemetry();
    when(() => account.deleteAccount()).thenAnswer((_) async => const Ok(null));
    when(() => local.clear(any())).thenAnswer((_) async => const Ok(null));
    when(() => local.holdWrites(any())).thenAnswer((_) async {});
    when(() => local.releaseWrites(any())).thenAnswer((_) async {});
    when(() => telemetry.forget(any())).thenAnswer((_) async => const Ok(null));
  });

  group('DeleteUserAccount', () {
    DeleteUserAccount delete() => DeleteUserAccount(account, local, telemetry);

    setUp(
      () =>
          when(() => account.signOut()).thenAnswer((_) async => const Ok(null)),
    );

    test('clears the device while still signed in, then signs out', () async {
      expect((await delete()('u1')).isOk, isTrue);
      verifyInOrder([
        () => local.holdWrites('u1'),
        () => account.deleteAccount(),
        () => local.clear('u1'),
        () => telemetry.forget('u1'),
        () => account.signOut(),
      ]);
    });

    test('a server failure keeps everything and stays signed in', () async {
      when(() => account.deleteAccount())
          .thenAnswer((_) async => const Err(NetworkFailure()));
      expect((await delete()('u1')).failureOrNull, isA<NetworkFailure>());
      verifyNever(() => local.clear(any()));
      verifyNever(() => telemetry.forget(any()));
      verifyNever(() => account.signOut());
      verifyInOrder([
        () => local.holdWrites('u1'),
        () => account.deleteAccount(),
        () => local.releaseWrites('u1'),
      ]);
    });

    test('data gone but the sign-in left: the device is cleared, the user '
        'stays signed in to finish', () async {
      when(() => account.deleteAccount())
          .thenAnswer((_) async => const Err(PartlyDeletedFailure()));
      expect((await delete()('u1')).failureOrNull, isA<PartlyDeletedFailure>());
      verify(() => local.clear('u1')).called(1);
      verify(() => telemetry.forget('u1')).called(1);
      verifyNever(() => account.signOut());
      verifyNever(() => local.releaseWrites(any()));
    });

    test('a local leftover does not undo a done deletion', () async {
      when(() => local.clear(any()))
          .thenAnswer((_) async => const Err(UnknownFailure()));
      when(() => telemetry.forget(any()))
          .thenAnswer((_) async => const Err(UnknownFailure()));
      expect((await delete()('u1')).isOk, isTrue);
      verify(() => account.signOut()).called(1);
    });
  });
}
