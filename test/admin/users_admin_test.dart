import 'package:bloc_test/bloc_test.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/admin_router.dart';
import 'package:get_workout/admin/users/data/callable_admin_user_repository.dart';
import 'package:get_workout/admin/users/domain/admin_user.dart';
import 'package:get_workout/admin/users/domain/admin_user_repository.dart';
import 'package:get_workout/admin/users/domain/user_admin_usecases.dart';
import 'package:get_workout/admin/users/presentation/user_cubit.dart';
import 'package:get_workout/admin/users/presentation/users_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockFunctions extends Mock implements FirebaseFunctions {}

class MockCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock implements HttpsCallableResult<Object?> {}

class MockRepository extends Mock implements AdminUserRepository {}

class MockAuthRepository extends Mock implements AuthRepository {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, {String? reason, Map<String, Object?>? more})
    : super(
        code: code,
        message: 'error',
        details: reason == null ? null : {'reason': reason, ...?more},
      );
}

final _signedUp = DateTime.utc(2026, 11, 2);

UserRow _row(String uid) => UserRow(
  uid: uid,
  email: '$uid@example.com',
  guest: false,
  premium: false,
  signedUp: _signedUp,
  lastWorkout: null,
);

UserDetail _detail({bool admin = false}) => UserDetail(
  uid: 'u1',
  email: 'u1@example.com',
  guest: false,
  providers: const ['password'],
  admin: admin,
  signedUp: _signedUp,
  lastActive: null,
  server: null,
  workouts: 0,
  lastWorkout: null,
  activeProgram: null,
  revenueCat: null,
  revenueCatState: RevenueCatState.noCustomer,
);

