import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart' hide Sparkline;
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/sparkline.dart';
import '../../../core/text_length.dart';
import '../../../core/widgets/featured_card.dart';
import '../../../l10n/app_localizations.dart';
import '../../body/presentation/body_list_cubit.dart';
import '../../body/presentation/body_text.dart';
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
      const WeekCard.range(),
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
      () => context.push(Routes.bodyWeightNew),
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
        chart: snapshot.weights.length > 1
            ? Sparkline(
                values: [for (final point in snapshot.weights) point.kg],
                color: ForgeStyle.of(context).colors.accent,
              )
            : SparklineEmpty(message: l10n.progressBodyTrendEmpty),
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
      icon: ForgeIcons.trendingUp,
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

/// This week's sets against the active program's planned weekly sets, and
/// how many trained muscles are in, below and above the band. Opens weekly
/// volume.
class _VolumeCard extends StatelessWidget {
  const _VolumeCard();

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

  /// The exercise names the header's detail has room for.
  static const _nameLength = 22;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<ProgressStrengthCubit>().state;
    final title = l10n.progressStrength;
    void open() => context.go(Routes.strength);
    return switch ((state.status, state.highlight)) {
      (ProgressStrengthStatus.loading, _) => SectionCard.loading(
        title: title,
        onTap: open,
      ),
      (ProgressStrengthStatus.failure, _) => SectionCard.error(
        title: title,
        onTap: open,
        message: l10n.strengthLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<ProgressStrengthCubit>().retry,
      ),
      (ProgressStrengthStatus.ready, null) => SectionCard.empty(
        title: title,
        onTap: open,
        message: state.trained
            ? l10n.progressStrengthNoE1rm
            : l10n.progressStrengthEmpty,
      ),
      (ProgressStrengthStatus.ready, final highlight?) => SectionCard(
        title: title,
        detail: l10n.progressStrengthDetail(
          _cut(
            state.exercise?.localized(context).name ??
                l10n.strengthRemovedExercise,
          ),
        ),
        onTap: open,
        child: _StrengthFigure(highlight.e1rmKg, highlight.change),
      ),
    };
  }

  /// Cut with "…" so the header keeps its title.
  static String _cut(String name) => name.length <= _nameLength
      ? name
      : '${cutToLength(name, _nameLength - 1).trimRight()}…';
}

class _StrengthFigure extends StatelessWidget {
  const _StrengthFigure(this.e1rmKg, this.change);
  final double e1rmKg;
  final ({double kg, int weeks})? change;

  static const _figureSize = 24.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final colors = ForgeStyle.of(context).colors;
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final change = this.change;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      spacing: Gap.sm,
      children: [
        Text(
          l10n.estimatedWeightText(e1rmKg, unit),
          style: text.headlineSmall!.copyWith(fontSize: _figureSize),
        ),
        if (change != null)
          Flexible(
            child: Text(
              l10n.progressStrengthChange(
                l10n.bodyWeightChangeNumber(change.kg, unit),
                l10n.progressWeeks(change.weeks),
              ),
              style: text.bodySmall!.copyWith(
                color: change.kg < 0 ? colors.danger : colors.success,
              ),
            ),
          ),
      ],
    );
  }
}

/// This week's sessions, distance and minutes; opens cardio.
class _CardioCard extends StatelessWidget {
  const _CardioCard();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = context.watch<CardioListCubit>().state;
    final title = l10n.progressCardio;
    void open() => context.go(Routes.cardio);
    return switch ((state.status, state.chart.lastOrNull)) {
      (CardioListStatus.failure, _) => SectionCard.error(
        title: title,
        onTap: open,
        message: l10n.cardioLoadFailed,
        retryLabel: l10n.retry,
        onRetry: context.read<CardioListCubit>().retry,
      ),
      (CardioListStatus.ready, _) when state.sessions.isEmpty =>
        SectionCard.empty(
          title: title,
          onTap: open,
          message: l10n.progressCardioEmpty,
        ),
      (CardioListStatus.ready, final week?) when week.sessions.isNotEmpty =>
        SectionCard(
          title: title,
          detail: l10n.progressThisWeek,
          onTap: open,
          child: Text(
            _line(
              context,
              l10n,
              week.sessions.length,
              week.distanceKm,
              week.duration,
            ),
            style: ForgeStyle.of(context).data.copyWith(
              fontSize: 15,
              height: 20 / 15,
              color: ForgeStyle.of(context).colors.ink,
            ),
          ),
        ),
      (CardioListStatus.ready, _) => SectionCard.empty(
        title: title,
        onTap: open,
        message: l10n.progressCardioNoneThisWeek,
      ),
      _ => SectionCard.loading(title: title, onTap: open),
    };
  }

  String _line(
    BuildContext context,
    AppLocalizations l10n,
    int sessions,
    double? km,
    Duration duration,
  ) {
    final count = l10n.cardioSessions(sessions);
    final minutes = l10n.cardioMinutesOf(duration);
    if (km == null) return l10n.progressCardioLineNoDistance(count, minutes);
    final unit = distanceUnitFor(
      context.select((SettingsCubit cubit) => cubit.state.settings.lengthUnit),
    );
    return l10n.progressCardioLine(count, l10n.distanceText(km, unit), minutes);
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
