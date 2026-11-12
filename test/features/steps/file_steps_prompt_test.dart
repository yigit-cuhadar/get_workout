import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/steps/data/file_steps_prompt.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('steps_prompt'));
  tearDown(() => directory.deleteSync(recursive: true));

  test('not asked until marked, then asked', () async {
    // A directory not created yet, as app support is on a first run.
    final prompt = FileStepsPrompt(
      () async => Directory('${directory.path}/support'),
    );
    expect((await prompt.askedHere()).valueOrNull, isFalse);

    expect((await prompt.markAskedHere()).isOk, isTrue);

    expect((await prompt.askedHere()).valueOrNull, isTrue);
  });
}
