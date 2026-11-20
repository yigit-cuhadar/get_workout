import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/first_weekday.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../strength/domain/strength.dart';
import '../../strength/presentation/strength_text.dart';
import '../../analytics/domain/analytics.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/body_chart.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import 'body_chart_cubit.dart';
import 'body_list_cubit.dart';
import 'body_text.dart';
import 'weight_sheet.dart';
import 'measurement_comparison.dart';
import 'measurement_summary_cubit.dart';

/// Two views of the user's body: Overview (three boxes, the chart, the two
/// ways to log, then every entry, newest first) and Compare (two
/// measurement days). Each keeps its state while the other shows. There
/// is one Body page: a link to Compare updates the one there.
class BodyPage extends StatelessWidget {
  const BodyPage({super.key, this.compareAfter});

  /// Shows Compare with this measurement day as the later one, also when
  /// it comes later to a page already open.
  final String? compareAfter;

  @override
  Widget build(BuildContext context) {
    // Read here: a provider's create may not listen to the localizations.
    final firstWeekday = context.watchFirstWeekday();
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: sl<BodyListCubit>()),
        BlocProvider(create: (_) => sl<BodyChartCubit>(param1: firstWeekday)),
        BlocProvider(create: (_) => sl<MeasurementSummaryCubit>(param1: null)),
      ],
      child: FirstWeekdayListener(
        created: firstWeekday,
        onChanged: (context, firstWeekday) =>
            context.read<BodyChartCubit>().changeFirstWeekday(firstWeekday),
        child: _BodyView(compareAfter: compareAfter),
      ),
    );
  }
}

class _BodyView extends StatefulWidget {
  const _BodyView({required this.compareAfter});

  final String? compareAfter;

  @override
  State<_BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<_BodyView> {
  late bool _compare = widget.compareAfter != null;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    if (widget.compareAfter case final id?) {
      context.read<MeasurementSummaryCubit>().showDay(id);
    }
    // Today's steps have grown meanwhile.
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<BodyChartCubit>().refreshSteps(),
    );
  }

  @override
  void didUpdateWidget(_BodyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final id = widget.compareAfter;
    if (id == null || id == oldWidget.compareAfter) return;
    context.read<MeasurementSummaryCubit>().showDay(id);
    setState(() => _compare = true);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _show(bool compare) {
    setState(() => _compare = compare);
    // The link that opened Compare is done; following it again works.
    if (widget.compareAfter != null) context.go(Routes.body);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocListener<BodyListCubit, BodyListState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        showForgeSnackbar(
          context,
          message: l10n.bodyWritesRejected,
          error: true,
        );
        context.read<BodyListCubit>().rejectionShown();
      },
      child: Scaffold(
        appBar: ForgeAppBar(title: l10n.bodyTitle),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, 0),
              child: ForgeSegmentedControl<bool>(
                segments: [
                  ForgeSegment(value: false, label: l10n.bodyOverview),
                  ForgeSegment(value: true, label: l10n.bodyCompare),
                ],
                selected: _compare,
                onChanged: _show,
              ),
            ),
            Expanded(
              child: BlocBuilder<BodyListCubit, BodyListState>(
                builder: (context, state) => switch (state.status) {
                  BodyListStatus.ready when state.entries.isEmpty =>
                    const _Empty(),
                  _ when _compare => const MeasurementComparison(compare: true),
                  BodyListStatus.loading => const _OverviewLoading(),
                  BodyListStatus.failure => ListView(
                    padding: const EdgeInsets.all(Gap.md),
                    children: [
                      ErrorView(
                        title: l10n.bodyLoadFailed,
                        message: l10n.loadFailedDetail,
                        retryLabel: l10n.retry,
                        onRetry: context.read<BodyListCubit>().retry,
                        card: true,
                      ),
                    ],
                  ),
                  BodyListStatus.ready => _Overview(state),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// No entries yet, on either view: what to do, with the two ways to log
/// under it.
class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        EmptyView(
          icon: ForgeIcons.monitorWeight,
          title: l10n.bodyEmptyTitle,
          message: l10n.bodyEmptyDetail,
          card: true,
        ),
        const SizedBox(height: 10),
        const _LogButtons(),
      ],
    );
  }
}

