import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../core/bar_chart.dart';
import '../../../core/first_weekday.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../domain/steps.dart';
import 'steps_cubit.dart';

/// Today's steps against the daily goal, this week and the last 30 days,
/// read from Apple Health or Health Connect; or what stands in the way.
class StepsPage extends StatelessWidget {
  const StepsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocProvider(create: (_) => sl<StepsCubit>(), child: const _StepsView());
}

class _StepsView extends StatefulWidget {
  const _StepsView();

  @override
  State<_StepsView> createState() => _StepsViewState();
}

class _StepsViewState extends State<_StepsView> {
  late final StepsCubit _cubit = context.read<StepsCubit>();
  late final AppLifecycleListener _lifecycle;

  /// Access may have changed in the system settings, and steps added,
  /// while the app was away.
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _cubit.load);
    _cubit.load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    void snack(String text) =>
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(text)));
    return MultiBlocListener(
      listeners: [
        // A failed refresh: the steps stay.
        BlocListener<StepsCubit, StepsState>(
          listenWhen: (previous, current) =>
              current.failure != previous.failure &&
              current.failureShown == StepsFailureShown.snack,
          listener: (_, _) => snack(l10n.stepsRefreshFailed),
        ),
        BlocListener<SettingsCubit, SettingsState>(
          listenWhen: (previous, current) =>
              current.failure != null && current.failure != previous.failure,
          listener: (_, _) => snack(l10n.settingsSaveFailed),
        ),
      ],
      child: BlocBuilder<StepsCubit, StepsState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(l10n.stepsTitle)),
          body: _body(context, state),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, StepsState state) {
    final l10n = AppLocalizations.of(context);
    final failed = ErrorView(
      message: l10n.stepsLoadFailed,
      retryLabel: l10n.retry,
      onRetry: _cubit.load,
    );
    if (state.failureShown == StepsFailureShown.page) return failed;
    final inlineFailure = state.failureShown == StepsFailureShown.inline
        ? const _InlineFailure()
        : null;
    final history = state.history;
    return switch (state.access) {
      null => const LoadingView(),
      StepsAccess.unsupported => EmptyView(
        message: l10n.stepsUnsupported,
        action: inlineFailure,
      ),
      StepsAccess.notInstalled => EmptyView(
        message: l10n.stepsNotInstalled,
        action: Column(
          children: [
            ?inlineFailure,
            FilledButton(
              onPressed: state.busy ? null : () => _openSettings(context),
              child: Text(l10n.stepsGetHealthConnect),
            ),
          ],
        ),
      ),
      StepsAccess.explain => _Explanation(
        busy: state.busy,
        failure: inlineFailure,
      ),
      StepsAccess.denied => EmptyView(
        message: l10n.stepsDenied,
        action: Column(
          children: [
            ?inlineFailure,
            FilledButton(
              onPressed: state.busy ? null : () => _openSettings(context),
              child: Text(l10n.stepsOpenHealthConnect),
            ),
            const SizedBox(height: Gap.sm),
            TextButton(
              onPressed: state.busy ? null : _cubit.allow,
              child: Text(l10n.stepsAskAgain),
            ),
          ],
        ),
      ),
      StepsAccess.granted ||
      StepsAccess.undetermined when history == null => const LoadingView(),
      StepsAccess.granted || StepsAccess.undetermined => _Steps(
        history: history!,
        accessHint: state.accessHint,
        onOpenSettings: () => _openSettings(context),
      ),
    };
  }

  Future<void> _openSettings(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failedText = AppLocalizations.of(context).stepsSettingsFailed;
    if (!await _cubit.openSettings()) {
      messenger.showSnackBar(SnackBar(content: Text(failedText)));
    }
  }
}

