import 'package:flutter/material.dart';
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

class _Steps extends StatelessWidget {
  const _Steps({
    required this.history,
    required this.accessHint,
    required this.onOpenSettings,
  });

  final StepsHistory history;
  final bool accessHint;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final goal = context.select(
      (SettingsCubit cubit) => cubit.state.settings.stepGoal,
    );
    final firstWeekday = MaterialLocalizations.of(context).firstWeekday;
    final locale = l10n.localeName;
    Widget title(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, 0),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    return RefreshIndicator(
      onRefresh: context.read<StepsCubit>().load,
      child: ListView(
        // Pull-to-refresh also when everything fits.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: Gap.xl),
        children: [
          _Today(
            progress: StepGoalProgress(steps: history.today, goal: goal),
          ),
          if (accessHint)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l10n.stepsZeroHint),
              subtitle: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onOpenSettings,
                  child: Text(l10n.stepsOpenSettings),
                ),
              ),
            ),
          title(l10n.stepsThisWeek),
          _StepsChart(
            title: l10n.stepsThisWeek,
            days: history.week(firstWeekday),
            goal: goal,
            dayLabel: DateFormat.E(locale),
          ),
          title(l10n.stepsLastDays(stepHistoryDays)),
          _StepsChart(
            title: l10n.stepsLastDays(stepHistoryDays),
            days: history.days,
            goal: goal,
            dayLabel: DateFormat.MMMd(locale),
          ),
          const SizedBox(height: Gap.md),
          ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: Text(l10n.stepsGoal),
            trailing: Text(l10n.stepsGoalValue(goal)),
            onTap: () => _editGoal(context, goal),
          ),
        ],
      ),
    );
  }

  static Future<void> _editGoal(BuildContext context, int goal) async {
    final settings = context.read<SettingsCubit>();
    final chosen = await showDialog<int>(
      context: context,
      builder: (_) => _GoalDialog(goal),
    );
    if (chosen == null) return;
    await settings.update(settings.state.settings.copyWith(stepGoal: chosen));
  }
}

class _Today extends StatelessWidget {
  const _Today({required this.progress});
  final StepGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.stepsToday, style: theme.textTheme.titleMedium),
          const SizedBox(height: Gap.sm),
          Text(
            l10n.stepsCount(progress.steps),
            style: theme.textTheme.headlineMedium,
          ),
          Text(l10n.stepsOfGoal(progress.goal)),
          const SizedBox(height: Gap.sm),
          LinearProgressIndicator(value: progress.fraction),
          const SizedBox(height: Gap.sm),
          Text(
            progress.reached
                ? l10n.stepsGoalReached
                : l10n.stepsToGo(progress.remaining),
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
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: BarChart(
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
      ),
    );
  }
}

/// Picks a daily goal between the limits, in steps of [StepGoal.step].
class _GoalDialog extends StatefulWidget {
  const _GoalDialog(this.initial);
  final int initial;

  @override
  State<_GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<_GoalDialog> {
  late int _goal = widget.initial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(l10n.stepsGoal),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.stepsGoalValue(_goal), style: theme.textTheme.titleLarge),
          Slider(
            value: _goal.toDouble(),
            min: StepGoal.min.toDouble(),
            max: StepGoal.max.toDouble(),
            divisions: (StepGoal.max - StepGoal.min) ~/ StepGoal.step,
            onChanged: (value) => setState(() => _goal = value.round()),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _goal),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
