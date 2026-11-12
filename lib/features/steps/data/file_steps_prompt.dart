import 'dart:io';

import 'package:forge_core/forge_core.dart';

import '../domain/steps_prompt.dart';

/// That the user was asked on this device is an empty file in
/// [_directory].
class FileStepsPrompt implements StepsPrompt {
  const FileStepsPrompt(this._directory);

  final Future<Directory> Function() _directory;

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
      File('${(await _directory()).path}/steps_access_asked');
}