/// What the steps are for, before the system asks for access; asked only
/// after the user continues.
class _Explanation extends StatelessWidget {
  const _Explanation({required this.busy, required this.failure});
  final bool busy;
  final Widget? failure;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final store = theme.platform == TargetPlatform.iOS
        ? l10n.stepsStoreApple
        : l10n.stepsStoreGoogle;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.stepsExplainTitle,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gap.md),
            Text(
              l10n.stepsExplainBody(store),
              style: theme.textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Gap.lg),
            ?failure,
            ForgeButton(
              label: l10n.stepsContinue,
              loading: busy,
              onPressed: context.read<StepsCubit>().allow,
            ),
          ],
        ),
      ),
    );
  }
}

/// That the last request or load failed, above the actions to try again.
class _InlineFailure extends StatelessWidget {
  const _InlineFailure();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final store = theme.platform == TargetPlatform.iOS
        ? l10n.stepsStoreApple
        : l10n.stepsStoreGoogle;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Text(
        l10n.stepsRequestFailed(store),
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.error,
        ),
      ),
    );
  }
}

/// Today as a ring with the goal edited in place, the access hint, and one
/// chart that switches between this week and the last 30 days.
class _Steps extends StatefulWidget {
  const _Steps({
    required this.history,
    required this.accessHint,
    required this.onOpenSettings,
  });

