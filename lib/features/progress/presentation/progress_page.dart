import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/first_weekday.dart';
import '../../../core/sparkline.dart';
import '../../../l10n/app_localizations.dart';
import '../../body/domain/measurement_summary.dart';
import '../../body/presentation/body_list_cubit.dart';
import '../../body/presentation/body_text.dart';
import '../../cardio/presentation/cardio_list_cubit.dart';
import '../../cardio/presentation/cardio_text.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../steps/domain/steps.dart';
import '../../today/presentation/today_steps_cubit.dart';
import '../../today/presentation/today_volume_cubit.dart';
import '../../today/presentation/today_week_cubit.dart';
import '../../today/presentation/week_strip.dart';
import '../../volume/domain/weekly_volume.dart';
import '../../volume/presentation/volume_charts.dart';
import '../../volume/presentation/volume_text.dart';
import '../domain/body_snapshot.dart';
import 'progress_body_cubit.dart';
import 'progress_month_cubit.dart';
import 'progress_strength_cubit.dart';

/// The Progress tab: one small widget per area, each opening its page and
/// each on its own data, so one failing leaves the others.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = MaterialLocalizations.of(context).firstWeekday;
    return MultiBlocProvider(
      key: ValueKey(firstWeekday),
      providers: [
        // The app's shared lists, as their pages show them.
        BlocProvider.value(value: sl<BodyListCubit>()),
        BlocProvider.value(value: sl<CardioListCubit>()),
        // Today's, so both tabs show the same week.
        BlocProvider(create: (_) => sl<ProgressBodyCubit>()),
        BlocProvider(create: (_) => sl<TodayWeekCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<ProgressMonthCubit>()),
        BlocProvider(create: (_) => sl<TodayVolumeCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<ProgressStrengthCubit>()),
        BlocProvider(create: (_) => sl<TodayStepsCubit>()),
      ],
      child: const _ProgressView(),
    );
  }
}

class _ProgressView extends StatefulWidget {
  const _ProgressView();

  @override
  State<_ProgressView> createState() => _ProgressViewState();
}

class _ProgressViewState extends State<_ProgressView> {
  late final AppLifecycleListener _lifecycle;

  /// Independent widgets, in order.
  static const _cards = [
    _BodyCard(),
    _CalendarCard(),
    _VolumeCard(),
    _StrengthCard(),
    _CardioAndSteps(),
  ];

  /// This week, month and day move on while the app sleeps, without a new
  /// snapshot to recompute them.
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshNow);
    _loadSteps();
  }

  void _refreshNow() {
    context.read<ProgressBodyCubit>().refreshNow();
    context.read<TodayWeekCubit>().refreshNow();
    context.read<ProgressMonthCubit>().refreshNow();
    context.read<TodayVolumeCubit>().refreshNow();
    context.read<CardioListCubit>().refreshNow();
    // Steps are read, never followed, and may change in the health store.
    _loadSteps();
  }

  void _loadSteps() => context.read<TodayStepsCubit>().load(
    context.read<SettingsCubit>().state.settings.stepGoal,
  );

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tabProgress)),
      body: BlocListener<SettingsCubit, SettingsState>(
        listenWhen: (previous, current) =>
            previous.settings.stepGoal != current.settings.stepGoal,
        listener: (_, _) => _loadSteps(),
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(Gap.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, card) in _cards.indexed) ...[
                    if (i > 0) const SizedBox(height: Gap.sm),
                    card,
                  ],
                ],
              ),
            ),
            const _CompareTile(),
          ],
        ),
      ),
    );
  }
}

/// A card that opens [onOpen] from anywhere on it, under a [title] row with
/// an optional [caption]. A [prominent] card stands out in the theme's
/// primary container colours.
class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.onOpen,
    required this.child,
    this.caption,
    this.prominent = false,
  });

  final String title;
  final String? caption;
  final VoidCallback onOpen;
  final Widget child;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final caption = this.caption;
    final card = Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: prominent ? colors.primaryContainer : null,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Gap.md,
                Gap.md,
                Gap.sm,
                Gap.sm,
              ),
              child: Row(
                children: [
                  Semantics(
                    header: true,
                    child: Text(title, style: theme.textTheme.titleMedium),
                  ),
                  const SizedBox(width: Gap.sm),
                  // Takes the rest of the row, so the arrow stays at its end.
                  Expanded(
                    child: Text(
                      caption ?? '',
                      style: theme.textTheme.bodyMedium,
                      textAlign: TextAlign.end,
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
    if (!prominent) return card;
    final foreground = colors.onPrimaryContainer;
    return Theme(
      data: theme.copyWith(
        textTheme: theme.textTheme.apply(
          bodyColor: foreground,
          displayColor: foreground,
        ),
        iconTheme: theme.iconTheme.copyWith(color: foreground),
      ),
      child: card,
    );
  }
}

/// A card's body while its data loads. Data comes from Firestore's cache
/// at once, so a spinner would only flash.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const SizedBox(height: Gap.md);
}

/// The padding of a card's body below its title row.
const _bodyPadding = EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md);

