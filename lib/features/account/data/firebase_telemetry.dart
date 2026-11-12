import 'dart:async';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:forge_core/forge_core.dart';

import '../domain/consent_repository.dart';

/// Firebase Analytics and Crashlytics, collecting only where [allowed] (the
/// prod project in release builds, as `forge_firebase` decides) and only
/// for a user who said yes.
///
/// Each user's last answer is a file of their own in [_directory], so
/// [start] can apply the signed-in user's at launch, before their settings
/// are read; another user's answer never applies. Both SDKs also start
/// with collection off natively (Info.plist, AndroidManifest.xml).
///
/// Changes run one at a time, in order. A user change ([follow]) or a
/// later answer counts from the moment it is made: an answer still waiting,
/// or still running (e.g. on a slow crash report deletion), stops before
/// its next step, so a yes never turns collection on, or is saved, after
/// it was overtaken.
class FirebaseTelemetry implements Telemetry {
  FirebaseTelemetry({
    required this.allowed,
    required this._directory,
    required this._analytics,
    required this._crashlytics,
  });

  final bool allowed;
  final Future<Directory> Function() _directory;
  final FirebaseAnalytics _analytics;
  final FirebaseCrashlytics _crashlytics;

  /// The user collection follows; see [follow].
  String? _uid;
  Future<void> _tail = Future.value();
  int _latest = 0;

  /// Stands in for `forge_firebase`'s `initFirebase` after
  /// `Firebase.initializeApp`, which turns collection on before the app can
  /// say whether the user agreed. [uid] is whoever is signed in at launch.
  Future<void> start(String? uid) async {
    _uid = uid;
    final consent = uid == null ? null : await _saved(uid);
    await _setCollection(consent == true);
    FlutterError.onError = _crashlytics.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      _crashlytics.recordError(error, stack, fatal: true);
      return true;
    };
    Log.onError = (error, stack, reason) =>
        _crashlytics.recordError(error, stack, reason: reason);
  }

  /// Completes once every change asked for so far has run.
  @visibleForTesting
  Future<void> get settled async {
    Future<void> tail;
    do {
      tail = _tail;
      await tail;
    } while (!identical(tail, _tail));
  }

  @override
  Future<Result<void>> follow(String? uid) {
    if (uid == _uid) return Future.value(const Ok(null));
    // Set now, so an answer in flight for the previous user stops.
    _uid = uid;
    ++_latest;
    return _run(() => _setCollection(false));
  }

  @override
  Future<Result<void>> apply(String uid, bool consent) {
    final turn = ++_latest;
    // A later answer, a user change or a forget since: no longer counts.
    bool current() => turn == _latest && uid == _uid;
    return _run(() async {
      if (!current()) return;
      if (!consent) {
        await _setCollection(false);
        return _save(uid, false);
      }
      // Reports recorded before the yes are never sent. The yes is saved
      // last, so a failure on the way never leaves one saved.
      if (await _saved(uid) != true) await _crashlytics.deleteUnsentReports();
      if (!current()) return;
      await _setCollection(true);
      // Overtaken while turning on: the change that did it runs next and
      // turns collection off again; the yes is not saved.
      if (!current()) return;
      await _save(uid, true);
    });
  }

  @override
  Future<Result<void>> forget(String uid) {
    ++_latest;
    return _run(() async {
      await _setCollection(false);
      await _save(uid, false);
      await _analytics.resetAnalyticsData();
      await _crashlytics.deleteUnsentReports();
    });
  }

  Future<Result<void>> _run(Future<void> Function() body) {
    final run = _tail.then((_) => body());
    _tail = run.catchError((Object _) {});
    return guard(() => run);
  }

  Future<void> _setCollection(bool consent) async {
    final collect = allowed && consent;
    await _crashlytics.setCrashlyticsCollectionEnabled(collect);
    await _analytics.setAnalyticsCollectionEnabled(collect);
  }

  /// Null when never saved here or unreadable.
  Future<bool?> _saved(String uid) async {
    try {
      return switch (await (await _file(uid)).readAsString()) {
        'true' => true,
        'false' => false,
        _ => null,
      };
    } on FileSystemException {
      return null;
    }
  }

  Future<void> _save(String uid, bool consent) async {
    final file = await _file(uid);
    await file.parent.create(recursive: true);
    await file.writeAsString('$consent', flush: true);
  }

  Future<File> _file(String uid) async {
    // Firebase uids are letters and digits; anything else is replaced.
    final name = uid.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File('${(await _directory()).path}/analytics_consent_$name');
  }
}
