import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../shell/admin_form.dart';
import '../../shell/admin_nav.dart';
import '../../shell/admin_text.dart';
import '../domain/announcement.dart';
import 'announcements_cubit.dart';

/// Writes a push announcement, sends it after a confirmation, and lists
/// the ones sent before.
class AnnouncementsPage extends StatelessWidget {
  const AnnouncementsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<AnnouncementsCubit>(),
    child: const _AnnouncementsView(),
  );
}

/// A request left `sending` too long ([isStaleSending]).
const _outcomeUnknown = 'Unknown — check a device before sending again';

/// What the panel says about a failed send at [now]. Only a failure after
/// which nothing was sent says sending again may send it.
String _sendFailureMessage(
  Failure failure, {
  required bool accessRefreshed,
  required DateTime now,
}) => switch (failure) {
  PermissionFailure() when accessRefreshed =>
    'Refused, but this account still has admin access and its token is '
        'now refreshed. Send again.',
  PermissionFailure() => 'Refused: this account has no current admin claim.',
  AnnouncementsUnavailableFailure() =>
    'Sending is not available: the sendAnnouncement function is not '
        'deployed to this project. Nothing was sent.',
  AnnouncementInProgressFailure(:final requestedAt)
      when isStaleSending(requestedAt, now) =>
    '$_outcomeUnknown. This announcement may or may not have reached '
        'devices, and it will not be sent again.',
  AnnouncementInProgressFailure() =>
    'This announcement is being sent right now. Check the history '
        'before sending again.',
  AnnouncementNotSentFailure() =>
    'FCM refused it, so nothing was sent. You can send it again.',
  AnnouncementOutcomeUnknownFailure() =>
    'FCM did not say whether it took the announcement: it may or may '
        'not reach devices. Check a device; the same text will not be '
        'sent again.',
  NetworkFailure() =>
    'No connection to Firebase; it may or may not have been sent. '
        'Sending the same text again never sends it twice.',
  ValidationFailure(:final message) => 'Refused: $message',
  _ =>
    '${failureMessage(failure)} It may or may not have been sent; '
        'sending the same text again never sends it twice.',
};

class _AnnouncementsView extends StatelessWidget {
  const _AnnouncementsView();

