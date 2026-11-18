import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart' hide Sparkline;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/number_text.dart';
import '../../../core/sparkline.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../core/widgets/volume_band.dart';
import '../../../l10n/app_localizations.dart';
import '../../body/presentation/body_list_cubit.dart';
import '../../body/presentation/body_text.dart';
import '../../body/presentation/weight_sheet.dart';
import '../../cardio/presentation/cardio_list_cubit.dart';
import '../../cardio/presentation/cardio_text.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../today/presentation/today_steps_cubit.dart';
import '../../today/presentation/today_volume_cubit.dart';
import '../../today/presentation/today_week_cubit.dart';
import '../../today/presentation/week_card.dart';
import '../../volume/domain/weekly_volume.dart';
import '../../volume/presentation/volume_charts.dart';
import '../../volume/presentation/volume_text.dart';
import '../domain/body_snapshot.dart';
import '../domain/measurement_prompt.dart';
import 'measurement_prompt_cubit.dart';
import 'progress_body_cubit.dart';
import 'progress_strength_cubit.dart';

/// The Progress tab: one card per area, each opening its page and each on
/// its own data, so one failing leaves the others; the measurement-day
/// prompt under Body when one is due.
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = context.watchFirstWeekday();
    final cardio = sl<CardioListCubit>();
    return MultiBlocProvider(
      providers: [
        // The app's shared lists, as their pages show them.
        BlocProvider.value(value: sl<BodyListCubit>()),
        BlocProvider.value(value: cardio),
        BlocProvider.value(value: sl<ProgramListCubit>()),
        BlocProvider(create: (_) => sl<ProgressBodyCubit>()),
        BlocProvider(create: (_) => sl<MeasurementPromptCubit>()),
        // Today's, so both tabs show the same week.
        BlocProvider(create: (_) => sl<TodayWeekCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<TodayVolumeCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<ProgressStrengthCubit>()),
        BlocProvider(create: (_) => sl<TodayStepsCubit>()),
      ],
      child: FirstWeekdayListener(
        created: firstWeekday,
        onChanged: (context, firstWeekday) {
          context.read<TodayWeekCubit>().changeFirstWeekday(firstWeekday);
          context.read<TodayVolumeCubit>().changeFirstWeekday(firstWeekday);
        },
        child: FirstWeekdayListener(
          created: cardio.firstWeekday,
          onChanged: (context, firstWeekday) =>
              context.read<CardioListCubit>().changeFirstWeekday(firstWeekday),
          child: const _ProgressView(),
        ),
      ),
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

  /// This week and today move on while the app sleeps, without a new
  /// snapshot to recompute them.
  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshNow);
    context.read<ProgramListCubit>().refreshNow();
    _loadSteps();
  }

  void _refreshNow() {
    context.read<ProgressBodyCubit>().refreshNow();
    context.read<MeasurementPromptCubit>().refreshNow();
    context.read<ProgramListCubit>().refreshNow();
    context.read<TodayWeekCubit>().refreshNow();
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
    final prompt = context.watch<MeasurementPromptCubit>().state;
    final steps = context.select(
      (TodayStepsCubit cubit) =>
          cubit.state.status != TodayStepsStatus.unavailable,
    );
    final cards = [
      const _BodyCard(),
      if (prompt != null) _MeasurementPromptBanner(prompt),
      const WeekCard(),
      const _VolumeCard(),
      const _StrengthCard(),
      const _CardioCard(),
      // No card on a device without a health store.
      if (steps) const _StepsCard(),
    ];
    return Scaffold(
      appBar: ForgeAppBar(title: AppLocalizations.of(context).tabProgress),
      body: BlocListener<SettingsCubit, SettingsState>(
        listenWhen: (previous, current) =>
            previous.settings.stepGoal != current.settings.stepGoal,
        listener: (_, _) => _loadSteps(),
        child: ListView.separated(
          padding: const EdgeInsets.all(Gap.md),
          itemCount: cards.length,
          separatorBuilder: (_, _) => const SizedBox(height: Gap.sm),
          itemBuilder: (_, index) => cards[index],
        ),
      ),
    );
  }
}

