import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';

import '../../access/domain/access_usecases.dart';
import '../../shell/request_id.dart';
import '../../shell/retrying_listener.dart';
import '../domain/announcement.dart';
import '../domain/announcement_admin_usecases.dart';

enum AnnouncementSendStatus {
  /// Nothing sent yet.
  editing,
  sending,

  /// The last send went through ([AnnouncementsState.sent]); the form was
  /// emptied.
  sent,
  failed,
}

/// Where the last test send to the admin's own devices stands.
enum AnnouncementTestStatus { idle, sending, sent, failed }

/// How far ahead `sendAnnouncement` takes a time.
const scheduleEarliest = Duration(minutes: 1);
const scheduleLatest = Duration(days: 30);

/// What is wrong with sending at [at] when it is [now]: too soon or too
/// late; null when it can go then.
String? scheduleProblemAt(DateTime at, DateTime now) {
  if (at.isBefore(now.add(scheduleEarliest))) {
    return 'Pick a time at least a minute from now';
  }
  if (at.isAfter(now.add(scheduleLatest))) {
    return 'Pick a time at most 30 days from now';
  }
  return null;
}

class AnnouncementsState extends Equatable {
  const AnnouncementsState({
    this.lastAttempt,
    this.draft = const AnnouncementDraft(),
    this.status = AnnouncementSendStatus.editing,
    this.failure,
    this.accessRefreshed = false,
    this.sent,
    this.formVersion = 0,
    this.history,
    this.historyFailure,
    this.scheduleProblem,
    this.testStatus = AnnouncementTestStatus.idle,
    this.testResult,
    this.testFailure,
    this.cancelling = const {},
    this.cancelFailure,
  });

  final AnnouncementDraft draft;

  /// The last request sent and not known to have gone through: its id and
  /// trimmed draft. Sending the same trimmed text again reuses the id, so
  /// the server never sends it twice; null after a send went through.
  final AnnouncementRequest? lastAttempt;
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

  /// Why the draft's time cannot be used ([scheduleProblemAt]), as of the
  /// last edit; null when it is sent now or the time is fine.
  final String? scheduleProblem;

  final AnnouncementTestStatus testStatus;

  /// The last test that went out, with [AnnouncementTestStatus.sent].
  final TestAnnouncementResult? testResult;

  /// Why the last test failed, with [AnnouncementTestStatus.failed].
  final Failure? testFailure;

  /// The scheduled requests being cancelled right now, by id.
  final Set<String> cancelling;

  /// Why the last cancel failed; replaced by the next cancel.
  final Failure? cancelFailure;

  bool get canSend =>
      status != AnnouncementSendStatus.sending &&
      draft.problems.isEmpty &&
      scheduleProblem == null;

  bool get canTest =>
      testStatus != AnnouncementTestStatus.sending &&
      status != AnnouncementSendStatus.sending &&
      draft.problems.isEmpty;

  AnnouncementsState copyWith({
    AnnouncementDraft? draft,
    AnnouncementRequest? Function()? lastAttempt,
    AnnouncementSendStatus? status,
    Failure? failure,
    bool? accessRefreshed,
    SentAnnouncement? sent,
    int? formVersion,
    List<Announcement>? history,
    Failure? Function()? historyFailure,
    String? Function()? scheduleProblem,
    AnnouncementTestStatus? testStatus,
    TestAnnouncementResult? testResult,
    Failure? testFailure,
    Set<String>? cancelling,
    Failure? Function()? cancelFailure,
  }) => AnnouncementsState(
    draft: draft ?? this.draft,
    lastAttempt: lastAttempt != null ? lastAttempt() : this.lastAttempt,
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
    scheduleProblem: scheduleProblem != null
        ? scheduleProblem()
        : this.scheduleProblem,
    testStatus: testStatus ?? this.testStatus,
    // A test's outcome belongs to its status and goes with it.
    testResult: testStatus == null ? this.testResult : testResult,
    testFailure: testStatus == null ? this.testFailure : testFailure,
    cancelling: cancelling ?? this.cancelling,
    cancelFailure: cancelFailure != null ? cancelFailure() : this.cancelFailure,
  );

  @override
  List<Object?> get props => [
    draft,
    lastAttempt,
    status,
    failure,
    accessRefreshed,
    sent,
    formVersion,
    history,
    historyFailure,
    scheduleProblem,
    testStatus,
    testResult,
    testFailure,
    cancelling,
    cancelFailure,
  ];
}

