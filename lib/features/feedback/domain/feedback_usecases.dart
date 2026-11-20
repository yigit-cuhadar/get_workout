import 'package:forge_core/forge_core.dart';

import 'feedback.dart';
import 'feedback_repository.dart';

typedef FeedbackSend = ({String uid, FeedbackDraft draft});

/// Sends the trimmed draft, or fails with a [ValidationFailure] naming its
/// [FeedbackDraft.problems] without writing anything.
class SendFeedback implements UseCase<void, FeedbackSend> {
  const SendFeedback(this._repository);
  final FeedbackRepository _repository;

  @override
  Future<Result<void>> call(FeedbackSend params) async {
    final problems = params.draft.problems;
    if (problems.isNotEmpty) {
      return Err(ValidationFailure(problems.map((p) => p.name).join(', ')));
    }
    return _repository.send(params.uid, params.draft.trimmed);
  }
}
