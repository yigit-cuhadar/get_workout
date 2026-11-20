import 'package:forge_core/forge_core.dart';

import 'feedback_entry.dart';

/// The users' feedback messages, which only admins may read and close.
abstract interface class AdminFeedbackRepository {
  /// The latest messages with [status], newest first, again whenever one
  /// changes. Errors are [Failure]s.
  Stream<List<FeedbackEntry>> watch(FeedbackEntryStatus status);

  /// Closes or reopens the message at [path].
  Future<Result<void>> setStatus(String path, FeedbackEntryStatus status);
}
