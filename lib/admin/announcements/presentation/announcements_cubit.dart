import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../access/domain/access_usecases.dart';
import '../../shell/retrying_listener.dart';
import '../domain/announcement.dart';
import '../domain/announcement_admin_usecases.dart';

enum AnnouncementSendStatus {
  editing,
  sending,

  /// The last send went through ([AnnouncementsState.sent]); the form is
  /// empty again.
  sent,
  failed,
}

class AnnouncementsState extends Equatable {
  const AnnouncementsState({
    required this.requestId,
    this.draft = const AnnouncementDraft(),
    this.status = AnnouncementSendStatus.editing,
    this.failure,
    this.accessRefreshed = false,
    this.sent,
    this.formVersion = 0,
    this.history,
    this.historyFailure,
  });

  final AnnouncementDraft draft;

  /// Sent with [draft]; kept until the draft changes or is sent, so sending
  /// again after a failure never sends it twice.
  final String requestId;
  final AnnouncementSendStatus status;

  /// Why the last send failed, with [AnnouncementSendStatus.failed].
  final Failure? failure;

  /// After a send refused for the admin claim: the token was refreshed and
  /// still carries it, so sending again may work.
  final bool accessRefreshed;

  /// The last send that went through, with [AnnouncementSendStatus.sent].
  final SentAnnouncement? sent;

  /// Changes when the form is emptied after a send, so its fields rebuild.
  final int formVersion;

  /// The latest announcements, newest first; null until first loaded.
  final List<Announcement>? history;

  /// Set when the history stream failed; [history] keeps the last list.
  final Failure? historyFailure;

  bool get canSend =>
      status != AnnouncementSendStatus.sending && draft.problems.isEmpty;

  AnnouncementsState copyWith({
    AnnouncementDraft? draft,
    String? requestId,
    AnnouncementSendStatus? status,
    Failure? failure,
    bool? accessRefreshed,
    SentAnnouncement? sent,
    int? formVersion,
    List<Announcement>? history,
    Failure? Function()? historyFailure,
  }) => AnnouncementsState(
    draft: draft ?? this.draft,
    requestId: requestId ?? this.requestId,
    status: status ?? this.status,
    // The outcome of a send belongs to its status and goes with it.
    failure: status == null ? this.failure : failure,
    accessRefreshed: status == null
        ? this.accessRefreshed
        : accessRefreshed ?? false,
    sent: status == null ? this.sent : sent,
    formVersion: formVersion ?? this.formVersion,
    history: history ?? this.history,
    historyFailure: historyFailure != null
        ? historyFailure()
        : this.historyFailure,
  );

  @override
  List<Object?> get props => [
    draft,
    requestId,
    status,
    failure,
    accessRefreshed,
    sent,
    formVersion,
    history,
    historyFailure,
  ];
}

/// Writes and sends push announcements, and shows the history of sent
/// ones, live. One send at a time; the page asks for confirmation before
/// [send].
class AnnouncementsCubit extends Cubit<AnnouncementsState> {
  AnnouncementsCubit({
    required WatchAnnouncements watchAnnouncements,
    required this._sendAnnouncement,
    required this._checkAdminAccess,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(AnnouncementsState(requestId: newAnnouncementRequestId())) {
    _listener = RetryingListener(
      watch: watchAnnouncements.call,
      onData: (history) =>
          emit(state.copyWith(history: history, historyFailure: () => null)),
      onFailure: (failure) =>
          emit(state.copyWith(historyFailure: () => failure)),
      firstRetryDelay: firstRetryDelay,
    );
  }

  final SendAnnouncement _sendAnnouncement;
  final CheckAdminAccess _checkAdminAccess;
  late final RetryingListener<List<Announcement>> _listener;

  /// Listens to the history again now.
  void retryHistory() => _listener.retry();

  void setLocale(String locale) => _edit(state.draft.copyWith(locale: locale));

  void setTitle(String title) => _edit(state.draft.copyWith(title: title));

  void setBody(String body) => _edit(state.draft.copyWith(body: body));

  /// Other text is another announcement, so it gets a new request id. Not
  /// while sending: the form is locked then.
  void _edit(AnnouncementDraft draft) {
    if (state.status == AnnouncementSendStatus.sending) return;
    if (draft == state.draft) return;
    emit(
      state.copyWith(
        draft: draft,
        requestId: newAnnouncementRequestId(),
        status: AnnouncementSendStatus.editing,
      ),
    );
  }

  /// Sends the draft once; a call while a send is underway does nothing.
  Future<void> send() async {
    if (!state.canSend) return;
    final request = (id: state.requestId, draft: state.draft);
    emit(state.copyWith(status: AnnouncementSendStatus.sending));
    final result = await _sendAnnouncement(request);
    if (isClosed) return;
    switch (result) {
      case Ok(value: final sent):
        emit(
          state.copyWith(
            draft: AnnouncementDraft(locale: request.draft.locale),
            requestId: newAnnouncementRequestId(),
            status: AnnouncementSendStatus.sent,
            sent: sent,
            formVersion: state.formVersion + 1,
          ),
        );
      case Err(failure: final PermissionFailure failure):
        // The claim may have been revoked, or the token may just be stale:
        // a refreshed token tells. Without the claim, the access gate (which
        // follows token changes) leaves this page.
        final access = await _checkAdminAccess(true);
        if (isClosed) return;
        emit(
          state.copyWith(
            status: AnnouncementSendStatus.failed,
            failure: failure,
            accessRefreshed: access.valueOrNull ?? false,
          ),
        );
      case Err(:final failure):
        emit(
          state.copyWith(
            status: AnnouncementSendStatus.failed,
            failure: failure,
          ),
        );
    }
  }

  @override
  Future<void> close() async {
    await _listener.cancel();
    return super.close();
  }
}
