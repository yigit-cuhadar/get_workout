import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../app/theme.dart';
import '../../../core/number_text.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../core/widgets/volume_band.dart';
import '../../../l10n/app_localizations.dart';
import '../../body/domain/body_stats.dart';
import '../../body/presentation/body_list_cubit.dart';
import '../../body/presentation/body_text.dart';
import '../../body/presentation/weight_sheet.dart';
import '../../cardio/domain/cardio_week.dart';
import '../../cardio/presentation/cardio_list_cubit.dart';
import '../../cardio/presentation/cardio_text.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_list_cubit.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../today/presentation/today_steps_cubit.dart';
import '../../today/presentation/today_volume_cubit.dart';
import '../../today/presentation/today_week_cubit.dart';
import '../../today/presentation/week_card.dart';
import '../../volume/domain/weekly_volume.dart';
import '../../volume/presentation/volume_charts.dart';
import '../../volume/presentation/volume_text.dart';
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

/// The latest weight in a featured band with its change over the last 2
/// weeks beside it and the newest body fat under it, those weeks as a line
/// with its highest and lowest weight and its first and last date, and the
/// two ways to log; the whole card opens Body.
class _BodyCard extends StatelessWidget {
  const _BodyCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final ProgressBodyState(:status, :snapshot) = context
        .watch<ProgressBodyCubit>()
        .state;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
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
        title: l10n.bodyWeight(latest.kg, unit),
        titleAside: switch (snapshot.change) {
          (:final kg, :final weeks) => l10n.progressBodyChange(
            l10n.bodyWeightChange(kg, unit),
            l10n.progressWeeks(weeks),
          ),
          null => null,
        },
        when: switch (snapshot.latestBodyFat) {
          (:final date, :final percent) => l10n.progressBodyFatOn(
            l10n.bodyFat(percent),
            l10n.bodyShortDate(date),
          ),
          null => null,
        },
        // A single weigh-in has no trend: the card goes without one.
        chart: _trend(l10n, snapshot.weights, unit),
        action: logWeight,
        moreActions: [measure],
        onTap: open,
      ),
    };
  }

  Widget? _trend(
    AppLocalizations l10n,
    List<WeightPoint> weights,
    WeightUnit unit,
  ) {
    if (weights.length < 2) return null;
    final values = [for (final point in weights) point.kg];
    return TrendLine.scaled(
      values: values,
      highLabel: l10n.bodyWeightNumber(values.reduce(math.max), unit),
      lowLabel: l10n.bodyWeightNumber(values.reduce(math.min), unit),
      startLabel: l10n.bodyShortDate(weights.first.date),
      endLabel: l10n.bodyShortDate(weights.last.date),
      semanticLabel: l10n.progressBodyTrend,
    );
  }
}

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
/// most trained muscles against their band and a key of the band's
/// colours with how many trained muscles are below, in and above it.
/// Opens weekly volume.
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
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gap.sm,
          children: [
            Row(
              spacing: Gap.sm,
              children: [
                Expanded(
                  child: Text(
                    l10n.progressVolumeThisWeek,
                    style: _quiet(context),
                  ),
                ),
                Text(
                  planned == null || planned == 0
                      ? l10n.setsText(week.totalSets.toDouble())
                      : l10n.progressVolumeOfPlanned(
                          _count(l10n, week.totalSets),
                          _count(l10n, planned),
                        ),
                  style: ForgeStyle.of(context).data,
                ),
              ],
            ),
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
            const Divider(height: 1),
            _zoneKey(context, week),
          ],
        ),
      ),
      _ => SectionCard.loading(title: title, onTap: open),
    };
  }

  Widget _zoneKey(BuildContext context, WeekVolume week) {
    final l10n = AppLocalizations.of(context);
    final band = GwColors.of(context);
    final zones = week.zoneCounts;
    return ColorKey(
      entries: [
        ColorKeyEntry(
          band.bandBelow,
          l10n.progressVolumeUnder(VolumeRange.min, zones[VolumeZone.below]!),
        ),
        ColorKeyEntry(
          band.bandIn,
          l10n.progressVolumeWithin(
            VolumeRange.min,
            VolumeRange.max,
            zones[VolumeZone.within]!,
          ),
        ),
        ColorKeyEntry(
          band.bandOver,
          l10n.progressVolumeOver(VolumeRange.max, zones[VolumeZone.above]!),
        ),
      ],
    );
  }
}

