import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:get_workout/features/account/domain/account_repository.dart';
import 'package:get_workout/features/account/presentation/account_page.dart';
import 'package:get_workout/features/account/presentation/delete_account_page.dart';
import 'package:get_workout/features/profile/domain/user_profile.dart';
import 'package:get_workout/features/profile/presentation/onboarding_page.dart';
import 'package:get_workout/features/profile/presentation/profile_page.dart';
import 'package:mocktail/mocktail.dart';

import 'flow_harness.dart';

const _other = AuthUser(id: 'u2', email: 'b@c.de');
const _newGuest = AuthUser(id: 'u2', isAnonymous: true);

void main() {
  late FlowApp app;

  setUpAll(registerFlowFallbacks);
  setUp(() => app = FlowApp());
  tearDown(() => app.dispose());

  Future<void> tapText(WidgetTester tester, String text) =>
      app.tapText(tester, text);

  /// Taps the button labelled [label], where the label is also a title.
  Future<void> tapButton(WidgetTester tester, String label) async {
    final button = find.widgetWithText(ForgeButton, label).last;
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  /// Signing out (or a deletion's sign-out) starts [_newGuest], who has no
  /// profile yet.
  void signOutStartsNewGuest() {
    when(() => app.repository.signInAnonymously()).thenAnswer((_) async {
      app.storedProfile = const UserProfile();
      app.users.add(_newGuest);
      return const Ok(_newGuest);
    });
  }

  group('guest to account', () {
    Future<void> openSheet(WidgetTester tester) async {
      await app.startAs(tester, guest);
      await app.tapTab(tester, 'Profile');
      expect(find.text('Guest'), findsOneWidget);
      await tapText(tester, 'Create an account to keep your workouts');
      expect(find.text('Keep your workouts safe'), findsOneWidget);
    }

    Future<void> openCreateAccount(WidgetTester tester) async {
      await openSheet(tester);
      await tapText(tester, 'Use email instead');
    }

    Future<void> fillForm(WidgetTester tester, String email, String password) =>
        tester
            .enterText(find.byType(TextField).first, email)
            .then(
              (_) => tester.enterText(find.byType(TextField).last, password),
            );

    testWidgets('Use email instead opens the full-screen create account; '
        'Back returns to Profile', (tester) async {
      await openCreateAccount(tester);

      expect(find.text('Keep your workouts safe'), findsNothing);
      expect(find.byType(AuthPage), findsOneWidget);
      expect(find.byType(ForgeNavigationBar), findsNothing);
      expect(
        find.widgetWithText(ForgeButton, 'Create account'),
        findsOneWidget,
      );
      expect(find.text('Already have an account? Sign in'), findsOneWidget);

      // The form's own back link shows the other options.
      await tapText(tester, 'Other options');
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Use email instead'), findsOneWidget);

      await app.tapBack(tester);
      expect(find.byType(AuthPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('Guest'), findsOneWidget);
    });

    testWidgets('the form shows its errors under the fields', (tester) async {
      await openCreateAccount(tester);
      when(() => app.repository.signUpWithEmail(any(), any())).thenAnswer(
        (_) async =>
            const Err(AuthFailure('taken', code: 'email-already-in-use')),
      );

      await tapButton(tester, 'Create account');
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Use at least 6 characters'), findsOneWidget);
      verifyNever(() => app.repository.signUpWithEmail(any(), any()));

      await fillForm(tester, 'a@b.co', 'secret1');
      await tapButton(tester, 'Create account');

      verify(() => app.repository.signUpWithEmail('a@b.co', 'secret1'))
          .called(1);
      expect(find.text('This email is already registered'), findsOneWidget);
      expect(find.text('Use at least 6 characters'), findsNothing);
      expect(find.byType(AuthPage), findsOneWidget);
    });

    testWidgets("a successful link keeps the guest's data", (tester) async {
      await openCreateAccount(tester);
      // Linking keeps the uid.
      when(() => app.repository.signUpWithEmail(any(), any()))
          .thenAnswer((_) async {
            app.users.add(member);
            return const Ok(member);
          });

      await fillForm(tester, 'a@b.co', 'secret1');
      await tapButton(tester, 'Create account');

      expect(find.byType(AuthPage), findsNothing);
      expect(find.byType(ProfilePage), findsOneWidget);
      expect(find.text('a@b.co'), findsOneWidget);
      expect(find.text('Guest'), findsNothing);
      // The same profile goes on: nothing is read again or written.
      verify(() => app.profiles.watchProfile('u1')).called(1);
      verifyNever(() => app.profiles.completeOnboarding(any(), any()));
      verifyNever(() => app.repository.signOut());
      expect(find.byType(OnboardingPage), findsNothing);
    });

    testWidgets('linking to an existing account asks to replace the guest '
        'data', (tester) async {
      await openSheet(tester);
      when(
        () => app.repository.signInWithProvider(
          SocialProvider.google,
          replaceGuest: false,
        ),
      ).thenAnswer(
        (_) async => const Err(AuthFailure('exists', code: accountExistsCode)),
      );
      when(
        () => app.repository.signInWithProvider(
          SocialProvider.google,
          replaceGuest: true,
        ),
      ).thenAnswer((_) async {
        app.users.add(_other);
        return const Ok(_other);
      });

      await tapText(tester, 'Continue with Google');
      expect(find.text('Use existing account?'), findsOneWidget);
      expect(
        find.text('What you did as a guest on this device will be lost.'),
        findsOneWidget,
      );

      // Cancel keeps the guest and the sheet.
      await tapText(tester, 'Cancel');
      expect(find.text('Use existing account?'), findsNothing);
      expect(find.text('Keep your workouts safe'), findsOneWidget);
      verifyNever(
        () => app.repository.signInWithProvider(
          SocialProvider.google,
          replaceGuest: true,
        ),
      );

      await tapText(tester, 'Continue with Google');
      await tapText(tester, 'Continue');

      verify(
        () => app.repository.signInWithProvider(
          SocialProvider.google,
          replaceGuest: true,
        ),
      ).called(1);
      expect(find.text('Keep your workouts safe'), findsNothing);
      expect(find.text('b@c.de'), findsOneWidget);
    });
  });

  group('account', () {
    Future<void> openAccount(
      WidgetTester tester, [
      AuthUser user = member,
    ]) async {
      await app.startAs(tester, user);
      await app.tapTab(tester, 'Profile');
      await tester.tap(find.text(user.email!));
      await tester.pump();
      await tester.pump();
      expect(find.byType(AccountPage), findsOneWidget);
      // Until the sync state is known its row shimmers.
      expect(find.text('Data'), findsNothing);
      app.backedUp.add(true);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the email, the sign-in method and the sync state', (
      tester,
    ) async {
      await openAccount(tester);
      expect(find.text('Email'), findsNWidgets(2));
      expect(find.text('a@b.co'), findsOneWidget);
      expect(find.text('Signed in with'), findsOneWidget);
      expect(find.text('Data'), findsOneWidget);
      expect(find.text('Backed up'), findsOneWidget);

      app.backedUp.add(false);
      await tester.pumpAndSettle();
      expect(find.text('Waiting to sync'), findsOneWidget);
      expect(find.text('Backed up'), findsNothing);
    });

    testWidgets('sign out asks first; a failed sign-out offers a retry', (
      tester,
    ) async {
      await openAccount(tester);
      signOutStartsNewGuest();
      var attempts = 0;
      when(() => app.repository.signOut()).thenAnswer((_) async {
        if (++attempts == 1) return const Err(NetworkFailure());
        app.users.add(null);
        return const Ok(null);
      });

      await tapText(tester, 'Sign out');
      expect(find.text('Sign out?'), findsOneWidget);
      expect(
        find.text("You'll continue as a new guest on this device."),
        findsOneWidget,
      );
      await tapText(tester, 'Cancel');
      expect(find.text('Sign out?'), findsNothing);
      expect(attempts, 0);

      await tapText(tester, 'Sign out');
      await tapButton(tester, 'Sign out');
      expect(attempts, 1);
      expect(find.text("Couldn't sign out."), findsOneWidget);
      expect(find.byType(AccountPage), findsOneWidget);

      await tapText(tester, 'Retry');

      expect(attempts, 2);
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
    });

    testWidgets('deleting asks to confirm, then the password, again after a '
        'wrong one, and starts over as a new guest', (tester) async {
      await openAccount(tester);
      signOutStartsNewGuest();
      var deletes = 0;
      when(() => app.account.deleteAccount()).thenAnswer(
        (_) async => ++deletes == 1
            ? const Err(AuthFailure('stale', code: recentLoginRequiredCode))
            : const Ok(null),
      );
      when(() => app.account.signOut()).thenAnswer((_) async {
        app.users.add(null);
        return const Ok(null);
      });
      when(() => app.repository.reauthenticate(any())).thenAnswer(
        (call) async => call.positionalArguments.single == 'secret1'
            ? const Ok(null)
            : const Err(AuthFailure('wrong', code: 'wrong-password')),
      );

      await tapText(tester, 'Delete account');
      expect(find.byType(DeleteAccountPage), findsOneWidget);
      expect(find.text('Your sign-in (a@b.co)'), findsOneWidget);

      await tapButton(tester, 'Delete account');
      expect(find.text('Delete everything?'), findsOneWidget);
      await tapText(tester, 'Delete');

      expect(find.text("Confirm it's you"), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, 'wrong1');
      await tapText(tester, 'Delete');
      verify(() => app.repository.reauthenticate('wrong1')).called(1);
      expect(find.text("Confirm it's you"), findsOneWidget);
      expect(find.text('That password is incorrect'), findsOneWidget);
      expect(deletes, 1);

      await tester.enterText(find.byType(TextField).last, 'secret1');
      await tapText(tester, 'Delete');

      expect(deletes, 2);
      verify(() => app.account.signOut()).called(1);
      expect(find.byType(DeleteAccountPage), findsNothing);
      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(find.text('Get started'), findsOneWidget);
    });

    /// The first deletion wants a recent sign-in, the next one deletes and
    /// signs out; returns how many deletions ran.
    int Function() deleteAfterSignIn() {
      signOutStartsNewGuest();
      var deletes = 0;
      when(() => app.account.deleteAccount()).thenAnswer(
        (_) async => ++deletes == 1
            ? const Err(AuthFailure('stale', code: recentLoginRequiredCode))
            : const Ok(null),
      );
      when(() => app.account.signOut()).thenAnswer((_) async {
        app.users.add(null);
        return const Ok(null);
      });
      return () => deletes;
    }

    testWidgets('a Google-only user confirms with Google, asked again after '
        'a closed sheet, and deletes', (tester) async {
      const googleUser = AuthUser(
        id: 'u1',
        email: 'a@gmail.com',
        signInMethods: {SignInMethod.google},
      );
      await openAccount(tester, googleUser);
      final deletes = deleteAfterSignIn();
      var sheets = 0;
      when(() => app.repository.reauthenticateWithProvider(any())).thenAnswer(
        (_) async => ++sheets == 1
            ? const Err(AuthFailure('closed', code: cancelledCode))
            : const Ok(null),
      );

      await tapText(tester, 'Delete account');
      await tapButton(tester, 'Delete account');
      await tapText(tester, 'Delete');

      expect(find.text("Confirm it's you"), findsOneWidget);
      expect(
        find.text('Sign in with Google again to delete your account.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(OrDivider), findsNothing);
      expect(find.text('Continue with Apple'), findsNothing);
      await tapText(tester, 'Continue with Google');
      verify(
        () => app.repository.reauthenticateWithProvider(SocialProvider.google),
      ).called(1);
      // The closed sheet says nothing; the dialog is back.
      expect(find.text("Confirm it's you"), findsOneWidget);
      expect(deletes(), 1);

      await tapText(tester, 'Continue with Google');

      expect(deletes(), 2);
      expect(find.byType(DeleteAccountPage), findsNothing);
      expect(find.byType(OnboardingPage), findsOneWidget);
    });

    testWidgets('an Apple user confirms with Apple, which deletes with its '
        'code; Apple refusing the revocation only says deleting failed', (
      tester,
    ) async {
      const appleUser = AuthUser(
        id: 'u1',
        email: 'a@icloud.com',
        signInMethods: {SignInMethod.apple},
      );
      await openAccount(tester, appleUser);
      signOutStartsNewGuest();
      var deletes = 0;
      when(() => app.account.deleteAccount(appleCode: any(named: 'appleCode')))
          .thenAnswer(
            (_) async => ++deletes == 1
                ? const Err(AppleNotRevokedFailure())
                : const Ok(null),
          );
      when(() => app.account.signOut()).thenAnswer((_) async {
        app.users.add(null);
        return const Ok(null);
      });
      when(() => app.repository.reauthenticateWithAppleCode())
          .thenAnswer((_) async => const Ok('code-1'));

      await tapText(tester, 'Delete account');
      await tapButton(tester, 'Delete account');
      await tapText(tester, 'Continue with Apple');

      expect(find.text("Couldn't delete your data. Try again"), findsOneWidget);
      expect(find.byType(DeleteAccountPage), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(DeleteAccountPage)))
          .removeCurrentSnackBar();
      await tester.pumpAndSettle();

      await tapButton(tester, 'Delete account');
      await tapText(tester, 'Continue with Apple');

      verify(() => app.account.deleteAccount(appleCode: 'code-1')).called(2);
      expect(find.byType(DeleteAccountPage), findsNothing);
      expect(find.byType(OnboardingPage), findsOneWidget);
    });

    testWidgets('a failed Apple confirmation names being offline or another '
        'account, else only that deleting failed; a closed sheet says '
        'nothing', (tester) async {
      const appleUser = AuthUser(
        id: 'u1',
        email: 'a@icloud.com',
        signInMethods: {SignInMethod.apple},
      );
      await openAccount(tester, appleUser);
      for (final (failure, text) in [
        (
          const NetworkFailure(),
          "You're offline, so nothing was deleted. Connect to the internet "
              'and try again.',
        ),
        (
          const AuthFailure('other', code: 'user-mismatch'),
          "That's a different account. Sign in with the one you use here.",
        ),
        (
          const AuthFailure('refused', code: 'invalid-credential'),
          "Couldn't delete your data. Try again",
        ),
        (
          const AuthFailure('refused', code: 'wrong-password'),
          "Couldn't delete your data. Try again",
        ),
        (const AuthFailure('odd'), "Couldn't delete your data. Try again"),
        (const AuthFailure('closed', code: cancelledCode), null),
      ]) {
        when(() => app.repository.reauthenticateWithAppleCode())
            .thenAnswer((_) async => Err(failure));
        if (find.text('Delete everything?').evaluate().isEmpty) {
          if (find.byType(DeleteAccountPage).evaluate().isEmpty) {
            await tapText(tester, 'Delete account');
          }
          await tapButton(tester, 'Delete account');
        }
        await tapText(tester, 'Continue with Apple');

        expect(find.text('That password is incorrect'), findsNothing);
        if (text == null) {
          expect(find.byType(SnackBar), findsNothing, reason: '$failure');
        } else {
          expect(find.text(text), findsOneWidget, reason: '$failure');
        }
        verifyNever(
          () => app.account.deleteAccount(appleCode: any(named: 'appleCode')),
        );
        ScaffoldMessenger.of(tester.element(find.byType(DeleteAccountPage)))
            .removeCurrentSnackBar();
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a user with a password and Google may confirm with either', (
      tester,
    ) async {
      const linked = AuthUser(
        id: 'u1',
        email: 'a@b.co',
        signInMethods: {SignInMethod.email, SignInMethod.google},
      );
      await openAccount(tester, linked);
      final deletes = deleteAfterSignIn();
      when(() => app.repository.reauthenticateWithProvider(any()))
          .thenAnswer((_) async => const Ok(null));

      await tapText(tester, 'Delete account');
      await tapButton(tester, 'Delete account');
      await tapText(tester, 'Delete');

      expect(
        find.text('Enter your password to delete your account.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(OrDivider), findsOneWidget);
      await tapText(tester, 'Continue with Google');

      verifyNever(() => app.repository.reauthenticate(any()));
      expect(deletes(), 2);
      expect(find.byType(OnboardingPage), findsOneWidget);
    });

    testWidgets('a deletion that leaves the sign-in shows Almost done with '
        'no way back', (tester) async {
      await openAccount(tester);
      signOutStartsNewGuest();
      var deletes = 0;
      when(() => app.account.deleteAccount()).thenAnswer(
        (_) async =>
            ++deletes == 1 ? const Err(PartlyDeletedFailure()) : const Ok(null),
      );
      when(() => app.account.signOut()).thenAnswer((_) async {
        app.users.add(null);
        return const Ok(null);
      });
      await tapText(tester, 'Delete account');
      expect(find.bySemanticsLabel('Back'), findsOneWidget);
      await tapButton(tester, 'Delete account');
      await tapText(tester, 'Delete');

      expect(
        find.text(
          'Almost done: your data is deleted, but your sign-in is not yet. '
          'Try again to finish.',
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Back'), findsNothing);
      expect(
        tester
            .widget<ForgeButton>(
              find.widgetWithText(ForgeButton, 'Delete account'),
            )
            .onPressed,
        isNull,
      );
      // The system back stays too.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DeleteAccountPage), findsOneWidget);

      await tapText(tester, 'Try again');

      expect(deletes, 2);
      expect(find.byType(OnboardingPage), findsOneWidget);
    });
  });
}