class _BodyCard extends StatelessWidget {
  const _BodyCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ProgressBodyState(:status, :empty, :snapshot) = context
        .watch<ProgressBodyCubit>()
        .state;
    return _ProgressCard(
      title: l10n.progressBody,
      onOpen: () => context.go(Routes.body),
      prominent: true,
      child: switch (status) {
        BodyListStatus.loading => const _Loading(),
        BodyListStatus.failure => ErrorView(
          message: l10n.bodyLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<ProgressBodyCubit>().retry,
        ),
        BodyListStatus.ready => Padding(
          padding: _bodyPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (empty) Text(l10n.bodyEmpty) else _BodyNumbers(snapshot),
              const SizedBox(height: Gap.md),
              const _LogButtons(),
            ],
          ),
        ),
      },
    );
  }
}

class _BodyNumbers extends StatelessWidget {
  const _BodyNumbers(this.snapshot);
  final BodySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final latestKg = snapshot.latestKg;
    final fat = snapshot.latestBodyFat;
    final weights = snapshot.weights;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (latestKg != null)
          Text(
            l10n.bodyWeight(latestKg, unit),
            style: theme.textTheme.headlineMedium,
          ),
        if (fat != null)
          Text(
            l10n.progressBodyFat(
              l10n.bodyFat(fat.percent),
              DateFormat.MMMd(l10n.localeName).format(fat.date),
            ),
          ),
        if (weights.length > 1) ...[
          const SizedBox(height: Gap.sm),
          Sparkline(
            values: [for (final point in weights) point.kg],
            color: theme.colorScheme.primary,
          ),
        ],
      ],
    );
  }
}

class _LogButtons extends StatelessWidget {
  const _LogButtons();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        ForgeButton(
          label: l10n.bodyLogWeight,
          onPressed: () => context.push(Routes.bodyWeightNew),
        ),
        OutlinedButton(
          onPressed: () => context.push(Routes.bodyMeasureNew),
          child: Text(l10n.bodyMeasurementDay),
        ),
      ],
    );
  }
}

/// This week as Today shows it, and how many workouts this month.
class _CalendarCard extends StatelessWidget {
  const _CalendarCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final month = context.watch<ProgressMonthCubit>().state;
    void open() => context.go(Routes.calendar);
    return _ProgressCard(
      title: l10n.progressCalendar,
      caption: month.status == ProgressMonthStatus.ready
          ? l10n.progressWorkoutsThisMonth(month.workouts)
          : null,
      onOpen: open,
      // A month that failed shows no count; it shares the week's cause,
      // whose retry also retries the month.
      child: WeekStrip(
        onOpen: open,
        onRetry: () {
          context.read<TodayWeekCubit>().retry();
          context.read<ProgressMonthCubit>().retry();
        },
      ),
    );
  }
}

/// This week's most trained muscles against the band, under the week's
/// total sets.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayVolumeCubit>().state;
    final week = state.week;
    return _ProgressCard(
      title: l10n.progressVolume,
      caption: state.status == TodayVolumeStatus.ready && week != null
          ? l10n.setsText(week.totalSets.toDouble())
          : null,
      onOpen: () => context.go(Routes.volume),
      child: switch ((state.status, week)) {
        (TodayVolumeStatus.failure, _) => ErrorView(
          message: l10n.volumeLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<TodayVolumeCubit>().retry,
        ),
        (TodayVolumeStatus.ready, final week?) => _TopMuscles(week),
        _ => const _Loading(),
      },
    );
  }
}

class _TopMuscles extends StatelessWidget {
  const _TopMuscles(this.week);
  final WeekVolume week;

  /// The most trained muscles shown.
  static const _count = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final numbers = NumberFormat.decimalPattern(l10n.localeName);
    final scale = volumeScale(week.sets.values);
    return Padding(
      padding: _bodyPadding,
      child: week.sets.isEmpty
          ? Text(l10n.volumeNoWorkoutsThisWeek)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final muscle in week.musclesBySets.take(_count))
                  if (week.setsOf(muscle) > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(l10n.muscleName(muscle)),
                          ),
                          Expanded(
                            flex: 3,
                            child: VolumeBandBar(
                              sets: week.setsOf(muscle),
                              scale: scale,
                            ),
                          ),
                          const SizedBox(width: Gap.sm),
                          Text(numbers.format(week.setsOf(muscle))),
                        ],
                      ),
                    ),
              ],
            ),
    );
  }
}

/// Up to three recently trained exercises with their best estimated 1RM,
/// each opening its own strength page; the rest of the card opens the list.
class _StrengthCard extends StatelessWidget {
  const _StrengthCard();

