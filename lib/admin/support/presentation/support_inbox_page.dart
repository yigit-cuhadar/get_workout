import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../domain/support_inbox_repository.dart';
import '../domain/support_thread.dart';
import 'new_thread_count_cubit.dart';
import 'support_format.dart';
import 'support_inbox_cubit.dart';
import 'support_thread_cubit.dart';

/// The width of the thread list on the T1 board.
const _listWidth = 380.0;

/// How far a reply sits in from the message it answers.
const _replyIndent = 48.0;

/// The users' messages from Help & feedback as threads: the lists on the
/// left, the open thread on the right with its replies and the reply box
/// (T1-T4 A).
class SupportInboxPage extends StatelessWidget {
  const SupportInboxPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<SupportInboxCubit>(),
    child: const _InboxView(),
  );
}

class _InboxView extends StatelessWidget {
  const _InboxView();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    return Scaffold(
      body: BlocListener<SupportInboxCubit, SupportInboxState>(
        listenWhen: (previous, current) =>
            current.updateFailure != null &&
            previous.updateFailure != current.updateFailure,
        listener: (context, state) => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(supportFailureMessage(state.updateFailure!)),
            ),
          ),
        child: ListView(
          padding: const EdgeInsets.all(Gap.lg),
          children: [
            Text('Support inbox', style: text.headlineSmall),
            const SizedBox(height: Gap.xs),
            Text(
              'Messages from Help & feedback and the review prompt',
              style: text.bodyMedium!.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: Gap.lg),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: _listWidth, child: _ThreadList()),
                SizedBox(width: Gap.md),
                Expanded(child: _OpenThread()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A white card with the board's border.
class _Pane extends StatelessWidget {
  const _Pane({required this.padding, required this.child});

  final double padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final style = ForgeStyle.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.colors.surface,
        border: Border.all(color: style.colors.line, width: style.cardBorder),
        borderRadius: BorderRadius.all(Radius.circular(style.radii.lg)),
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}

class _ThreadList extends StatelessWidget {
  const _ThreadList();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupportInboxCubit>();
    final state = context.watch<SupportInboxCubit>().state;
    final threads = state.threads[state.filter];
    final failure = state.failures[state.filter];
    final now = DateTime.now();
    return _Pane(
      padding: Gap.md,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Gap.sm,
            runSpacing: Gap.sm,
            children: [
              for (final filter in ThreadFilter.values)
                ForgeChip(
                  label: switch (filter) {
                    ThreadFilter.open => 'Open',
                    ThreadFilter.closed => 'Closed',
                  },
                  count: state.threads[filter]?.length,
                  selected: state.filter == filter,
                  onPressed: () => cubit.filter(filter),
                ),
            ],
          ),
          const SizedBox(height: Gap.md),
          if (failure != null)
            ErrorView(
              title: threads == null
                  ? 'The threads did not load'
                  : 'Live updates stopped',
              message:
                  '${supportFailureMessage(failure)} Retrying automatically.',
              onRetry: cubit.retry,
              retryLabel: 'Retry now',
            ),
          if (threads == null && failure == null) const LoadingView(),
          if (threads != null && threads.isEmpty)
            EmptyView(
              message: switch (state.filter) {
                ThreadFilter.open => 'No open threads.',
                ThreadFilter.closed => 'No closed threads.',
              },
              compact: true,
            ),
          for (final thread in threads ?? const <SupportThread>[])
            _ThreadRow(
              thread: thread,
              now: now,
              selected: thread.path == state.selectedPath,
            ),
        ],
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.now,
    required this.selected,
  });

  final SupportThread thread;
  final DateTime now;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final isNew = thread.status == ThreadStatus.unreplied;
    return Material(
      color: selected ? colors.surfaceSunken : colors.surface,
      borderRadius: const BorderRadius.all(Radius.circular(ForgeRadii.button)),
      child: InkWell(
        borderRadius: const BorderRadius.all(
          Radius.circular(ForgeRadii.button),
        ),
        onTap: () => context.read<SupportInboxCubit>().select(thread),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.md,
            vertical: Gap.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      thread.email ?? 'No reply email',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall!.copyWith(
                        fontWeight: isNew ? FontWeight.w700 : null,
                        color: thread.email == null ? colors.inkMuted : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Text(
                    threadTimeLabel(thread.createdAt, now),
                    style: text.bodySmall!.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
              const SizedBox(height: Gap.xs),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      thread.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium!.copyWith(color: colors.inkMuted),
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  _StatusTag(thread.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag(this.status);

  final ThreadStatus status;

  @override
  Widget build(BuildContext context) => ForgeTag(
    threadStatusLabel(status),
    kind: switch (status) {
      ThreadStatus.unreplied => ForgeTagKind.category,
      ThreadStatus.replied => ForgeTagKind.source,
      ThreadStatus.closed => ForgeTagKind.neutral,
    },
  );
}

class _OpenThread extends StatelessWidget {
  const _OpenThread();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SupportInboxCubit>().state;
    final thread = state.selected;
    if (thread == null) {
      return const EmptyView(
        message: 'Pick a thread to read it and reply.',
        card: true,
      );
    }
    return BlocProvider(
      key: ValueKey(thread.path),
      create: (_) => sl<SupportThreadCubit>(param1: thread.path),
      child: _ThreadView(
        thread: thread,
        updating: state.updating.contains(thread.path),
      ),
    );
  }
}

class _ThreadView extends StatelessWidget {
  const _ThreadView({required this.thread, required this.updating});

  final SupportThread thread;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final state = context.watch<SupportThreadCubit>().state;
    final replies = state.replies;
    final now = DateTime.now();
    return _Pane(
      padding: Gap.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  thread.email ?? 'No reply email',
                  style: text.titleMedium,
                ),
              ),
              _StatusTag(thread.status),
              const SizedBox(width: Gap.sm),
              ForgeButton(
                label: thread.status == ThreadStatus.closed
                    ? 'Reopen'
                    : 'Close',
                variant: ForgeButtonVariant.outline,
                loading: updating,
                onPressed: () =>
                    context.read<SupportInboxCubit>().toggle(thread),
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          _Message(thread: thread),
          if (state.repliesFailure case final failure?) ...[
            const SizedBox(height: Gap.md),
            ErrorView(
              title: 'The replies did not load',
              message:
                  '${supportFailureMessage(failure)} Retrying automatically.',
              onRetry: context.read<SupportThreadCubit>().retryReplies,
              retryLabel: 'Retry now',
            ),
          ],
          for (final reply in replies ?? const <SupportReply>[]) ...[
            const SizedBox(height: Gap.md),
            _Reply(reply: reply, now: now),
          ],
          const SizedBox(height: Gap.md),
          Divider(height: 1, color: colors.line),
          const SizedBox(height: Gap.md),
          if (thread.canReply)
            _ReplyBox(thread: thread)
          else
            Text(
              'No reply email. This person left the email field empty, so a '
              'reply cannot be sent. Close the thread once it is handled.',
              style: text.bodyMedium!.copyWith(color: colors.inkMuted),
            ),
        ],
      ),
    );
  }
}

