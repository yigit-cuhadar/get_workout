import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/chart_geometry.dart';
import '../../../core/first_weekday.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../strength/domain/strength.dart';
import '../../strength/presentation/strength_text.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/body_chart.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import 'body_chart_cubit.dart';
import 'body_list_cubit.dart';
import 'body_text.dart';
import 'measurement_comparison.dart';
import 'measurement_summary_cubit.dart';
import 'series_chart.dart';

/// Two views of the user's body: Overview (the chart, the two ways to log,
/// then every entry, newest first) and Compare (two measurement days).
/// Each keeps its state while the other shows.
class BodyPage extends StatelessWidget {
  const BodyPage({super.key, this.compareAfter});

  /// Opens on Compare with this measurement day as the later one.
  final String? compareAfter;

  @override
  Widget build(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: sl<BodyListCubit>()),
      BlocProvider(
        create: (context) => sl<BodyChartCubit>(
          param1: MaterialLocalizations.of(context).firstWeekday,
        ),
      ),
      BlocProvider(
        create: (_) {
          final cubit = sl<MeasurementSummaryCubit>(param1: null);
          if (compareAfter case final id?) cubit.chooseAfter(id);
          return cubit;
        },
      ),
    ],
    child: _BodyView(compare: compareAfter != null),
  );
}

class _BodyView extends StatefulWidget {
  const _BodyView({required this.compare});

  /// Whether it opens on Compare.
  final bool compare;

  @override
  State<_BodyView> createState() => _BodyViewState();
}

class _BodyViewState extends State<_BodyView> {
  late bool _compare = widget.compare;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return BlocConsumer<BodyListCubit, BodyListState>(
      listenWhen: (_, current) => current.writeRejected,
      listener: (context, _) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.bodyWritesRejected)));
        context.read<BodyListCubit>().rejectionShown();
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(title: Text(l10n.bodyTitle)),
        body: switch (state.status) {
          BodyListStatus.loading => const LoadingView(),
          BodyListStatus.failure => ErrorView(
            message: l10n.bodyLoadFailed,
            retryLabel: l10n.retry,
            onRetry: context.read<BodyListCubit>().retry,
          ),
          BodyListStatus.ready when state.entries.isEmpty => EmptyView(
            message: l10n.bodyEmpty,
            action: const _LogButtons(),
          ),
          BodyListStatus.ready => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: false, label: Text(l10n.bodyOverview)),
                    ButtonSegment(value: true, label: Text(l10n.bodyCompare)),
                  ],
                  selected: {_compare},
                  onSelectionChanged: (selection) =>
                      setState(() => _compare = selection.single),
                ),
              ),
              Expanded(
                child: _compare
                    ? const MeasurementComparison(compare: true)
                    : _Overview(state),
              ),
            ],
          ),
        },
      ),
    );
  }
}

class _LogButtons extends StatelessWidget {
  const _LogButtons();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: Gap.sm,
      runSpacing: Gap.sm,
      children: [
        ForgeButton(
          label: l10n.bodyLogWeight,
          onPressed: () => context.go(Routes.bodyWeightNew),
        ),
        OutlinedButton(
          onPressed: () => context.go(Routes.bodyMeasureNew),
          child: Text(l10n.bodyMeasurementDay),
        ),
      ],
    );
  }
}

/// Built lazily: the latest weight, the chart and buttons, then one row
/// per entry.
class _Overview extends StatelessWidget {
  const _Overview(this.state);
  final BodyListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <WidgetBuilder>[
      (_) => _Header(state),
      (_) => _ChartCard(state),
      (_) =>
          const Padding(padding: EdgeInsets.all(Gap.md), child: _LogButtons()),
      (context) => ListTile(
        dense: true,
        title: Text(
          l10n.bodyHistory,
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ),
      for (final entry in state.entries)
        (_) => _EntryTile(entry, bodyFat: state.bodyFat[entry.id]),
    ];
    return ListView.builder(
      // Keeps its place while Compare shows.
      key: const PageStorageKey('overview'),
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](context),
    );
  }
}

