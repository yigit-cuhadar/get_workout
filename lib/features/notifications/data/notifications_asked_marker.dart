import 'dart:io';

import 'package:forge_core/forge_core.dart';

/// That this device was asked to let the app notify, by the reminders or
/// the rest notification: an empty file in [_directory]. The platforms
/// read a device never asked as refused.
class NotificationsAskedMarker {
  const NotificationsAskedMarker(this._directory);

  final Future<Directory> Function() _directory;

  Future<Result<bool>> exists() =>
      guard(() async => (await _marker()).exists());

  Future<Result<void>> set() => guard(() async {
    final marker = await _marker();
    await marker.parent.create(recursive: true);
    await marker.writeAsString('');
  });

  Future<File> _marker() async =>
      File('${(await _directory()).path}/notifications_asked');
}
