import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_health/forge_health.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/page_parts.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/domain/calendar_date.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/first_weekday.dart';
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
        showForgeSnackbar(context, message: text, error: true);
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
          appBar: ForgeAppBar(title: l10n.stepsTitle),
          body: _body(context, state),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, StepsState state) {
    final l10n = AppLocalizations.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final store = ios ? l10n.stepsStoreApple : l10n.stepsStoreGoogle;
    if (state.failureShown == StepsFailureShown.page) {
      return ErrorView(
        title: l10n.stepsLoadFailed,
        message: l10n.stepsLoadFailedDetail,
        retryLabel: l10n.retry,
        onRetry: _cubit.load,
      );
    }
    // Asking or opening the settings failed: say so in place of the
    // prompt, with a retry of what failed.
    if (state.failureShown == StepsFailureShown.inline) {
      return _Centred(
        PermissionPrompt.failed(
          title: l10n.stepsRequestFailed(store),
          message: l10n.stepsRequestFailedDetail,
          retryLabel: l10n.retry,
          onRetry: state.access == StepsAccess.notInstalled
              ? _cubit.load
              : _cubit.allow,
        ),
      );
    }
    final history = state.history;
    return switch (state.access) {
      null => const _Loading(),
      StepsAccess.unsupported => EmptyView(message: l10n.stepsUnsupported),
      StepsAccess.notInstalled => _Centred(
        PermissionPrompt.missing(
          title: l10n.stepsNotInstalledTitle,
          message: l10n.stepsNotInstalled,
          getLabel: l10n.stepsGetHealthConnect,
          onGet: () => _openSettings(context),
          notNowLabel: l10n.stepsNotNow,
          onNotNow: () => context.pop(),
        ),
      ),
      StepsAccess.explain => _Centred(
        PermissionPrompt.ask(
          icon: ForgeIcons.directionsWalk,
          title: l10n.stepsExplainTitle,
          message: l10n.stepsExplainBody(store),
          allowLabel: l10n.stepsAllow,
          onAllow: _cubit.allow,
          // HealthKit never says it refused, so iOS says where to look.
          note: ios ? l10n.stepsExplainNote : null,
        ),
      ),
      StepsAccess.denied => _Centred(
        PermissionPrompt.refused(
          title: l10n.stepsDeniedTitle,
          message: l10n.stepsDenied,
          settingsLabel: l10n.stepsOpenHealthConnect,
          onOpenSettings: () => _openSettings(context),
          askAgainLabel: l10n.stepsAskAgain,
          onAskAgain: _cubit.allow,
        ),
      ),
      StepsAccess.granted ||
      StepsAccess.undetermined when history == null => const _Loading(),
      StepsAccess.granted || StepsAccess.undetermined => _Steps(
        history: history!,
        accessHint: state.accessHint,
        onOpenSettings: () => _openSettings(context),
      ),
    };
  }

  Future<void> _openSettings(BuildContext context) async {
    final failed = AppLocalizations.of(context).stepsSettingsFailed;
    if (!await _cubit.openSettings() && context.mounted) {
      showForgeSnackbar(context, message: failed, error: true);
    }
  }
}

/// A prompt in the middle of the page, scrolling at large text.
class _Centred extends StatelessWidget {
  const _Centred(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.md),
      child: child,
    ),
  );
}

