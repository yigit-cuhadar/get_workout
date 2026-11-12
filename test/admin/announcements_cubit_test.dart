import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:forge_core/forge_core.dart';
import 'package:get_workout/admin/access/domain/access_usecases.dart';
import 'package:get_workout/admin/announcements/domain/admin_announcement_repository.dart';
import 'package:get_workout/admin/announcements/domain/announcement.dart';
import 'package:get_workout/admin/announcements/domain/announcement_admin_usecases.dart';
import 'package:get_workout/admin/announcements/presentation/announcements_cubit.dart';
import 'package:mocktail/mocktail.dart';

class MockRepository extends Mock implements AdminAnnouncementRepository {}

class MockCheckAdminAccess extends Mock implements CheckAdminAccess {}

void main() {
  late MockRepository repository;
  late MockCheckAdminAccess checkAdminAccess;
  late StreamController<List<Announcement>> history;
  late AnnouncementsCubit cubit;

  const sent = SentAnnouncement(messageId: 'm1', alreadySent: false);
  final announcement = Announcement(
    id: 'r0',
    locale: 'en',
    title: 'Hello',
    body: 'World',
    status: AnnouncementStatus.sent,
    sentBy: 'admin1',
    requestedAt: DateTime(2026),
    sentAt: DateTime(2026),
  );

  setUpAll(
    () => registerFallbackValue((id: 'x', draft: const AnnouncementDraft())),
  );

  setUp(() async {
    repository = MockRepository();
    checkAdminAccess = MockCheckAdminAccess();
    history = StreamController();
    when(() => repository.watchHistory()).thenAnswer((_) => history.stream);
    when(() => repository.send(any())).thenAnswer((_) async => const Ok(sent));
    when(() => checkAdminAccess(true)).thenAnswer((_) async => const Ok(true));
    // No retry fires during a test: [history] can be listened to only once.
    cubit = AnnouncementsCubit(
      watchAnnouncements: WatchAnnouncements(repository),
      sendAnnouncement: SendAnnouncement(repository),
      checkAdminAccess: checkAdminAccess,
      firstRetryDelay: const Duration(hours: 1),
    );
  });

  tearDown(() => cubit.close());

  void fill() => cubit
    ..setTitle(' New programs ')
    ..setBody('Three are live.');

  List<AnnouncementRequest> requests() => [
    for (final request in verify(() => repository.send(captureAny())).captured)
      request as AnnouncementRequest,
  ];

  test('shows the history, and keeps it when the stream fails', () async {
    expect(cubit.state.history, isNull);
    history.add([announcement]);
    await pumpEventQueue();
    expect(cubit.state.history, [announcement]);
    history.addError(const PermissionFailure());
    await pumpEventQueue();
    expect(cubit.state.historyFailure, isA<PermissionFailure>());
    expect(cubit.state.history, [announcement]);
  });

  test('cannot send until the draft passes', () async {
    expect(cubit.state.canSend, isFalse);
    await cubit.send();
    verifyNever(() => repository.send(any()));
    cubit.setTitle('Title');
    expect(cubit.state.canSend, isFalse);
    cubit.setBody('Body');
    expect(cubit.state.canSend, isTrue);
  });

  test('sends the trimmed draft, then empties the form', () async {
    fill();
    await cubit.send();
    final request = requests().single;
    expect(request.id, matches(RegExp(r'^[A-Za-z0-9]{20}$')));
    expect(
      request.draft,
      const AnnouncementDraft(title: 'New programs', body: 'Three are live.'),
    );
    final state = cubit.state;
    expect(state.status, AnnouncementSendStatus.sent);
    expect(state.sent, sent);
    expect(state.draft, const AnnouncementDraft());
    expect(state.lastAttempt, isNull);
    expect(state.formVersion, 1);
  });

  test('after a success, the same text again is a new request', () async {
    fill();
    await cubit.send();
    fill();
    await cubit.send();
    final ids = requests().map((r) => r.id).toList();
    expect(ids[1], isNot(ids[0]));
  });

  test('sends once while a send is underway, and locks the form', () async {
    final pending = Completer<Result<SentAnnouncement>>();
    when(() => repository.send(any())).thenAnswer((_) => pending.future);
    fill();
    final first = cubit.send();
    expect(cubit.state.status, AnnouncementSendStatus.sending);
    expect(cubit.state.canSend, isFalse);
    await cubit.send();
    cubit.setTitle('Changed');
    expect(cubit.state.draft.title, ' New programs ');
    pending.complete(const Ok(sent));
    await first;
    verify(() => repository.send(any())).called(1);
  });

  group('after a failure', () {
    setUp(() {
      when(() => repository.send(any()))
          .thenAnswer((_) async => const Err(NetworkFailure()));
      fill();
    });

    /// The ids of every request sent, the first failing one included.
    Future<List<String>> idsAfter(void Function() edit) async {
      await cubit.send();
      expect(cubit.state.status, AnnouncementSendStatus.failed);
      expect(cubit.state.failure, isA<NetworkFailure>());
      edit();
      await cubit.send();
      return [for (final request in requests()) request.id];
    }

    test('a retry keeps the request id', () async {
      final ids = await idsAfter(() {});
      expect(ids[1], ids[0]);
    });

    test('typing and deleting a character keeps the request id', () async {
      final ids = await idsAfter(
        () => cubit
          ..setBody('Three are live.!')
          ..setBody('Three are live.'),
      );
      expect(ids[1], ids[0]);
    });

    test('spaces around the text keep the request id', () async {
      final ids = await idsAfter(
        () => cubit
          ..setTitle('New programs')
          ..setBody('Three are live.  '),
      );
      expect(ids[1], ids[0]);
    });

    test('other text is a new request id', () async {
      final ids = await idsAfter(() => cubit.setBody('Four are live.'));
      expect(ids[1], isNot(ids[0]));
      expect(cubit.state.lastAttempt?.draft.body, 'Four are live.');
    });
  });

  test('a refusal for the claim refreshes the token and says so', () async {
    when(() => repository.send(any()))
        .thenAnswer((_) async => const Err(PermissionFailure()));
    fill();
    await cubit.send();
    verify(() => checkAdminAccess(true)).called(1);
    expect(cubit.state.failure, isA<PermissionFailure>());
    expect(cubit.state.accessRefreshed, isTrue);

    when(() => checkAdminAccess(true)).thenAnswer((_) async => const Ok(false));
    await cubit.send();
    expect(cubit.state.accessRefreshed, isFalse);
  });

  test('an edit after a send goes back to editing', () async {
    fill();
    await cubit.send();
    cubit.setTitle('Next');
    expect(cubit.state.status, AnnouncementSendStatus.editing);
    expect(cubit.state.sent, isNull);
  });
}
