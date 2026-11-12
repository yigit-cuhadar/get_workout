import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
import 'package:get_workout/features/account/domain/consent_repository.dart';
import 'package:get_workout/features/account/presentation/consent_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockConsentRepository extends Mock implements ConsentRepository {}

class MockTelemetry extends Mock implements Telemetry {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');

  late MockAuthRepository auth;
  late MockConsentRepository consents;
  late MockTelemetry telemetry;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<bool?>> stored;

  setUp(() {
    auth = MockAuthRepository();
    consents = MockConsentRepository();
    telemetry = MockTelemetry();
    users = StreamController<AuthUser?>();
    stored = {};
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => consents.watchConsent(any())).thenAnswer(
      (call) => stored
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<bool?>.new,
          )
          .stream,
    );
    when(() => consents.saveConsent(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => telemetry.apply(any())).thenAnswer((_) async => const Ok(null));
  });

  ConsentCubit build() => ConsentCubit(
    watchAuthUser: WatchAuthUser(auth),
    watchConsent: WatchAnalyticsConsent(consents),
    saveConsent: SaveAnalyticsConsent(consents),
    applyConsent: ApplyAnalyticsConsent(telemetry),
  );

  test('applies nothing before a user answer is read', () async {
    final cubit = build();
    users.add(guest);
    await pumpEventQueue();
    expect(cubit.state, const ConsentState());
    verifyNever(() => telemetry.apply(any()));
    await cubit.close();
  });

  blocTest<ConsentCubit, ConsentState>(
    'a guest who has not answered is asked and collects nothing',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add(null);
      await pumpEventQueue();
    },
    expect: () => [const ConsentState(loaded: true)],
    verify: (cubit) {
      expect(cubit.state.unanswered, isTrue);
      verify(() => telemetry.apply(false)).called(1);
    },
  );

  blocTest<ConsentCubit, ConsentState>(
    'applies every change of the answer, once each',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      for (final consent in [true, true, false]) {
        stored['u1']!.add(consent);
        await pumpEventQueue();
      }
    },
    expect: () => [
      const ConsentState(loaded: true, consent: true),
      const ConsentState(loaded: true, consent: false),
    ],
    verify: (_) {
      verifyInOrder([
        () => telemetry.apply(true),
        () => telemetry.apply(false),
      ]);
      verifyNoMoreInteractions(telemetry);
    },
  );

  blocTest<ConsentCubit, ConsentState>(
    'follows whoever is signed in, never the previous user',
    build: build,
    act: (_) async {
      users.add(member);
      await pumpEventQueue();
      stored['u1']!.add(true);
      await pumpEventQueue();
      users.add(guest);
      await pumpEventQueue();
      stored['u1']!.add(false);
      await pumpEventQueue();
      stored['g1']!.add(null);
      await pumpEventQueue();
    },
    expect: () => [
      const ConsentState(loaded: true, consent: true),
      const ConsentState(),
      const ConsentState(loaded: true),
    ],
    verify: (_) {
      verifyInOrder([
        () => telemetry.apply(true),
        () => telemetry.apply(false),
      ]);
      verifyNoMoreInteractions(telemetry);
    },
  );

  blocTest<ConsentCubit, ConsentState>(
    'an answer is saved for the signed-in user',
    build: build,
    act: (cubit) async {
      users.add(guest);
      await pumpEventQueue();
      await cubit.answer(true);
    },
    verify: (_) => verify(() => consents.saveConsent('g1', true)).called(1),
  );

  blocTest<ConsentCubit, ConsentState>(
    'a failed save is reported and the answer stays as stored',
    setUp: () =>
        when(() => consents.saveConsent(any(), any()))
            .thenAnswer((_) async => const Err(NetworkFailure())),
    build: build,
    act: (cubit) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.add(false);
      await pumpEventQueue();
      await cubit.answer(true);
    },
    expect: () => [
      const ConsentState(loaded: true, consent: false),
      isA<ConsentState>()
          .having((s) => s.consent, 'consent', false)
          .having((s) => s.failure, 'failure', isA<NetworkFailure>()),
    ],
  );

  blocTest<ConsentCubit, ConsentState>(
    'a failed read leaves collection as it was',
    build: build,
    act: (_) async {
      users.add(guest);
      await pumpEventQueue();
      stored['g1']!.addError(const PermissionFailure());
      await pumpEventQueue();
    },
    expect: () => <ConsentState>[],
    verify: (_) => verifyNever(() => telemetry.apply(any())),
  );
}
