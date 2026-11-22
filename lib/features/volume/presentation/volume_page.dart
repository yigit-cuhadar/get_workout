import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:intl/intl.dart';

import '../../../app/theme.dart';
import '../../../core/widgets/muscle_heat.dart';
import '../../../core/widgets/muscle_model.dart';
import '../../../core/widgets/volume_band.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/vocabulary.dart';
import '../../exercises/presentation/body_model_cubit.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/domain/calendar_date.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/weekly_volume.dart';
import 'volume_charts.dart';
import 'volume_cubit.dart';
import 'volume_text.dart';

/// A week's sets per muscle on the body model and as bars against the
/// reference band, with the 12-week trend of the total (Premium); a muscle
/// opens where its sets came from and, with Premium, its 12-week trend.
class VolumePage extends StatelessWidget {
  const VolumePage({super.key});

  @override
  Widget build(BuildContext context) {
    final firstWeekday = context.watchFirstWeekday();
    return BlocProvider(
      create: (_) => sl<VolumeCubit>(param1: firstWeekday),
      child: FirstWeekdayListener(
        created: firstWeekday,
        onChanged: (context, firstWeekday) =>
            context.read<VolumeCubit>().changeFirstWeekday(firstWeekday),
        child: const _VolumeView(),
      ),
    );
  }
}

class _VolumeView extends StatelessWidget {
  const _VolumeView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<VolumeCubit>();
    final state = context.watch<VolumeCubit>().state;
    final shown = state.shown;
    return Scaffold(
      appBar: ForgeAppBar(title: l10n.volumeTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
        children: [
          for (final part in [
            _WeekSelector(state),
            // While another week loads the one before stays, so the model
            // keeps its camera and nothing flashes.
            ...switch (state.status) {
              VolumeStatus.failure => [
                ErrorView(
                  title: l10n.volumeLoadFailed,
                  message: l10n.loadFailedDetail,
                  retryLabel: l10n.retry,
                  onRetry: cubit.retry,
                ),
              ],
              _ when shown == null => [
                const VolumeModel(sets: {}),
                SectionCard.loading(
                  title: l10n.volumeSetsPerMuscle,
                  onTap: null,
                ),
              ],
              _ when shown.entries.isEmpty => [
                EmptyView(
                  title: state.isThisWeek
                      ? l10n.volumeNoSetsThisWeek
                      : l10n.volumeNoSetsThatWeek,
                  message: l10n.volumeNoSetsDetail,
                ),
                _TotalTrend(state),
              ],
              _ => [
                VolumeModel(
                  sets: shown.sets,
                  semanticLabel: l10n.volumeModelLabel(
                    weekRangeText(context, state.week),
                  ),
                  onOpen: (muscle) => _showMuscle(context, muscle),
                ),
                VolumeMuscleList(
                  muscles: [
                    for (final muscle in shown.musclesBySets)
                      (muscle: muscle, sets: shown.setsOf(muscle)),
                  ],
                  total: shown.totalSets,
                  onOpen: (muscle) => _showMuscle(context, muscle),
                ),
                _TotalTrend(state),
              ],
            },
          ])
            Padding(padding: const EdgeInsets.only(bottom: 10), child: part),
        ],
      ),
    );
  }
}

class _WeekSelector extends StatelessWidget {
  const _WeekSelector(this.state);
  final VolumeState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<VolumeCubit>();
    return PeriodSelector(
      period: weekRangeText(context, state.week),
      onPrevious: cubit.previousWeek,
      onNext: state.hasNext ? cubit.nextWeek : null,
      onPeriodTap: () => _pickDay(context),
      previousLabel: l10n.volumePreviousWeek,
      nextLabel: l10n.volumeNextWeek,
    );
  }

  /// The system date picker up to today; the picked day's week opens.
  Future<void> _pickDay(BuildContext context) async {
    final cubit = context.read<VolumeCubit>();
    final now = DateTime.now();
    final shown = state.week.toLocalDateTime();
    final picked = await showDatePicker(
      context: context,
      initialDate: shown.isAfter(now) ? now : shown,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) cubit.showWeekOf(CalendarDate.of(picked));
  }
}

