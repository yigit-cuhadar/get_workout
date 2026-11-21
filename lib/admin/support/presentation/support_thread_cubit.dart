import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../shell/request_id.dart';
import '../../shell/retrying_listener.dart';
import '../domain/support_inbox_usecases.dart';
import '../domain/support_thread.dart';

enum ReplySendStatus {
  editing,
  sending,

  /// The last reply went out; the box is empty again.
  sent,
  failed,
}

class SupportThreadState extends Equatable {
  const SupportThreadState({
    this.replies,
    this.repliesFailure,
    this.draft = '',
    this.status = ReplySendStatus.editing,
    this.failure,
    this.lastAttempt,
    this.formVersion = 0,
  });

  /// The thread's replies, oldest first; null until loaded.
  final List<SupportReply>? replies;

  /// Set when the replies' stream failed; [replies] keep the last list.
  final Failure? repliesFailure;

  /// The reply as typed.
  final String draft;
  final ReplySendStatus status;

  /// Why the last send failed, with [ReplySendStatus.failed].
  final Failure? failure;

  /// The last request sent and not known to have gone through. Sending the
  /// same trimmed text again reuses its id, so the server never emails it
  /// twice; null after a send went through.
  final ReplyRequest? lastAttempt;

  /// Changes when the box is emptied after a send, so its field rebuilds.
  final int formVersion;

  bool get canSend =>
      status != ReplySendStatus.sending &&
      draft.trim().isNotEmpty &&
      draft.trim().length <= maxReplyLength;

  SupportThreadState copyWith({
    List<SupportReply>? replies,
    Failure? Function()? repliesFailure,
    String? draft,
    ReplySendStatus? status,
    Failure? failure,
    ReplyRequest? Function()? lastAttempt,
    int? formVersion,
  }) => SupportThreadState(
    replies: replies ?? this.replies,
    repliesFailure: repliesFailure != null
        ? repliesFailure()
        : this.repliesFailure,
    draft: draft ?? this.draft,
    status: status ?? this.status,
    // The outcome of a send belongs to its status and goes with it.
    failure: status == null ? this.failure : failure,
    lastAttempt: lastAttempt != null ? lastAttempt() : this.lastAttempt,
    formVersion: formVersion ?? this.formVersion,
  );

  @override
  List<Object?> get props => [
    replies,
    repliesFailure,
    draft,
    status,
    failure,
    lastAttempt,
    formVersion,
  ];
}

/// One thread's replies, live, and the reply box: Send reply leaves the
/// thread Replied, Send and close closes it. One send at a time.
class SupportThreadCubit extends Cubit<SupportThreadState> {
  SupportThreadCubit({
    required this.threadPath,
    required WatchReplies watchReplies,
    required this._sendReply,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(const SupportThreadState()) {
    _listener = RetryingListener(
      watch: () => watchReplies(threadPath),
      onData: (replies) =>
          emit(state.copyWith(replies: replies, repliesFailure: () => null)),
      onFailure: (failure) =>
          emit(state.copyWith(repliesFailure: () => failure)),
      firstRetryDelay: firstRetryDelay,
    );
  }

  final String threadPath;
  final SendReply _sendReply;
  late final RetryingListener<List<SupportReply>> _listener;

  /// Listens to the replies again now.
  void retryReplies() => _listener.retry();

  /// Not while sending: the box is locked then.
  void setDraft(String draft) {
    if (state.status == ReplySendStatus.sending || draft == state.draft) {
      return;
    }
    emit(state.copyWith(draft: draft, status: ReplySendStatus.editing));
  }

  /// Sends the draft once, closing the thread with [close]. The same
  /// trimmed text as the last attempt goes under its id, so a retry is
  /// never emailed twice; other text is another reply.
  Future<void> send({required bool close}) async {
    if (!state.canSend) return;
    final message = state.draft.trim();
    final last = state.lastAttempt;
    final ReplyRequest request = (
      id: last != null && last.message == message ? last.id : newRequestId(),
      threadPath: threadPath,
      message: message,
      close: close,
    );
    emit(
      state.copyWith(
        lastAttempt: () => request,
        status: ReplySendStatus.sending,
      ),
    );
    final result = await _sendReply(request);
    if (isClosed) return;
    emit(switch (result) {
      Ok() => state.copyWith(
        draft: '',
        lastAttempt: () => null,
        status: ReplySendStatus.sent,
        formVersion: state.formVersion + 1,
      ),
      Err(:final failure) => state.copyWith(
        status: ReplySendStatus.failed,
        failure: failure,
      ),
    });
  }

  @override
  Future<void> close() async {
    await _listener.cancel();
    return super.close();
  }
}
