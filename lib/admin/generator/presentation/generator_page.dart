import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../shell/admin_text.dart';
import '../../shell/page_header.dart';
import '../../shell/problem_card.dart';
import '../../shell/publishing.dart';
import '../../shell/unload_guard.dart';
import '../domain/generator_rules.dart';
import '../domain/rules_changes.dart';
import 'dosing_tab.dart';
import 'generator_rules_cubit.dart';
import 'history_panel.dart';
import 'generator_simulator_cubit.dart';
import 'review_dialog.dart';
import 'rules_text.dart';
import 'simulator_tab.dart';
import 'templates_tab.dart';
import 'value_tabs.dart';

final _date = DateFormat('d MMM y');

/// The generator's rules: the version line, the unpublished-changes bar and
/// a tab per part of the rules, all editing one draft (AG1 A), and the
/// simulator (AG4). Its state
/// answers whether the page may be left ([mayLeave]), and the browser asks
/// before the tab closes while there are unpublished changes.
class GeneratorPage extends StatefulWidget {
  const GeneratorPage({super.key});

  @override
  State<GeneratorPage> createState() => GeneratorPageState();
}

class GeneratorPageState extends State<GeneratorPage> {
  late final _cubit = sl<GeneratorRulesCubit>()..load();
  late final _unloadGuard = sl<UnloadGuard>();

  @override
  void dispose() {
    _unloadGuard.active = false;
    _cubit.close();
    super.dispose();
  }

  /// Whether the page may be left: yes without unpublished changes, else
  /// when the admin confirms losing them.
  Future<bool> mayLeave() async {
    final count = _cubit.state.changes.length;
    if (count == 0 || !mounted) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave without publishing?'),
        content: Text(
          'Your $count unpublished ${count == 1 ? 'change' : 'changes'} to '
          'the generator rules will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: _cubit),
      // Lives with the page, so its answers outlast switching tabs.
      BlocProvider(create: (_) => sl<GeneratorSimulatorCubit>()),
    ],
    child: BlocListener<GeneratorRulesCubit, GeneratorRulesState>(
      listenWhen: (previous, state) => previous.hasChanges != state.hasChanges,
      listener: (_, state) => _unloadGuard.active = state.hasChanges,
      child: const _GeneratorView(),
    ),
  );
}

String _versionLine(StoredRules loaded) => loaded.version == 0
    ? 'No rules published yet'
    : [
        'Version ${loaded.version}',
        [
          'published',
          if (loaded.publishedAt case final at?) _date.format(at.toLocal()),
          'by ${loaded.publishedByEmail ?? 'content import'}',
        ].join(' '),
      ].join(' · ');

String _failureMessage(Failure failure) => switch (failure) {
  GeneratorRulesUnavailableFailure() =>
    'The generator rules functions are not deployed to this project.',
  _ => failureMessage(failure),
};

/// What the page says about a failed publish.
String _publishFailureMessage(Failure failure, {required bool refreshed}) =>
    switch (failure) {
      PermissionFailure() when refreshed =>
        'Refused, but this account still has admin access and its token is '
            'now refreshed. Publish again.',
      PermissionFailure() =>
        'Refused: this account has no current admin claim.',
      GeneratorRulesInvalidFailure(:final problems) =>
        'Not published: the server found ${problems.length} problem(s). '
            'They are listed at the top.',
      GeneratorRulesUnavailableFailure() =>
        'Not published: the generator rules functions are not deployed to '
            'this project.',
      ValidationFailure(:final message) => 'Refused: $message',
      NetworkFailure() =>
        'No connection to Firebase; it may or may not have been published. '
            'Open History to see.',
      _ =>
        '${failureMessage(failure)} Open History to see whether it was '
            'published.',
    };

class _GeneratorView extends StatelessWidget {
  const _GeneratorView();

  @override
  Widget build(BuildContext context) {
    final historyOpen = context.select(
      (GeneratorRulesCubit cubit) => cubit.state.historyOpen,
    );
    return Scaffold(
      body: BlocListener<GeneratorRulesCubit, GeneratorRulesState>(
        listenWhen: (previous, state) =>
            previous.publishStatus != state.publishStatus,
        listener: (context, state) {
          // Not on the reload after a publish, which would hide its line.
          final messenger = ScaffoldMessenger.of(context);
          switch (state) {
            case GeneratorRulesState(
              publishStatus: PublishStatus.published,
              published: final version?,
            ):
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(content: Text('Published version $version.')),
                );
            case GeneratorRulesState(publishFailure: final failure?)
                when failure is! GeneratorRulesStaleFailure:
              messenger
                ..hideCurrentSnackBar()
                ..showSnackBar(
                  SnackBar(
                    content: Text(
                      _publishFailureMessage(
                        failure,
                        refreshed: state.accessRefreshed,
                      ),
                    ),
                  ),
                );
            default:
          }
        },
        child: PageWithHistory(
          page: const _Rules(),
          history: historyOpen ? const HistoryPanel() : null,
        ),
      ),
    );
  }
}

