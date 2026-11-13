import 'dart:async';
import 'dart:io';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_firebase/forge_firebase.dart';
import 'package:get_workout/features/account/domain/account_usecases.dart';
import 'package:get_workout/features/account/domain/consent_repository.dart';
import 'package:get_workout/features/account/presentation/consent_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class MockConsentRepository extends Mock implements ConsentRepository {}

class MockAnalytics extends Mock implements FirebaseAnalytics {}

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

/// [FirebaseTelemetry] keeping every result it returned, so a test can wait
/// until each change asked of it has run.
class TrackedTelemetry implements Telemetry {
  TrackedTelemetry(this._telemetry);

  final FirebaseTelemetry _telemetry;
  final _running = <Future<Result<void>>>[];

  Future<Result<void>> _track(Future<Result<void>> result) {
    _running.add(result);
    return result;
  }

  /// Completes once every change asked for so far, and any asked for while
  /// waiting, has run.
  Future<void> get settled async {
    while (_running.isNotEmpty) {
      final running = List.of(_running);
      _running.clear();
      await Future.wait(running);
    }
  }

  @override
  Future<Result<void>> follow(String? uid) => _track(_telemetry.follow(uid));

  @override
  Future<Result<void>> apply(String uid, bool consent) =>
      _track(_telemetry.apply(uid, consent));

  @override
  Future<Result<void>> forget(String uid) => _track(_telemetry.forget(uid));
}