/// The latest weight with its date, and the way to the target weight.
class _Header extends StatelessWidget {
  const _Header(this.state);
  final BodyListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final target = context.select(
      (ProfileCubit cubit) => cubit.state.profile.targetWeightKg,
    );
    final latest = latestWeighIn(state.entries);
    final latestKg = latest?.weightKg;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (latest != null && latestKg != null)
            Text(
              l10n.bodyLatest(
                l10n.bodyWeight(latestKg, unit),
                MaterialLocalizations.of(context).formatMediumDate(latest.date),
              ),
              style: theme.textTheme.titleMedium,
            ),
          if (target != null)
            Text(
              _targetText(l10n, target: target, latest: latestKg, unit: unit),
              style: theme.textTheme.bodyMedium,
            ),
        ],
      ),
    );
  }

  static String _targetText(
    AppLocalizations l10n, {
    required double target,
    required double? latest,
    required WeightUnit unit,
  }) {
    final weight = l10n.bodyWeight(target, unit);
    if (latest == null) return l10n.bodyTarget(weight);
    final toGo = l10n.bodyWeight((latest - target).abs(), unit);
    return toGo == l10n.bodyWeight(0, unit)
        ? l10n.bodyTargetReached(weight)
        : l10n.bodyTargetToGo(weight, toGo);
  }
}

/// How one series is drawn and written, in the user's units.
class _SeriesLook {
  const _SeriesLook(this.l10n, this.settings);

  final AppLocalizations l10n;
  final UserSettings settings;

  /// The colours of the series by their place on the chart: lines, and the
  /// lighter bars.
  static List<Color> lineColors(ColorScheme colors) => [
    colors.primary,
    colors.tertiary,
    colors.secondary,
  ];

  static List<Color> barColors(ColorScheme colors) => [
    colors.primaryContainer,
    colors.tertiaryContainer,
    colors.secondaryContainer,
  ];

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

  /// The smallest difference the axis shows; see [niceTicks].
  double precision(BodySeries series) => series.isBar ? 1 : 0.1;

  /// A plotted value on an axis.
  String axisLabel(BodySeries series, double value) =>
      (NumberFormat.decimalPattern(
        l10n.localeName,
      )..maximumFractionDigits = series.isBar ? 0 : 1).format(value);

  /// A point's value with its unit; both sides of a pair.
  String value(BodySeries series, SeriesPoint point) {
    String length(double? cm) => cm == null
        ? l10n.bodyNoValue
        : l10n.bodyLength(cm, settings.lengthUnit);
    return switch (series) {
      BodySeries.weight ||
      BodySeries.fatMass ||
      BodySeries.leanMass => l10n.bodyWeight(point.value, settings.weightUnit),
      BodySeries.bodyFat => l10n.bodyFat(point.value),
      BodySeries.weeklySets || BodySeries.dailySteps =>
        NumberFormat.decimalPattern(l10n.localeName)
            .format(point.value.round()),
      _ => switch (point.sides) {
        [final left, final right] => l10n.bodyPair(length(left), length(right)),
        _ => length(point.value),
      },
    };
  }
}