/// The page's parts shimmering while the steps load.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        const SurfaceCard(child: Center(child: Progress.ringLoading())),
        const SizedBox(height: Gap.md),
        StepperField.loading(),
        const SizedBox(height: Gap.md),
        Chart.loading(title: l10n.stepsThisWeek),
      ],
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
    final firstWeekday = context.watchFirstWeekday();
    final days = _month ? history.days : history.week(firstWeekday);
    final today = history.days.lastOrNull?.day;
    return RefreshIndicator(
      onRefresh: context.read<StepsCubit>().load,
      child: ListView(
        // Pull-to-refresh also when everything fits.
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Gap.md),
        children: [
          _Today(StepGoalProgress(steps: history.today, goal: goal)),
          const SizedBox(height: Gap.md),
          _GoalEditor(goal),
          if (widget.accessHint) ...[
            const SizedBox(height: Gap.md),
            NoticeBanner(
              icon: ForgeIcons.info,
              title: l10n.stepsZeroHintTitle,
              message: l10n.stepsZeroHint,
              action: ForgeButton(
                label: l10n.stepsOpenSettings,
                variant: ForgeButtonVariant.secondary,
                onPressed: widget.onOpenSettings,
              ),
            ),
          ],
          const SizedBox(height: Gap.md),
          ForgeSegmentedControl<bool>(
            segments: [
              ForgeSegment(value: false, label: l10n.stepsThisWeek),
              ForgeSegment(
                value: true,
                label: l10n.stepsLastDays(stepHistoryDays),
              ),
            ],
            selected: _month,
            onChanged: (month) => setState(() => _month = month),
          ),
          const SizedBox(height: Gap.md),
          if (_month)
            _MonthChart(days: days, goal: goal)
          else
            _WeekChart(days: days, goal: goal, today: today),
          if (today != null)
            _Summary(StepsSummary.before(today, days, goal: goal)),
        ],
      ),
    );
  }
}

