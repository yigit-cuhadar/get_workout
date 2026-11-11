import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/access/domain/admin_access_repository.dart';
import 'package:get_workout/admin/access/presentation/access_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockAccessRepository extends Mock implements AdminAccessRepository {}

void main() {
  const admin = AuthUser(id: 'u1', email: 'admin@example.com');
  const other = AuthUser(id: 'u2', email: 'someone@example.com');

  group('CheckAdminAccess.isAdmin', () {
    test('needs the admin claim to be boolean true', () {
      expect(CheckAdminAccess.isAdmin({'admin': true}), isTrue);
      expect(CheckAdminAccess.isAdmin({'admin': 'true'}), isFalse);
      expect(CheckAdminAccess.isAdmin({'admin': false}), isFalse);
      expect(CheckAdminAccess.isAdmin({}), isFalse);
    });
  });

  group('AccessCubit', () {
    late MockAuthRepository auth;
    late MockAccessRepository access;
    late StreamController<AuthUser?> users;

    setUp(() {
      auth = MockAuthRepository();
      access = MockAccessRepository();
      users = StreamController<AuthUser?>();
      when(() => auth.watchUser()).thenAnswer((_) => users.stream);
      when(() => auth.signOut()).thenAnswer((_) async => const Ok(null));
    });

    void claims(Map<String, Object?> claims, {bool refresh = false}) =>
        when(() => access.claims(refresh: refresh))
            .thenAnswer((_) async => Ok(claims));

    AccessCubit build() => AccessCubit(
      watchAuthUser: WatchAuthUser(auth),
      checkAdminAccess: CheckAdminAccess(access),
      signOut: SignOut(auth),
    );

    blocTest<AccessCubit, AccessState>(
      'a signed-out session',
      build: build,
      act: (_) => users.add(null),
      expect: () => [const SignedOut()],
    );

    blocTest<AccessCubit, AccessState>(
      'an admin is let in',
      setUp: () => claims({'admin': true}),
      build: build,
      act: (_) => users.add(admin),
      expect: () => [
        const AccessChecking(),
        const SignedIn(admin, isAdmin: true),
      ],
    );

    blocTest<AccessCubit, AccessState>(
      'a user without the claim is not an admin until a refreshed token '
      'carries it',
      setUp: () {
        claims({});
        claims({'admin': true}, refresh: true);
      },
      build: build,
      act: (cubit) async {
        users.add(other);
        await pumpEventQueue();
        await cubit.refreshAccess();
      },
      expect: () => [
        const AccessChecking(),
        const SignedIn(other, isAdmin: false),
        const AccessChecking(),
        const SignedIn(other, isAdmin: true),
      ],
      verify: (_) => verify(() => access.claims(refresh: true)).called(1),
    );

    blocTest<AccessCubit, AccessState>(
      'a failed claims read can be retried',
      setUp: () {
        when(() => access.claims(refresh: false))
            .thenAnswer((_) async => const Err(NetworkFailure()));
        claims({'admin': true}, refresh: true);
      },
      build: build,
      act: (cubit) async {
        users.add(admin);
        await pumpEventQueue();
        await cubit.refreshAccess();
      },
      expect: () => [
        const AccessChecking(),
        isA<AccessCheckFailed>(),
        const AccessChecking(),
        const SignedIn(admin, isAdmin: true),
      ],
    );

    blocTest<AccessCubit, AccessState>(
      'signing out while the claims are read ends signed out',
      setUp: () {
        final pending = Completer<Result<Map<String, Object?>>>();
        when(() => access.claims(refresh: false))
            .thenAnswer((_) => pending.future);
        addTearDown(() => pending.complete(const Ok({'admin': true})));
      },
      build: build,
      act: (_) async {
        users.add(admin);
        await pumpEventQueue();
        users.add(null);
      },
      expect: () => [const AccessChecking(), const SignedOut()],
    );
  });
}
