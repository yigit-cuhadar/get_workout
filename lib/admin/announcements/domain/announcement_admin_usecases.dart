import 'package:forge_core/forge_core.dart';

import 'admin_announcement_repository.dart';
import 'announcement.dart';

class WatchAnnouncements {
  const WatchAnnouncements(this._repository);
  final AdminAnnouncementRepository _repository;

  Stream<List<Announcement>> call() => _repository.watchHistory();
}

/// Sends the trimmed draft, or fails with a [ValidationFailure] without
/// asking the server when it breaks a rule ([AnnouncementDraft.problems]).
class SendAnnouncement
    implements UseCase<SentAnnouncement, AnnouncementRequest> {
  const SendAnnouncement(this._repository);
  final AdminAnnouncementRepository _repository;

  @override
  Future<Result<SentAnnouncement>> call(AnnouncementRequest params) async {
    final problems = params.draft.problems;
    if (problems.isNotEmpty) {
      return Err(
        ValidationFailure(
          problems.map((p) => '${p.field}: ${p.message}').join(', '),
        ),
      );
    }
    return _repository.send((id: params.id, draft: params.draft.trimmed));
  }
}
