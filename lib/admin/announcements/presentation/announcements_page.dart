import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../features/exercises/domain/content_rules.dart';
import '../../shell/admin_text.dart';
import '../../shell/page_header.dart';
import '../domain/announcement.dart';
import 'announcement_text.dart';
import 'announcements_cubit.dart';
import 'send_confirm_dialog.dart';

/// The widest the page grows on a desktop screen, as the Dashboard.
const _maxPageWidth = 1280.0;

/// The form's width beside the history (A1 board).
const _formWidth = 460.0;

/// From this width the form and the history sit side by side.
const _twoColumnWidth = 840.0;

/// Writes a push announcement for an audience, sends it now or at a time
/// after a confirmation, or as a test to the admin's own devices, and lists
/// the scheduled and sent ones: the form on the left, the history on the
/// right.
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
      AnnouncementsState(sent: SentAnnouncement(:final scheduledFor?)) => (
        title: 'Scheduled',
        message:
            'It goes ${scheduleLabel(scheduledFor)}. You can cancel it in '
            'the list until then.',
        role: p.info,
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
  AnnouncementNotScheduledFailure() => (
    title: 'Not scheduled',
    message:
        'The schedule was not stored, so nothing will go. You can schedule '
        'it again.',
    role: p.danger,
  ),
  AnnouncementCancelledFailure() => (
    title: 'Cancelled',
    message:
        'This announcement was cancelled and never goes. Change its text to '
        'send a new one.',
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

/// What the panel says about the last test send.
_Outcome? _testOutcome(AnnouncementsState state, ForgePalette p) =>
    switch (state) {
      AnnouncementsState(
        testStatus: AnnouncementTestStatus.sent,
        testResult: TestAnnouncementResult(:final delivered, :final failed),
      ) =>
        (
          title: 'Test sent',
          message: failed == 0
              ? 'It reached ${_devices(delivered)} of yours.'
              : 'It reached ${_devices(delivered)} of yours; $failed refused '
                    'it.',
          role: p.success,
        ),
      AnnouncementsState(testFailure: NoTestDevicesFailure()) => (
        title: 'No device to test on',
        message:
            'None of your devices takes notifications: allow them for '
            'GetWorkout and open the app once signed in to this account.',
        role: p.danger,
      ),
      AnnouncementsState(testFailure: AnnouncementNotSentFailure()) => (
        title: 'Test not sent',
        message: 'It reached none of your devices.',
        role: p.danger,
      ),
      AnnouncementsState(testFailure: final failure?) => (
        title: 'Test not sent',
        message: failureMessage(failure),
        role: p.danger,
      ),
      _ => null,
    };

String _devices(int count) => count == 1 ? '1 device' : '$count devices';

/// A soft fill of [role] and an ink for text on it, as Forge's tags tint.
(Color fill, Color ink) _tint(ForgePalette p, Color role) =>
    (Color.lerp(p.surface, role, 0.16)!, Color.lerp(p.ink, role, 0.7)!);

class _AnnouncementsView extends StatelessWidget {
  const _AnnouncementsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxPageWidth),
          child: ListView(
            padding: const EdgeInsets.all(Gap.lg),
            children: [
              const PageHeader(
                title: 'Announcements',
                subtitle: 'Push notifications to the users who allowed them',
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
    final text = Theme.of(context).textTheme;
    final draft = state.draft;
    final sending = state.status == AnnouncementSendStatus.sending;
    final testing = state.testStatus == AnnouncementTestStatus.sending;
    final scheduleAt = draft.scheduleAt;
    final outcome = _outcome(state, colors, DateTime.now());
    final testOutcome = _testOutcome(state, colors);
    Widget label(String value) => Text(value, style: text.titleSmall);
    return SectionCard.plain(
      title: 'New announcement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md,
        children: [
          Text(
            'A push notification to the devices that allowed notifications, '
            'for its audience and language. Tapping it opens Today.',
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.sm,
            children: [
              label('Audience'),
              ForgeSegmentedControl<AnnouncementAudience>(
                segments: [
                  for (final audience in AnnouncementAudience.values)
                    ForgeSegment(
                      value: audience,
                      label: audienceLabel(audience),
                    ),
                ],
                selected: draft.audience,
                onChanged: cubit.setAudience,
              ),
            ],
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.sm,
            children: [
              label('When'),
              ForgeSegmentedControl<bool>(
                segments: const [
                  ForgeSegment(value: false, label: 'Now'),
                  ForgeSegment(value: true, label: 'Schedule'),
                ],
                selected: scheduleAt != null,
                onChanged: cubit.setScheduled,
              ),
              if (scheduleAt != null) _ScheduleFields(scheduleAt, state),
            ],
          ),
          const Divider(height: Gap.sm),
          Row(
            children: [
              ForgeButton(
                label: 'Send me a test',
                variant: ForgeButtonVariant.outline,
                loading: testing,
                onPressed: state.canTest ? cubit.sendTest : null,
              ),
              const Spacer(),
              ForgeButton(
                label: switch ((sending, scheduleAt)) {
                  (true, _) => 'Sending…',
                  (false, null) => 'Send now…',
                  (false, _) => 'Schedule…',
                },
                loading: sending,
                onPressed: state.canSend
                    ? () => _confirmThenSend(context)
                    : null,
              ),
            ],
          ),
          if (testOutcome != null) _OutcomeBox(testOutcome),
          if (outcome != null) _OutcomeBox(outcome),
        ],
      ),
    );
  }
}

/// The date and time a scheduled draft goes, in the admin's own time with
/// its zone named, each opening its picker; under them what that means, or
/// why the time cannot be used.
class _ScheduleFields extends StatelessWidget {
  const _ScheduleFields(this.at, this.state);

  final DateTime at;
  final AnnouncementsState state;

  Future<void> _pickDate(BuildContext context) async {
    final cubit = context.read<AnnouncementsCubit>();
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(scheduleLatest),
    );
    if (picked == null) return;
    cubit.setScheduleAt(
      DateTime(picked.year, picked.month, picked.day, at.hour, at.minute),
    );
  }

  Future<void> _pickTime(BuildContext context) async {
    final cubit = context.read<AnnouncementsCubit>();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
      // The page writes times in 24 hours; the picker says them the same.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    cubit.setScheduleAt(
      DateTime(at.year, at.month, at.day, picked.hour, picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ForgeStyle.of(context).colors;
    final small = Theme.of(context).textTheme.bodySmall;
    final problem = state.scheduleProblem;
    final locked = state.status == AnnouncementSendStatus.sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.xs,
      children: [
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ForgeButton(
              label: DateFormat('EEE, MMM d').format(at),
              variant: ForgeButtonVariant.outline,
              leadingIcon: ForgeIcons.event,
              onPressed: locked ? null : () => _pickDate(context),
            ),
            ForgeButton(
              label: DateFormat('HH:mm').format(at),
              variant: ForgeButtonVariant.outline,
              leadingIcon: ForgeIcons.timer,
              onPressed: locked ? null : () => _pickTime(context),
            ),
            Text(
              at.timeZoneName,
              style: small?.copyWith(color: colors.inkMuted),
            ),
          ],
        ),
        Text(
          problem ??
              'It goes at this time in your time zone; you can cancel it '
                  'until then.',
          style: small?.copyWith(
            color: problem == null ? colors.inkMuted : colors.danger,
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

/// The history: scheduled announcements first, in their own section with
/// Cancel, then the rest, newest first.
class _History extends StatelessWidget {
  const _History();

  Future<void> _confirmThenCancel(
    BuildContext context,
    Announcement announcement,
  ) async {
    final cubit = context.read<AnnouncementsCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this scheduled announcement?'),
        content: Text(
          '"${announcement.title}" will not go '
          '${scheduleLabel(announcement.scheduledFor!)}. To send it later, '
          'schedule it again.',
        ),
        actions: [
          ForgeButton(
            label: 'Keep it',
            variant: ForgeButtonVariant.outline,
            onPressed: () => Navigator.pop(context, false),
          ),
          ForgeButton(
            label: 'Cancel it',
            variant: ForgeButtonVariant.danger,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed ?? false) await cubit.cancel(announcement.id);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AnnouncementsCubit>();
    final state = context.watch<AnnouncementsCubit>().state;
    final colors = ForgeStyle.of(context).colors;
    final history = state.history ?? const <Announcement>[];
    final failure = state.historyFailure;
    // Soonest first: the next to go leads.
    final scheduled = [
      for (final a in history)
        if (a.status == AnnouncementStatus.scheduled) a,
    ]..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));
    final past = [
      for (final a in history)
        if (a.status != AnnouncementStatus.scheduled) a,
    ];
    Widget section(String title) => Padding(
      padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.xs),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: colors.inkMuted,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
    return BlocListener<AnnouncementsCubit, AnnouncementsState>(
      listenWhen: (previous, current) =>
          current.cancelFailure != null &&
          previous.cancelFailure != current.cancelFailure,
      listener: (context, state) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(switch (state.cancelFailure!) {
              AnnouncementNotCancellableFailure() =>
                'It is no longer scheduled: it went or is going.',
              final failure => 'Not cancelled: ${failureMessage(failure)}',
            }),
          ),
        ),
      child: SectionCard.plain(
        title: 'Announcements',
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
                      state.history == null
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
            if (state.history == null && failure == null) const LoadingView(),
            if (state.history != null && history.isEmpty)
              Text(
                'Nothing sent yet.',
                style: TextStyle(color: colors.inkMuted),
              ),
            if (scheduled.isNotEmpty) ...[
              section('Scheduled · ${scheduled.length}'),
              for (final (i, announcement) in scheduled.indexed) ...[
                if (i > 0) const Divider(height: Gap.lg),
                _HistoryRow(
                  announcement,
                  cancelling: state.cancelling.contains(announcement.id),
                  onCancel: () => _confirmThenCancel(context, announcement),
                ),
              ],
              if (past.isNotEmpty) section('Sent'),
            ],
            for (final (i, announcement) in past.indexed) ...[
              if (i > 0 || (failure != null && scheduled.isEmpty))
                const Divider(height: Gap.lg),
              _HistoryRow(announcement),
            ],
          ],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow(
    this.announcement, {
    this.cancelling = false,
    this.onCancel,
  });

  final Announcement announcement;
  final bool cancelling;

  /// Given for a scheduled one: asks, then cancels it.
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final a = announcement;
    final when = switch (a) {
      Announcement(
        status: AnnouncementStatus.scheduled,
        :final scheduledFor?,
      ) =>
        'goes ${dateTimeLabel(scheduledFor)}',
      Announcement(
        status: AnnouncementStatus.cancelled,
        :final scheduledFor?,
      ) =>
        'was due ${dateTimeLabel(scheduledFor)}',
      _ => dateTimeLabel(a.sentAt ?? a.requestedAt),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Gap.xs,
      children: [
        Text(a.title, style: text.titleSmall),
        Text(a.body, style: text.bodyMedium?.copyWith(color: colors.inkMuted)),
        Text(
          '${audienceLabel(a.audience)} · ${a.locale} · $when · by ${a.sender}',
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        Row(
          spacing: Gap.sm,
          children: [
            _StatusTag(a),
            if (onCancel case final cancel?)
              ForgeButton(
                label: 'Cancel',
                variant: ForgeButtonVariant.danger,
                size: ForgeButtonSize.small,
                loading: cancelling,
                onPressed: cancelling ? null : cancel,
              ),
          ],
        ),
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
      AnnouncementStatus.scheduled => ('Scheduled', ForgeTagKind.source),
      AnnouncementStatus.cancelled => ('Cancelled', ForgeTagKind.neutral),
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