/// The latest weight in a featured band with its change since the
/// weigh-in before, the newest body fat, the last 12 weeks as a line and
/// the two ways to log; the whole card opens Body.
class _BodyCard extends StatelessWidget {
  const _BodyCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ProgressBodyState(:status, :snapshot) = context
        .watch<ProgressBodyCubit>()
        .state;
    final eyebrow = l10n.progressBody;
    void open() => context.go(Routes.body);
    final logWeight = FeaturedAction(
      l10n.bodyLogWeight,
      () => showWeightSheet(context),
    );
    final measure = FeaturedAction(
      l10n.bodyMeasurementDay,
      () => context.push(Routes.bodyMeasureNew),
    );
    return switch ((status, snapshot.latest)) {
      (BodyListStatus.loading, _) => FeaturedCard.loading(eyebrow: eyebrow),
      (BodyListStatus.failure, _) => FeaturedCard.bandError(
        eyebrow: eyebrow,
        error: FeaturedError(
          l10n.bodyLoadFailed,
          retryLabel: l10n.retry,
          onRetry: context.read<ProgressBodyCubit>().retry,
        ),
        action: logWeight,
        moreActions: [measure],
        onTap: open,
      ),
      (BodyListStatus.ready, null) => FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: eyebrow,
        title: l10n.bodyEmptyTitle,
        note: l10n.progressBodyEmptyNote,
        action: logWeight,
        moreActions: [measure],
        onTap: open,
      ),
      (BodyListStatus.ready, final latest?) => FeaturedCard(
        form: FeaturedCardForm.band,
        eyebrow: eyebrow,
        title: l10n.bodyWeight(
          latest.kg,
          context.select(
            (SettingsCubit cubit) => cubit.state.settings.weightUnit,
          ),
        ),
        line: _changeLine(context, snapshot),
        // A single weigh-in has no trend: the card goes without one.
        chart: snapshot.weights.length > 1
            ? Sparkline(
                values: [for (final point in snapshot.weights) point.kg],
                color: ForgeStyle.of(context).colors.accent,
              )
            : null,
        action: logWeight,
        moreActions: [measure],
        onTap: open,
      ),
    };
  }

  /// "−0.4 since Nov 8" with the newest body fat at its end; none with a
  /// single weigh-in.
  FeaturedLine? _changeLine(BuildContext context, BodySnapshot snapshot) {
    final (change, previous) = (snapshot.change, snapshot.previous);
    if (change == null || previous == null) return null;
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final fat = snapshot.latestBodyFat;
    return FeaturedLine(
      l10n.progressBodySince(
        l10n.bodyWeightChangeNumber(change, unit),
        _shortDate(l10n, previous.date),
      ),
      data: fat == null
          ? null
          : l10n.progressBodyFat(l10n.bodyFat(fat.percent)),
      icon: change < 0 ? ForgeIcons.trendingDown : ForgeIcons.trendingUp,
    );
  }
}

/// "Nov 8", with the year when it is not this year's.
String _shortDate(AppLocalizations l10n, DateTime date) =>
    (date.year == DateTime.now().year
            ? DateFormat.MMMd(l10n.localeName)
            : DateFormat.yMMMd(l10n.localeName))
        .format(date);