/// The total sets of each of the [trendWeeks] weeks ending with the one
/// shown, for Premium; a locked card opening the paywall for everyone
/// else, and while that is unknown.
class _TotalTrend extends StatelessWidget {
  const _TotalTrend(this.state);
  final VolumeState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dates = MaterialLocalizations.of(context);
    final title = l10n.volumeTrendCard(trendWeeks);
    if (context.watchPremium() != PremiumStatus.premium) {
      return SectionCard.locked(
        title: title,
        onTap: context.openPaywall,
        tag: ForgeTag(l10n.cataloguePremium, kind: ForgeTagKind.premium),
        message: l10n.volumeTrendCardLocked(trendWeeks),
      );
    }
    if (!state.hasTrend) return Chart.loading(title: title);
    final weeks = state.weeks;
    String start(WeekVolume week) =>
        dates.formatShortMonthDay(week.start.toLocalDateTime());
    final totals = [for (final week in weeks) week.totalSets.toDouble()];
    return Chart.line(
      title: title,
      detail: l10n.setsText(totals.last),
      values: totals,
      pointLabel: (index) => l10n.volumeTrendPoint(
        l10n.setsText(totals[index]),
        weekRangeText(context, weeks[index].start),
      ),
      startLabel: start(weeks.first),
      endLabel: start(weeks.last),
      semanticLabel: l10n.volumeTotalTrendLabel(
        l10n.inlineList(totals.map(l10n.setsText)),
      ),
    );
  }
}

/// Each muscle's weekly [muscles] sets as a band against the reference,
/// in the order given, in the Sets per muscle card with their [total] and
/// what the band means; a band opens its muscle through [onOpen], when
/// given, and the line says so.
class VolumeMuscleList extends StatelessWidget {
  const VolumeMuscleList({
    super.key,
    required this.muscles,
    required this.total,
    this.onOpen,
  });

  final List<({Muscle muscle, double sets})> muscles;
  final int total;
  final ValueChanged<Muscle>? onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scale = volumeScale(muscles.map((m) => m.sets));
    final onOpen = this.onOpen;
    return SectionCard(
      title: l10n.volumeSetsPerMuscle,
      detail: l10n.volumeTotal(l10n.wholeNumber(total)),
      onTap: null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 10,
        children: [
          for (final (:muscle, :sets) in muscles)
            InkWell(
              onTap: onOpen == null ? null : () => onOpen(muscle),
              child: VolumeBand(muscle: muscle, sets: sets, scale: scale),
            ),
          Text(
            onOpen == null
                ? l10n.volumeTarget(VolumeRange.min, VolumeRange.max)
                : l10n.volumeFootnote(VolumeRange.min, VolumeRange.max),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// The model in its card with each trained muscle of [sets] in the heat
/// scale's colour (an untrained one keeps the body's colour), what it does
/// and the scale under it. Tapping a muscle calls [onOpen]; without it the
/// model only turns, and its hint says so. Before the body model loads,
/// and while [sets] are unknown (no [semanticLabel]), it shimmers.
class VolumeModel extends StatefulWidget {
  const VolumeModel({
    super.key,
    required this.sets,
    this.semanticLabel,
    this.onOpen,
  });

  final Map<Muscle, double> sets;
  final String? semanticLabel;
  final ValueChanged<Muscle>? onOpen;

  @override
  State<VolumeModel> createState() => _VolumeModelState();
}

class _VolumeModelState extends State<VolumeModel> {
  /// Share of the screen height the card takes, leaving the bars in view.
  static const _heightRatio = 0.45;

  @override
  void initState() {
    super.initState();
    context.read<BodyModelCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sets = widget.sets;
    final label = widget.semanticLabel;
    final model = context.watch<BodyModelCubit>().state;
    // One model, turned by dragging, shows the front and the back.
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * _heightRatio,
      child: switch (model) {
        BodyModelFailed() => MuscleModel.failed(
          message: l10n.muscleModelTryAgain,
          onRetry: context.read<BodyModelCubit>().load,
        ),
        BodyModelReady(:final model) when label != null => MuscleModel(
          model: model,
          colors: muscleHeatColors(GwColors.of(context), sets),
          sides: false,
          onOpen: widget.onOpen,
          semanticLabel: label,
          footer: _Footer(
            widget.onOpen == null
                ? l10n.volumeModelTurnHint
                : l10n.volumeModelHint,
          ),
        ),
        _ => const MuscleModel.loading(
          sides: false,
          footer: SkeletonBar(widthFactor: 0.6, height: 8),
        ),
      },
    );
  }
}

/// What the model does, over the heat scale.
class _Footer extends StatelessWidget {
  const _Footer(this.hint);
  final String hint;

  @override
  Widget build(BuildContext context) {
    final muted = ForgeStyle.of(context).colors.inkMuted;
    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: Gap.sm,
          children: [
            ForgeIcon(ForgeIcons.sync, size: 16, color: muted),
            Flexible(
              child: Text(
                hint,
                style: Theme.of(context).textTheme.labelMedium!
                    .copyWith(fontWeight: FontWeight.w400, color: muted),
              ),
            ),
          ],
        ),
        const MuscleHeatLegend(),
      ],
    );
  }
}