/// The chosen series with their latest values, the chart, and its range.
class _ChartCard extends StatelessWidget {
  const _ChartCard(this.state);
  final BodyListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = _SeriesLook.lineColors(theme.colorScheme);
    final look = _SeriesLook(
      l10n,
      context.select((SettingsCubit cubit) => cubit.state.settings),
    );
    return BlocBuilder<BodyChartCubit, BodyChartState>(
      builder: (context, chart) {
        final cubit = context.read<BodyChartCubit>();
        final empty = chart.points.values.every((points) => points.isEmpty);
        return Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final (i, series) in chart.shown.indexed)
                    InputChip(
                      avatar: Icon(
                        series.isBar ? Icons.bar_chart : Icons.show_chart,
                        color: colors[i],
                      ),
                      label: Text(
                        l10n.bodyChartValue(
                          l10n.seriesName(series),
                          switch (chart.points[series]?.lastOrNull) {
                            final point? => look.value(series, point),
                            null => l10n.bodyNoValue,
                          },
                        ),
                      ),
                      // The chart always shows something.
                      onDeleted: chart.shown.length > 1
                          ? () => cubit.toggle(series)
                          : null,
                      deleteButtonTooltipMessage: l10n.bodyChartRemove(
                        l10n.seriesName(series),
                      ),
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.add),
                    label: Text(l10n.bodyChartAdd),
                    onPressed: () => _showAddSheet(context),
                  ),
                ],
              ),
              const SizedBox(height: Gap.sm),
              if (empty)
                Text(l10n.bodyChartEmpty, style: theme.textTheme.bodyMedium)
              else
                _Chart(chart, look),
              const SizedBox(height: Gap.sm),
              _RangePicker(state.range),
              if (state.olderLocked) ...[
                const SizedBox(height: Gap.sm),
                Text(l10n.bodyOlderLocked, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Every series of [chart] on its own scale; see [chartAxes]. Lines span
/// their values (weight also the target while its line shows); bars rise
/// from zero to their own largest value.
class _Chart extends StatelessWidget {
  const _Chart(this.chart, this.look);
  final BodyChartState chart;
  final _SeriesLook look;

  /// Beyond this span the bottom labels name months and years.
  static const _daysOfShortDates = 300;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final colorScheme = Theme.of(context).colorScheme;
    final lineColors = _SeriesLook.lineColors(colorScheme);
    final barColors = _SeriesLook.barColors(colorScheme);
    final targetKg = context.select(
      (ProfileCubit cubit) => cubit.state.profile.targetWeightKg,
    );
    final from = chart.from!;
    final to = chart.to!;
    final axisDates = to.difference(from).inDays > _daysOfShortDates
        ? DateFormat.yMMM(locale)
        : DateFormat.MMMd(locale);
    DateTime date(double x) => DateTime.fromMillisecondsSinceEpoch(x.round());
    double x(DateTime date) => date.millisecondsSinceEpoch.toDouble();
    const week = Duration(days: DateTime.daysPerWeek);
    final axes = chart.axes;
    ChartSeries chartSeries(int i, BodySeries series) {
      final points = chart.points[series] ?? const [];
      final values = [
        for (final point in points) look.shown(series, point.value),
      ];
      final guide = series == BodySeries.weight && chart.targetLine
          ? switch (targetKg) {
              final kg? => look.shown(series, kg),
              null => null,
            }
          : null;
      final range = [...values, ?guide];
      return ChartSeries(
        points: [
          for (final (j, point) in points.indexed)
            (x: x(point.date), y: values[j]),
        ],
        color: series.isBar ? barColors[i] : lineColors[i],
        ticks: range.isEmpty
            ? const []
            : niceTicks(
                series.isBar ? 0 : range.reduce(math.min),
                range.reduce(math.max),
                precision: look.precision(series),
              ),
        axis: switch (axes[series]!) {
          ChartAxis.left => SeriesAxis.left,
          ChartAxis.right => SeriesAxis.right,
          ChartAxis.none => SeriesAxis.none,
        },
        yLabel: (value) => look.axisLabel(series, value),
        bars: series.isBar,
        guide: guide,
      );
    }

    /// The values of every series on the tapped day, or in its week.
    String selection(double value) {
      final tapped = date(value);
      bool at(BodySeries series, SeriesPoint point) => series.isBar
          ? !tapped.isBefore(point.date) &&
                tapped.isBefore(point.date.add(week))
          : point.date == tapped;
      return l10n.bodyPoint(
        [
          for (final series in chart.shown)
            if (chart.points[series]
                    ?.where((point) => at(series, point))
                    .firstOrNull
                case final point?)
              l10n.bodyChartValue(
                l10n.seriesName(series),
                look.value(series, point),
              ),
        ].join(' · '),
        DateFormat.yMMMd(locale).format(tapped),
      );
    }

    return SeriesChart(
      xMin: x(from),
      xMax: x(to),
      barSpan: week.inMilliseconds.toDouble(),
      xLabel: (value) => axisDates.format(date(value)),
      series: [
        for (final (i, series) in chart.shown.indexed) chartSeries(i, series),
      ],
      selectionLabel: selection,
    );
  }
}

/// Picks the series of the chart, at most [BodySeries.maxShown], and
/// whether the target weight shows. Every change applies at once.
Future<void> _showAddSheet(BuildContext context) {
  final cubit = context.read<BodyChartCubit>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        builder: (context, scrollController) =>
            _AddSheet(scrollController: scrollController),
      ),
    ),
  );
}