/// Writes push announcements and sends them now or at a time, sends a
/// test to the admin's own devices, cancels scheduled ones, and shows the
/// history, live. One send at a time; the page asks for confirmation
/// before [send] and [cancel].
class AnnouncementsCubit extends Cubit<AnnouncementsState> {
  AnnouncementsCubit({
    required WatchAnnouncements watchAnnouncements,
    required this._sendAnnouncement,
    required this._sendTestAnnouncement,
    required this._cancelAnnouncement,
    required this._checkAdminAccess,
    this._now = DateTime.now,
    Duration firstRetryDelay = const Duration(seconds: 1),
  }) : super(const AnnouncementsState()) {
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
  final SendTestAnnouncement _sendTestAnnouncement;
  final CancelAnnouncement _cancelAnnouncement;
  final CheckAdminAccess _checkAdminAccess;
  final DateTime Function() _now;
  late final RetryingListener<List<Announcement>> _listener;

  /// Listens to the history again now.
  void retryHistory() => _listener.retry();

  void setLocale(String locale) => _edit(state.draft.copyWith(locale: locale));

  void setTitle(String title) => _edit(state.draft.copyWith(title: title));

  void setBody(String body) => _edit(state.draft.copyWith(body: body));

  void setAudience(AnnouncementAudience audience) =>
      _edit(state.draft.copyWith(audience: audience));

  /// Sends now, or at a time: the next full hour at least an hour away to
  /// begin with, which the page's pickers then change.
  void setScheduled(bool scheduled) {
    if (scheduled == (state.draft.scheduleAt != null)) return;
    if (!scheduled) return _edit(state.draft.copyWith(scheduleAt: () => null));
    final now = _now();
    final start = DateTime(now.year, now.month, now.day, now.hour + 2);
    _edit(state.draft.copyWith(scheduleAt: () => start));
  }

  void setScheduleAt(DateTime at) =>
      _edit(state.draft.copyWith(scheduleAt: () => at));

  /// Not while sending: the form is locked then. The last send's outcome
  /// stays until the next send.
  void _edit(AnnouncementDraft draft) {
    if (state.status == AnnouncementSendStatus.sending) return;
    if (draft == state.draft) return;
    emit(
      state.copyWith(
        draft: draft,
        scheduleProblem: () => _scheduleProblem(draft),
      ),
    );
  }

  String? _scheduleProblem(AnnouncementDraft draft) =>
      switch (draft.scheduleAt) {
        final at? => scheduleProblemAt(at, _now()),
        null => null,
      };

  /// Sends the draft once; a call while a send is underway does nothing.
  /// The same trimmed text as the last attempt goes under its id, so a
  /// retry is never sent twice; other text is another announcement.
  Future<void> send() async {
    // The time may have passed while the form stood open.
    final problem = _scheduleProblem(state.draft);
    if (problem != state.scheduleProblem) {
      emit(state.copyWith(scheduleProblem: () => problem));
    }
    if (!state.canSend) return;
    final draft = state.draft.trimmed;
    final last = state.lastAttempt;
    final AnnouncementRequest request = (
      id: last != null && last.draft == draft ? last.id : newRequestId(),
      draft: draft,
    );
    emit(
      state.copyWith(
        lastAttempt: () => request,
        status: AnnouncementSendStatus.sending,
        // A test's outcome is about the draft before it went.
        testStatus: AnnouncementTestStatus.idle,
      ),
    );
    final result = await _sendAnnouncement(request);
    if (isClosed) return;
    switch (result) {
      case Ok(value: final sent):
        emit(
          state.copyWith(
            draft: AnnouncementDraft(
              locale: request.draft.locale,
              audience: request.draft.audience,
            ),
            lastAttempt: () => null,
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

  /// Sends the draft to the admin's own devices only; one at a time.
  Future<void> sendTest() async {
    if (!state.canTest) return;
    emit(state.copyWith(testStatus: AnnouncementTestStatus.sending));
    final result = await _sendTestAnnouncement(state.draft);
    if (isClosed) return;
    emit(switch (result) {
      Ok(value: final sent) => state.copyWith(
        testStatus: AnnouncementTestStatus.sent,
        testResult: sent,
      ),
      Err(:final failure) => state.copyWith(
        testStatus: AnnouncementTestStatus.failed,
        testFailure: failure,
      ),
    });
  }

  /// Cancels the scheduled request [id]; the history shows the change.
  Future<void> cancel(String id) async {
    if (state.cancelling.contains(id)) return;
    emit(
      state.copyWith(
        cancelling: {...state.cancelling, id},
        cancelFailure: () => null,
      ),
    );
    final result = await _cancelAnnouncement(id);
    if (isClosed) return;
    emit(
      state.copyWith(
        cancelling: {...state.cancelling}..remove(id),
        cancelFailure: () => result.failureOrNull,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _listener.cancel();
    return super.close();
  }
}
