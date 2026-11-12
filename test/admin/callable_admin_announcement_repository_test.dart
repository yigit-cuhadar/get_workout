import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' hide Result;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/announcements/data/callable_admin_announcement_repository.dart';
import 'package:get_workout/admin/announcements/domain/announcement.dart';
import 'package:mocktail/mocktail.dart';

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

void main() {
  late MockFunctions functions;
  late MockCallable callable;
  late MockCallableResult result;
  late FakeFirebaseFirestore firestore;
  late CallableAdminAnnouncementRepository repository;

  const request = (
    id: 'req1234567890abcdefg',
    draft: AnnouncementDraft(title: 'New programs', body: 'Go.'),
  );

  setUp(() {
    functions = MockFunctions();
    callable = MockCallable();
    result = MockCallableResult();
    firestore = FakeFirebaseFirestore();
    repository = CallableAdminAnnouncementRepository(functions, firestore);
    when(() => functions.httpsCallable('sendAnnouncement'))
        .thenReturn(callable);
    when(() => callable.call<Object?>(any())).thenAnswer((_) async => result);
    when(() => result.data).thenReturn({
      'id': request.id,
      'messageId': 'projects/p/messages/1',
      'alreadySent': false,
    });
  });

  group('send', () {
    test('calls the function with the request id and draft', () async {
      final sent = await repository.send(request);
      expect(
        sent.valueOrNull,
        const SentAnnouncement(
          messageId: 'projects/p/messages/1',
          alreadySent: false,
        ),
      );
      verify(
        () => callable.call<Object?>({
          'requestId': request.id,
          'locale': 'en',
          'title': 'New programs',
          'body': 'Go.',
        }),
      ).called(1);
    });

    test('says when the request was sent before', () async {
      when(
        () => result.data,
      ).thenReturn({'messageId': 'projects/p/messages/1', 'alreadySent': true});
      expect((await repository.send(request)).valueOrNull?.alreadySent, isTrue);
    });

    Future<Failure?> failureFor(FunctionsError error) async {
      when(() => callable.call<Object?>(any())).thenThrow(error);
      return (await repository.send(request)).failureOrNull;
    }

    test('the reason in the details decides, not the code', () async {
      expect(
        await failureFor(
          FunctionsError('permission-denied', reason: 'not-admin'),
        ),
        isA<PermissionFailure>(),
      );
      expect(
        await failureFor(
          FunctionsError('already-exists', reason: 'in-progress'),
        ),
        isA<AnnouncementInProgressFailure>().having(
          (f) => f.requestedAt,
          'requestedAt',
          isNull,
        ),
      );
      expect(
        await failureFor(
          FunctionsError(
            'already-exists',
            reason: 'in-progress',
            more: {'requestedAt': 1700000000000},
          ),
        ),
        isA<AnnouncementInProgressFailure>().having(
          (f) => f.requestedAt,
          'requestedAt',
          DateTime.fromMillisecondsSinceEpoch(1700000000000),
        ),
      );
      expect(
        await failureFor(FunctionsError('internal', reason: 'send-failed')),
        isA<AnnouncementNotSentFailure>(),
      );
      expect(
        await failureFor(FunctionsError('unknown', reason: 'outcome-unknown')),
        isA<AnnouncementOutcomeUnknownFailure>(),
      );
      for (final reason in ['invalid-input', 'request-id-reused']) {
        expect(
          await failureFor(FunctionsError('invalid-argument', reason: reason)),
          isA<ValidationFailure>(),
        );
      }
    });

    test('a function not deployed or not callable is unavailable', () async {
      for (final code in ['not-found', 'permission-denied']) {
        expect(
          await failureFor(FunctionsError(code)),
          isA<AnnouncementsUnavailableFailure>(),
        );
      }
    });

    test('other errors map as Firebase errors', () async {
      expect(
        await failureFor(FunctionsError('unavailable')),
        isA<NetworkFailure>(),
      );
      expect(
        await failureFor(FunctionsError('unauthenticated')),
        isA<PermissionFailure>(),
      );
      expect(
        await failureFor(FunctionsError('internal')),
        isA<UnknownFailure>(),
      );
    });
  });

  test('the history is the latest announcements, newest first', () async {
    final announcements = firestore.collection('announcements');
    await announcements.doc('old').set({
      'locale': 'en',
      'title': 'Old',
      'body': 'Before.',
      'status': 'failed',
      'sentBy': 'admin1',
      'requestedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    await announcements.doc('new').set({
      'locale': 'en',
      'title': 'New',
      'body': 'After.',
      'status': 'sent',
      'sentBy': 'admin2',
      'requestedAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
      'sentAt': Timestamp.fromDate(DateTime(2026, 2, 1, 0, 0, 1)),
      'messageId': 'projects/p/messages/2',
    });
    await announcements.doc('odd').set({
      'title': 'Odd',
      'status': 'queued',
      'requestedAt': Timestamp.fromDate(DateTime(2025, 1, 1)),
    });

    final history = await repository.watchHistory().first;
    expect(history.map((a) => a.id), ['new', 'old', 'odd']);
    expect(
      history.first,
      Announcement(
        id: 'new',
        locale: 'en',
        title: 'New',
        body: 'After.',
        status: AnnouncementStatus.sent,
        sentBy: 'admin2',
        requestedAt: DateTime(2026, 2, 1),
        sentAt: DateTime(2026, 2, 1, 0, 0, 1),
      ),
    );
    expect(history[1].status, AnnouncementStatus.failed);
    expect(history[2].status, AnnouncementStatus.unknown);
    expect(history[2].sentAt, isNull);
  });
}
