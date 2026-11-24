import 'package:forge_core/forge_core.dart';

import 'admin_announcement_repository.dart';
import 'announcement.dart';

class WatchAnnouncements {
  const WatchAnnouncements(this._repository);
  final AdminAnnouncementRepository _repository;

  Stream<List<Announcement>> call() => _repository.watchHistory();
}

/// A [ValidationFailure] naming what [draft] breaks
/// ([AnnouncementDraft.problems]); null when nothing.
ValidationFailure? _problemsOf(AnnouncementDraft draft) {
  final problems = draft.problems;
  if (problems.isEmpty) return null;
  return ValidationFailure(
    problems.map((p) => '${p.field}: ${p.message}').join(', '),
  );
}

/// Sends (or schedules) the trimmed draft, or fails with a
/// [ValidationFailure] without asking the server when it breaks a rule
/// ([AnnouncementDraft.problems]).
class SendAnnouncement
    implements UseCase<SentAnnouncement, AnnouncementRequest> {
  const SendAnnouncement(this._repository);
  final AdminAnnouncementRepository _repository;

  @override
  Future<Result<SentAnnouncement>> call(AnnouncementRequest params) async {
    if (_problemsOf(params.draft) case final failure?) return Err(failure);
    return _repository.send((id: params.id, draft: params.draft.trimmed));
  }
}

/// Sends the trimmed draft to the admin's own devices, checked as
/// [SendAnnouncement] checks it.
class SendTestAnnouncement
    implements UseCase<TestAnnouncementResult, AnnouncementDraft> {
  const SendTestAnnouncement(this._repository);
  final AdminAnnouncementRepository _repository;

  @override
  Future<Result<TestAnnouncementResult>> call(AnnouncementDraft params) async {
    if (_problemsOf(params) case final failure?) return Err(failure);
    return _repository.sendTest(params.trimmed);
  }
}

/// Cancels a scheduled announcement by its request id.
class CancelAnnouncement implements UseCase<void, String> {
  const CancelAnnouncement(this._repository);
  final AdminAnnouncementRepository _repository;

  @override
  Future<Result<void>> call(String params) => _repository.cancel(params);
}