/// The next measurement day, the newest photos and Start; swiping it away
/// hides it until the next one.
class _MeasurementPromptBanner extends StatelessWidget {
  const _MeasurementPromptBanner(this.prompt);
  final MeasurementPrompt prompt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final day = DateFormat.MMMEd(l10n.localeName);
    return TipBanner.action(
      icon: ForgeIcons.straighten,
      title: prompt.today
          ? l10n.progressMeasurementToday
          : l10n.progressMeasurementOn(
              DateFormat.EEEE(l10n.localeName)
                  .format(prompt.date.toLocalDateTime()),
            ),
      detail: switch ((prompt.lastPhotos, prompt.lastMeasured)) {
        ((:final date, :final poses)?, _) => l10n.progressMeasurementPhotos(
          day.format(date),
          poses.map(l10n.poseName).join(', '),
        ),
        (null, final date?) => l10n.progressMeasurementLast(day.format(date)),
        (null, null) => l10n.progressMeasurementNoPhotos,
      },
      action: ForgeButton(
        label: l10n.progressMeasurementStart,
        size: ForgeButtonSize.small,
        onPressed: () => context.push(Routes.bodyMeasureNew),
      ),
      onDismiss: context.read<MeasurementPromptCubit>().dismiss,
    );
  }
}

/// This week's sets against the active program's planned weekly sets, the
/// most trained muscles against their band and how many trained muscles
/// are in, below and above it. Opens weekly volume.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard();

  /// The most trained muscles shown.
  static const _topMuscles = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayVolumeCubit>().state;
    final planned = context.select(
      (ProgramListCubit cubit) => cubit.state.plannedWeeklySets,
    );
    final title = l10n.progressVolume;
    void open() => context.go(Routes.volume);
    return switch ((state.status, state.week)) {
      (TodayVolumeStatus.failure, _) => SectionCard.error(
        title: title,
        onTap: open,
        message: l10n.volumeLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<TodayVolumeCubit>().retry,
      ),
      (TodayVolumeStatus.ready, final week?) when week.sets.isEmpty =>
        SectionCard.empty(
          title: title,
          onTap: open,
          message: l10n.progressVolumeEmpty,
        ),
      (TodayVolumeStatus.ready, final week?) => SectionCard(
        title: title,
        detail: planned == null || planned == 0
            ? l10n.setsText(week.totalSets.toDouble())
            : l10n.progressVolumeOfPlanned(
                _count(l10n, week.totalSets),
                _count(l10n, planned),
              ),
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            if (planned != null && planned > 0)
              Progress.track(
                value: week.totalSets.toDouble(),
                goal: planned.toDouble(),
              ),
            for (final muscle in week.musclesBySets.take(_topMuscles))
              if (week.setsOf(muscle) > 0)
                VolumeBand(
                  muscle: muscle,
                  sets: week.setsOf(muscle),
                  scale: volumeScale(week.sets.values),
                ),
            Text(_zonesText(l10n, week), style: _quiet(context)),
          ],
        ),
      ),
      _ => SectionCard.loading(title: title, onTap: open),
    };
  }

  String _zonesText(AppLocalizations l10n, WeekVolume week) {
    final zones = week.zoneCounts;
    return l10n.todayVolumeZones(
      zones[VolumeZone.within]!,
      zones[VolumeZone.below]!,
      zones[VolumeZone.above]!,
    );
  }
}

String _count(AppLocalizations l10n, int value) =>
    NumberFormat.decimalPattern(l10n.localeName).format(value);

