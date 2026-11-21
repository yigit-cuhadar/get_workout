import 'package:forge_core/forge_core.dart';

import 'support_thread.dart';

/// The users' feedback as support threads, which only admins may read,
/// close and reopen, and the replies the callable `sendSupportReply`
/// emails and keeps on them.
abstract interface class SupportInboxRepository {
  /// The latest threads of [filter], newest first, again whenever one
  /// changes. Errors are [Failure]s.
  Stream<List<SupportThread>> watchThreads(ThreadFilter filter);

  /// How many threads are New, up to [newCountCap], again whenever it
  /// changes. Errors are [Failure]s.
  Stream<int> watchNewCount();

  /// The replies to the thread at [threadPath], oldest first, again
  /// whenever one changes. Errors are [Failure]s.
  Stream<List<SupportReply>> watchReplies(String threadPath);

  /// Sets the thread at [path] to [status] (only the server sets
  /// [ThreadStatus.replied] on a thread never replied to).
  Future<Result<void>> setStatus(String path, ThreadStatus status);

  /// Sends [request] as it is (trim and check it first). Fails with
  /// [PermissionFailure] without the admin claim,
  /// [RepliesUnavailableFailure] when the function cannot be called,
  /// [ReplyInProgressFailure] while the same request is `sending`,
  /// [ReplyNotSentFailure] when Gmail certainly refused it,
  /// [ReplyOutcomeUnknownFailure] when Gmail may have taken it,
  /// [NotFoundFailure] when the thread is gone, [ValidationFailure] when
  /// the function refuses the input or the thread has no email, and
  /// [NetworkFailure] offline.
  Future<Result<void>> sendReply(ReplyRequest request);
}

/// The most New threads counted; more show as this many.
const newCountCap = 100;
