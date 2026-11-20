import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/feedback/data/firestore_admin_feedback_repository.dart';
import 'package:get_workout/admin/feedback/domain/admin_feedback_repository.dart';
import 'package:get_workout/admin/feedback/domain/feedback_admin_usecases.dart';
import 'package:get_workout/admin/feedback/domain/feedback_entry.dart';
import 'package:get_workout/admin/feedback/presentation/feedback_admin_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockAdminFeedbackRepository extends Mock
    implements AdminFeedbackRepository {}

Map<String, Object?> _doc(String uid, String message, String status, int day) =>
    {
      'uid': uid,
      'message': message,
      'source': 'profile',
      'appVersion': '1.0.0+1',
      'platform': 'ios',
      'osVersion': '26.1',
      'deviceModel': 'iPhone17,1',
      'locale': 'en-GB',
      'status': status,
      'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
    };

FeedbackEntry _entry(String path, FeedbackEntryStatus status) => FeedbackEntry(
  path: path,
  uid: 'u1',
  email: null,
  message: 'Hi',
  source: 'profile',
  appVersion: '',
  platform: '',
  osVersion: '',
  deviceModel: '',
  locale: '',
  createdAt: null,
  status: status,
);

void main() {
  group('FirestoreAdminFeedbackRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreAdminFeedbackRepository repository;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreAdminFeedbackRepository(firestore);
      await firestore
          .doc('users/u1/feedback/a')
          .set(_doc('u1', 'Old', 'open', 1));
      await firestore.doc('users/u2/feedback/b').set({
        ..._doc('u2', 'New', 'open', 3),
        'email': 'c@d.co',
      });
      await firestore
          .doc('users/u2/feedback/c')
          .set(_doc('u2', 'Done', 'closed', 2));
    });

    test(
      'lists one status across users, newest first, with every field',
      () async {
        final open = await repository.watch(FeedbackEntryStatus.open).first;

        expect(open.map((e) => e.message), ['New', 'Old']);
        expect(
          open.first,
          FeedbackEntry(
            path: 'users/u2/feedback/b',
            uid: 'u2',
            email: 'c@d.co',
            message: 'New',
            source: 'profile',
            appVersion: '1.0.0+1',
            platform: 'ios',
            osVersion: '26.1',
            deviceModel: 'iPhone17,1',
            locale: 'en-GB',
            createdAt: DateTime(2026, 11, 3),
            status: FeedbackEntryStatus.open,
          ),
        );
        expect(
          (await repository.watch(FeedbackEntryStatus.closed).first).map(
            (e) => e.message,
          ),
          ['Done'],
        );
      },
    );

    test('closes and reopens by path, changing only the status', () async {
      await repository.setStatus(
        'users/u1/feedback/a',
        FeedbackEntryStatus.closed,
      );

      final doc = await firestore.doc('users/u1/feedback/a').get();
      expect(doc.data(), {..._doc('u1', 'Old', 'closed', 1)});
    });

    test(
      'reads a missing or odd field as empty, an unknown status as open',
      () {
        final entry = FirestoreAdminFeedbackRepository.fromMap(
          'users/u/feedback/x',
          {'message': 'Hi', 'email': 3, 'status': 'snoozed'},
        );

        expect(entry.email, isNull);
        expect(entry.uid, '');
        expect(entry.createdAt, isNull);
        expect(entry.status, FeedbackEntryStatus.open);
      },
    );
  });

  group('FeedbackAdminCubit', () {
    late MockAdminFeedbackRepository repository;
    late StreamController<List<FeedbackEntry>> open;
    late StreamController<List<FeedbackEntry>> closed;
    final a = _entry('users/u1/feedback/a', FeedbackEntryStatus.open);
    final c = _entry('users/u2/feedback/c', FeedbackEntryStatus.closed);

    setUp(() {
      repository = MockAdminFeedbackRepository();
      open = StreamController();
      closed = StreamController();
      when(() => repository.watch(FeedbackEntryStatus.open))
          .thenAnswer((_) => open.stream);
      when(() => repository.watch(FeedbackEntryStatus.closed))
          .thenAnswer((_) => closed.stream);
      when(() => repository.setStatus(any(), FeedbackEntryStatus.closed))
          .thenAnswer((_) async => const Ok(null));
    });

    setUpAll(() => registerFallbackValue(FeedbackEntryStatus.open));

    FeedbackAdminCubit build() => FeedbackAdminCubit(
      watchFeedback: WatchFeedback(repository),
      setFeedbackStatus: SetFeedbackStatus(repository),
      firstRetryDelay: Duration.zero,
    );

    blocTest<FeedbackAdminCubit, FeedbackAdminState>(
      'shows open messages, then closed ones when filtered',
      build: build,
      act: (cubit) async {
        open.add([a]);
        await pumpEventQueue();
        cubit.filter(FeedbackEntryStatus.closed);
        open.add([a, a]);
        closed.add([c]);
        await pumpEventQueue();
      },
      expect: () => [
        FeedbackAdminState(entries: [a]),
        const FeedbackAdminState(filter: FeedbackEntryStatus.closed),
        FeedbackAdminState(filter: FeedbackEntryStatus.closed, entries: [c]),
      ],
    );

    blocTest<FeedbackAdminCubit, FeedbackAdminState>(
      'closes an open message, marking it busy meanwhile',
      build: build,
      act: (cubit) => cubit.toggle(a),
      expect: () => [
        FeedbackAdminState(updating: {a.path}),
        const FeedbackAdminState(),
      ],
      verify: (_) =>
          verify(() => repository.setStatus(a.path, FeedbackEntryStatus.closed))
              .called(1),
    );

    blocTest<FeedbackAdminCubit, FeedbackAdminState>(
      'keeps a failed change to show',
      setUp: () => when(() => repository.setStatus(any(), any()))
          .thenAnswer((_) async => const Err(PermissionFailure('no claim'))),
      build: build,
      act: (cubit) => cubit.toggle(c),
      expect: () => [
        FeedbackAdminState(updating: {c.path}),
        const FeedbackAdminState(updateFailure: PermissionFailure('no claim')),
      ],
    );
  });
}
