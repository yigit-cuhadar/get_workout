import 'dart:io';

import 'package:forge_core/forge_core.dart';
import 'package:forge_notifications/forge_notifications.dart';

import '../domain/rest_notifications.dart';

/// [RestNotifications] over the app's local notifications, waiting until
/// they are initialised. That the user was asked on this device is an
/// empty file in [_directory].
class DeviceRestNotifications implements RestNotifications {
  const DeviceRestNotifications(this._notifications, this._directory);

  final Future<Notifications> _notifications;
  final Future<Directory> Function() _directory;

  /// The rest notification's id; other notifications use others.
  static const id = 1;

  @override
  Future<Result<bool>> allowed() async =>
      (await (await _notifications).status()).map(
        (permission) => permission == NotificationPermission.granted,
      );

  @override
  Future<Result<bool>> request() async {
    final notifications = await _notifications;
    final granted = (await notifications.request()).map(
      (permission) => permission == NotificationPermission.granted,
    );
    if (granted.valueOrNull == true &&
        (await notifications.canScheduleExact()).valueOrNull == false) {
      // Refused or failed, the notification falls back to an inexact alarm.
      await notifications.requestExact();
    }
    return granted;
  }

  @override
  Future<Result<void>> schedule(
    DateTime at, {
    required String title,
    required String body,
  }) async =>
      (await _notifications).scheduleAt(id, at, title: title, body: body);

  @override
  Future<Result<void>> cancel() async => (await _notifications).cancel(id);

  @override
  Future<Result<bool>> askedHere() =>
      guard(() async => (await _marker()).exists());

  @override
  Future<Result<void>> markAskedHere() => guard(() async {
    final marker = await _marker();
    await marker.parent.create(recursive: true);
    await marker.writeAsString('');
  });

  Future<File> _marker() async =>
      File('${(await _directory()).path}/rest_notifications_asked');
}
