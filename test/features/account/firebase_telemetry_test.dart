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

  setUp(() {
    directory = Directory.systemTemp.createTempSync('telemetry');
    analytics = MockAnalytics();
    crashlytics = MockCrashlytics();
    when(() => analytics.setAnalyticsCollectionEnabled(any()))
        .thenAnswer((_) async {});
    when(() => analytics.resetAnalyticsData()).thenAnswer((_) async {});
    when(() => crashlytics.setCrashlyticsCollectionEnabled(any()))
        .thenAnswer((_) async {});
    when(() => crashlytics.deleteUnsentReports()).thenAnswer((_) async {});
  });

  tearDown(() => directory.deleteSync(recursive: true));

  FirebaseTelemetry telemetry({bool allowed = true}) => FirebaseTelemetry(
    allowed: allowed,
    // Not created yet, as app support is on a first run.
    directory: () async => Directory('${directory.path}/support'),
    analytics: analytics,
    crashlytics: crashlytics,
  );

  void verifyCollection(bool collect) {
    verify(() => crashlytics.setCrashlyticsCollectionEnabled(collect));
    verify(() => analytics.setAnalyticsCollectionEnabled(collect));
  }

  group('start', () {
    final onError = FlutterError.onError;
    final platformError = PlatformDispatcher.instance.onError;
    final logError = Log.onError;
    tearDown(() {
      FlutterError.onError = onError;
      PlatformDispatcher.instance.onError = platformError;
      Log.onError = logError;
    });

    test('collects nothing on a device never asked', () async {
      await telemetry().start();
      verifyCollection(false);
    });

    test('applies the consent applied last on this device', () async {
      await telemetry().apply(true);
      clearInteractions(analytics);
      clearInteractions(crashlytics);

      await telemetry().start();

      verifyCollection(true);
    });
  });

  test('collects only with consent', () async {
    final subject = telemetry();
    await subject.apply(true);
    verifyCollection(true);
    await subject.apply(false);
    verifyCollection(false);
  });

  test('never collects where not allowed, whatever the consent', () async {
    await telemetry(allowed: false).apply(true);
    verifyCollection(false);
    verifyNever(() => crashlytics.deleteUnsentReports());
    verifyNever(() => crashlytics.setCrashlyticsCollectionEnabled(true));
  });

  test('crash reports kept from before a yes are dropped, once', () async {
    final subject = telemetry();
    await subject.apply(false);
    verifyNever(() => crashlytics.deleteUnsentReports());
    await subject.apply(true);
    verify(() => crashlytics.deleteUnsentReports()).called(1);
    // Reports recorded with consent are left to be sent.
    await subject.apply(true);
    verifyNever(() => crashlytics.deleteUnsentReports());
  });

  test('forgets the analytics id and unsent reports', () async {
    expect((await telemetry().forget()).isOk, isTrue);
    verify(() => analytics.resetAnalyticsData()).called(1);
    verify(() => crashlytics.deleteUnsentReports()).called(1);
  });

  test('a failure is reported, not thrown', () async {
    when(() => analytics.setAnalyticsCollectionEnabled(any()))
        .thenThrow(Exception('no plugin'));
    expect((await telemetry().apply(true)).isOk, isFalse);
  });
}
