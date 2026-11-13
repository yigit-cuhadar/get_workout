import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/body/data/file_body_chart_store.dart';
import 'package:get_workout/features/body/domain/body_chart.dart';

void main() {
  late Directory directory;
  late FileBodyChartStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('body_chart');
    // Not created yet, as app support is on a first run.
    store = FileBodyChartStore(
      () async => Directory('${directory.path}/support'),
    );
  });
  tearDown(() => directory.deleteSync(recursive: true));

  File file(String uid) =>
      File('${directory.path}/support/body_chart_$uid.json');

  test('nothing chosen until saved, then read back per user', () async {
    expect((await store.load('u1')).valueOrNull, isNull);

    const choice = BodyChartChoice(
      series: [BodySeries.thigh, BodySeries.weeklySets],
      targetLine: false,
    );
    expect((await store.save('u1', choice)).isOk, isTrue);

    expect((await store.load('u1')).valueOrNull, choice);
    expect((await store.load('u2')).valueOrNull, isNull);
  });

  test('unknown codes are dropped', () async {
    file('u1')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        '{"version": 1, "series": ["waist", "wingspan", 3], '
        '"targetLine": true}',
      );

    expect(
      (await store.load('u1')).valueOrNull,
      const BodyChartChoice(series: [BodySeries.waist]),
    );
  });

  test('an unreadable file reads as not chosen; a save replaces it', () async {
    file('u1')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"version": 2}');
    expect((await store.load('u1')).valueOrNull, isNull);

    file('u1').writeAsStringSync('not json');
    expect((await store.load('u1')).valueOrNull, isNull);

    const choice = BodyChartChoice(series: [BodySeries.hips]);
    await store.save('u1', choice);
    expect((await store.load('u1')).valueOrNull, choice);
  });
}
