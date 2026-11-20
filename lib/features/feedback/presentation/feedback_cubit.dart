import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_auth/forge_auth.dart';
import 'package:forge_core/forge_core.dart';

import '../../analytics/domain/analytics.dart';
import '../domain/feedback.dart';
import '../domain/feedback_usecases.dart';

enum FeedbackFormStatus { editing, sending, sent, failed }

class FeedbackState extends Equatable {
  const FeedbackState({
    required this.draft,
    this.status = FeedbackFormStatus.editing,
    this.showProblems = false,
    this.failure,
  });

  final FeedbackDraft draft;
  final FeedbackFormStatus status;

  /// A send was tried with [FeedbackDraft.problems]; the form shows them
  /// from then on.
  final bool showProblems;

  /// Why the last send failed, with [FeedbackFormStatus.failed].
  final Failure? failure;

  Set<FeedbackProblem> get problems => showProblems ? draft.problems : const {};

  FeedbackState copyWith({
    FeedbackDraft? draft,
    FeedbackFormStatus? status,
    bool? showProblems,
    Failure? failure,
  }) => FeedbackState(
    draft: draft ?? this.draft,
    status: status ?? this.status,
    showProblems: showProblems ?? this.showProblems,
    failure: failure,
  );

  @override
  List<Object?> get props => [draft, status, showProblems, failure];
}

/// The feedback form, opened from [source]. The reply email starts as the
/// account's, empty for a guest.
class FeedbackCubit extends Cubit<FeedbackState> {
  FeedbackCubit({
    required this._sendFeedback,
    required GetCurrentUser getCurrentUser,
    required FeedbackSource source,
    required this._analytics,
  }) : _getCurrentUser = getCurrentUser,
       super(
         FeedbackState(
           draft: FeedbackDraft(
             source: source,
             email: getCurrentUser()?.email ?? '',
           ),
         ),
       );

  final SendFeedback _sendFeedback;
  final Analytics _analytics;
  final GetCurrentUser _getCurrentUser;

  void setMessage(String message) =>
      _edit(state.draft.copyWith(message: message));

  void setEmail(String email) => _edit(state.draft.copyWith(email: email));

  void _edit(FeedbackDraft draft) {
    if (state.status == FeedbackFormStatus.sending || draft == state.draft) {
      return;
    }
    emit(state.copyWith(draft: draft, status: FeedbackFormStatus.editing));
  }

  /// Sends once; with problems it only shows them.
  Future<void> send() async {
    if (state.status == FeedbackFormStatus.sending ||
        state.status == FeedbackFormStatus.sent) {
      return;
    }
    if (state.draft.problems.isNotEmpty) {
      emit(state.copyWith(showProblems: true));
      return;
    }
    final uid = _getCurrentUser()?.id;
    if (uid == null) {
      emit(
        state.copyWith(
          status: FeedbackFormStatus.failed,
          failure: const AuthFailure('signed out'),
        ),
      );
      return;
    }
    emit(state.copyWith(status: FeedbackFormStatus.sending));
    final result = await _sendFeedback((uid: uid, draft: state.draft));
    if (result.isOk) unawaited(_analytics.feedbackSend());
    if (isClosed) return;
    emit(
      state.copyWith(
        status: result.isOk
            ? FeedbackFormStatus.sent
            : FeedbackFormStatus.failed,
        failure: result.failureOrNull,
      ),
    );
  }
}