class _AddSheet extends StatelessWidget {
  const _AddSheet({required this.scrollController});

  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return BlocBuilder<BodyChartCubit, BodyChartState>(
      builder: (context, state) {
        final cubit = context.read<BodyChartCubit>();
        final shown = state.shown;
        return ListView(
          controller: scrollController,
          children: [
            ListTile(
              title: Text(
                l10n.bodyChartTitle,
                style: theme.textTheme.titleLarge,
              ),
              subtitle: Text(
                l10n.bodyChartPicked(shown.length, BodySeries.maxShown),
              ),
              trailing: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.bodyDone),
              ),
            ),
            for (final group in BodySeriesGroup.values) ...[
              ListTile(
                dense: true,
                title: Text(
                  l10n.seriesGroupName(group),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final series in state.available)
                if (series.group == group)
                  CheckboxListTile(
                    value: shown.contains(series),
                    // The last one stays; none is added past the most.
                    onChanged:
                        (shown.contains(series)
                            ? shown.length > 1
                            : shown.length < BodySeries.maxShown)
                        ? (_) => cubit.toggle(series)
                        : null,
                    title: Text(l10n.seriesName(series)),
                    subtitle: switch (series) {
                      BodySeries.weeklySets => Text(l10n.bodyWeeklySetsHint),
                      BodySeries.dailySteps => Text(l10n.bodyDailyStepsHint),
                      _ => null,
                    },
                  ),
            ],
            SwitchListTile(
              title: Text(l10n.bodyTargetLine),
              subtitle: Text(l10n.bodyTargetLineHint),
              value: state.targetLine,
              onChanged: cubit.showTargetLine,
            ),
          ],
        );
      },
    );
  }
}

/// The chart's ranges; a Premium one asks for Premium first, and is
/// marked locked for a free user.
class _RangePicker extends StatelessWidget {
  const _RangePicker(this.range);
  final StrengthRange range;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = context.watchPremium() == PremiumStatus.free;
    return SegmentedButton<StrengthRange>(
      showSelectedIcon: false,
      segments: [
        for (final option in StrengthRange.values)
          ButtonSegment(
            value: option,
            label: Text(l10n.rangeName(option)),
            icon: locked && option.premium
                ? const Icon(Icons.lock_outline)
                : null,
          ),
      ],
      selected: {range},
      onSelectionChanged: (selection) => _select(context, selection.single),
    );
  }

  static Future<void> _select(BuildContext context, StrengthRange range) async {
    final cubit = context.read<BodyListCubit>();
    if (range.premium && !await context.requirePremium()) return;
    cubit.selectRange(range);
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile(this.entry, {required this.bodyFat});
  final BodyEntry entry;
  final double? bodyFat;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final weight = entry.weightKg;
    final fat = bodyFat;
    final contents = [
      ?l10n.entryContents(entry),
      if (fat != null) l10n.bodyFatOn(l10n.bodyFat(fat)),
    ].join(' · ');
    return ListTile(
      leading: Icon(
        entry.isWeightOnly ? Icons.monitor_weight_outlined : Icons.straighten,
      ),
      title: Text(
        MaterialLocalizations.of(context).formatMediumDate(entry.date),
      ),
      subtitle: contents.isEmpty ? null : Text(contents),
      trailing: weight == null ? null : Text(l10n.bodyWeight(weight, unit)),
      onTap: () => context.go(Routes.bodyEntry(entry.id)),
    );
  }
}
