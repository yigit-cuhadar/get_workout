import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/line_chart.dart';
import '../../../l10n/app_localizations.dart';
import '../../profile/presentation/profile_cubit.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../strength/domain/strength.dart';
import '../../strength/presentation/strength_text.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/body_entry.dart';
import '../domain/body_stats.dart';
import 'body_list_cubit.dart';
import 'body_text.dart';

/// The weight trend, the two ways to log, then every entry, newest first.
class BodyPage extends StatelessWidget {
  const BodyPage({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocProvider.value(value: sl<BodyListCubit>(), child: const _BodyView());
}

class _BodyView extends StatelessWidget {
  const _BodyView();

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
          BodyListStatus.ready => _Entries(state),
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

/// Built lazily: the chart and buttons, then one row per entry.
class _Entries extends StatelessWidget {
  const _Entries(this.state);
  final BodyListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final rows = <WidgetBuilder>[
      (_) => _WeightCard(state),
      // Only once some entry has a body fat to show.
      if (state.bodyFat.isNotEmpty) (_) => _BodyFatCard(state),
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
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index](context),
    );
  }
}

class _WeightCard extends StatelessWidget {
  const _WeightCard(this.state);
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
    final latest = latestWeightKg(state.entries);
    final points = state.points;
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.bodyWeightTrend, style: theme.textTheme.titleMedium),
          if (latest != null)
            Text(
              l10n.bodyLatest(l10n.bodyWeight(latest, unit)),
              style: theme.textTheme.bodyMedium,
            ),
          if (target != null)
            Text(
              _targetText(l10n, target: target, latest: latest, unit: unit),
              style: theme.textTheme.bodyMedium,
            ),
          const SizedBox(height: Gap.sm),
          _RangePicker(state.range),
          const SizedBox(height: Gap.sm),
          if (points.isEmpty)
            Text(l10n.bodyNoWeights, style: theme.textTheme.bodyMedium)
          else
            _TrendChart([
              for (final point in points)
                (date: point.date, value: unit.fromKg(point.kg)),
            ], label: (value) => l10n.bodyWeight(unit.toKg(value), unit)),
          if (state.olderLocked) ...[
            const SizedBox(height: Gap.sm),
            Text(l10n.bodyOlderLocked, style: theme.textTheme.bodySmall),
          ],
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

/// The body-fat trend over the weight chart's range, which it also picks.
class _BodyFatCard extends StatelessWidget {
  const _BodyFatCard(this.state);
  final BodyListState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final points = state.bodyFatPoints;
    // Shown only when some entry has one; entries are newest first.
    final latest = state.entries
        .map((entry) => state.bodyFat[entry.id])
        .nonNulls
        .first;
    return Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.bodyFatTitle, style: theme.textTheme.titleMedium),
          Text(
            l10n.bodyLatest(l10n.bodyFat(latest)),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: Gap.sm),
          _RangePicker(state.range),
          const SizedBox(height: Gap.sm),
          if (points.isEmpty)
            Text(l10n.bodyNoBodyFat, style: theme.textTheme.bodyMedium)
          else
            _TrendChart([
              for (final point in points)
                (date: point.date, value: point.percent),
            ], label: l10n.bodyFat),
          if (state.bodyFatOlderLocked) ...[
            const SizedBox(height: Gap.sm),
            Text(l10n.bodyFatOlderLocked, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
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

/// Values over time, in the unit [label] writes them in.
class _TrendChart extends StatelessWidget {
  const _TrendChart(this.points, {required this.label});

  /// Oldest first.
  final List<({DateTime date, double value})> points;
  final String Function(double value) label;

  /// Beyond this span the bottom labels name months and years.
  static const _daysOfShortDates = 300;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = l10n.localeName;
    final span = points.last.date.difference(points.first.date).inDays;
    final axisDates = span > _daysOfShortDates
        ? DateFormat.yMMM(locale)
        : DateFormat.MMMd(locale);
    final numbers = NumberFormat.decimalPattern(locale)
      ..maximumFractionDigits = 1;
    DateTime date(double x) => DateTime.fromMillisecondsSinceEpoch(x.round());
    return LineChart(
      points: [
        for (final point in points)
          (x: point.date.millisecondsSinceEpoch.toDouble(), y: point.value),
      ],
      xLabel: (x) => axisDates.format(date(x)),
      yLabel: numbers.format,
      // Body weight and fat move in tenths.
      yPrecision: 0.1,
      pointLabel: (index) {
        final point = points[index];
        return l10n.bodyPoint(
          label(point.value),
          DateFormat.yMMMd(locale).format(point.date),
        );
      },
    );
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
