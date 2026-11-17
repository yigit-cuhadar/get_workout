import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_workout/features/account/data/firestore_sync_repository.dart';
import 'package:mocktail/mocktail.dart';

class MockFirestore extends Mock implements FirebaseFirestore {}

void main() {
  late MockFirestore firestore;
  late StreamController<void> inSync;
  late Completer<void> written;

  setUp(() {
    firestore = MockFirestore();
    inSync = StreamController<void>.broadcast();
    written = Completer<void>();
    when(() => firestore.snapshotsInSync()).thenAnswer((_) => inSync.stream);
    when(() => firestore.waitForPendingWrites())
        .thenAnswer((_) => written.future);
  });

  tearDown(() => inSync.close());

  FirestoreSyncRepository repository() => FirestoreSyncRepository(
    firestore,
    settle: const Duration(milliseconds: 10),
  );

  test('is backed up when nothing waits', () async {
    written.complete();
    expect(await repository().watchBackedUp().first, isTrue);
  });

  test('waits until the server has the writes', () async {
    final states = <bool>[];
    final subscription = repository().watchBackedUp().listen(states.add);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(states, [false]);
    written.complete();
    await pumpEventQueue();
    expect(states, [false, true]);
    await subscription.cancel();
  });

  test('checks again when the listeners settle', () async {
    written.complete();
    final states = <bool>[];
    final subscription = repository().watchBackedUp().listen(states.add);
    await pumpEventQueue();
    expect(states, [true]);
    written = Completer<void>();
    inSync.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(states, [true, false]);
    await subscription.cancel();
  });

  test('a failed wait reads as waiting', () async {
    written.completeError(StateError('user changed'));
    final states = <bool>[];
    final subscription = repository().watchBackedUp().listen(states.add);
    await pumpEventQueue();
    expect(states, [false]);
    await subscription.cancel();
  });
}
