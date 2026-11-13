import 'dart:convert';
import 'dart:io';

import 'package:forge_core/forge_core.dart';

import '../domain/body_chart.dart';

/// Each user's Body chart choice as JSON
/// (`{"version": 1, "series": ["<code>", …], "targetLine": true}`) in
/// `body_chart_<uid>.json` in [_directory], replaced whole on every save
/// (temporary file, then rename). A file that cannot be read, or of an
/// unknown version, reads as not chosen and is replaced by the next save:
/// it holds nothing that cannot be picked again. Unknown series codes are
/// dropped. Saves run one at a time, so the last choice saved wins.
class FileBodyChartStore implements BodyChartStore {
  FileBodyChartStore(this._directory);

  final Future<Directory> Function() _directory;
  Future<void> _tail = Future.value();

  static const version = 1;

  @override
  Future<Result<BodyChartChoice?>> load(String uid) => guard(() async {
    await _tail;
    final file = await _file(uid);
    if (!await file.exists()) return null;
    try {
      if (jsonDecode(await file.readAsString()) case {
        'version': version,
        'series': final List<Object?> series,
        'targetLine': final bool targetLine,
      }) {
        return BodyChartChoice(
          series: [for (final code in series) ?BodySeries.fromCode(code)],
          targetLine: targetLine,
        );
      }
      throw const FormatException('unknown body chart file');
    } on FormatException catch (error, stack) {
      Log.e('body', 'body chart choice unreadable', error, stack);
      return null;
    }
  });

  @override
  Future<Result<void>> save(String uid, BodyChartChoice choice) {
    final run = _tail.then((_) => _write(uid, choice));
    _tail = run.catchError((Object _) {});
    return guard(() => run);
  }

  Future<void> _write(String uid, BodyChartChoice choice) async {
    final file = await _file(uid);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.partial');
    await temporary.writeAsString(
      jsonEncode({
        'version': version,
        'series': [for (final series in choice.series) series.code],
        'targetLine': choice.targetLine,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<File> _file(String uid) async =>
      File('${(await _directory()).path}/body_chart_$uid.json');
}
