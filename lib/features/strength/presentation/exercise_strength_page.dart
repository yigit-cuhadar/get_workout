import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:forge_core/forge_core.dart';
import 'package:forge_ui/forge_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../l10n/app_localizations.dart';
import '../../exercises/domain/exercise.dart';
import '../../exercises/presentation/exercise_catalogue_cubit.dart';
import '../../exercises/presentation/vocabulary_labels.dart';
import '../../programs/presentation/program_text.dart';
import '../../settings/domain/user_settings.dart';
import '../../settings/presentation/settings_cubit.dart';
import '../../subscription/presentation/premium.dart';
import '../domain/strength.dart';
import 'exercise_strength_cubit.dart';
import 'strength_list_cubit.dart';
import 'strength_list_page.dart';
import 'strength_text.dart';

/// An exercise's estimated one-rep max over time, its records and its
/// sessions, each session opening its workout. The Exercise row switches
/// to another exercise with stats.
class ExerciseStrengthPage extends StatelessWidget {
  const ExerciseStrengthPage({super.key, required this.exerciseId});

  final String exerciseId;

  @override
  Widget build(BuildContext context) {
    // Read here: the create callback must not look up inherited widgets.
    final unit = context.read<SettingsCubit>().state.settings.weightUnit;
    return BlocProvider(
      // A switch to another exercise keeps this page: start over.
      key: ValueKey(exerciseId),
      create: (_) =>
          sl<ExerciseStrengthCubit>(param1: exerciseId, param2: unit),
      child: _StrengthView(exerciseId),
    );
  }
}

class _StrengthView extends StatelessWidget {
  const _StrengthView(this.exerciseId);
  final String exerciseId;

  static const _loadingRows = 3;

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
    final removed = context.select(
      (ExerciseCatalogueCubit catalogue) => switch (catalogue.state) {
        final CatalogueReady ready =>
          exercise == null && ready.knows(exerciseId),
        _ => false,
      },
    );
    final name = exercise?.localized(context).name;
    final state = context.watch<ExerciseStrengthCubit>().state;
    return BlocListener<SettingsCubit, SettingsState>(
      listenWhen: (previous, current) =>
          previous.settings.weightUnit != current.settings.weightUnit,
      listener: (_, settings) => cubit.setUnit(settings.settings.weightUnit),
      child: Scaffold(
        appBar: ForgeAppBar(title: l10n.strengthTitle),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.xs, Gap.md, Gap.md),
          children: [
            for (final part in [
              ListRowCard(
                children: [
                  ListRow(
                    title: l10n.strengthExercise,
                    value: removed ? l10n.strengthRemovedExercise : name ?? '',
                    end: ListRowEnd.chevron,
                    onTap: () => _pickExercise(context),
                  ),
                ],
              ),
              ...switch (state.status) {
                ExerciseStrengthStatus.loading => [
                  Chart.loading(title: l10n.strengthChartTitle),
                  ListRowCard(
                    children: [
                      for (var i = 0; i < _loadingRows; i++)
                        ListRow.loading(index: i),
                    ],
                  ),
                ],
                ExerciseStrengthStatus.failure => [
                  ErrorView(
                    title: l10n.strengthLoadFailed,
                    message: l10n.loadFailedDetail,
                    retryLabel: l10n.retry,
                    onRetry: cubit.retry,
                  ),
                ],
                ExerciseStrengthStatus.ready when !state.trained => [
                  EmptyView(
                    title: name == null
                        ? l10n.strengthNoSessionsYet
                        : l10n.strengthNoSessions(name),
                    message: l10n.strengthNotDone,
                  ),
                ],
                ExerciseStrengthStatus.ready => _strength(
                  context,
                  state,
                  exercise: exercise,
                  name: name,
                ),
              },
            ])
              Padding(padding: const EdgeInsets.only(bottom: 10), child: part),
          ],
        ),
      ),
    );
  }

  List<Widget> _strength(
    BuildContext context,
    ExerciseStrengthState state, {
    required Exercise? exercise,
    required String? name,
  }) {
    final l10n = AppLocalizations.of(context);
    final unit = context.select(
      (SettingsCubit cubit) => cubit.state.settings.weightUnit,
    );
    final type = exercise?.loggingType ?? state.loggingType!;
    return [
      if (state.charted) ...[
        _RangePicker(state.range),
        _E1rmChart(state, unit: unit, name: name),
      ],
      if (state.olderLocked)
        ListRowCard(
          children: [
            ListRow(
              leading: ForgeIcon(
                ForgeIcons.lock,
                size: 18,
                color: ForgeStyle.of(context).colors.inkMuted,
              ),
              title: l10n.strengthOlderLocked,
              trailing: ForgeButton(
                label: l10n.strengthUnlock,
                variant: ForgeButtonVariant.text,
                size: ForgeButtonSize.small,
                onPressed: context.openPaywall,
              ),
            ),
          ],
        ),
      ListRowCard(
        children: [
          for (final entry in state.records)
            ListRow(
              title: l10n.recordName(entry.kind),
              detail: l10n.dayDate(entry.record.date),
              value: l10n.recordValue(entry, type, unit),
              dataValue: true,
            ),
        ],
      ),
      if (state.sessions.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionLabel(l10n.strengthSessions),
            ListRowCard(
              children: [
                for (final session in state.sessions)
                  ListRow(
                    title: l10n.sessionText(session, type, unit),
                    dataTitle: true,
                    detail: l10n.sessionDetail(session),
                    end: ListRowEnd.chevron,
                    onTap: () =>
                        context.push(Routes.calendarWorkout(session.workoutId)),
                  ),
              ],
            ),
          ],
        ),
    ];
  }

  /// The Exercise sheet: the Strength list's rows with their search, this
  /// exercise ticked; another one replaces this page, so Back still returns
  /// to the list.
  Future<void> _pickExercise(BuildContext context) {
    final router = GoRouter.of(context);
    return showForgeBottomSheet<void>(
      context: context,
      builder: (sheet) => BlocProvider(
        create: (_) => sl<StrengthListCubit>(),
        child: ForgeBottomSheet(
          title: AppLocalizations.of(sheet).strengthExercise,
          child: StrengthSearch(
            padding: EdgeInsets.zero,
            selected: exerciseId,
            onPick: (_, id) {
              Navigator.pop(sheet);
              if (id != exerciseId) router.go(Routes.strengthExercise(id));
            },
          ),
        ),
      ),
    );
  }
}

