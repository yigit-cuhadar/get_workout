import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/app/router.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  const guest = AuthUser(id: 'u1', isAnonymous: true);
  const member = AuthUser(id: 'u1', email: 'a@b.co');
  late MockAuthRepository repository;
  late StreamController<AuthUser?> users;
  late AuthCubit auth;

  // Created inside each test so stream events run in the test's fake zone.
  void setUpAuth() {
    repository = MockAuthRepository();
    users = StreamController<AuthUser?>();
    when(() => repository.watchUser()).thenAnswer((_) => users.stream);
    when(() => repository.currentUser).thenReturn(guest);
    auth = AuthCubit(
      watchAuthUser: WatchAuthUser(repository),
      signOut: SignOut(repository),
      deleteAccount: DeleteAccount(repository),
      signInAnonymously: SignInAnonymously(repository),
    );
    sl.registerFactory(
      () => AuthFormCubit(
        signInWithEmail: SignInWithEmail(repository),
        signUpWithEmail: SignUpWithEmail(repository),
        signInWithProvider: SignInWithProvider(repository),
        sendPasswordReset: SendPasswordReset(repository),
        getCurrentUser: GetCurrentUser(repository),
      ),
    );
  }

  tearDown(() async {
    await auth.close();
    await sl.reset();
  });

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    BlocProvider.value(
      value: auth,
      child: MaterialApp.router(routerConfig: buildRouter(auth)),
    ),
  );

  Future<void> openSignUpAsGuest(WidgetTester tester) async {
    setUpAuth();
    await pumpApp(tester);
    users.add(guest);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.byType(AuthPage), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'a@b.co');
  }

  testWidgets('the auth page closes once the guest is upgraded', (
    tester,
  ) async {
    await openSignUpAsGuest(tester);

    users.add(member);
    await tester.pumpAndSettle();

    expect(find.byType(AuthPage), findsNothing);
    expect(find.text('a@b.co'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('a failed guest start offers a retry', (tester) async {
    setUpAuth();
    var attempts = 0;
    when(() => repository.signInAnonymously()).thenAnswer((_) async {
      if (++attempts == 1) return const Err(NetworkFailure());
      users.add(guest);
      return const Ok(guest);
    });
    await pumpApp(tester);

    users.add(null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });

  testWidgets('a session update keeps the auth form', (tester) async {
    await openSignUpAsGuest(tester);

    users.add(const AuthUser(id: 'u1', displayName: 'G', isAnonymous: true));
    await tester.pumpAndSettle();

    expect(find.byType(AuthPage), findsOneWidget);
    expect(find.text('a@b.co'), findsOneWidget);
  });
}
