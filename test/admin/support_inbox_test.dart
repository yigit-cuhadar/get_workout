import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/support/data/firestore_support_inbox_repository.dart';
import 'package:get_workout/admin/support/domain/support_inbox_repository.dart';
import 'package:get_workout/admin/support/domain/support_inbox_usecases.dart';
import 'package:get_workout/admin/support/domain/support_thread.dart';
import 'package:get_workout/admin/support/presentation/new_thread_count_cubit.dart';
import 'package:get_workout/admin/support/presentation/support_format.dart';
import 'package:get_workout/admin/support/presentation/support_inbox_cubit.dart';
import 'package:get_workout/admin/support/presentation/support_thread_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockRepository extends Mock implements SupportInboxRepository {}

class MockFunctions extends Mock implements FirebaseFunctions {}

class MockCallable extends Mock implements HttpsCallable {}

class MockCallableResult extends Mock implements HttpsCallableResult<Object?> {}

class FunctionsError extends FirebaseFunctionsException {
  FunctionsError(String code, {String? reason, Map<String, Object?>? more})
    : super(
        code: code,
        message: 'error',
        details: reason == null ? null : {'reason': reason, ...?more},
      );
}

Map<String, Object?> _doc(String message, String status, int day) => {
  'uid': 'u1',
  'message': message,
  'source': 'profile',
  'appVersion': '1.0.0+12',
  'platform': 'ios',
  'osVersion': '18.1',
  'deviceModel': 'iPhone 15',
  'locale': 'en-GB',
  'status': status,
  'createdAt': Timestamp.fromDate(DateTime(2026, 11, day)),
};

SupportThread _thread(
  String path, {
  ThreadStatus status = ThreadStatus.unreplied,
  String? email = 'p@example.com',
  DateTime? lastReplyAt,
}) => SupportThread(
  path: path,
  uid: 'u1',
  email: email,
  message: 'Hi',
  source: 'profile',
  appVersion: '1.0.0+12',
  platform: 'ios',
  osVersion: '18.1',
  deviceModel: 'iPhone 15',
  locale: 'en-GB',
  createdAt: null,
  status: status,
  lastReplyAt: lastReplyAt,
);