void main() {
  setUpAll(() => registerFallbackValue(PremiumDuration.week));

  group('PremiumDuration.endFrom', () {
    final now = DateTime.utc(2026, 11, 21, 12);

    test('matches the server: a week, a calendar month or year, never', () {
      expect(PremiumDuration.week.endFrom(now), DateTime.utc(2026, 11, 28, 12));
      expect(
        PremiumDuration.month.endFrom(now),
        DateTime.utc(2026, 12, 21, 12),
      );
      expect(PremiumDuration.year.endFrom(now), DateTime.utc(2027, 11, 21, 12));
      expect(PremiumDuration.lifetime.endFrom(now), isNull);
    });

    test('a month from the 31st overflows as JavaScript dates do', () {
      expect(
        PremiumDuration.month.endFrom(DateTime.utc(2026, 1, 31)),
        DateTime.utc(2026, 3, 3),
      );
    });
  });

  test('a user opens under the Users section', () {
    final users = adminSections.singleWhere((s) => s.label == 'Users');
    expect(users.opens(AdminRoutes.user('a/b')), isTrue);
    expect(AdminRoutes.user('a/b'), '/users/a%2Fb');
  });

  group('CallableAdminUserRepository', () {
    late MockFunctions functions;
    late MockCallable callable;
    late MockCallableResult result;
    late CallableAdminUserRepository repository;

    void answer(String function, Object? data) {
      when(() => functions.httpsCallable(function)).thenReturn(callable);
      when(() => result.data).thenReturn(data);
    }

    setUp(() {
      functions = MockFunctions();
      callable = MockCallable();
      result = MockCallableResult();
      repository = CallableAdminUserRepository(functions);
      when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
    });

    test('pages sign-ups with the cursor', () async {
      answer('adminListUsers', {
        'users': [
          {
            'uid': 'u1',
            'email': null,
            'guest': true,
            'premium': false,
            'signedUpMillis': _signedUp.millisecondsSinceEpoch,
            'lastWorkoutMillis': null,
          },
        ],
        'next': {'createdAtMillis': 5, 'uid': 'u1'},
      });
      final page = (await repository.latest(
        after: const UserCursor(createdAtMillis: 9, uid: 'u0'),
      )).valueOrNull!;
      expect(page.users.single.guest, isTrue);
      expect(page.users.single.signedUp, _signedUp);
      expect(page.next, const UserCursor(createdAtMillis: 5, uid: 'u1'));
      verify(
        () => callable.call<Object?>({
          'cursor': {'createdAtMillis': 9, 'uid': 'u0'},
        }),
      ).called(1);
    });

    test('reads a user, the server\'s "never" as no end', () async {
      const never = 253402214400000; // 9999-12-31
      answer('adminGetUser', {
        'uid': 'u1',
        'email': 'u1@example.com',
        'guest': false,
        'providers': ['password', 'apple.com'],
        'admin': true,
        'signedUpMillis': _signedUp.millisecondsSinceEpoch,
        'lastActiveMillis': null,
        'server': {
          'premium': true,
          'expiresAtMillis': never,
          'productId': null,
          'lastEventMillis': 7,
        },
        'activity': {
          'workouts': 4,
          'lastWorkoutMillis': 8,
          'activeProgram': 'PPL',
        },
        'revenueCat': {
          'premium': {'expiresAtMillis': never},
          'subscriptions': [
            {
              'store': 'promotional',
              'status': 'active',
              'givesAccess': true,
              'productId': null,
              'periodEndsAtMillis': never,
              'autoRenewal': 'will_not_renew',
            },
          ],
          'lastSeen': {
            'atMillis': 9,
            'platform': 'iOS',
            'platformVersion': '18.1',
            'appVersion': '1.0.0',
          },
        },
        'revenueCatState': 'ok',
      });
      final user = (await repository.user('u1')).valueOrNull!;
      expect(user.admin, isTrue);
      expect(user.hasPassword, isTrue);
      expect(user.server!.activeAt(DateTime.now()), isTrue);
      expect(user.workouts, 4);
      expect(user.activeProgram, 'PPL');
      final customer = user.revenueCat!;
      expect(customer.premium, isTrue);
      expect(customer.premiumEnds, isNull);
      expect(customer.promotional!.periodEnds, isNull);
      expect(customer.storeSubscription, isNull);
      expect(customer.lastSeen.platform, 'iOS');
    });

    test('grants by duration name and returns the end', () async {
      answer('adminGrantPremium', {'expiresAtMillis': 1000});
      final end = await repository.grantPremium('u1', PremiumDuration.year);
      expect(
        end.valueOrNull,
        DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
      );
      verify(() => callable.call<Object?>({'uid': 'u1', 'duration': 'year'}))
          .called(1);
    });

    Future<Failure?> failureFor(FunctionsError error) async {
      when(() => functions.httpsCallable(any())).thenReturn(callable);
      when(() => callable.call<Object?>(any())).thenThrow(error);
      return (await repository.delete('u1')).failureOrNull;
    }

    test('maps each refusal by its reason', () async {
      expect(
        await failureFor(
          FunctionsError('permission-denied', reason: 'not-admin'),
        ),
        isA<PermissionFailure>(),
      );
      expect(
        await failureFor(FunctionsError('not-found', reason: 'user-not-found')),
        isA<NotFoundFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError('failed-precondition', reason: 'own-account'),
        ),
        isA<OwnAccountFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError(
            'unavailable',
            reason: 'revenuecat-failed',
            more: {'status': 403},
          ),
        ),
        isA<RevenueCatFailure>().having((f) => f.status, 'status', 403),
      );
    });
  });

  group('UsersCubit', () {
    late MockRepository repository;

    UsersCubit build() => UsersCubit(
      listLatestUsers: ListLatestUsers(repository),
      findUser: FindUser(repository),
    );

    setUp(() => repository = MockRepository());

    blocTest<UsersCubit, UsersState>(
      'loads a page, then appends the next on Load more',
      setUp: () {
        when(() => repository.latest()).thenAnswer(
          (_) async => Ok((
            users: [_row('a')],
            next: const UserCursor(createdAtMillis: 1, uid: 'a'),
          )),
        );
        when(
          () => repository.latest(
            after: const UserCursor(createdAtMillis: 1, uid: 'a'),
          ),
        ).thenAnswer((_) async => Ok((users: [_row('b')], next: null)));
      },
      build: build,
      act: (cubit) async {
        await cubit.load();
        await cubit.loadMore();
        await cubit.loadMore();
      },
      skip: 3,
      expect: () => [
        UsersState(users: [_row('a'), _row('b')]),
      ],
    );

    blocTest<UsersCubit, UsersState>(
      'keeps the rows loaded when Load more fails',
      setUp: () {
        when(() => repository.latest()).thenAnswer(
          (_) async => Ok((
            users: [_row('a')],
            next: const UserCursor(createdAtMillis: 1, uid: 'a'),
          )),
        );
        when(
          () => repository.latest(
            after: const UserCursor(createdAtMillis: 1, uid: 'a'),
          ),
        ).thenAnswer((_) async => const Err(NetworkFailure()));
      },
      build: build,
      act: (cubit) async {
        await cubit.load();
        await cubit.loadMore();
      },
      skip: 3,
      expect: () => [
        UsersState(
          users: [_row('a')],
          next: const UserCursor(createdAtMillis: 1, uid: 'a'),
          failure: const NetworkFailure(),
        ),
      ],
    );

    test('find returns the uid, or null with the failure', () async {
      when(() => repository.find('u1@example.com'))
          .thenAnswer((_) async => const Ok('u1'));
      when(() => repository.find('x'))
          .thenAnswer((_) async => const Err(NotFoundFailure()));
      final cubit = build();
      expect(await cubit.find(' u1@example.com '), 'u1');
      expect(await cubit.find('x'), isNull);
      expect(cubit.state.findFailure, isA<NotFoundFailure>());
      expect(await cubit.find('  '), isNull);
      expect(cubit.state.findFailure, isA<ValidationFailure>());
      verifyNever(() => repository.find(''));
    });

    blocTest<UsersCubit, UsersState>(
      'drops a deleted user',
      build: build,
      seed: () => UsersState(users: [_row('a'), _row('b')]),
      act: (cubit) => cubit.removed('a'),
      expect: () => [
        UsersState(users: [_row('b')]),
      ],
    );
  });

  group('UserCubit', () {
    late MockRepository repository;
    late MockAuthRepository auth;

    UserCubit build() => UserCubit(
      uid: 'u1',
      getAdminUser: GetAdminUser(repository),
      grantPremium: GrantPromotionalPremium(repository),
      revokePremium: RevokePromotionalPremium(repository),
      sendPasswordReset: SendPasswordReset(auth),
      setUserAdmin: SetUserAdmin(repository),
      deleteUserAccount: DeleteUserAccount(repository),
    );

    setUp(() {
      repository = MockRepository();
      auth = MockAuthRepository();
      when(() => repository.user('u1')).thenAnswer((_) async => Ok(_detail()));
    });

    blocTest<UserCubit, UserState>(
      'grants Premium, then reads the user again',
      setUp: () =>
          when(() => repository.grantPremium('u1', PremiumDuration.month))
              .thenAnswer((_) async => const Ok(null)),
      build: build,
      seed: () => UserState(user: _detail()),
      act: (cubit) => cubit.grantPremium(PremiumDuration.month),
      expect: () => [
        UserState(user: _detail(), running: UserAction.grantPremium),
        // Read again: the same user, so no further state.
        UserState(user: _detail(), done: UserAction.grantPremium),
      ],
      verify: (_) => verify(() => repository.user('u1')).called(1),
    );

    blocTest<UserCubit, UserState>(
      'a refusal is the action failure; the user is not read again',
      setUp: () =>
          when(() => repository.setAdmin('u1', admin: true))
              .thenAnswer((_) async => const Err(OwnAccountFailure())),
      build: build,
      seed: () => UserState(user: _detail()),
      act: (cubit) => cubit.setAdmin(admin: true),
      expect: () => [
        UserState(user: _detail(), running: UserAction.makeAdmin),
        UserState(user: _detail(), actionFailure: const OwnAccountFailure()),
      ],
      verify: (_) => verifyNever(() => repository.user('u1')),
    );

    blocTest<UserCubit, UserState>(
      'sends the password reset to the user\'s email',
      setUp: () =>
          when(() => auth.sendPasswordReset('u1@example.com'))
              .thenAnswer((_) async => const Ok(null)),
      build: build,
      seed: () => UserState(user: _detail()),
      act: (cubit) => cubit.sendPasswordReset(),
      expect: () => [
        UserState(user: _detail(), running: UserAction.sendPasswordReset),
        UserState(user: _detail(), done: UserAction.sendPasswordReset),
      ],
    );

    blocTest<UserCubit, UserState>(
      'deletes once, ignoring a second action meanwhile',
      setUp: () =>
          when(() => repository.delete('u1'))
              .thenAnswer((_) async => const Ok(null)),
      build: build,
      seed: () => UserState(user: _detail()),
      act: (cubit) => Future.wait([cubit.delete(), cubit.revokePremium()]),
      expect: () => [
        UserState(user: _detail(), running: UserAction.delete),
        UserState(user: _detail(), done: UserAction.delete),
      ],
      verify: (_) => verifyNever(() => repository.revokePremium(any())),
    );
  });
}
