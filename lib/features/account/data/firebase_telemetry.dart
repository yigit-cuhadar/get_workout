import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/consent_repository.dart';

/// Firebase Analytics and Crashlytics, collecting only where [allowed] (the
/// prod project in release builds, as `forge_firebase` decides) and only
/// with the user's consent.
///
/// The last consent applied is a file in [_directory], so [start] can apply
/// it at launch before anyone's settings are read. Both SDKs also start with
/// collection off natively (Info.plist, AndroidManifest.xml), so a first
/// launch collects nothing before a yes.
class FirebaseTelemetry implements Telemetry {
  const FirebaseTelemetry({
    required this.allowed,
    required this._directory,
    required this._analytics,
    required this._crashlytics,
  });

  final bool allowed;
  final Future<Directory> Function() _directory;
  final FirebaseAnalytics _analytics;
  final FirebaseCrashlytics _crashlytics;

  /// Stands in for `forge_firebase`'s `initFirebase` after
  /// `Firebase.initializeApp`: that turns collection on before the app can
  /// say whether the user agreed.
  Future<void> start() async {
    final consent = await _readConsent();
    await _setCollection(allowed && consent == true);
    FlutterError.onError = _crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
    Log.onError = (error, stack, reason) =>
        _crashlytics.recordError(error, stack, reason: reason);
  }

  @override
  Future<Result<void>> apply(bool consent) => guard(() async {
    final previous = await _readConsent();
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString('$consent');
    final collect = allowed && consent;
    // Reports recorded while the user had not agreed are never sent.
    if (collect && previous != true) await _crashlytics.deleteUnsentReports();
    await _setCollection(collect);
  });

  @override
  Future<Result<void>> forget() => guard(() async {
    await _analytics.resetAnalyticsData();
    await _crashlytics.deleteUnsentReports();
  });

  Future<void> _setCollection(bool collect) async {
    await _crashlytics.setCrashlyticsCollectionEnabled(collect);
    await _analytics.setAnalyticsCollectionEnabled(collect);
  }

  /// Null when never applied on this device or unreadable.
  Future<bool?> _readConsent() async {
    try {
      return switch (await (await _file()).readAsString()) {
        'true' => true,
        'false' => false,
        _ => null,
      };
    } on FileSystemException {
      return null;
    }
  }

  Future<File> _file() async =>
      File('${(await _directory()).path}/analytics_consent');
}