  final StepsHistory history;
  final bool accessHint;
  final VoidCallback onOpenSettings;

  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> {
  bool _month = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final history = widget.history;
    final goal = context.select(
      (SettingsCubit cubit) => cubit.state.settings.stepGoal,
    );
    final firstWeekday = MaterialLocalizations.of(context).firstWeekday;
    final locale = l10n.localeName;
    final days = _month ? history.days : history.week(firstWeekday);
    final title = _month
        ? l10n.stepsLastDays(stepHistoryDays)
        : l10n.stepsThisWeek;
    return RefreshIndicator(
      onRefresh: context.read<StepsCubit>().load,
      child: ListView(
        // Pull-to-refresh also when everything fits.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.md),
        children: [
          _Today(
            progress: StepGoalProgress(steps: history.today, goal: goal),
          ),
          if (widget.accessHint)
            Card(
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.stepsZeroHint),
                subtitle: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: widget.onOpenSettings,
                    child: Text(l10n.stepsOpenSettings),
                  ),
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: false,
                        label: Text(l10n.stepsThisWeek),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text(l10n.stepsLastDays(stepHistoryDays)),
                      ),
                    ],
                    selected: {_month},
                    onSelectionChanged: (selection) =>
                        setState(() => _month = selection.single),
                  ),
                  const SizedBox(height: Gap.md),
                  _StepsChart(
                    title: title,
                    days: days,
                    goal: goal,
                    dayLabel: _month
                        ? DateFormat.MMMd(locale)
                        : DateFormat.E(locale),
                  ),
                  if (history.days.lastOrNull case final today?)
                    _Summary(StepsSummary.before(today.day, days, goal: goal)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's steps as a ring around the count, what is left to the goal, and
/// the goal with minus and plus; tapping it types it.
class _Today extends StatelessWidget {
  const _Today({required this.progress});
  final StepGoalProgress progress;

  /// Wide enough for the count in the ring's middle.
  static const _ring = Gap.xl * 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          children: [
            Semantics(
              label:
                  '${l10n.stepsCount(progress.steps)} '
                  '${l10n.stepsOfGoal(progress.goal)}',
              excludeSemantics: true,
              child: SizedBox.square(
                dimension: _ring,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: progress.fraction,
                      strokeWidth: Gap.sm,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                    ),
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            number.format(progress.steps),
                            style: theme.textTheme.headlineSmall,
                          ),
                          Text(
                            l10n.stepsOfGoal(progress.goal),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.stepsToday, style: theme.textTheme.titleMedium),
                  Text(
                    progress.reached
                        ? l10n.stepsGoalReached
                        : l10n.stepsToGo(progress.remaining),
                  ),
                  const SizedBox(height: Gap.sm),
                  Text(l10n.stepsGoal, style: theme.textTheme.labelMedium),
                  _GoalEditor(progress.goal),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The daily goal between minus and plus, which move it by [StepGoal.step]
/// within the limits; tapping the number types it.
class _GoalEditor extends StatelessWidget {
  const _GoalEditor(this.goal);
  final int goal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    return Row(
      children: [
        IconButton(
          tooltip: l10n.stepsGoalLower(StepGoal.step),
          icon: const Icon(Icons.remove),
          onPressed: goal > StepGoal.min
              ? () => _save(context, StepGoal.stepped(goal, -1))
              : null,
        ),
        Expanded(
          child: Tooltip(
            message: l10n.stepsGoalType,
            child: TextButton(
              onPressed: () => _type(context),
              child: Text(
                number.format(goal),
                style: theme.textTheme.titleMedium,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: l10n.stepsGoalRaise(StepGoal.step),
          icon: const Icon(Icons.add),
          onPressed: goal < StepGoal.max
              ? () => _save(context, StepGoal.stepped(goal, 1))
              : null,
        ),
      ],
    );
  }

  Future<void> _type(BuildContext context) async {
    final typed = await showDialog<int>(
      context: context,
      builder: (_) => _GoalDialog(goal),
    );
    if (typed != null && context.mounted) await _save(context, typed);
  }

  static Future<void> _save(BuildContext context, int goal) {
    final settings = context.read<SettingsCubit>();
    return settings.update(settings.state.settings.copyWith(stepGoal: goal));
  }
}

/// The daily average and the days the goal was reached, over the days of
/// the chart that are over; nothing while none is.
class _Summary extends StatelessWidget {
  const _Summary(this.summary);
  final StepsSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (summary.days == 0) return const SizedBox.shrink();
    Widget stat(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          Text(value, style: theme.textTheme.titleMedium),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Row(
        children: [
          stat(l10n.stepsAverage, l10n.stepsCount(summary.average)),
          const SizedBox(width: Gap.md),
          stat(
            l10n.stepsGoalReached,
            l10n.stepsReachedDays(summary.reached, summary.days),
          ),
        ],
      ),
    );
  }
}

/// A bar a day with the goal across; a tap names the day and its steps.
class _StepsChart extends StatelessWidget {
  const _StepsChart({
    required this.title,
    required this.days,
    required this.goal,
    required this.dayLabel,
  });

  final String title;
  final List<DailySteps> days;
  final int goal;

  /// The label below a bar.
  final DateFormat dayLabel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final axis = NumberFormat.compact(locale: l10n.localeName);
    final fullDate = DateFormat.MMMEd(l10n.localeName);
    String dayText(DailySteps day) =>
        l10n.stepsOnDay(fullDate.format(day.day), l10n.stepsCount(day.count));
    return BarChart(
      values: [for (final day in days) day.count.toDouble()],
      xLabel: (index) => dayLabel.format(days[index].day),
      yLabel: axis.format,
      yPrecision: 1,
      barLabel: (index) => dayText(days[index]),
      semanticLabel: l10n.stepsChartLabel(
        title,
        l10n.stepsGoalValue(goal),
        l10n.inlineList(days.map(dayText)),
      ),
      target: goal.toDouble(),
    );
  }
}

/// Types the daily goal; a number within the limits is taken on the
/// nearest step.
class _GoalDialog extends StatefulWidget {
  const _GoalDialog(this.initial);
  final int initial;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late final _controller = TextEditingController(text: '${widget.initial}');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final goal = switch (int.tryParse(_controller.text)) {
      final value? => StepGoal.typed(value),
      null => null,
    };
    if (goal != null) return Navigator.pop(context, goal);
    final l10n = AppLocalizations.of(context);
    setState(() => _error = l10n.stepsGoalRange(StepGoal.min, StepGoal.max));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.stepsGoal),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        // Whole numbers only; five digits hold the largest goal.
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(errorText: _error, errorMaxLines: 2),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
