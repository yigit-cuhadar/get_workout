import 'dart:convert';
import 'dart:io';

import 'package:forge_core/forge_core.dart';

import '../../programs/domain/calendar_date.dart';
import '../domain/measurement_prompt.dart';

/// Each user's dismissed measurement prompt as JSON
/// (`{"version": 1, "dismissed": "YYYY-MM-DD"}`) in
/// `measurement_prompt_<uid>.json` in [_directory], replaced whole on every
/// save (temporary file, then rename). A file that cannot be read reads as
/// nothing dismissed: at worst the prompt shows again.
class FileMeasurementPromptStore implements MeasurementPromptStore {
  FileMeasurementPromptStore(this._directory);

  final Future<Directory> Function() _directory;
  Future<void> _tail = Future.value();

  static const version = 1;

  @override
  Future<Result<CalendarDate?>> loadDismissed(String uid) => guard(() async {
    await _tail;
    final file = await _file(uid);
    if (!await file.exists()) return null;
    try {
      if (jsonDecode(await file.readAsString()) case {
        'version': version,
        'dismissed': final String dismissed,
      }) {
        return CalendarDate.tryParse(dismissed);
      }
      throw const FormatException('unknown measurement prompt file');
    } on FormatException catch (error, stack) {
      Log.e('progress', 'measurement prompt file unreadable', error, stack);
      return null;
    }
  });

  @override
  Future<Result<void>> saveDismissed(String uid, CalendarDate date) {
    final run = _tail.then((_) => _write(uid, date));
    _tail = run.catchError((Object _) {});
    return guard(() => run);
  }

  Future<void> _write(String uid, CalendarDate date) async {
    final file = await _file(uid);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.partial');
    await temporary.writeAsString(
      jsonEncode({'version': version, 'dismissed': date.toIso()}),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<File> _file(String uid) async =>
      File('${(await _directory()).path}/measurement_prompt_$uid.json');
}