class _Rules extends StatelessWidget {
  const _Rules();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final loaded = state.loaded;
    if (loaded == null) {
      return switch (state.loadFailure) {
        final failure? => ErrorView(
          title: 'The generator rules did not load',
          message: _failureMessage(failure),
          onRetry: cubit.load,
          retryLabel: 'Retry',
        ),
        null => const LoadingView(),
      };
    }
    final changes = state.changes;
    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.md,
        children: [
          PageHeader(
            title: 'Generator',
            subtitle: _versionLine(loaded),
            trailing: [
              if (state.checking || state.checkDue)
                const Padding(
                  padding: EdgeInsets.only(top: Gap.sm),
                  child: Text('Checking…'),
                ),
              if (changes.isEmpty)
                OutlinedButton(
                  onPressed: state.historyOpen
                      ? cubit.closeHistory
                      : cubit.openHistory,
                  child: const Text('History'),
                ),
            ],
          ),
          if (changes.isNotEmpty) _ChangesBar(state),
          if (state.loadFailure case final failure?)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(_failureMessage(failure)),
              trailing: TextButton(
                onPressed: cubit.load,
                child: const Text('Retry'),
              ),
            ),
          if (state.stale)
            MaterialBanner(
              content: const Text(
                'Not published: someone else published a new version of the '
                'rules meanwhile. Reload to compare your changes with it; '
                'they are kept.',
              ),
              actions: [
                TextButton(onPressed: cubit.load, child: const Text('Reload')),
              ],
            ),
          if (state.checkFailure case final failure?)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(
                'The rules could not be checked. ${_failureMessage(failure)}',
              ),
              trailing: TextButton(
                onPressed: cubit.checkDraft,
                child: const Text('Retry'),
              ),
            ),
          const Expanded(child: _Tabs()),
        ],
      ),
    );
  }
}

/// "n unpublished changes · Dosing" with Discard, History and Review and
/// publish.
class _ChangesBar extends StatelessWidget {
  const _ChangesBar(this.state);

  final GeneratorRulesState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    return PublishBar(
      count: state.changes.length,
      where: state.changedTabs.map((tab) => tab.label).join(', '),
      publishing: state.publishing,
      onDiscard: cubit.discard,
      onReview: state.canPublish ? () => showReviewDialog(context) : null,
      actions: [
        OutlinedButton(
          onPressed: state.historyOpen ? cubit.closeHistory : cubit.openHistory,
          child: const Text('History'),
        ),
      ],
    );
  }
}

/// The tabs over the open tab's content, with the problem card on top.
class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(
    length: RulesTab.values.length,
    vsync: this,
    initialIndex: context.read<GeneratorRulesCubit>().state.tab.index,
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeneratorRulesCubit>();
    final state = context.watch<GeneratorRulesCubit>().state;
    final draft = state.draft;
    return BlocListener<GeneratorRulesCubit, GeneratorRulesState>(
      listenWhen: (previous, state) => previous.tab != state.tab,
      // A problem line opens its tab.
      listener: (context, state) => _tabs.index = state.tab.index,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            onTap: (index) => cubit.selectTab(RulesTab.values[index]),
            tabs: [
              for (final tab in RulesTab.values)
                Tab(
                  child: _TabLabel(
                    tab.label,
                    hasProblem: state.problemTabs.contains(tab),
                  ),
                ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: Gap.md),
              children: [
                if (state.problems.isNotEmpty && draft != null) ...[
                  ProblemCard(
                    lines: [
                      for (final problem in state.problems)
                        (
                          label: _problemLabel(draft, problem),
                          message: problem.message,
                          onOpen: tabOf(problem.path) == null
                              ? null
                              : () => cubit.openProblem(problem),
                        ),
                    ],
                  ),
                  const SizedBox(height: Gap.md),
                ],
                if (draft == null)
                  const EmptyView(
                    message:
                        'The content import seeds the rules. Until it has, '
                        'there is nothing to edit here.',
                  )
                else
                  switch (state.tab) {
                    RulesTab.templates => const TemplatesTab(),
                    RulesTab.dosing => const DosingTab(),
                    RulesTab.volume => const VolumeTab(),
                    RulesTab.selection => const SelectionTab(),
                    RulesTab.areas => const AreasTab(),
                    RulesTab.simulator => const SimulatorTab(),
                  },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Where a problem is, starting with its tab.
String _problemLabel(GeneratorRules draft, RulesProblem problem) {
  final place = placeOf(draft, problem.path);
  return switch (tabOf(problem.path)) {
    final tab? when !place.startsWith(tab.label) => '${tab.label} · $place',
    _ => place,
  };
}

/// A tab's name, with a mark when it has a problem.
class _TabLabel extends StatelessWidget {
  const _TabLabel(this.label, {required this.hasProblem});

  final String label;
  final bool hasProblem;

  /// The diameter of the problem mark.
  static const _mark = 8.0;

  @override
  Widget build(BuildContext context) {
    if (!hasProblem) return Text(label);
    return Semantics(
      label: '$label, has problems',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Gap.xs,
        children: [
          Text(label),
          Container(
            width: _mark,
            height: _mark,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ForgeStyle.of(context).colors.danger,
            ),
          ),
        ],
      ),
    );
  }
}