  /// The tiles a row has room for.
  static const _slots = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProgressStrengthCubit>().state;
    return _ProgressCard(
      title: l10n.progressStrength,
      caption: l10n.strengthBestE1rm,
      onOpen: () => context.go(Routes.strength),
      child: switch (state.status) {
        ProgressStrengthStatus.loading => const _Loading(),
        ProgressStrengthStatus.failure => ErrorView(
          message: l10n.strengthLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<ProgressStrengthCubit>().retry,
        ),
        ProgressStrengthStatus.ready when state.tiles.isEmpty => Padding(
          padding: _bodyPadding,
          child: Text(
            state.trained ? l10n.progressStrengthNoE1rm : l10n.strengthEmpty,
          ),
        ),
        ProgressStrengthStatus.ready => Padding(
          padding: _bodyPadding,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < _slots; i++) ...[
                  if (i > 0) const SizedBox(width: Gap.sm),
                  Expanded(
                    child: i < state.tiles.length
                        ? _StrengthTile(state.tiles[i])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ),
      },
    );
  }
}

class _StrengthTile extends StatelessWidget {
  const _StrengthTile(this.tile);
  final StrengthTile tile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    return Card.outlined(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(Routes.strengthExercise(tile.exerciseId)),
        child: Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tile.exercise?.localized(context).name ??
                    l10n.strengthRemovedExercise,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: Gap.xs),
              Text(
                l10n.estimatedWeightText(tile.e1rmKg, unit),
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cardio and steps side by side; cardio alone without a health store.
class _CardioAndSteps extends StatelessWidget {
  const _CardioAndSteps();

  @override
  Widget build(BuildContext context) {
    // Until steps are known to be readable here, cardio takes the row, so
    // nothing moves on a device without a health store.
    final steps = context.select(
      (TodayStepsCubit cubit) => switch (cubit.state.status) {
        TodayStepsStatus.loading || TodayStepsStatus.unavailable => false,
        _ => true,
      },
    );
    if (!steps) return const _CardioCard();
    return const IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _CardioCard()),
          SizedBox(width: Gap.sm),
          Expanded(child: _StepsCard()),
        ],
      ),
    );
  }
}

/// This week's cardio minutes and sessions, weeks from Monday as on the
/// cardio page.
class _CardioCard extends StatelessWidget {
  const _CardioCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final state = context.watch<CardioListCubit>().state;
    return _ProgressCard(
      title: l10n.progressCardio,
      caption: l10n.progressThisWeek,
      onOpen: () => context.go(Routes.cardio),
      child: switch ((state.status, state.chart.lastOrNull)) {
        (CardioListStatus.failure, _) => ErrorView(
          message: l10n.cardioLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<CardioListCubit>().retry,
        ),
        (CardioListStatus.ready, final week?) => Padding(
          padding: _bodyPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.cardioMinutesOf(week.duration),
                style: theme.textTheme.headlineSmall,
              ),
              Text(l10n.progressCardioSessions(week.sessions.length)),
            ],
          ),
        ),
        _ => const _Loading(),
      },
    );
  }
}

/// Today's steps against the daily goal; the Steps page sets access up.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayStepsCubit>().state;
    return _ProgressCard(
      title: l10n.progressSteps,
      caption: l10n.stepsToday,
      onOpen: () => context.go(Routes.steps),
      child: switch ((state.status, state.progress)) {
        (TodayStepsStatus.setUp, _) => Padding(
          padding: _bodyPadding,
          child: Text(l10n.todayStepsSetUp),
        ),
        (TodayStepsStatus.failure, _) => ErrorView(
          message: l10n.stepsLoadFailed,
          retryLabel: l10n.retry,
          onRetry: () => context.read<TodayStepsCubit>().load(
            context.read<SettingsCubit>().state.settings.stepGoal,
          ),
        ),
        (TodayStepsStatus.ready, final progress?) => _StepsProgress(progress),
        _ => const _Loading(),
      },
    );
  }
}

class _StepsProgress extends StatelessWidget {
  const _StepsProgress(this.progress);
  final StepGoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: _bodyPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            NumberFormat.decimalPattern(l10n.localeName).format(progress.steps),
            style: theme.textTheme.headlineSmall,
          ),
          Text(l10n.stepsOfGoal(progress.goal)),
          const SizedBox(height: Gap.sm),
          LinearProgressIndicator(value: progress.fraction),
        ],
      ),
    );
  }
}

/// Opens the newest measurement day compared with the previous one; off,
/// saying why, until there are two.
class _CompareTile extends StatelessWidget {
  const _CompareTile();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocSelector<BodyListCubit, BodyListState, (bool, String?)>(
      selector: (state) => (
        state.status == BodyListStatus.ready,
        newestComparable(state.entries)?.id,
      ),
      builder: (context, selected) {
        final (ready, id) = selected;
        return ListTile(
          leading: const Icon(Icons.compare),
          title: Text(l10n.progressCompare),
          subtitle: ready && id == null
              ? Text(l10n.progressCompareNeedsTwo)
              : null,
          trailing: const Icon(Icons.chevron_right),
          enabled: id != null,
          onTap: id == null
              ? null
              : () => context.go(Routes.bodyEntryCompare(id)),
        );
      },
    );
  }
}