/// The user's message with what the app sent along.
class _Message extends StatelessWidget {
  const _Message({required this.thread});

  final SupportThread thread;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = ForgeStyle.of(context);
    final muted = text.bodySmall!.copyWith(color: style.colors.inkMuted);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: style.colors.line),
        borderRadius: BorderRadius.all(Radius.circular(style.radii.md)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Heading(
              title: thread.email ?? 'No reply email',
              time: fullTimeLabel(thread.createdAt),
            ),
            const SizedBox(height: Gap.sm),
            SelectableText(thread.message, style: text.bodyMedium),
            const SizedBox(height: Gap.sm),
            SelectableText.rich(
              TextSpan(
                style: muted,
                children: [
                  TextSpan(text: threadDetailsLabel(thread)),
                  TextSpan(
                    text: thread.uid,
                    style: style.data.copyWith(color: style.colors.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, required this.time});

  final String title;
  final String time;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(child: Text(title, style: text.titleSmall)),
        const SizedBox(width: Gap.sm),
        Text(time, style: text.bodySmall!.copyWith(color: colors.inkMuted)),
      ],
    );
  }
}

class _Reply extends StatelessWidget {
  const _Reply({required this.reply, required this.now});

  final SupportReply reply;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final style = ForgeStyle.of(context);
    final colors = style.colors;
    final by = reply.sentByEmail;
    final foot = switch (reply.status) {
      ReplyStatus.sent => [
        if (by != null) 'Sent by $by',
        'emailed to ${reply.to}',
      ].join(' · '),
      _ when reply.outcomeUnknownAt(now) =>
        'May not have been emailed to ${reply.to}',
      ReplyStatus.sending => 'Sending to ${reply.to}…',
      ReplyStatus.failed => 'Not sent: Gmail did not take it',
      ReplyStatus.unknown => 'Unknown state',
    };
    return Padding(
      padding: const EdgeInsets.only(left: _replyIndent),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.all(Radius.circular(style.radii.md)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Heading(
                title: 'Reply from $supportAddress',
                time: fullTimeLabel(reply.sentAt ?? reply.requestedAt),
              ),
              const SizedBox(height: Gap.sm),
              SelectableText(reply.message, style: text.bodyMedium),
              const SizedBox(height: Gap.sm),
              Text(
                foot,
                style: text.bodySmall!.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReplyBox extends StatelessWidget {
  const _ReplyBox({required this.thread});

  final SupportThread thread;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SupportThreadCubit>();
    final state = context.watch<SupportThreadCubit>().state;
    final sending = state.status == ReplySendStatus.sending;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ForgeTextField(
          key: ValueKey(state.formVersion),
          label:
              'Reply by email to ${thread.email} from $supportAddress · '
              'subject “$replySubject”',
          hint: 'Write a reply…',
          multiline: true,
          maxLength: maxReplyLength,
          enabled: !sending,
          errorText: switch (state.failure) {
            final failure? when state.status == ReplySendStatus.failed =>
              supportFailureMessage(failure),
            _ => null,
          },
          onChanged: cubit.setDraft,
        ),
        const SizedBox(height: Gap.md),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            ForgeButton(
              label: 'Send and close',
              variant: ForgeButtonVariant.outline,
              onPressed: state.canSend ? () => cubit.send(close: true) : null,
            ),
            ForgeButton(
              label: 'Send reply',
              loading: sending,
              onPressed: state.canSend ? () => cubit.send(close: false) : null,
            ),
          ],
        ),
      ],
    );
  }
}

/// The menu's count of New threads beside Support inbox; nothing while
/// there are none or the count is unknown.
class NewThreadCount extends StatelessWidget {
  const NewThreadCount({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<NewThreadCountCubit>(),
    child: BlocBuilder<NewThreadCountCubit, int?>(
      builder: (context, count) => switch (count) {
        null || 0 => const SizedBox.shrink(),
        final n => ForgeTag(
          n >= newCountCap ? '$newCountCap+' : '$n',
          kind: ForgeTagKind.neutral,
        ),
      },
    ),
  );
}
