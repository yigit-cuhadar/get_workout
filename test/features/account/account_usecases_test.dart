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
    when(() => telemetry.forget()).thenAnswer((_) async => const Ok(null));
    when(() => telemetry.apply(any())).thenAnswer((_) async => const Ok(null));
  });

  group('DeleteUserAccount', () {
    DeleteUserAccount delete() => DeleteUserAccount(account, local, telemetry);

    test('clears the device only after the server deleted', () async {
      expect((await delete()('u1')).isOk, isTrue);
      verifyInOrder([
        () => account.deleteAccount(),
        () => local.clear('u1'),
        () => telemetry.forget(),
      ]);
    });

    test('a server failure keeps everything on the device', () async {
      when(() => account.deleteAccount())
          .thenAnswer((_) async => const Err(NetworkFailure()));
      expect((await delete()('u1')).failureOrNull, isA<NetworkFailure>());
      verifyNever(() => local.clear(any()));
      verifyNever(() => telemetry.forget());
    });

    test('a local leftover does not undo a done deletion', () async {
      when(() => local.clear(any()))
          .thenAnswer((_) async => const Err(UnknownFailure()));
      when(() => telemetry.forget())
          .thenAnswer((_) async => const Err(UnknownFailure()));
      expect((await delete()('u1')).isOk, isTrue);
    });
  });

  group('ApplyAnalyticsConsent', () {
    test('not answered collects nothing', () async {
      await ApplyAnalyticsConsent(telemetry)(null);
      verify(() => telemetry.apply(false)).called(1);
    });

    test('an answer is applied as given', () async {
      await ApplyAnalyticsConsent(telemetry)(true);
      await ApplyAnalyticsConsent(telemetry)(false);
      verifyInOrder([
        () => telemetry.apply(true),
        () => telemetry.apply(false),
      ]);
    });
  });
}
