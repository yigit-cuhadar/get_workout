import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/programs/domain/calendar_date.dart';
import 'package:get_workout/features/progress/data/file_measurement_prompt_store.dart';

void main() {
  late Directory directory;
  late FileMeasurementPromptStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('measurement_prompt');
    // Not created yet, as app support is on a first run.
    store = FileMeasurementPromptStore(
      () async => Directory('${directory.path}/support'),
    );
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test('nothing dismissed until saved, then read back per user', () async {
    expect((await store.loadDismissed('u1')).valueOrNull, isNull);

    final sunday = CalendarDate(2026, 11, 15);
    expect((await store.saveDismissed('u1', sunday)).isOk, isTrue);

    expect((await store.loadDismissed('u1')).valueOrNull, sunday);
    expect((await store.loadDismissed('u2')).valueOrNull, isNull);
  });

  test('an unreadable file reads as nothing dismissed', () async {
    File('${directory.path}/support/measurement_prompt_u1.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"version": 9}');

    final result = await store.loadDismissed('u1');
    expect(result.isOk, isTrue);
    expect(result.valueOrNull, isNull);
  });
}
