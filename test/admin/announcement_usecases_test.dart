import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/announcements/domain/admin_announcement_repository.dart';
import 'package:get_workout/admin/announcements/domain/announcement.dart';
import 'package:get_workout/admin/announcements/domain/announcement_admin_usecases.dart';
import 'package:get_workout/admin/shell/request_id.dart';
import 'package:mocktail/mocktail.dart';

class MockRepository extends Mock implements AdminAnnouncementRepository {}

void main() {
  const draft = AnnouncementDraft(title: ' New programs ', body: ' Go. \n');

  List<String> fields(AnnouncementDraft draft) => [
    for (final problem in draft.problems) problem.field,
  ];

  group('AnnouncementDraft', () {
    test('a trimmed title and body in a language of the app pass', () {
      expect(draft.problems, isEmpty);
      expect(
        draft.trimmed,
        const AnnouncementDraft(title: 'New programs', body: 'Go.'),
      );
    });

    test('empty or blank text and unknown languages are problems', () {
      expect(fields(const AnnouncementDraft()), ['title', 'body']);
      expect(fields(draft.copyWith(title: '  ', body: '\n')), [
        'title',
        'body',
      ]);
      expect(fields(draft.copyWith(locale: 'de')), ['locale']);
    });

    test('the limits count the trimmed text', () {
      final atLimits = draft.copyWith(
        title: ' ${'t' * AnnouncementLimits.title} ',
        body: ' ${'b' * AnnouncementLimits.body} ',
      );
      expect(atLimits.problems, isEmpty);
      expect(
        fields(
          atLimits.copyWith(
            title: 't' * (AnnouncementLimits.title + 1),
            body: 'b' * (AnnouncementLimits.body + 1),
          ),
        ),
        ['title', 'body'],
      );
    });
  });

  test('a request still sending after 5 minutes has an unknown outcome', () {
    final requestedAt = DateTime(2026, 1, 1, 12);
    Announcement record(AnnouncementStatus status) => Announcement(
      id: 'r1',
      locale: 'en',
      title: 'T',
      body: 'B',
      status: status,
      sentBy: 'admin1',
      requestedAt: requestedAt,
      sentAt: null,
    );
    final soon = requestedAt.add(const Duration(minutes: 5));
    final later = soon.add(const Duration(seconds: 1));
    expect(record(AnnouncementStatus.sending).outcomeUnknownAt(soon), isFalse);
    expect(record(AnnouncementStatus.sending).outcomeUnknownAt(later), isTrue);
    expect(record(AnnouncementStatus.sent).outcomeUnknownAt(later), isFalse);
    expect(record(AnnouncementStatus.failed).outcomeUnknownAt(later), isFalse);
    expect(isStaleSending(null, later), isFalse);
  });

  test('request ids are 20 random letters and digits', () {
    final ids = {for (var i = 0; i < 100; i++) newRequestId()};
    expect(ids, hasLength(100));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
    }
  });

  group('SendAnnouncement', () {
    late MockRepository repository;
    late SendAnnouncement send;
    const sent = SentAnnouncement(messageId: 'm1', alreadySent: false);

    setUpAll(
      () => registerFallbackValue((id: 'x', draft: const AnnouncementDraft())),
    );

    setUp(() {
      repository = MockRepository();
      send = SendAnnouncement(repository);
      when(() => repository.send(any()))
          .thenAnswer((_) async => const Ok(sent));
    });

    test('sends the trimmed draft under the request id', () async {
      expect((await send((id: 'r1', draft: draft))).valueOrNull, sent);
      verify(
        () => repository.send((
          id: 'r1',
          draft: const AnnouncementDraft(title: 'New programs', body: 'Go.'),
        )),
      ).called(1);
    });

    test('a draft with problems is refused without the server', () async {
      final result = await send((id: 'r1', draft: const AnnouncementDraft()));
      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => repository.send(any()));
    });

    test('keeps the audience and time through trimming', () async {
      final at = DateTime(2026, 12, 1, 9);
      await send((
        id: 'r1',
        draft: draft.copyWith(
          audience: AnnouncementAudience.premium,
          scheduleAt: () => at,
        ),
      ));
      verify(
        () => repository.send((
          id: 'r1',
          draft: AnnouncementDraft(
            title: 'New programs',
            body: 'Go.',
            audience: AnnouncementAudience.premium,
            scheduleAt: at,
          ),
        )),
      ).called(1);
    });
  });

  group('SendTestAnnouncement', () {
    late MockRepository repository;
    const tested = TestAnnouncementResult(delivered: 1, failed: 0);

    setUpAll(() => registerFallbackValue(const AnnouncementDraft()));

    setUp(() {
      repository = MockRepository();
      when(() => repository.sendTest(any()))
          .thenAnswer((_) async => const Ok(tested));
    });

    test('tests the trimmed draft', () async {
      final result = await SendTestAnnouncement(repository)(draft);
      expect(result.valueOrNull, tested);
      verify(
        () => repository.sendTest(
          const AnnouncementDraft(title: 'New programs', body: 'Go.'),
        ),
      ).called(1);
    });

    test('a draft with problems is refused without the server', () async {
      final result = await SendTestAnnouncement(repository)(
        const AnnouncementDraft(),
      );
      expect(result.failureOrNull, isA<ValidationFailure>());
      verifyNever(() => repository.sendTest(any()));
    });
  });

  test('CancelAnnouncement cancels by request id', () async {
    final repository = MockRepository();
    when(() => repository.cancel('r1')).thenAnswer((_) async => const Ok(null));
    expect((await CancelAnnouncement(repository)('r1')).isOk, isTrue);
    verify(() => repository.cancel('r1')).called(1);
  });

  test('the sender is the email, or the uid on older rows', () {
    Announcement record({String? email}) => Announcement(
      id: 'r1',
      locale: 'en',
      title: 'T',
      body: 'B',
      status: AnnouncementStatus.sent,
      sentBy: 'admin1',
      senderEmail: email,
      requestedAt: null,
      sentAt: null,
    );
    expect(record(email: 'a@x.com').sender, 'a@x.com');
    expect(record().sender, 'admin1');
  });
}
