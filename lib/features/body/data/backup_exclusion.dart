import 'package:flutter/services.dart';
import 'package:forge_core/forge_core.dart';

/// Keeps a file or folder (and all it holds) out of the device's own
/// backups. On iOS this sets `isExcludedFromBackup` through the Runner's
/// `getworkout/backup_exclusion` channel (`AppDelegate.swift`); Android
/// does it with the backup rules in its manifest, so there is nothing to do
/// at run time. A failure is logged only.
Future<void> Function(String path) backupExclusion(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? _excludeOnIos : _nothing;

const _channel = MethodChannel('getworkout/backup_exclusion');

Future<void> _excludeOnIos(String path) async {
  try {
    await _channel.invokeMethod<void>('exclude', path);
  } on Object catch (error, stack) {
    Log.e('body', 'not kept out of the device backup: $path', error, stack);
  }
}

Future<void> _nothing(String path) async {}
