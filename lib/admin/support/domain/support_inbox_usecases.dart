import 'package:forge_core/forge_core.dart';

import 'support_inbox_repository.dart';
import 'support_thread.dart';

class WatchThreads {
  const WatchThreads(this._repository);
  final SupportInboxRepository _repository;

  Stream<List<SupportThread>> call(ThreadFilter filter) =>
      _repository.watchThreads(filter);
}

class WatchNewThreadCount {
  const WatchNewThreadCount(this._repository);
  final SupportInboxRepository _repository;

  Stream<int> call() => _repository.watchNewCount();
}

class WatchReplies {
  const WatchReplies(this._repository);
  final SupportInboxRepository _repository;

  Stream<List<SupportReply>> call(String threadPath) =>
      _repository.watchReplies(threadPath);
}

class CloseThread implements UseCase<void, SupportThread> {
  const CloseThread(this._repository);
  final SupportInboxRepository _repository;

  @override
  Future<Result<void>> call(SupportThread params) =>
      _repository.setStatus(params.path, ThreadStatus.closed);
}

/// Opens a closed thread again, as New or, once replied to, as Replied.
class ReopenThread implements UseCase<void, SupportThread> {
  const ReopenThread(this._repository);
  final SupportInboxRepository _repository;

  @override
  Future<Result<void>> call(SupportThread params) =>
      _repository.setStatus(params.path, params.reopenedStatus);
}

/// Sends the trimmed reply, or fails with a [ValidationFailure] without
/// asking the server when it is empty or longer than [maxReplyLength].
class SendReply implements UseCase<void, ReplyRequest> {
  const SendReply(this._repository);
  final SupportInboxRepository _repository;

  @override
  Future<Result<void>> call(ReplyRequest params) async {
    final message = params.message.trim();
    if (message.isEmpty) return const Err(ValidationFailure('reply empty'));
    if (message.length > maxReplyLength) {
      return const Err(
        ValidationFailure('reply longer than $maxReplyLength characters'),
      );
    }
    return _repository.sendReply((
      id: params.id,
      threadPath: params.threadPath,
      message: message,
      close: params.close,
    ));
  }
}
