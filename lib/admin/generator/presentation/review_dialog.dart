import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_ui/forge_ui.dart';

import '../../shell/admin_text.dart';
import '../../shell/publishing.dart';
import '../domain/generator_rules.dart';
import 'generator_rules_cubit.dart';
import 'generator_sizes.dart';
import 'rules_text.dart';

/// What a finding of each kind says, after its count.
const _kindLines = {
  FindingKind.refused: 'get no program',
  FindingKind.uncovered: 'leave a target muscle without direct work',
  FindingKind.short: 'have a day under half the session',
};

/// The kind as the findings list names it.
const _kindNames = {
  FindingKind.refused: 'No program',
  FindingKind.uncovered: 'Muscle without direct work',
  FindingKind.short: 'Short day',
};

/// Checks the draft and opens the review (AG5): what changes, what the
/// standard answers get with it next to the published rules, a note, and
/// Publish version N.
Future<void> showReviewDialog(BuildContext context) {
  final cubit = context.read<GeneratorRulesCubit>();
  cubit.review();
  return showDialog<void>(
    context: context,
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const ReviewDialog()),
  );
}

class ReviewDialog extends StatefulWidget {
  const ReviewDialog({super.key});

  @override
  State<ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<ReviewDialog> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    await context.read<GeneratorRulesCubit>().publish(_note.text);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: ForgeStyle.of(context).colors.inkMuted,
    );
    final heading = theme.textTheme.labelLarge?.copyWith(
      color: ForgeStyle.of(context).colors.inkMuted,
    );
    final next = (state.loaded?.version ?? 0) + 1;
    return AlertDialog(
      title: Text('Publish version $next of the generator rules'),
      content: SizedBox(
        width: GeneratorSizes.dialog,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Gap.md,
            children: [
              if (state.restores case final version?)
                Text('Restores version $version.', style: muted),
              Text('WHAT CHANGES', style: heading),
              ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: GeneratorSizes.changesHeight,
                ),
                child: SingleChildScrollView(
                  child: ChangeTable([
                    for (final change in state.changes)
                      if (changeLine(change, state.rules!, state.draft!) case (
                        :final where,
                        :final now,
                        :final after,
                      ))
                        (where, now, after),
                  ]),
                ),
              ),
              Text(
                // The check's answer does not say how many it tried.
                'TRIED ON STANDARD ANSWERS',
                style: heading,
              ),
              _Tried(state),
              TextField(
                controller: _note,
                maxLength: maxRulesNote,
                decoration: const InputDecoration(
                  labelText: 'Note for the history (optional)',
                ),
              ),
              Text(
                'Every program generated from now on uses version $next. '
                'Programs users already saved do not change. An earlier '
                'version can be restored from History.',
                style: muted,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.publishing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: state.canPublish && !state.checking ? _publish : null,
          child: Text(
            state.publishing ? 'Publishing…' : 'Publish version $next',
          ),
        ),
        if (state.checkFailure != null)
          TextButton(onPressed: cubit.checkDraft, child: const Text('Retry')),
      ],
    );
  }
}

/// What the standard answers get with the draft, next to the published
/// rules.
class _Tried extends StatelessWidget {
  const _Tried(this.state);

  final GeneratorRulesState state;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    if (state.checking || (!state.draftChecked && state.checkFailure == null)) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.xs,
        children: [
          LinearProgressIndicator(),
          Text('Trying the rules on the standard answers…'),
        ],
      );
    }
    if (state.checkFailure case final failure?) {
      return Text('The rules could not be checked. ${failureMessage(failure)}');
    }
    if (state.problems.isNotEmpty) {
      return Text(
        'The server found ${state.problems.length} problem(s) in the rules. '
        'Close this and fix them first; they are listed at the top of the '
        'page.',
      );
    }
    final findings = state.check?.findings ?? const <Finding>[];
    final published = state.loadedFindings;
    final total = answerCount(findings);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Gap.sm,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.sm,
          children: [
            for (final kind in FindingKind.values)
              Expanded(
                child: _Count(
                  count: answerCount(findings, kind),
                  line: _kindLines[kind]!,
                  published: switch (published) {
                    final published? => '${answerCount(published, kind)}',
                    null when state.publishedCheckFailure != null => '?',
                    null => '…',
                  },
                ),
              ),
          ],
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'These are warnings and do not block publishing.',
              style: muted,
            ),
            if (total > 0)
              TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => FindingsDialog(findings),
                ),
                child: Text('See the $total answers'),
              ),
          ],
        ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({
    required this.count,
    required this.line,
    required this.published,
  });

  final int count;
  final String line;
  final String published;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = ForgeStyle.of(context).colors.inkMuted;
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(Gap.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Gap.xs,
          children: [
            Text('$count', style: text.titleLarge),
            Text(line, style: text.bodySmall),
            Text(
              'published: $published',
              style: text.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Every finding of the check: the answer, its kind and what it is.
class FindingsDialog extends StatelessWidget {
  const FindingsDialog(this.findings, {super.key});

  final List<Finding> findings;

  @override
  Widget build(BuildContext context) {
    final heading = Theme.of(context).textTheme.labelMedium
        ?.copyWith(color: ForgeStyle.of(context).colors.inkMuted);
    const widths = [130.0, 110.0, 50.0, 100.0, 190.0];
    Widget row(List<String> cells, [TextStyle? style]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, width) in widths.indexed)
            SizedBox(
              width: width,
              child: Text(cells[i], style: style),
            ),
          Expanded(child: Text(cells.last, style: style)),
        ],
      ),
    );
    final count = answerCount(findings);
    return AlertDialog(
      title: Text('$count answers with warnings'),
      content: SizedBox(
        width: GeneratorSizes.dialog * 1.4,
        height: MediaQuery.sizeOf(context).height * 0.6,
        child: Column(
          children: [
            row([
              'Goal',
              'Level',
              'Days',
              'Equipment',
              'Warning',
              'Detail',
            ], heading),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: findings.length,
                itemBuilder: (context, i) {
                  final finding = findings[i];
                  return row([
                    codeWords(finding.goal),
                    codeWords(finding.level),
                    '${finding.daysPerWeek}',
                    codeWords(finding.equipment),
                    _kindNames[finding.kind]!,
                    finding.detail,
                  ]);
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
