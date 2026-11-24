import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../shell/admin_text.dart';
import '../domain/announcement.dart';
import 'announcements_cubit.dart';
import 'send_confirm_dialog.dart';

/// The widest the page grows on a desktop screen, as the Dashboard.
const _maxPageWidth = 1280.0;

/// The form's width beside the history (A1 board).
const _formWidth = 460.0;

/// From this width the form and the history sit side by side.
const _twoColumnWidth = 840.0;

/// Writes a push announcement, sends it after a confirmation, and lists
/// the ones sent before: the form on the left, the history on the right.
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

/// How a send's outcome reads, and the colour role of its box.
typedef _Outcome = ({String title, String? message, Color role});

/// What the panel says about the last send at [now]. Only a failure after
/// which nothing was sent says sending again may send it.
_Outcome? _outcome(AnnouncementsState state, ForgePalette p, DateTime now) =>
    switch (state) {
      AnnouncementsState(sent: SentAnnouncement(alreadySent: true)) => (
        title: 'Already sent',
        message: 'This announcement was sent before; it was not sent again.',
        role: p.success,
      ),
      AnnouncementsState(status: AnnouncementSendStatus.sent) => (
        title: 'Sent',
        message: null,
        role: p.success,
      ),
      AnnouncementsState(failure: final failure?) => _failure(
        failure,
        accessRefreshed: state.accessRefreshed,
        p: p,
        now: now,
      ),
      _ => null,
    };

_Outcome _failure(
  Failure failure, {
  required bool accessRefreshed,
  required ForgePalette p,
  required DateTime now,
}) => switch (failure) {
  PermissionFailure() when accessRefreshed => (
    title: 'Refused',
    message:
        'This account still has admin access and its token is now '
        'refreshed. Send again.',
    role: p.danger,
  ),
  PermissionFailure() => (
    title: 'Refused',
    message: 'This account has no current admin claim.',
    role: p.danger,
  ),
  AnnouncementsUnavailableFailure() => (
    title: 'Sending is not available',
    message:
        'The sendAnnouncement function is not deployed to this project. '
        'Nothing was sent.',
    role: p.danger,
  ),
  AnnouncementInProgressFailure(:final requestedAt)
      when isStaleSending(requestedAt, now) =>
    (
      title: 'Outcome unknown',
      message:
          '$_outcomeUnknown. This announcement may or may not have reached '
          'devices, and it will not be sent again.',
      role: p.danger,
    ),
  AnnouncementInProgressFailure() => (
    title: 'Being sent',
    message:
        'This announcement is being sent right now. Check the history '
        'before sending again.',
    role: p.info,
  ),
  AnnouncementNotSentFailure() => (
    title: 'Not sent',
    message: 'FCM refused it, so nothing was sent. You can send it again.',
    role: p.danger,
  ),
  AnnouncementOutcomeUnknownFailure() => (
    title: 'Outcome unknown',
    message:
        'FCM did not say whether it took the announcement: it may or may '
        'not reach devices. Check a device; the same text will not be '
        'sent again.',
    role: p.danger,
  ),
  NetworkFailure() => (
    title: 'No connection',
    message:
        'No connection to Firebase; it may or may not have been sent. '
        'Sending the same text again never sends it twice.',
    role: p.danger,
  ),
  ValidationFailure(:final message) => (
    title: 'Refused',
    message: message,
    role: p.danger,
  ),
  _ => (
    title: 'Failed',
    message:
        '${failureMessage(failure)} It may or may not have been sent; '
        'sending the same text again never sends it twice.',
    role: p.danger,
  ),
};

/// A soft fill of [role] and an ink for text on it, as Forge's tags tint.
(Color fill, Color ink) _tint(ForgePalette p, Color role) =>
    (Color.lerp(p.surface, role, 0.16)!, Color.lerp(p.ink, role, 0.7)!);