/// Log weight and Measurement day side by side.
class _LogButtons extends StatelessWidget {
  const _LogButtons();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      spacing: 10,
      children: [
        Expanded(
          child: ForgeButton(
            label: l10n.bodyLogWeight,
            onPressed: () => showWeightSheet(context),
          ),
        ),
        Expanded(
          child: ForgeButton(
            label: l10n.bodyMeasurementDay,
            variant: ForgeButtonVariant.secondary,
            onPressed: () => context.go(Routes.bodyMeasureNew),
          ),
        ),
      ],
    );
  }
}

const _rowGap = SizedBox(height: 10);

/// The Overview's skeleton: the boxes, the chart, the history.
class _OverviewLoading extends StatelessWidget {
  const _OverviewLoading();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        const Row(
          spacing: Gap.sm,
          children: [
            Expanded(child: StatTile.compactLoading()),
            Expanded(child: StatTile.compactLoading()),
            Expanded(child: StatTile.compactLoading()),
          ],
        ),
        _rowGap,
        MultiSeriesChart.loading(title: l10n.rangeName(StrengthRange.free)),
        _rowGap,
        const Padding(
          padding: EdgeInsets.fromLTRB(Gap.xs, Gap.sm, Gap.xs, 0),
          child: SkeletonBar(widthFactor: 0.3, height: 10),
        ),
        _rowGap,
        ListRowCard(
          children: [for (var i = 0; i < 3; i++) ListRow.loading(index: i)],
        ),
      ],
    );
  }
}

/// Built lazily: the boxes, the chart and buttons, then one row per
/// entry.
class _Overview extends StatelessWidget {
  const _Overview(this.state);
  final BodyListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final entries = state.entries;
    return CustomScrollView(
      // Keeps its place while Compare shows.
      key: const PageStorageKey('overview'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
          sliver: SliverList.list(
            children: [
              _Boxes(state),
              _rowGap,
              _ChartCard(state),
              _rowGap,
              const _LogButtons(),
              _rowGap,
              SectionLabel(l10n.bodyHistory),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.md),
          sliver: ListRowCard.sliver(
            itemCount: entries.length,
            itemBuilder: (context, i) =>
                _EntryRow(entries[i], bodyFat: state.bodyFat[entries[i].id]),
          ),
        ),
      ],
    );
  }
}

/// Weight, body fat and lean mass with their changes; see [bodyOverview].
class _Boxes extends StatelessWidget {
  const _Boxes(this.state);
  final BodyListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final target = context.select(
      (ProfileCubit cubit) => cubit.state.profile.targetWeightKg,
    );
    final overview = bodyOverview(
      state.entries,
      state.bodyFat,
      targetKg: target,
    );
    Widget box(
      String label,
      OverviewBox? box,
      String Function(double) value,
      String Function(double) change,
    ) => Expanded(
      child: box == null
          ? StatTile.compact(label: label, figure: l10n.bodyNoValue)
          : StatTile.compact(
              label: label,
              figure: value(box.value),
              change: switch (box.change) {
                final difference? => change(difference),
                null => null,
              },
              changeIsGood: switch (box.tone) {
                ChangeTone.good => true,
                ChangeTone.bad => false,
                ChangeTone.neutral => null,
              },
            ),
    );
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gap.sm,
        children: [
          box(
            l10n.bodyWeightTitle,
            overview.weight,
            (kg) => l10n.bodyWeight(kg, unit),
            (kg) => l10n.bodyWeightChangeNumber(kg, unit),
          ),
          box(
            l10n.bodyFatTitle,
            overview.bodyFat,
            l10n.bodyFat,
            l10n.bodyFatChangeNumber,
          ),
          box(
            l10n.bodyLeanMass,
            overview.leanMass,
            (kg) => l10n.bodyWeight(kg, unit),
            (kg) => l10n.bodyWeightChangeNumber(kg, unit),
          ),
        ],
      ),
    );
  }
}

