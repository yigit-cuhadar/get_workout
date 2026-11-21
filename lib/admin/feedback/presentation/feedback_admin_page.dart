import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_form.dart';
import '../../shell/admin_text.dart';
import '../domain/feedback_entry.dart';
import 'feedback_admin_cubit.dart';

/// The users' messages from Help & feedback, newest first, open or
/// closed, each with everything sent along and Close or Reopen.
class FeedbackAdminPage extends StatelessWidget {
  const FeedbackAdminPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<FeedbackAdminCubit>(),
    child: const _FeedbackView(),
  );
}

class _FeedbackView extends StatelessWidget {
  const _FeedbackView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<FeedbackAdminCubit>();
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: BlocConsumer<FeedbackAdminCubit, FeedbackAdminState>(
        listenWhen: (previous, current) =>
            current.updateFailure != null &&
            previous.updateFailure != current.updateFailure,
        listener: (context, state) => ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(failureMessage(state.updateFailure!))),
          ),
        builder: (context, state) {
          final entries = state.entries;
          final failure = state.failure;
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxFormWidth),
              child: ListView(
                padding: const EdgeInsets.all(Gap.md),
                children: [
                  Wrap(
                    spacing: Gap.sm,
                    children: [
                      for (final status in FeedbackEntryStatus.values)
                        ChoiceChip(
                          label: Text(_statusLabel(status)),
                          selected: state.filter == status,
                          onSelected: (_) => cubit.filter(status),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                  if (failure != null)
                    ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(
                        entries == null
                            ? failureMessage(failure)
                            : 'Live updates stopped: '
                                  '${failureMessage(failure)} '
                                  'Retrying automatically.',
                      ),
                      trailing: TextButton(
                        onPressed: cubit.retry,
                        child: const Text('Retry now'),
                      ),
                    ),
                  if (entries == null && failure == null) const LoadingView(),
                  if (entries != null && entries.isEmpty)
                    Text(
                      'No ${_statusLabel(state.filter).toLowerCase()} '
                      'messages.',
                    ),
                  for (final entry in entries ?? const <FeedbackEntry>[])
                    _EntryCard(
                      entry,
                      updating: state.updating.contains(entry.path),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

String _statusLabel(FeedbackEntryStatus status) => switch (status) {
  FeedbackEntryStatus.open => 'Open',
  FeedbackEntryStatus.closed => 'Closed',
};

class _EntryCard extends StatelessWidget {
  const _EntryCard(this.entry, {required this.updating});

  final FeedbackEntry entry;
  final bool updating;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final e = entry;
    final facts = [
      ('Sent', dateTimeLabel(e.createdAt)),
      ('Reply to', e.email ?? 'none'),
      ('From', e.source),
      ('User', e.uid),
      ('App', e.appVersion),
      ('Device', '${e.platform} ${e.osVersion} · ${e.deviceModel}'),
      ('Locale', e.locale),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(e.message, style: text.bodyLarge),
            const SizedBox(height: Gap.md),
            for (final (label, value) in facts)
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '$label: ', style: text.labelMedium),
                    TextSpan(text: value),
                  ],
                ),
              ),
            const SizedBox(height: Gap.sm),
            Wrap(
              spacing: Gap.sm,
              children: [
                if (e.email case final email?)
                  TextButton.icon(
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: email)),
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy email'),
                  ),
                FilledButton.tonal(
                  onPressed: updating
                      ? null
                      : () => context.read<FeedbackAdminCubit>().toggle(e),
                  child: Text(
                    e.status == FeedbackEntryStatus.open ? 'Close' : 'Reopen',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