class _AnnouncementsView extends StatelessWidget {
  const _AnnouncementsView();

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxPageWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              Text(
                'Push notifications to every user who allowed them',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: Gap.md),
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < _twoColumnWidth) {
                    return const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Gap.md,
                      children: [_Form(), _History()],
                    );
                  }
                  return const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Gap.md,
                    children: [
                      SizedBox(width: _formWidth, child: _Form()),
                      Expanded(child: _History()),
                    ],
                  );
                },
              ),
            ],
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SendConfirmDialog(draft: cubit.state.draft.trimmed),
    );
    if (confirmed ?? false) await cubit.send();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AnnouncementsCubit>();
    final state = context.watch<AnnouncementsCubit>().state;
    final colors = ForgeStyle.of(context).colors;
    final draft = state.draft;
    final sending = state.status == AnnouncementSendStatus.sending;
    final outcome = _outcome(state, colors, DateTime.now());
    return SectionCard.plain(
      title: 'New announcement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md,
        children: [
          Text(
            'A push notification to every device that allowed '
            'notifications, for its language. Tapping it opens Today.',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: colors.inkMuted),
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
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ForgeButton(
              label: sending ? 'Sending…' : 'Send…',
              loading: sending,
              onPressed: state.canSend ? () => _confirmThenSend(context) : null,
            ),
          ),
          if (outcome != null) _OutcomeBox(outcome),
        ],
      ),
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
      minLines: multiline ? 3 : 1,
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

/// The last send's outcome, kept under the form until the next send.
class _OutcomeBox extends StatelessWidget {
  const _OutcomeBox(this.outcome);

  final _Outcome outcome;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    final text = Theme.of(context).textTheme;
    final (fill, ink) = _tint(style.colors, outcome.role);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(style.radii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Gap.xs,
            children: [
              Text(outcome.title, style: text.titleSmall?.copyWith(color: ink)),
              if (outcome.message case final message?)
                Text(message, style: text.bodyMedium?.copyWith(color: ink)),
            ],
          ),
        ),
      ),
    );
  }
}

class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AnnouncementsCubit>();
    final state = context.watch<AnnouncementsCubit>().state;
    final colors = ForgeStyle.of(context).colors;
    final history = state.history;
    final failure = state.historyFailure;
    return SectionCard.plain(
      title: 'Sent before',
      note: 'Latest $announcementHistoryLength',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null)
            Row(
              spacing: Gap.sm,
              children: [
                Expanded(
                  child: Text(
                    history == null
                        ? failureMessage(failure)
                        : 'Live updates stopped: ${failureMessage(failure)} '
                              'Retrying automatically.',
                    style: TextStyle(color: colors.danger),
                  ),
                ),
                ForgeButton(
                  label: 'Retry now',
                  variant: ForgeButtonVariant.outline,
                  size: ForgeButtonSize.small,
                  onPressed: cubit.retryHistory,
                ),
              ],
            ),
          if (history == null && failure == null) const LoadingView(),
          if (history != null && history.isEmpty)
            Text('Nothing sent yet.', style: TextStyle(color: colors.inkMuted)),
          for (final (i, announcement)
              in (history ?? const <Announcement>[]).indexed) ...[
            if (i > 0 || failure != null) const Divider(height: Gap.lg),
            _HistoryRow(announcement),
          ],
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(this.announcement);

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final a = announcement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.xs,
      children: [
        Text(a.title, style: text.titleSmall),
        Text(a.body, style: text.bodyMedium?.copyWith(color: colors.inkMuted)),
        Text(
          '${a.locale} · ${dateTimeLabel(a.sentAt ?? a.requestedAt)} · '
          'by ${a.sentBy}',
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        _StatusTag(a),
      ],
    );
  }
}

/// Where [announcement] stands, as a tag; a failed or unknown outcome on a
/// danger tint, wrapping its longer label.
class _StatusTag extends StatelessWidget {
  const _StatusTag(this.announcement);

  final Announcement announcement;

  @override
  Widget build(BuildContext context) {
    final a = announcement;
    // A null kind is drawn on a danger tint.
    final (label, kind) = switch (a.status) {
      _ when a.outcomeUnknownAt(DateTime.now()) => (_outcomeUnknown, null),
      AnnouncementStatus.failed => ('Failed, not sent', null),
      AnnouncementStatus.sent => ('Sent', ForgeTagKind.record),
      AnnouncementStatus.sending => ('Sending', ForgeTagKind.source),
      AnnouncementStatus.unknown => ('Unknown', ForgeTagKind.neutral),
    };
    if (kind != null) return ForgeTag(label, kind: kind);
    // Forge's tags have no danger kind and stay on one line.
    final style = ForgeStyle.of(context);
    final (fill, ink) = _tint(style.colors, style.colors.danger);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(style.radii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Gap.sm,
          vertical: Gap.xs,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: ink, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