/// The chart's ranges; a Premium one asks for Premium first, and is
/// locked for a free user.
class _RangePicker extends StatelessWidget {
  const _RangePicker(this.range);
  final StrengthRange range;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locked = context.watchPremium() == PremiumStatus.free;
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
      onChanged: (option) => _select(context, option),
      onLocked: (option) => _select(context, option),
    );
  }

  static Future<void> _select(BuildContext context, StrengthRange range) async {
    final cubit = context.read<ExerciseStrengthCubit>();
    if (range.premium && !await context.requirePremium()) return;
    cubit.selectRange(range);
  }
}

/// Each workout's best e1RM in the range, one dot per workout; the
/// empty form when the range has none.
class _E1rmChart extends StatelessWidget {
  const _E1rmChart(this.state, {required this.unit, required this.name});

  final ExerciseStrengthState state;
  final WeightUnit unit;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final points = state.points;
    final title = l10n.strengthChartTitle;
    if (points.isEmpty) {
      return Chart.empty(
        title: title,
        detail: l10n.strengthDates(
          l10n.shortDate(state.rangeStart!),
          l10n.shortDate(DateTime.now()),
        ),
        emptyTitle: l10n.strengthChartEmptyTitle(state.range.name),
        message: l10n.strengthChartEmptyMessage(
          name ?? l10n.strengthRemovedExercise,
        ),
      );
    }
    final start = state.rangeStart ?? points.first.date;
    return Chart.line(
      title: title,
      detail: l10n.strengthDates(
        l10n.shortDate(start),
        l10n.shortDate(state.sessions.first.date),
      ),
      values: [for (final point in points) point.value],
      pointLabel: (index) => l10n.strengthPoint(
        l10n.estimatedWeightText(unit.toKg(points[index].value), unit),
        l10n.shortDate(points[index].date),
      ),
      startLabel: l10n.shortDate(points.first.date),
      endLabel: l10n.shortDate(points.last.date),
      semanticLabel: l10n.strengthChartLabel(
        l10n.inlineList([
          for (final point in points)
            l10n.estimatedWeightText(unit.toKg(point.value), unit),
        ]),
      ),
    );
  }
}
