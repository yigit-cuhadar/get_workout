import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_purchases/forge_purchases.dart';
import 'package:get_workout/features/subscription/presentation/purchaser_session.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockEntitlementCubit extends Mock implements EntitlementCubit {}

void main() {
  const guest = AuthUser(id: 'g1', isAnonymous: true);
  const linked = AuthUser(id: 'g1', email: 'a@b.co');
  const other = AuthUser(id: 'u2', email: 'c@d.co');

  late StreamController<AuthUser?> users;
  late MockAuthRepository auth;
  late MockEntitlementCubit entitlement;
  late PurchaserSession session;

  setUp(() {
    users = StreamController<AuthUser?>();
    auth = MockAuthRepository();
    when(auth.watchUser).thenAnswer((_) => users.stream);
    entitlement = MockEntitlementCubit();
    when(() => entitlement.identify(any()))
        .thenAnswer((_) async => const Ok(null));
    when(entitlement.reset).thenAnswer((_) async => const Ok(null));
  });

  // Called inside fakeAsync where timing matters, so its timers are fake.
  void start() => session = PurchaserSession(
    watchAuthUser: WatchAuthUser(auth),
    entitlement: entitlement,
    retryDelay: const Duration(seconds: 1),
    maxRetryDelay: const Duration(seconds: 2),
  );

  test('identifies the signed-in user and resets when signed out', () async {
    start();
    users
      ..add(null)
      ..add(guest)
      ..add(other)
      ..add(null);
    await pumpEventQueue();

    await session.cancel();
    verifyInOrder([
      entitlement.reset,
      () => entitlement.identify('g1'),
      () => entitlement.identify('u2'),
      entitlement.reset,
    ]);
  });

  test('linking keeps the uid, so the store user is not switched', () async {
    start();
    users
      ..add(guest)
      ..add(linked);
    await pumpEventQueue();

    await session.cancel();
    verify(() => entitlement.identify('g1')).called(1);
    verifyNever(entitlement.reset);
  });

  test('retries a failed switch with backoff until it succeeds', () {
    fakeAsync((async) {
      start();
      var attempts = 0;
      when(() => entitlement.identify('g1')).thenAnswer(
        (_) async =>
            ++attempts < 4 ? const Err(NetworkFailure()) : const Ok(null),
      );
      users.add(guest);
      async.flushMicrotasks();
      expect(attempts, 1);

      async.elapse(const Duration(seconds: 1));
      expect(attempts, 2);
      // Doubled, then capped at two seconds.
      async.elapse(const Duration(seconds: 2));
      expect(attempts, 3);
      async.elapse(const Duration(seconds: 2));
      expect(attempts, 4);

      async.elapse(const Duration(minutes: 1));
      expect(attempts, 4);
      session.cancel();
    });
  });

  test('resume retries a failed switch at once', () {
    fakeAsync((async) {
      start();
      var attempts = 0;
      when(() => entitlement.identify('g1')).thenAnswer(
        (_) async =>
            ++attempts < 2 ? const Err(NetworkFailure()) : const Ok(null),
      );
      users.add(guest);
      async.flushMicrotasks();

      session.resume();
      async.flushMicrotasks();
      expect(attempts, 2);

      session.resume();
      async.elapse(const Duration(seconds: 5));
      expect(attempts, 2);
      session.cancel();
    });
  });

  test('a new user drops the previous user\'s retry', () {
    fakeAsync((async) {
      start();
      when(() => entitlement.identify('g1'))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      users.add(guest);
      async.flushMicrotasks();

      users.add(other);
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));

      verify(() => entitlement.identify('g1')).called(1);
      verify(() => entitlement.identify('u2')).called(1);
      session.cancel();
    });
  });
}