TextStyle _quiet(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!;

/// The most recently trained exercise's latest estimated 1RM and its
/// change over the last 12 weeks; opens the strength list.
class _StrengthCard extends StatelessWidget {
  const _StrengthCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProgressStrengthCubit>().state;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final title = l10n.progressStrength;
    void open() => context.go(Routes.strength);
    return switch ((state.status, state.highlight)) {
      (ProgressStrengthStatus.loading, _) => StatTile.loading(
        title: title,
        onTap: open,
      ),
      (ProgressStrengthStatus.failure, _) => StatTile.error(
        title: title,
        onTap: open,
        message: l10n.strengthLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<ProgressStrengthCubit>().retry,
      ),
      (ProgressStrengthStatus.ready, null) => StatTile.empty(
        title: title,
        onTap: open,
        message: state.trained
            ? l10n.progressStrengthNoE1rm
            : l10n.progressStrengthEmpty,
      ),
      (ProgressStrengthStatus.ready, final highlight?) => StatTile(
        title: title,
        detail: l10n.progressStrengthDetail(
          state.exercise?.localized(context).name ??
              l10n.strengthRemovedExercise,
        ),
        onTap: open,
        figure: l10n.estimatedWeightNumber(highlight.e1rmKg, unit),
        unit: l10n.weightUnitLabel(unit),
        caption: switch (highlight.change) {
          final change? => l10n.progressStrengthChange(
            l10n.bodyWeightChangeNumber(change.kg, unit),
            l10n.progressWeeks(change.weeks),
          ),
          null => l10n.progressStrengthFirst,
        },
      ),
    };
  }
}

/// This week's distance, or minutes when no session has one, with the
/// sessions under it; opens cardio.
class _CardioCard extends StatelessWidget {
  const _CardioCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<CardioListCubit>().state;
    final unit = distanceUnitFor(
      context.select((SettingsCubit cubit) => cubit.state.settings.lengthUnit),
    );
    final title = l10n.progressCardio;
    void open() => context.go(Routes.cardio);
    return switch ((state.status, state.chart.lastOrNull)) {
      (CardioListStatus.failure, _) => StatTile.error(
        title: title,
        onTap: open,
        message: l10n.cardioLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<CardioListCubit>().retry,
      ),
      (CardioListStatus.ready, _) when state.sessions.isEmpty => StatTile.empty(
        title: title,
        onTap: open,
        message: l10n.progressCardioEmpty,
      ),
      (CardioListStatus.ready, final week?) when week.sessions.isNotEmpty =>
        switch (week.distanceKm) {
          final km? => StatTile(
            title: title,
            detail: l10n.progressThisWeek,
            onTap: open,
            figure: formatDecimal(unit.fromKm(km), 2),
            unit: l10n.distanceUnitLabel(unit),
            caption: l10n.progressCardioLineNoDistance(
              l10n.cardioSessions(week.sessions.length),
              l10n.cardioMinutesOf(week.duration),
            ),
          ),
          null => StatTile(
            title: title,
            detail: l10n.progressThisWeek,
            onTap: open,
            figure: '${(week.duration.inSeconds / 60).round()}',
            unit: l10n.cardioMinutesShort,
            caption: l10n.cardioSessions(week.sessions.length),
          ),
        },
      (CardioListStatus.ready, _) => StatTile.empty(
        title: title,
        onTap: open,
        message: l10n.progressCardioNoneThisWeek,
      ),
      _ => StatTile.loading(title: title, onTap: open),
    };
  }
}

/// Today's steps against the daily goal; the Steps page sets access up.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayStepsCubit>().state;
    final title = l10n.progressSteps;
    void open() => context.go(Routes.steps);
    return switch ((state.status, state.progress)) {
      (TodayStepsStatus.setUp, _) => SectionCard.empty(
        title: title,
        onTap: open,
        message: l10n.todayStepsSetUp,
      ),
      (TodayStepsStatus.failure, _) => SectionCard.error(
        title: title,
        onTap: open,
        message: l10n.stepsLoadFailed,
        retryLabel: l10n.retry,
        onRetry: () => context.read<TodayStepsCubit>().load(
          context.read<SettingsCubit>().state.settings.stepGoal,
        ),
      ),
      (TodayStepsStatus.ready, final progress?) => SectionCard(
        title: title,
        detail: l10n.progressStepsOfGoal(
          _count(l10n, progress.steps),
          _count(l10n, progress.goal),
        ),
        onTap: open,
        child: Progress.track(
          value: progress.steps.toDouble(),
          goal: progress.goal.toDouble(),
        ),
      ),
      _ => SectionCard.loading(title: title, onTap: open),
    };
  }
}