/// The cubit over the real [FirebaseTelemetry], with the Firebase SDKs
/// recording whether they collect, so these check what is collected.
void main() {
  const guestA = AuthUser(id: 'a', isAnonymous: true);
  const guestB = AuthUser(id: 'b', isAnonymous: true);
  const member = AuthUser(id: 'm', email: 'm@b.co');

  late Directory directory;
  late MockAuthRepository auth;
  late MockConsentRepository consents;
  late MockAnalytics analytics;
  late MockCrashlytics crashlytics;
  late StreamController<AuthUser?> users;
  late Map<String, StreamController<StoredConsent>> stored;

  /// What the SDKs were last told; null before anything.
  bool? collecting;
  late List<bool> history;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('consent');
    auth = MockAuthRepository();
    consents = MockConsentRepository();
    analytics = MockAnalytics();
    crashlytics = MockCrashlytics();
    users = StreamController<AuthUser?>();
    stored = {};
    collecting = null;
    history = [];
    when(() => auth.watchUser()).thenAnswer((_) => users.stream);
    when(() => consents.watchConsent(any())).thenAnswer(
      (call) => stored
          .putIfAbsent(
            call.positionalArguments.first as String,
            StreamController<StoredConsent>.new,
          )
          .stream,
    );
    when(() => consents.saveConsent(any(), any()))
        .thenAnswer((_) async => const Ok(null));
    when(() => analytics.setAnalyticsCollectionEnabled(any()))
        .thenAnswer((call) async {
          collecting = call.positionalArguments.first as bool;
          history.add(collecting!);
        });
    when(() => analytics.resetAnalyticsData()).thenAnswer((_) async {});
    when(() => crashlytics.setCrashlyticsCollectionEnabled(any()))
        .thenAnswer((_) async {});
    when(() => crashlytics.deleteUnsentReports()).thenAnswer((_) async {});
  });

  tearDown(() => directory.deleteSync(recursive: true));

  FirebaseTelemetry telemetry() => FirebaseTelemetry(
    allowed: true,
    directory: () async => directory,
    analytics: analytics,
    crashlytics: crashlytics,
  );

  /// The telemetry the cubit drives.
  late TrackedTelemetry subject;
  setUp(() => subject = TrackedTelemetry(telemetry()));

  late ValueNotifier<bool> deleting;
  setUp(() => deleting = ValueNotifier(false));

  ConsentCubit build() => ConsentCubit(
    watchAuthUser: WatchAuthUser(auth),
    getCurrentUser: GetCurrentUser(auth),
    deletionUnderway: deleting,
    watchConsent: WatchAnalyticsConsent(consents),
    saveConsent: SaveAnalyticsConsent(consents),
    followUser: FollowAnalyticsUser(subject),
    applyConsent: ApplyAnalyticsConsent(subject),
  );

  /// Lets the cubit see the events, then waits until every change it asked
  /// of the telemetry has run, so assertions never depend on timing.
  Future<void> settle() async {
    await pumpEventQueue();
    await subject.settled;
  }

  Future<void> signIn(AuthUser? user) async {
    when(() => auth.currentUser).thenReturn(user);
    users.add(user);
    await settle();
  }

  Future<void> answer(
    String uid,
    bool? consent, {
    bool fromServer = true,
  }) async {
    stored[uid]!.add((consent: consent, fromServer: fromServer));
    await settle();
  }

  test('a yes collects for that user', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', true);
    expect(collecting, isTrue);
    expect(cubit.state.consent, isTrue);
    await cubit.close();
  });

  test('A said yes, signs out; guest B is not collected', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', true);
    expect(collecting, isTrue);

    await signIn(null);
    expect(collecting, isFalse);
    await signIn(guestB);
    expect(collecting, isFalse);
    // A's answer arriving late is no longer followed.
    await answer('a', true);
    expect(collecting, isFalse);
    await cubit.close();
  });

  test('a failed read for the new user leaves collection off', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', true);
    await signIn(guestB);
    stored['b']!.addError(const PermissionFailure());
    await settle();
    expect(collecting, isFalse);
    expect(cubit.state.loaded, isFalse);
    await cubit.close();
  });

  test('killed before B\'s answer arrives, the next start for B collects '
      'nothing, while A still gets their own', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', true);
    await signIn(guestB);
    await cubit.close();

    await telemetry().restore('b');
    expect(collecting, isFalse);
    await telemetry().restore('a');
    expect(collecting, isTrue);
  });

  test('a guest who said yes signs in to an account that said no', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', true);
    history.clear();

    await signIn(member);
    await answer('m', false);

    expect(history, everyElement(isFalse));
    expect(collecting, isFalse);
    await cubit.close();
  });

  test(
    'after deletion nothing is collected, now or at the next start',
    () async {
      final cubit = build();
      await signIn(guestA);
      await answer('a', true);

      await subject.forget('a');
      expect(collecting, isFalse);
      await telemetry().restore('a');
      expect(collecting, isFalse);
      await cubit.close();
    },
  );

  test('the deleted user\'s vanished answer neither asks nor applies, and '
      'the next guest is asked once the server says so', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', null);
    expect(cubit.state.unanswered, isTrue);
    history.clear();

    deleting.value = true;
    await settle();
    expect(cubit.state, const ConsentState());
    // The server deleted A's document.
    await answer('a', null);
    expect(cubit.state.unanswered, isFalse);
    expect(history, isEmpty);

    // Signed out before the deletion ends; A is not followed again.
    when(() => auth.currentUser).thenReturn(null);
    deleting.value = false;
    await settle();
    expect(cubit.state, const ConsentState());

    await signIn(guestB);
    await answer('b', null);
    expect(cubit.state.uid, 'b');
    expect(cubit.state.unanswered, isTrue);
    await cubit.close();
  });

  test('a deletion that failed follows the user again', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', true);

    deleting.value = true;
    await settle();
    expect(cubit.state.loaded, isFalse);

    // Watched afresh, like Firestore's new snapshot stream.
    stored.remove('a');
    deleting.value = false;
    await answer('a', true);
    expect(cubit.state.consent, isTrue);
    expect(collecting, isTrue);
    await cubit.close();
  });

  test('a cached copy without an answer neither asks nor applies', () async {
    final cubit = build();
    await signIn(guestA);
    history.clear();
    await answer('a', null, fromServer: false);
    expect(cubit.state.unanswered, isFalse);
    expect(history, isEmpty);

    await answer('a', null);
    expect(cubit.state.unanswered, isTrue);
    expect(collecting, isFalse);
    await cubit.close();
  });

  test('a yes still running when the user changes never turns collection '
      'on, however slowly its steps finish', () async {
    final slowDelete = Completer<void>();
    when(() => crashlytics.deleteUnsentReports())
        .thenAnswer((_) => slowDelete.future);
    final cubit = build();
    await signIn(guestA);
    history.clear();

    // A's yes starts and waits on the crash report deletion...
    stored['a']!.add((consent: true, fromServer: true));
    await pumpEventQueue();
    // ...while B signs in, and only then does the deletion finish.
    users.add(guestB);
    await pumpEventQueue();
    slowDelete.complete();
    await subject.settled;

    expect(history, everyElement(isFalse));
    expect(collecting, isFalse);
    verifyNever(() => analytics.setAnalyticsCollectionEnabled(true));
    // Nor is the overtaken yes saved for the next start.
    await telemetry().restore('a');
    expect(collecting, isFalse);
    await cubit.close();
  });

  test('a slow off for the new user still ends off when it finishes '
      'after the yes it follows', () async {
    final slowOff = Completer<void>();
    final cubit = build();
    await signIn(guestA);
    await answer('a', true);
    when(() => analytics.setAnalyticsCollectionEnabled(false))
        .thenAnswer((_) async {
          await slowOff.future;
          collecting = false;
          history.add(false);
        });

    users.add(guestB);
    await pumpEventQueue();
    // An answer for A arriving now is not applied, even though the off
    // has not finished.
    stored['a']!.add((consent: true, fromServer: true));
    await pumpEventQueue();
    slowOff.complete();
    await subject.settled;

    expect(collecting, isFalse);
    await cubit.close();
  });

  blocTest<ConsentCubit, ConsentState>(
    'an answer is saved for the signed-in user',
    build: () => build(),
    act: (cubit) async {
      await signIn(guestA);
      await answer('a', null);
      await cubit.answer(true);
    },
    verify: (_) => verify(() => consents.saveConsent('a', true)).called(1),
  );

  test('an answer given after the user changed is not saved', () async {
    final cubit = build();
    await signIn(guestA);
    await answer('a', null);
    // A dialog asked A; B signs in before the answer comes.
    await signIn(guestB);
    await cubit.answer(true);
    await signIn(null);
    await cubit.answer(true);

    verifyNever(() => consents.saveConsent(any(), any()));
    await cubit.close();
  });

  blocTest<ConsentCubit, ConsentState>(
    'a failed save is reported and the answer stays as stored',
    setUp: () =>
        when(() => consents.saveConsent(any(), any()))
            .thenAnswer((_) async => const Err(NetworkFailure())),
    build: () => build(),
    act: (cubit) async {
      await signIn(guestA);
      await answer('a', false);
      await cubit.answer(true);
    },
    expect: () => [
      const ConsentState(uid: 'a', stored: (consent: false, fromServer: true)),
      isA<ConsentState>()
          .having((s) => s.consent, 'consent', false)
          .having((s) => s.failure, 'failure', isA<NetworkFailure>()),
    ],
  );
}
