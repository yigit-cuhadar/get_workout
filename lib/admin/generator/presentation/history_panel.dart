import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_text.dart';
import '../../shell/publishing.dart';
import '../domain/generator_rules.dart';
import 'generator_rules_cubit.dart';

/// The last versions, newest first; picking an earlier one puts its rules
/// into the draft, so the review shows what restoring it changes.
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key});

  Future<void> _restore(BuildContext context, StoredRules entry) async {
    final cubit = context.read<GeneratorRulesCubit>();
    final changes = cubit.state.changes.length;
    if (changes > 0) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Restore version ${entry.version}?'),
          content: Text(
            'Its rules replace your $changes unpublished '
            '${changes == 1 ? 'change' : 'changes'} in the draft.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore into the draft'),
            ),
          ],
        ),
      );
      if (!(replace ?? false)) return;
    }
    await cubit.restore(entry.version);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: ForgeStyle.of(context).colors.inkMuted,
    );
    final history = state.history;
    final failure = state.historyFailure;
    final current = state.loaded?.version;
    final restoring = state.restores;
    return HistoryPane(
      onClose: cubit.closeHistory,
      onRetry: cubit.retryHistory,
      loaded: history != null,
      failure: failure == null ? null : failureMessage(failure),
      intro:
          'Pick a version to restore it: its rules go into the draft, and '
          'Review and publish shows what that changes.',
      children: [
        if (state.restoreFailure case final failure?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.error_outline),
            title: Text('The version did not load. ${failureMessage(failure)}'),
          ),
        if (history != null && history.isEmpty)
          Text('No versions yet.', style: muted),
        for (final entry in history ?? const <StoredRules>[])
          Card(
            child: InkWell(
              onTap: entry.version == current || state.publishing
                  ? null
                  : () => _restore(context, entry),
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Gap.xs,
                  children: [
                    Row(
                      spacing: Gap.xs,
                      children: [
                        Expanded(
                          child: Text(
                            'Version ${entry.version}',
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (entry.version == current)
                          const ForgeTag('Current', kind: ForgeTagKind.record),
                        if (entry.version == restoring)
                          const ForgeTag(
                            'In the draft',
                            kind: ForgeTagKind.category,
                          ),
                        if (entry.version == state.restoreLoading)
                          const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    Text(
                      '${dateTimeLabel(entry.publishedAt)} · '
                      '${entry.publishedByEmail ?? 'content import'}',
                      style: muted,
                    ),
                    if (entry.note case final note?) Text(note),
                    if (entry.restores case final restores?)
                      Text('Restores version $restores', style: muted),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