/// Today's steps in the ring, "of" the goal inside it, and what is left
/// to it under it.
class _Today extends StatelessWidget {
  const _Today(this.progress);
  final StepGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final style = ForgeStyle.of(context);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    return SurfaceCard(
      child: Column(
        children: [
          Progress.ring(
            value: progress.steps.toDouble(),
            goal: progress.goal.toDouble(),
            figure: number.format(progress.steps),
            caption: l10n.stepsOfGoal(progress.goal),
          ),
          const SizedBox(height: Gap.sm),
          Text(
            progress.reached
                ? l10n.stepsGoalReached
                : l10n.stepsToGo(progress.remaining),
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: style.colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

/// The daily goal between minus and plus, which move it by
/// [StepGoal.step] within the limits; tapping the number types it, taken
/// on the nearest step. Each change saves at once.
class _GoalEditor extends StatefulWidget {
  const _GoalEditor(this.goal);

  /// The saved goal.
  final int goal;

  @override
  State<_GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<_GoalEditor> {
  /// The goal last picked, until the saved one catches up: settings change
  /// only when the write comes back, so quick taps step from this.
  int? _picked;

  /// Whether [_picked] was not written: it equalled the saved goal when
  /// picked, while an earlier pick was still on its way, so
  /// [SettingsCubit.update] took it for no change.
  bool _unwritten = false;

  /// The last typed value was no goal.
  bool _outOfRange = false;

  int get _goal => _picked ?? widget.goal;

  @override
  void didUpdateWidget(_GoalEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.goal == oldWidget.goal) return;
    if (widget.goal == _picked) {
      _picked = null;
      _unwritten = false;
    } else if (_picked case final picked? when _unwritten) {
      _unwritten = false;
      _write(picked);
    }
  }

  void _changed(double? value) {
    final goal = value == null || value != value.roundToDouble()
        ? null
        : StepGoal.typed(value.toInt());
    if (goal == null) return setState(() => _outOfRange = true);
    _outOfRange = false;
    _pick(goal);
  }

  void _pick(int goal) {
    setState(() => _picked = goal);
    final settings = context.read<SettingsCubit>();
    _unwritten = goal == settings.state.settings.stepGoal;
    if (!_unwritten) _write(goal);
  }

  void _write(int goal) {
    final settings = context.read<SettingsCubit>();
    settings.update(settings.state.settings.copyWith(stepGoal: goal));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // A failed save leaves the saved goal as it was.
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          current.failure != null && current.failure != previous.failure,
      listener: (_, _) => setState(() {
        _picked = null;
        _unwritten = false;
      }),
      child: StepperField(
        value: _goal.toDouble(),
        unit: l10n.stepsGoalUnit,
        step: StepGoal.step.toDouble(),
        min: StepGoal.min.toDouble(),
        max: StepGoal.max.toDouble(),
        errorText: _outOfRange
            ? l10n.stepsGoalRange(StepGoal.min, StepGoal.max)
            : null,
        onChanged: _changed,
      ),
    );
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
    final number = NumberFormat.decimalPattern(l10n.localeName);
    if (summary.days == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: ListRowCard(
        children: [
          ListRow(
            title: l10n.stepsAverage,
            value: number.format(summary.average),
          ),
          ListRow(
            title: l10n.stepsGoalReached,
            value: l10n.stepsReachedDays(summary.reached, summary.days),
          ),
        ],
      ),
    );
  }
}

String _dayText(AppLocalizations l10n, DailySteps day) => l10n.stepsOnDay(
  DateFormat.MMMEd(l10n.localeName).format(day.day),
  l10n.stepsCount(day.count),
);

/// This week as Forge bars: a value over each day so far, today in accent,
/// the goal across.
class _WeekChart extends StatelessWidget {
  const _WeekChart({required this.days, required this.goal, this.today});

  final List<DailySteps> days;
  final int goal;
  final DateTime? today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final letter = DateFormat.EEEEE(l10n.localeName);
    final compact = NumberFormat.compact(locale: l10n.localeName);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    final day = DateFormat.MMMEd(l10n.localeName);
    final today = this.today;
    final todayDate = today == null ? null : CalendarDate.of(today);
    bool future(DailySteps day) =>
        todayDate != null && CalendarDate.of(day.day).isAfter(todayDate);
    final current = todayDate == null
        ? null
        : days.indexWhere((day) => CalendarDate.of(day.day) == todayDate);
    final title = l10n.stepsThisWeek;
    return Chart.bar(
      title: title,
      detail: l10n.stepsGoalDetail(goal),
      bars: [
        for (final steps in days)
          future(steps)
              ? ChartBar(label: letter.format(steps.day))
              : ChartBar(
                  label: letter.format(steps.day),
                  value: steps.count.toDouble(),
                  valueLabel: compact.format(steps.count),
                  tooltip: l10n.stepsTooltip(
                    number.format(steps.count),
                    day.format(steps.day),
                  ),
                ),
      ],
      current: current == null || current < 0 ? null : current,
      target: goal.toDouble(),
      semanticLabel: l10n.stepsChartLabel(
        title,
        l10n.stepsGoalValue(goal),
        l10n.inlineList(
          days.where((day) => !future(day)).map((d) => _dayText(l10n, d)),
        ),
      ),
    );
  }
}

/// The last 30 days as Forge's dense bars, today in accent, the goal
/// across; holding a bar names its day's steps.
class _MonthChart extends StatelessWidget {
  const _MonthChart({required this.days, required this.goal});

  final List<DailySteps> days;
  final int goal;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final number = NumberFormat.decimalPattern(l10n.localeName);
    final dayLabel = DateFormat.MMMd(l10n.localeName);
    final dayLong = DateFormat.MMMEd(l10n.localeName);
    final title = l10n.stepsLastDays(stepHistoryDays);
    return Chart.barDense(
      title: title,
      detail: l10n.stepsGoalDetail(goal),
      bars: [
        for (final day in days)
          ChartBar(
            label: dayLabel.format(day.day),
            value: day.count.toDouble(),
            tooltip: l10n.stepsTooltip(
              number.format(day.count),
              dayLong.format(day.day),
            ),
          ),
      ],
      current: days.isEmpty ? null : days.length - 1,
      target: goal.toDouble(),
      semanticLabel: l10n.stepsChartLabel(
        title,
        l10n.stepsGoalValue(goal),
        l10n.inlineList(days.map((d) => _dayText(l10n, d))),
      ),
    );
  }
}
