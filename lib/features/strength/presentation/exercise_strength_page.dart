import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/router.dart';
import '../../../core/line_chart.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/strength.dart';
import 'exercise_strength_cubit.dart';
import 'strength_text.dart';

/// An exercise's records, each opening the workout that set it, and its
/// estimated one-rep max over time.
class ExerciseStrengthPage extends StatelessWidget {
  const ExerciseStrengthPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    // Read here: the create callback must not look up inherited widgets.
    final unit = context.read<SettingsCubit>().state.settings.weightUnit;
    return BlocProvider(
      create: (_) =>
          sl<ExerciseStrengthCubit>(param1: exerciseId, param2: unit),
      child: _StrengthView(exerciseId),
    );
  }
}

class _StrengthView extends StatelessWidget {
  const _StrengthView(this.exerciseId);
  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cubit = context.read<ExerciseStrengthCubit>();
    final exercise = context.select(
      (ExerciseCatalogueCubit catalogue) => switch (catalogue.state) {
        CatalogueReady(:final exercises) =>
          exercises.where((e) => e.id == exerciseId).firstOrNull,
        _ => null,
      },
    );
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          previous.settings.weightUnit != current.settings.weightUnit,
      listener: (_, settings) => cubit.setUnit(settings.settings.weightUnit),
      child: BlocBuilder<ExerciseStrengthCubit, ExerciseStrengthState>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: Text(
              exercise?.localized(context).name ?? l10n.strengthTitle,
            ),
          ),
          body: switch (state.status) {
            ExerciseStrengthStatus.loading => const LoadingView(),
            ExerciseStrengthStatus.failure => ErrorView(
              message: l10n.strengthLoadFailed,
              retryLabel: l10n.retry,
              onRetry: cubit.retry,
            ),
            ExerciseStrengthStatus.ready when !state.trained => EmptyView(
              message: l10n.strengthNotDone,
            ),
            ExerciseStrengthStatus.ready => _Strength(state),
          },
        ),
      ),
    );
  }
}

class _Strength extends StatelessWidget {
  const _Strength(this.state);
  final ExerciseStrengthState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final dates = MaterialLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    return ListView(
      padding: const EdgeInsets.only(bottom: Gap.xl),
      children: [
        if (state.charted) ...[
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Text(
              l10n.strengthChartTitle(l10n.weightUnitLabel(unit)),
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: _RangePicker(state.range),
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: state.points.isEmpty
                ? Text(l10n.strengthChartEmpty)
                : _E1rmChart(state.points, unit),
          ),
          if (state.olderLocked)
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(l10n.strengthOlderLocked),
              trailing: TextButton(
                onPressed: () => context.openPaywall(),
                child: Text(l10n.strengthUnlock),
              ),
            ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 0),
          child: Text(l10n.strengthRecords, style: theme.textTheme.titleMedium),
        ),
        for (final (:kind, :record) in state.records)
          ListTile(
            title: Text(l10n.recordName(kind)),
            subtitle: Text(dates.formatMediumDate(record.date)),
            trailing: Text(
              l10n.recordValue(kind, record.value, unit),
              style: theme.textTheme.titleSmall,
            ),
            onTap: () => context.push(Routes.historyWorkout(record.workoutId)),
          ),
      ],
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
    final cubit = context.read<ExerciseStrengthCubit>();
    if (range.premium && !await context.requirePremium()) return;
    cubit.selectRange(range);
  }
}

class _E1rmChart extends StatelessWidget {
  const _E1rmChart(this.points, this.unit);
  final List<E1rmPoint> points;
  final WeightUnit unit;

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
    // Whole kg or lb: finer steps would only show noise.
    final numbers = NumberFormat.decimalPattern(locale)
      ..maximumFractionDigits = 0;
    DateTime date(double x) => DateTime.fromMillisecondsSinceEpoch(x.round());
    return LineChart(
      points: [
        for (final point in points)
          (x: point.date.millisecondsSinceEpoch.toDouble(), y: point.value),
      ],
      xLabel: (x) => axisDates.format(date(x)),
      yLabel: numbers.format,
      yPrecision: 1,
      pointLabel: (index) {
        final point = points[index];
        return l10n.strengthPoint(
          l10n.weightText(unit.toKg(point.value), unit),
          DateFormat.yMMMd(locale).format(point.date),
        );
      },
    );
  }
}