Future<void> _showMuscle(BuildContext context, Muscle muscle) =>
    showForgeBottomSheet<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: context.read<VolumeCubit>(),
        child: _MuscleSheet(muscle),
      ),
    );

/// One muscle in the week shown: its sets, where they came from and its
/// trend.
class _MuscleSheet extends StatelessWidget {
  const _MuscleSheet(this.muscle);
  final Muscle muscle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final dates = MaterialLocalizations.of(context);
    final state = context.watch<VolumeCubit>().state;
    final week = state.shown;
    if (week == null) return const SizedBox.shrink();
    final sets = week.setsOf(muscle);
    final contributions = week.contributionsTo(muscle);
    return ForgeBottomSheet(
      title: l10n.muscleName(muscle),
      subtitle: l10n.volumeMuscleSummary(
        l10n.setsText(sets),
        l10n.zoneLabel(VolumeZone.of(sets)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 10,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.volumeContributionsTitle,
                style: text.titleMedium,
              ),
            ),
            if (contributions.isEmpty)
              Text(l10n.volumeNoContributions, style: text.bodySmall)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (:entry, sets: given) in contributions)
                    ListRow(
                      title: _exerciseName(context, entry),
                      detail: l10n.volumeContribution(
                        entry.workoutName,
                        dates.formatShortMonthDay(entry.startedAt.toLocal()),
                      ),
                      value: l10n.setsText(given),
                    ),
                ],
              ),
            _Trend(muscle: muscle, state: state),
          ],
        ),
      ),
    );
  }

  /// The library's name, custom exercises included; the name stored with
  /// the workout for one no longer there.
  String _exerciseName(BuildContext context, VolumeEntry entry) {
    final catalogue = context.watch<ExerciseCatalogueCubit>().state;
    final known = catalogue is CatalogueReady
        ? catalogue.exercises.where((e) => e.id == entry.exerciseId).firstOrNull
        : null;
    return known?.localized(context).name ?? entry.exerciseName;
  }
}

/// The muscle's sets per week, for Premium; a locked row that opens the
/// paywall for everyone else, nothing while that is unknown.
class _Trend extends StatelessWidget {
  const _Trend({required this.muscle, required this.state});

  final Muscle muscle;
  final VolumeState state;

  /// The stand-in's height while the weeks load.
  static const _height = 110.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    final dates = MaterialLocalizations.of(context);
    final premium = context.watchPremium();
    if (premium == PremiumStatus.unknown) return const SizedBox.shrink();
    final weeks = state.weeks;
    final title = state.isThisWeek
        ? l10n.volumeTrendTitle(trendWeeks)
        : l10n.volumeTrendTitleUntil(
            trendWeeks,
            dates.formatShortMonthDay(
              state.week.addDays(DateTime.daysPerWeek - 1).toLocalDateTime(),
            ),
          );
    if (premium == PremiumStatus.premium && state.hasTrend) {
      final numbers = NumberFormat.decimalPattern(l10n.localeName);
      final sets = [for (final week in weeks) week.setsOf(muscle)];
      return Chart.bar(
        title: title,
        card: false,
        band: (
          low: VolumeRange.min.toDouble(),
          high: VolumeRange.max.toDouble(),
        ),
        bars: [
          for (final (i, week) in weeks.indexed)
            ChartBar(
              label: '${week.start.day}',
              value: sets[i],
              valueLabel: numbers.format(sets[i]),
              tooltip: l10n.volumeTrendTooltip(
                l10n.setsText(sets[i]),
                dates.formatShortMonthDay(week.start.toLocalDateTime()),
              ),
            ),
        ],
        semanticLabel: l10n.volumeTrendLabel(
          l10n.muscleName(muscle),
          l10n.inlineList(sets.map(l10n.setsText)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Semantics(header: true, child: Text(title, style: text.titleMedium)),
        if (premium == PremiumStatus.free)
          ListRow(
            leading: ForgeIcon(
              ForgeIcons.lock,
              size: 18,
              color: ForgeStyle.of(context).colors.inkMuted,
            ),
            title: l10n.volumeTrendLocked(trendWeeks),
            end: ListRowEnd.chevron,
            onTap: context.openPaywall,
          )
        else
          const SkeletonBar(widthFactor: 1, height: _height, radius: Gap.sm),
      ],
    );
  }
}