/// How one series is drawn and written, in the user's units.
class _SeriesLook {
  const _SeriesLook(this.l10n, this.settings);

  final AppLocalizations l10n;
  final UserSettings settings;

  /// The look of the [index]th line of the chart.
  static const looks = [SeriesLook.accent, SeriesLook.info, SeriesLook.success];

  /// [value] as the chart plots it.
  double shown(BodySeries series, double value) => switch (series) {
    BodySeries.weight ||
    BodySeries.fatMass ||
    BodySeries.leanMass => settings.weightUnit.fromKg(value),
    BodySeries.bodyFat ||
    BodySeries.weeklySets ||
    BodySeries.dailySteps => value,
    _ => settings.lengthUnit.fromCm(value),
  };

  /// A plotted value with its unit.
  String format(BodySeries series, double value) => switch (series) {
    BodySeries.weight || BodySeries.fatMass || BodySeries.leanMass =>
      l10n.bodyWeight(settings.weightUnit.toKg(value), settings.weightUnit),
    BodySeries.bodyFat => l10n.bodyFat(value),
    BodySeries.weeklySets || BodySeries.dailySteps =>
      NumberFormat.decimalPattern(l10n.localeName).format(value.round()),
    _ => l10n.bodyLength(settings.lengthUnit.toCm(value), settings.lengthUnit),
  };

  /// The tap tag of a pair of measurements: both sides of the entry on the
  /// tapped day ("36 / 35.5 cm"); null for any other series.
  String Function(ChartPoint)? pairTag(
    BodySeries series,
    List<SeriesPoint> points,
  ) {
    if (series.measurements.length != 2) return null;
    final unit = settings.lengthUnit;
    String side(double? cm) =>
        cm == null ? l10n.bodyNoValue : l10n.bodyLengthNumber(cm, unit);
    final byDay = {
      for (final point in points)
        if (point.sides case [final left, final right])
          point.date: l10n.bodyQuantity(
            l10n.bodyPair(side(left), side(right)),
            l10n.bodyLengthUnit(unit),
          ),
    };
    return (point) => byDay[point.day] ?? format(series, point.value);
  }

  List<ChartPoint> points(BodySeries series, List<SeriesPoint> points) => [
    for (final point in points)
      (day: point.date, value: shown(series, point.value)),
  ];
}

/// The chosen series over the chart's range, the range control while
/// there are older entries, and the way to older results for a free
/// user.
class _ChartCard extends StatefulWidget {
  const _ChartCard(this.state);
  final BodyListState state;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  bool _adding = false;