void main() {
  setUpAll(() {
    registerFallbackValue(ThreadStatus.closed);
    registerFallbackValue((id: '', threadPath: '', message: '', close: false));
  });

  group('FirestoreSupportInboxRepository', () {
    late FakeFirebaseFirestore firestore;
    late MockFunctions functions;
    late MockCallable callable;
    late FirestoreSupportInboxRepository repository;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      functions = MockFunctions();
      callable = MockCallable();
      repository = FirestoreSupportInboxRepository(firestore, functions);
      when(() => functions.httpsCallable('sendSupportReply'))
          .thenReturn(callable);
      when(() => callable.call<Object?>(any()))
          .thenAnswer((_) async => MockCallableResult());
      await firestore.doc('users/u1/feedback/a').set(_doc('Old', 'open', 1));
      await firestore.doc('users/u2/feedback/b').set({
        ..._doc('Answered', 'replied', 3),
        'email': 'c@d.co',
        'lastReplyAt': Timestamp.fromDate(DateTime(2026, 11, 4)),
      });
      await firestore.doc('users/u2/feedback/c').set(_doc('Done', 'closed', 2));
      await firestore.doc('users/u3/feedback/d').set(_doc('Fresh', 'open', 5));
    });

    test('Open lists New and Replied across users, newest first', () async {
      final open = await repository.watchThreads(ThreadFilter.open).first;
      expect(open.map((t) => t.message), ['Fresh', 'Answered', 'Old']);
      expect(
        open[1],
        SupportThread(
          path: 'users/u2/feedback/b',
          uid: 'u1',
          email: 'c@d.co',
          message: 'Answered',
          source: 'profile',
          appVersion: '1.0.0+12',
          platform: 'ios',
          osVersion: '18.1',
          deviceModel: 'iPhone 15',
          locale: 'en-GB',
          createdAt: DateTime(2026, 11, 3),
          status: ThreadStatus.replied,
          lastReplyAt: DateTime(2026, 11, 4),
        ),
      );
      final closed = await repository.watchThreads(ThreadFilter.closed).first;
      expect(closed.map((t) => t.message), ['Done']);
    });

    test('counts the New threads', () async {
      expect(await repository.watchNewCount().first, 2);
    });

    test('lists a thread\'s replies oldest first', () async {
      final replies = firestore.collection('users/u2/feedback/b/replies');
      await replies.doc('r2').set({
        'message': 'Second',
        'to': 'c@d.co',
        'status': 'sending',
        'sentByEmail': null,
        'requestedAt': Timestamp.fromDate(DateTime(2026, 11, 5)),
      });
      await replies.doc('r1').set({
        'message': 'First',
        'to': 'c@d.co',
        'status': 'sent',
        'sentByEmail': 'admin@example.com',
        'requestedAt': Timestamp.fromDate(DateTime(2026, 11, 4)),
        'sentAt': Timestamp.fromDate(DateTime(2026, 11, 4, 0, 1)),
      });

      final list = await repository.watchReplies('users/u2/feedback/b').first;

      expect(list, [
        SupportReply(
          id: 'r1',
          message: 'First',
          to: 'c@d.co',
          status: ReplyStatus.sent,
          sentByEmail: 'admin@example.com',
          requestedAt: DateTime(2026, 11, 4),
          sentAt: DateTime(2026, 11, 4, 0, 1),
        ),
        SupportReply(
          id: 'r2',
          message: 'Second',
          to: 'c@d.co',
          status: ReplyStatus.sending,
          sentByEmail: null,
          requestedAt: DateTime(2026, 11, 5),
          sentAt: null,
        ),
      ]);
    });

    test('stores each status as the rules and the app know it', () async {
      for (final (status, stored) in [
        (ThreadStatus.closed, 'closed'),
        (ThreadStatus.replied, 'replied'),
        (ThreadStatus.unreplied, 'open'),
      ]) {
        await repository.setStatus('users/u2/feedback/b', status);
        final doc = await firestore.doc('users/u2/feedback/b').get();
        expect(doc.data()!['status'], stored);
        expect(doc.data()!['message'], 'Answered');
      }
    });

    test('reads an empty or odd email as none, an unknown status as New', () {
      final thread = FirestoreSupportInboxRepository.threadFromMap(
        'users/u/feedback/x',
        {'message': 'Hi', 'email': '', 'status': 'snoozed'},
      );
      expect(thread.email, isNull);
      expect(thread.canReply, isFalse);
      expect(thread.status, ThreadStatus.unreplied);
      expect(thread.createdAt, isNull);
    });

    test('sends a reply through the function', () async {
      final result = await repository.sendReply((
        id: 'req1234567890abcdefg',
        threadPath: 'users/u2/feedback/b',
        message: 'Thanks.',
        close: true,
      ));
      expect(result, isA<Ok<void>>());
      verify(
        () => callable.call<Object?>({
          'requestId': 'req1234567890abcdefg',
          'threadPath': 'users/u2/feedback/b',
          'message': 'Thanks.',
          'close': true,
        }),
      ).called(1);
    });

    test('maps each refusal of the function', () async {
      Future<Failure?> failureFor(FunctionsError error) async {
        when(() => callable.call<Object?>(any())).thenThrow(error);
        return (await repository.sendReply((
          id: 'req1234567890abcdefg',
          threadPath: 'users/u2/feedback/b',
          message: 'Thanks.',
          close: false,
        ))).failureOrNull;
      }

      expect(
        await failureFor(
          FunctionsError('permission-denied', reason: 'not-admin'),
        ),
        isA<PermissionFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError(
            'already-exists',
            reason: 'in-progress',
            more: {'requestedAt': 42},
          ),
        ),
        isA<ReplyInProgressFailure>().having(
          (f) => f.requestedAt,
          'requestedAt',
          DateTime.fromMillisecondsSinceEpoch(42),
        ),
      );
      for (final reason in ['invalid-input', 'request-id-reused', 'no-email']) {
        expect(
          await failureFor(FunctionsError('invalid-argument', reason: reason)),
          isA<ValidationFailure>(),
          reason: reason,
        );
      }
      expect(
        await failureFor(FunctionsError('not-found', reason: 'no-thread')),
        isA<NotFoundFailure>(),
      );
      expect(
        await failureFor(FunctionsError('internal', reason: 'send-failed')),
        isA<ReplyNotSentFailure>(),
      );
      expect(
        await failureFor(FunctionsError('unknown', reason: 'outcome-unknown')),
        isA<ReplyOutcomeUnknownFailure>(),
      );
      expect(
        await failureFor(FunctionsError('not-found')),
        isA<RepliesUnavailableFailure>(),
      );
    });
  });

  group('use cases', () {
    late MockRepository repository;

    setUp(() {
      repository = MockRepository();
      when(() => repository.setStatus(any(), any()))
          .thenAnswer((_) async => const Ok(null));
      when(() => repository.sendReply(any()))
          .thenAnswer((_) async => const Ok(null));
    });

    test('reopening goes back to New, or Replied once replied to', () async {
      final reopen = ReopenThread(repository);
      await reopen(_thread('a', status: ThreadStatus.closed));
      await reopen(
        _thread(
          'b',
          status: ThreadStatus.closed,
          lastReplyAt: DateTime(2026, 11, 4),
        ),
      );
      verify(() => repository.setStatus('a', ThreadStatus.unreplied)).called(1);
      verify(() => repository.setStatus('b', ThreadStatus.replied)).called(1);
    });

    test('a reply is sent trimmed; an empty or long one is not', () async {
      final send = SendReply(repository);
      ReplyRequest request(String message) =>
          (id: 'id', threadPath: 'a', message: message, close: false);

      expect(await send(request('  Thanks. \n')), isA<Ok<void>>());
      verify(() => repository.sendReply(request('Thanks.'))).called(1);
      expect(
        (await send(request('   '))).failureOrNull,
        isA<ValidationFailure>(),
      );
      expect(
        (await send(request('x' * (maxReplyLength + 1)))).failureOrNull,
        isA<ValidationFailure>(),
      );
      verifyNever(() => repository.sendReply(request('   ')));
    });
  });

  group('SupportInboxCubit', () {
    late MockRepository repository;
    late StreamController<List<SupportThread>> open;
    late StreamController<List<SupportThread>> closed;
    final a = _thread('users/u1/feedback/a');
    final c = _thread('users/u2/feedback/c', status: ThreadStatus.closed);

    setUp(() {
      repository = MockRepository();
      open = StreamController.broadcast();
      closed = StreamController.broadcast();
      when(() => repository.watchThreads(ThreadFilter.open))
          .thenAnswer((_) => open.stream);
      when(() => repository.watchThreads(ThreadFilter.closed))
          .thenAnswer((_) => closed.stream);
      when(() => repository.setStatus(any(), any()))
          .thenAnswer((_) async => const Ok(null));
    });

    SupportInboxCubit build() => SupportInboxCubit(
      watchThreads: WatchThreads(repository),
      closeThread: CloseThread(repository),
      reopenThread: ReopenThread(repository),
      firstRetryDelay: Duration.zero,
    );

    blocTest<SupportInboxCubit, SupportInboxState>(
      'keeps both lists, and the open thread across lists',
      build: build,
      act: (cubit) async {
        open.add([a]);
        closed.add([c]);
        await pumpEventQueue();
        cubit.select(a);
        cubit.filter(ThreadFilter.closed);
        // Closed elsewhere: it moves lists and stays open.
        final closedA = _thread(a.path, status: ThreadStatus.closed);
        open.add([]);
        closed.add([closedA, c]);
        await pumpEventQueue();
        expect(cubit.state.selected, closedA);
      },
      expect: () => [
        SupportInboxState(
          threads: {
            ThreadFilter.open: [a],
          },
        ),
        SupportInboxState(
          threads: {
            ThreadFilter.open: [a],
            ThreadFilter.closed: [c],
          },
        ),
        isA<SupportInboxState>().having((s) => s.selected, 'selected', a),
        isA<SupportInboxState>().having(
          (s) => s.filter,
          'filter',
          ThreadFilter.closed,
        ),
        isA<SupportInboxState>(),
        isA<SupportInboxState>(),
      ],
    );

    blocTest<SupportInboxCubit, SupportInboxState>(
      'closes an open thread and reopens a closed one',
      build: build,
      act: (cubit) async {
        await cubit.toggle(a);
        await cubit.toggle(c);
      },
      expect: () => [
        SupportInboxState(updating: {a.path}),
        const SupportInboxState(),
        SupportInboxState(updating: {c.path}),
        const SupportInboxState(),
      ],
      verify: (_) {
        verify(() => repository.setStatus(a.path, ThreadStatus.closed))
            .called(1);
        verify(() => repository.setStatus(c.path, ThreadStatus.unreplied))
            .called(1);
      },
    );

    blocTest<SupportInboxCubit, SupportInboxState>(
      'keeps a failed change to show, and a failed list apart',
      setUp: () => when(() => repository.setStatus(any(), any()))
          .thenAnswer((_) async => const Err(PermissionFailure('no claim'))),
      build: build,
      act: (cubit) async {
        closed.addError(const NetworkFailure('offline'));
        await pumpEventQueue();
        await cubit.toggle(a);
      },
      skip: 1,
      expect: () => [
        SupportInboxState(
          failures: const {ThreadFilter.closed: NetworkFailure('offline')},
          updating: {a.path},
        ),
        const SupportInboxState(
          failures: {ThreadFilter.closed: NetworkFailure('offline')},
          updateFailure: PermissionFailure('no claim'),
        ),
      ],
    );
  });

  group('SupportThreadCubit', () {
    late MockRepository repository;
    const path = 'users/u1/feedback/a';

    setUp(() {
      repository = MockRepository();
      when(() => repository.watchReplies(path))
          .thenAnswer((_) => const Stream.empty());
      when(() => repository.sendReply(any()))
          .thenAnswer((_) async => const Ok(null));
    });

    SupportThreadCubit build() => SupportThreadCubit(
      threadPath: path,
      watchReplies: WatchReplies(repository),
      sendReply: SendReply(repository),
      firstRetryDelay: Duration.zero,
    );

    ReplyRequest sentRequest() =>
        verify(() => repository.sendReply(captureAny())).captured.single
            as ReplyRequest;

    blocTest<SupportThreadCubit, SupportThreadState>(
      'sends the trimmed reply and empties the box',
      build: build,
      act: (cubit) async {
        cubit.setDraft(' Thanks. ');
        await cubit.send(close: true);
      },
      expect: () => [
        const SupportThreadState(draft: ' Thanks. '),
        isA<SupportThreadState>().having(
          (s) => s.status,
          'status',
          ReplySendStatus.sending,
        ),
        const SupportThreadState(status: ReplySendStatus.sent, formVersion: 1),
      ],
      verify: (_) {
        final request = sentRequest();
        expect(request.threadPath, path);
        expect(request.message, 'Thanks.');
        expect(request.close, isTrue);
        expect(request.id, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
      },
    );

    test(
      'a retry of the same text reuses the request id; new text does not',
      () async {
        when(() => repository.sendReply(any()))
            .thenAnswer((_) async => const Err(ReplyOutcomeUnknownFailure()));
        final cubit = build();
        cubit.setDraft('Thanks.');
        await cubit.send(close: false);
        expect(cubit.state.status, ReplySendStatus.failed);
        expect(cubit.state.failure, isA<ReplyOutcomeUnknownFailure>());
        final first = sentRequest();

        await cubit.send(close: true);
        expect(sentRequest().id, first.id);

        cubit.setDraft('Thanks!');
        await cubit.send(close: false);
        expect(sentRequest().id, isNot(first.id));
        await cubit.close();
      },
    );

    blocTest<SupportThreadCubit, SupportThreadState>(
      'sends nothing while the box is empty',
      build: build,
      act: (cubit) async {
        cubit.setDraft('  ');
        await cubit.send(close: false);
      },
      expect: () => [const SupportThreadState(draft: '  ')],
      verify: (_) => verifyNever(() => repository.sendReply(any())),
    );
  });

  blocTest<NewThreadCountCubit, int?>(
    'NewThreadCountCubit follows the count of New threads',
    build: () {
      final repository = MockRepository();
      when(repository.watchNewCount)
          .thenAnswer((_) => Stream.fromIterable([2, 3]));
      return NewThreadCountCubit(
        watchNewThreadCount: WatchNewThreadCount(repository),
      );
    },
    expect: () => [2, 3],
  );

  group('format', () {
    final now = DateTime(2026, 11, 21, 12);

    test('a thread\'s time in its row', () {
      expect(threadTimeLabel(null, now), 'Pending');
      expect(
        threadTimeLabel(DateTime(2026, 11, 21, 11, 59, 30), now),
        'Just now',
      );
      expect(threadTimeLabel(DateTime(2026, 11, 21, 11, 15), now), '45m ago');
      expect(threadTimeLabel(DateTime(2026, 11, 21, 9, 30), now), '2h ago');
      expect(threadTimeLabel(DateTime(2026, 11, 20, 18), now), 'Yesterday');
      expect(threadTimeLabel(DateTime(2026, 11, 18), now), 'Nov 18');
      expect(threadTimeLabel(DateTime(2025, 11, 18), now), 'Nov 18, 2025');
    });

    test('what the app sent along', () {
      expect(
        threadDetailsLabel(_thread('a')),
        'From Profile · App 1.0.0 (12) · iOS 18.1 · iPhone 15 · en-GB · user ',
      );
    });

    test('a reply sending for long has an unknown outcome', () {
      SupportReply reply(ReplyStatus status) => SupportReply(
        id: 'r',
        message: 'Hi',
        to: 'p@example.com',
        status: status,
        sentByEmail: null,
        requestedAt: now,
        sentAt: null,
      );
      final later = now.add(staleReplyAfter + const Duration(seconds: 1));
      expect(reply(ReplyStatus.sending).outcomeUnknownAt(now), isFalse);
      expect(reply(ReplyStatus.sending).outcomeUnknownAt(later), isTrue);
      expect(reply(ReplyStatus.sent).outcomeUnknownAt(later), isFalse);
    });
  });
}