  void _show(BuildContext context, String message) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Announcements'),
        actions: const [AdminNav()],
      ),
      body: BlocListener<AnnouncementsCubit, AnnouncementsState>(
        listenWhen: (previous, state) => previous.status != state.status,
        listener: (context, state) {
          switch (state) {
            case AnnouncementsState(sent: SentAnnouncement(alreadySent: true)):
              _show(context, 'Already sent before; not sent again.');
            case AnnouncementsState(status: AnnouncementSendStatus.sent):
              _show(context, 'Sent.');
            case AnnouncementsState(failure: final failure?):
              _show(
                context,
                _sendFailureMessage(
                  failure,
                  accessRefreshed: state.accessRefreshed,
                  now: DateTime.now(),
                ),
              );
            default:
          }
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxFormWidth),
            child: ListView(
              padding: const EdgeInsets.all(Gap.md),
              children: const [
                _Form(),
                SizedBox(height: Gap.md),
                _History(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Form extends StatelessWidget {
  const _Form();

  Future<void> _confirmThenSend(BuildContext context) async {
    final cubit = context.read<AnnouncementsCubit>();
    final draft = cubit.state.draft.trimmed;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send this announcement to every user?'),
        content: SizedBox(
          width: maxFormWidth / 2,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'It notifies every user of the "${draft.locale}" app '
                'language who allowed notifications, right away. A sent '
                'announcement cannot be recalled or edited.',
              ),
              const SizedBox(height: Gap.md),
              Text(draft.title, style: Theme.of(context).textTheme.titleSmall),
              Text(draft.body),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Send to everyone'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await cubit.send();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AnnouncementsCubit>();
    final state = context.watch<AnnouncementsCubit>().state;
    final draft = state.draft;
    final sending = state.status == AnnouncementSendStatus.sending;
    return FormSection(
      title: 'New announcement',
      children: [
        const Text(
          'A push notification to every device that allowed notifications, '
          'for its language. Tapping it opens Today. iOS devices get none '
          'until push is set up for iOS.',
        ),
        DropdownButtonFormField<String>(
          initialValue: draft.locale,
          decoration: const InputDecoration(labelText: 'Language'),
          items: [
            for (final language in languages)
              DropdownMenuItem(value: language, child: Text(language)),
          ],
          onChanged: sending
              ? null
              : (locale) {
                  if (locale != null) cubit.setLocale(locale);
                },
        ),
        _CountedField(
          key: ValueKey(('title', state.formVersion)),
          label: 'Title',
          value: draft.title,
          length: draft.trimmed.title.length,
          max: AnnouncementLimits.title,
          enabled: !sending,
          onChanged: cubit.setTitle,
        ),
        _CountedField(
          key: ValueKey(('body', state.formVersion)),
          label: 'Body',
          value: draft.body,
          length: draft.trimmed.body.length,
          max: AnnouncementLimits.body,
          enabled: !sending,
          multiline: true,
          onChanged: cubit.setBody,
        ),
        if (sending) const LinearProgressIndicator(),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: state.canSend ? () => _confirmThenSend(context) : null,
            icon: const Icon(Icons.campaign_outlined),
            label: Text(sending ? 'Sending...' : 'Send...'),
          ),
        ),
      ],
    );
  }
}

/// A text field with its trimmed length against [max], in the error colour
/// once over.
class _CountedField extends StatelessWidget {
  const _CountedField({
    super.key,
    required this.label,
    required this.value,
    required this.length,
    required this.max,
    required this.enabled,
    required this.onChanged,
    this.multiline = false,
  });

  final String label;
  final String value;
  final int length;
  final int max;
  final bool enabled;
  final bool multiline;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final over = length > max;
    return TextFormField(
      initialValue: value,
      enabled: enabled,
      maxLines: multiline ? null : 1,
      decoration: InputDecoration(
        labelText: label,
        counterText: '$length / $max',
        counterStyle: over
            ? TextStyle(color: Theme.of(context).colorScheme.error)
            : null,
        errorText: over ? 'At most $max characters' : null,
      ),
      onChanged: onChanged,
    );
  }
}

class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AnnouncementsCubit>();
    final state = context.watch<AnnouncementsCubit>().state;
    final history = state.history;
    final failure = state.historyFailure;
    return FormSection(
      title: 'Sent before',
      children: [
        if (failure != null)
          ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(
              history == null
                  ? failureMessage(failure)
                  : 'Live updates stopped: ${failureMessage(failure)} '
                        'Retrying automatically.',
            ),
            trailing: TextButton(
              onPressed: cubit.retryHistory,
              child: const Text('Retry now'),
            ),
          ),
        if (history == null && failure == null) const LoadingView(),
        if (history != null && history.isEmpty) const Text('Nothing sent yet.'),
        for (final announcement in history ?? const <Announcement>[])
          _HistoryRow(announcement),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.announcement);

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = announcement;
    final (status, color) = switch (a.status) {
      _ when a.outcomeUnknownAt(DateTime.now()) => (
        _outcomeUnknown,
        scheme.error,
      ),
      AnnouncementStatus.sent => ('Sent', scheme.primary),
      AnnouncementStatus.sending => ('Sending', scheme.tertiary),
      AnnouncementStatus.failed => ('Failed, not sent', scheme.error),
      AnnouncementStatus.unknown => ('Unknown', scheme.outline),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(a.title),
      subtitle: Text(
        '${a.body}\n'
        '${a.locale} · ${dateTimeLabel(a.sentAt ?? a.requestedAt)} · '
        'by ${a.sentBy}',
      ),
      isThreeLine: true,
      trailing: Text(status, style: TextStyle(color: color)),
    );
  }
}