String _count(AppLocalizations l10n, int value) =>
    NumberFormat.decimalPattern(l10n.localeName).format(value);

TextStyle _quiet(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall!;

/// The most recently trained exercise's latest estimated 1RM, its change
/// over the last 2 weeks and those weeks as a line; opens the strength
/// list.
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
        caption: highlight.change == null ? l10n.progressStrengthFirst : null,
        change: switch (highlight.change) {
          final change? => l10n.progressStrengthChange(
            l10n.bodyWeightChangeNumber(change.kg, unit),
            l10n.progressWeeks(change.weeks),
          ),
          null => null,
        },
        // A stronger lift is good; no change has no colour.
        changeIsGood: switch (highlight.change?.kg) {
          final kg? when kg > 0 => true,
          final kg? when kg < 0 => false,
          _ => null,
        },
        // A single e1RM in the 2 weeks has no trend.
        chart: highlight.trend.length > 1
            ? TrendLine(values: highlight.trend)
            : null,
      ),
    };
  }
}

/// This week's distance, or minutes when no session has one, with the
/// sessions under it and each day's minutes as a bar; opens cardio.
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
      (CardioListStatus.ready, _)
          when state.sessions.isEmpty && state.healthConnected =>
        StatTile.empty(
          title: title,
          onTap: open,
          message: l10n.progressCardioNoneConnected,
          actionLabel: l10n.cardioLog,
          onAction: () => context.go(Routes.cardioNew),
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
            chart: _days(context, week),
          ),
          null => StatTile(
            title: title,
            detail: l10n.progressThisWeek,
            onTap: open,
            figure: '${(week.duration.inSeconds / 60).round()}',
            unit: l10n.cardioMinutesShort,
            caption: l10n.cardioSessions(week.sessions.length),
            chart: _days(context, week),
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

  Widget _days(BuildContext context, CardioWeek week) {
    final l10n = AppLocalizations.of(context);
    final letter = DateFormat.EEEEE(l10n.localeName);
    final weekday = DateFormat.EEEE(l10n.localeName);
    final start = week.start;
    final days = [
      for (final (i, duration) in week.dailyDurations.indexed)
        (
          date: DateTime(start.year, start.month, start.day + i),
          duration: duration,
        ),
    ];
    return DayBars(
      days: [
        for (final (:date, :duration) in days)
          (label: letter.format(date), value: duration.inSeconds / 60),
      ],
      color: ForgeStyle.of(context).colors.info,
      semanticLabel: l10n.progressCardioDays(
        [
          for (final (:date, :duration) in days)
            if (duration > Duration.zero)
              '${weekday.format(date)} ${l10n.cardioMinutesOf(duration)}',
        ].join(', '),
      ),
    );
  }
}

/// Today's steps against the daily goal; without access, why there is no
/// number and the way to the Steps page, which sets access up.
class _StepsCard extends StatelessWidget {
  const _StepsCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<TodayStepsCubit>().state;
    final title = l10n.progressSteps;
    void open() => context.go(Routes.steps);
    return switch ((state.status, state.progress)) {
      (TodayStepsStatus.setUp, _) => StatTile.empty(
        title: title,
        onTap: open,
        message: l10n.progressStepsConnect(healthStoreName(context)),
        actionLabel: l10n.progressStepsConnectAction(healthStoreName(context)),
        onAction: open,
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