  Future<void> _add() async {
    setState(() => _adding = true);
    await _showAddSheet(context);
    if (mounted) setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = widget.state;
    final look = _SeriesLook(
      l10n,
      context.select((SettingsCubit cubit) => cubit.state.settings),
    );
    final targetKg = context.select(
      (ProfileCubit cubit) => cubit.state.profile.targetWeightKg,
    );
    final title = l10n.rangeName(state.range);
    return BlocConsumer<BodyChartCubit, BodyChartState>(
      listenWhen: (_, current) => current.saveFailed,
      listener: (context, _) {
        showForgeSnackbar(context, message: l10n.bodySaveFailed, error: true);
        context.read<BodyChartCubit>().saveFailureShown();
      },
      builder: (context, chart) {
        final cubit = context.read<BodyChartCubit>();
        final from = chart.from;
        final to = chart.to;
        final waiting = chart.shown.every(chart.loading.contains);
        final range = state.hasOlder ? _RangePicker(state.range) : null;
        final lockedCaption = state.olderLocked ? l10n.bodyOlderLocked : null;
        final VoidCallback? onLockedCaptionTap = state.olderLocked
            ? () => context.requirePremium(PremiumFeature.bodyHistory)
            : null;
        if (from == null || to == null || waiting) {
          return waiting
              ? MultiSeriesChart.loading(title: title)
              : MultiSeriesChart.empty(
                  title: title,
                  emptyTitle: l10n.bodyChartEmptyTitle,
                  message: l10n.bodyChartEmpty,
                  range: range,
                  lockedCaption: lockedCaption,
                  onLockedCaptionTap: onLockedCaptionTap,
                );
        }
        final target =
            chart.targetLine &&
                chart.shown.contains(BodySeries.weight) &&
                targetKg != null
            ? targetKg
            : null;
        var line = 0;
        final series = [
          for (final shown in chart.shown)
            if (chart.failed.contains(shown))
              ChartSeries.failed(
                label: l10n.seriesName(shown),
                look: SeriesLook.info,
                error: l10n.bodySeriesFailed(l10n.seriesName(shown)),
                retryLabel: l10n.retry,
                onRetry: () => cubit.retry(shown),
              )
            else if (shown.isBar)
              ChartSeries.bars(
                label: l10n.seriesName(shown),
                points: look.points(shown, chart.points[shown] ?? const []),
                format: (value) => look.format(shown, value),
              )
            else if (shown == BodySeries.weight)
              ChartSeries.averaged(
                label: l10n.seriesName(shown),
                points: look.points(shown, chart.points[shown] ?? const []),
                average: look.points(shown, chart.weightAverage),
                dailyLabel: l10n.bodyChartDaily,
                averageLabel: l10n.bodyChartAverage,
                format: (value) => look.format(shown, value),
                look: _SeriesLook.looks[line++],
                target: target == null ? null : look.shown(shown, target),
                targetLabel: target == null ? null : l10n.bodyChartTargetLabel,
              )
            else
              ChartSeries(
                label: l10n.seriesName(shown),
                points: look.points(shown, chart.points[shown] ?? const []),
                format: (value) => look.format(shown, value),
                formatPoint: look.pairTag(
                  shown,
                  chart.points[shown] ?? const [],
                ),
                look: _SeriesLook.looks[line++],
              ),
        ];
        return MultiSeriesChart(
          title: title,
          detail: target == null
              ? null
              : l10n.bodyChartTargetDetail(
                  l10n.bodyWeight(target, look.settings.weightUnit),
                ),
          series: series,
          from: from,
          to: to,
          dateLabel: l10n.bodyShortDate,
          startLabel: l10n.bodyShortDate(from),
          endLabel: l10n.bodyShortDate(to),
          onSeriesTap: (_) => _add(),
          addLabel: l10n.bodyChartAdd,
          onAdd: _add,
          adding: _adding,
          range: range,
          lockedCaption: lockedCaption,
          onLockedCaptionTap: onLockedCaptionTap,
          semanticLabel: l10n.bodyChartSemantics(title),
        );
      },
    );
  }
}

/// Picks the series of the chart, at most [BodySeries.maxShown], and
/// whether the target weight shows. Every change applies at once.
Future<void> _showAddSheet(BuildContext context) {
  final cubit = context.read<BodyChartCubit>();
  final premium = context.read<BodyListCubit>();
  return showForgeBottomSheet<void>(
    context: context,
    builder: (_) => MultiBlocProvider(
      providers: [
        BlocProvider.value(value: cubit),
        BlocProvider.value(value: premium),
      ],
      child: _AddSheet(gate: context),
    ),
  );
}

class _AddSheet extends StatelessWidget {
  const _AddSheet({required this.gate});

