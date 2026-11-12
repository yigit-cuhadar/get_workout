import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/features/account/data/firebase_telemetry.dart';
import 'package:mocktail/mocktail.dart';

class MockAnalytics extends Mock implements FirebaseAnalytics {}

class MockCrashlytics extends Mock implements FirebaseCrashlytics {}

void main() {
  late Directory directory;
  late MockAnalytics analytics;
  late MockCrashlytics crashlytics;

  /// What the SDKs were last told; null before anything.
  bool? collecting;

  final flutterError = FlutterError.onError;
  final platformError = PlatformDispatcher.instance.onError;
  final logError = Log.onError;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('telemetry');
    analytics = MockAnalytics();
    crashlytics = MockCrashlytics();
    collecting = null;
    when(() => analytics.setAnalyticsCollectionEnabled(any())).thenAnswer(
      (call) async => collecting = call.positionalArguments.first as bool,
    );
    when(() => analytics.resetAnalyticsData()).thenAnswer((_) async {});
    when(() => crashlytics.setCrashlyticsCollectionEnabled(any()))
        .thenAnswer((_) async {});
    when(() => crashlytics.deleteUnsentReports()).thenAnswer((_) async {});
  });

  tearDown(() {
    FlutterError.onError = flutterError;
    PlatformDispatcher.instance.onError = platformError;
    Log.onError = logError;
    directory.deleteSync(recursive: true);
  });

  FirebaseTelemetry telemetry({bool allowed = true}) => FirebaseTelemetry(
    allowed: allowed,
    // Not created yet, as app support is on a first run.
    directory: () async => Directory('${directory.path}/support'),
    analytics: analytics,
    crashlytics: crashlytics,
  );

  /// A telemetry following [uid] that said [consent].
  Future<FirebaseTelemetry> answered(String uid, bool consent) async {
    final subject = telemetry();
    await subject.follow(uid);
    await subject.apply(uid, consent);
    return subject;
  }

  group('start', () {
    test('collects nothing for nobody or a user never asked here', () async {
      await telemetry().start(null);
      expect(collecting, isFalse);
      await telemetry().start('u1');
      expect(collecting, isFalse);
    });

    test('applies only the signed-in user\'s own answer', () async {
      await answered('u1', true);
      await answered('u2', false);

      await telemetry().start('u1');
      expect(collecting, isTrue);
      await telemetry().start('u2');
      expect(collecting, isFalse);
      await telemetry().start(null);
      expect(collecting, isFalse);
    });
  });

  test('another user turns collection off until their answer', () async {
    final subject = await answered('u1', true);
    expect(collecting, isTrue);

    await subject.follow('u2');
    expect(collecting, isFalse);
    // The previous user's answer no longer applies.
    await subject.apply('u1', true);
    expect(collecting, isFalse);
    await subject.apply('u2', true);
    expect(collecting, isTrue);
  });

  test('following the same user again changes nothing', () async {
    final subject = await answered('u1', true);
    await subject.follow('u1');
    expect(collecting, isTrue);
  });

  test('never collects where not allowed, whatever the consent', () async {
    final subject = telemetry(allowed: false);
    await subject.follow('u1');
    await subject.apply('u1', true);
    expect(collecting, isFalse);
    verifyNever(() => crashlytics.setCrashlyticsCollectionEnabled(true));
  });

  test('of quick answers the latest wins', () async {
    final subject = telemetry();
    await subject.follow('u1');
    await Future.wait([subject.apply('u1', true), subject.apply('u1', false)]);
    expect(collecting, isFalse);
    await telemetry().start('u1');
    expect(collecting, isFalse);
  });

  test('crash reports kept from before a yes are dropped, once', () async {
    final subject = await answered('u1', false);
    verifyNever(() => crashlytics.deleteUnsentReports());
    await subject.apply('u1', true);
    verify(() => crashlytics.deleteUnsentReports()).called(1);
    // Reports recorded with consent are left to be sent.
    await subject.apply('u1', true);
    verifyNever(() => crashlytics.deleteUnsentReports());
  });

  test('a yes that fails on the way is not saved', () async {
    when(() => crashlytics.deleteUnsentReports())
        .thenThrow(Exception('no plugin'));
    final subject = telemetry();
    await subject.follow('u1');
    expect((await subject.apply('u1', true)).isOk, isFalse);
    expect(collecting, isFalse);

    await telemetry().start('u1');
    expect(collecting, isFalse);
  });

  test('forgetting a user stops collection and records no', () async {
    final subject = await answered('u1', true);
    expect((await subject.forget('u1')).isOk, isTrue);
    expect(collecting, isFalse);
    verify(() => analytics.resetAnalyticsData()).called(1);
    await telemetry().start('u1');
    expect(collecting, isFalse);
  });

  test(
    'a failure is reported, not thrown, and later calls still run',
    () async {
      when(() => analytics.setAnalyticsCollectionEnabled(any()))
          .thenThrow(Exception('no plugin'));
      final subject = telemetry();
      expect((await subject.follow('u1')).isOk, isFalse);
      expect((await subject.apply('u1', false)).isOk, isFalse);
    },
  );
}
