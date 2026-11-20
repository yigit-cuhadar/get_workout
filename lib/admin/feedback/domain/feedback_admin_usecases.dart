import 'package:forge_core/forge_core.dart';

import 'admin_feedback_repository.dart';
import 'feedback_entry.dart';

class WatchFeedback {
  const WatchFeedback(this._repository);
  final AdminFeedbackRepository _repository;

  Stream<List<FeedbackEntry>> call(FeedbackEntryStatus status) =>
      _repository.watch(status);
}

typedef FeedbackStatusChange = ({String path, FeedbackEntryStatus status});

class SetFeedbackStatus implements UseCase<void, FeedbackStatusChange> {
  const SetFeedbackStatus(this._repository);
  final AdminFeedbackRepository _repository;

  @override
  Future<Result<void>> call(FeedbackStatusChange params) =>
      _repository.setStatus(params.path, params.status);
}