  /// Below the root navigator, where the paywall gate's providers are.
  final BuildContext gate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = ForgeStyle.of(context).colors;
    return BlocBuilder<BodyChartCubit, BodyChartState>(
      builder: (context, state) {
        final cubit = context.read<BodyChartCubit>();
        final shown = state.shown;
        final full = shown.length >= BodySeries.maxShown;
        Widget row(BodySeries series) {
          final detail = switch (series) {
            BodySeries.weeklySets => l10n.bodyWeeklySetsHint,
            BodySeries.dailySteps => l10n.bodyDailyStepsHint,
            _ => null,
          };
          final picked = shown.contains(series);
          if (state.locked(series)) {
            return ListRow(
              title: l10n.seriesName(series),
              detail: detail,
              trailing: ForgeIcon(
                ForgeIcons.lock,
                size: 18,
                color: colors.inkMuted,
              ),
              disabled: full,
              onTap: () => _unlock(cubit, series),
            );
          }
          return ListRow(
            title: l10n.seriesName(series),
            detail: detail,
            checked: picked,
            // The last one stays; none is added past the most.
            disabled: !picked && full,
            onTap: picked && shown.length == 1
                ? null
                : () => cubit.toggle(series),
          );
        }

        return ForgeBottomSheet(
          title: l10n.bodyChartTitle,
          subtitle: l10n.bodyChartPicked(shown.length, BodySeries.maxShown),
          headerAction: ForgeButton(
            label: l10n.bodyDone,
            variant: ForgeButtonVariant.text,
            size: ForgeButtonSize.small,
            onPressed: () => Navigator.pop(context),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in BodySeriesGroup.values)
                  if (state.available.any((s) => s.group == group)) ...[
                    SectionLabel(l10n.seriesGroupName(group)),
                    for (final series in state.available)
                      if (series.group == group) row(series),
                  ],
                ListRow(
                  title: l10n.bodyTargetLine,
                  detail: l10n.bodyTargetLineHint,
                  trailing: ForgeSwitch(
                    value: state.targetLine,
                    onChanged: cubit.showTargetLine,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// A training series asks for Premium first, as the ranges do.
  Future<void> _unlock(BodyChartCubit cubit, BodySeries series) async {
    if (await gate.requirePremium(PremiumFeature.bodySeries)) {
      await cubit.add(series);
    }
  }
}

/// The chart's ranges; a Premium one is locked for a free user and opens
/// the paywall.
class _RangePicker extends StatelessWidget {
  const _RangePicker(this.range);
  final StrengthRange range;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = context.watchPremium() == PremiumStatus.free;
    final cubit = context.read<BodyListCubit>();
    return ForgeSegmentedControl<StrengthRange>(
      segments: [
        for (final option in StrengthRange.values)
          ForgeSegment(
            value: option,
            label: l10n.rangeName(option),
            locked: locked && option.premium,
          ),
      ],
      selected: range,
      onChanged: cubit.selectRange,
      onLocked: (option) async {
        if (await context.requirePremium(PremiumFeature.bodyRange)) {
          cubit.selectRange(option);
        }
      },
    );
  }
}

/// An entry of the history: its weight, its date (a measurement day says
/// so) and its body fat; a tap opens it.
class _EntryRow extends StatelessWidget {
  const _EntryRow(this.entry, {required this.bodyFat});
  final BodyEntry entry;
  final double? bodyFat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final date = l10n.bodyShortDayDate(entry.date);
    return ListRow(
      title: switch (entry.weightKg) {
        final kg? => l10n.bodyWeight(kg, unit),
        null => l10n.bodyNoValue,
      },
      detail: entry.isWeightOnly ? date : l10n.bodyHistoryMeasurementDay(date),
      value: switch (bodyFat) {
        final fat? => l10n.bodyFat(fat),
        null => l10n.bodyNoValue,
      },
      end: ListRowEnd.chevron,
      onTap: () => context.go(Routes.bodyEntry(entry.id)),
    );
  }
}
